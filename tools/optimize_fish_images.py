#!/usr/bin/env python3
"""어류 도감 이미지(assets/fish) 최적화 스크립트.

도감 타일은 폰에서 최대 ~360px로 렌더되므로 1024px 원본은 과합니다.
이 스크립트는 PNG를 적정 해상도로 리사이즈하고 다시 인코딩해 다운로드 용량을 줄입니다.

- 투명도(RGBA)는 보존합니다.
- 결과가 원본보다 작을 때만 덮어씁니다(절대 커지지 않음).
- 원본은 git에 있으니 되돌릴 수 있습니다. 먼저 --dry-run 으로 확인하세요.

사용 예:
  python tools/optimize_fish_images.py --dry-run         # 미리보기(쓰기 없음)
  python tools/optimize_fish_images.py                   # 512px 무손실 최적화
  python tools/optimize_fish_images.py --colors 64       # 64색 양자화(추가 절감, 약손실)
  python tools/optimize_fish_images.py --max-size 384    # 더 작게

요구사항: Pillow (pip install pillow)
"""
import argparse
import glob
import io
import os
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("Pillow가 필요합니다:  pip install pillow")

# Windows 콘솔(cp949)에서도 한글이 깨지지 않도록 UTF-8 출력
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:  # noqa: BLE001
    pass


def human(n: float) -> str:
    if n < 1024:
        return f"{n:.0f}B"
    if n < 1024 * 1024:
        return f"{n/1024:.1f}KB"
    return f"{n/1024/1024:.2f}MB"


_SENTINEL = (255, 0, 255)  # flood-fill 표식(그레이스케일 실루엣엔 없는 색)


def white_bg_to_alpha(im: "Image.Image", tol: int) -> "Image.Image":
    """가장자리에서 연결된 '흰 배경'만 투명화(내부 흰 영역엔 구멍 안 뚫림).

    네 변의 픽셀 중 '흰색에 가까운' 지점에서만 flood-fill을 시작하므로,
    배경이 흰색이 아닌 이미지(예: 색이 칠해진 일러스트)는 건드리지 않는다.
    """
    im = im.convert("RGBA")
    w, h = im.size
    rgb = im.convert("RGB")
    rpx = rgb.load()

    def near_white(p) -> bool:
        return p[0] >= 255 - tol and p[1] >= 255 - tol and p[2] >= 255 - tol

    seeds = []
    sx = max(1, w // 64)
    sy = max(1, h // 64)
    for x in range(0, w, sx):
        seeds.append((x, 0))
        seeds.append((x, h - 1))
    for y in range(0, h, sy):
        seeds.append((0, y))
        seeds.append((w - 1, y))

    filled = False
    for s in seeds:
        if rpx[s] != _SENTINEL and near_white(rpx[s]):
            ImageDraw.floodfill(rgb, s, _SENTINEL, thresh=tol)
            filled = True
    if not filled:
        return im  # 흰 배경 없음 → 원본 유지

    # 표식 픽셀 → 완전 투명(+ RGB 0으로 정리해 압축률↑)
    rdata = list(rgb.getdata())
    src = list(im.getdata())
    out = [
        (0, 0, 0, 0) if rd == _SENTINEL else px
        for rd, px in zip(rdata, src)
    ]
    im.putdata(out)
    return im


def luminance_alpha(
    im: "Image.Image", dark_pt: int, light_pt: int, sat_skip: int = 40
) -> "Image.Image":
    """밝기를 알파로 변환해 경계를 깔끔하게 만든다(실루엣 전용).

    어두운 실루엣은 그대로 두고, 밝을수록 알파를 줄여 흰 테두리(헤일로)를 부드럽게
    없앤다. '흰색만 찾아 지우기'와 달리 중간 밝기 경계까지 자연스럽게 처리된다.
    채도가 높은(컬러) 이미지는 건드리지 않는다.
    """
    im = im.convert("RGBA")

    # 채도 검사(축소본 샘플): 컬러 일러스트면 스킵
    small = im.resize((64, 64))
    maxsat = 0
    for (r, g, b, a) in small.getdata():
        if a > 16:
            s = max(r, g, b) - min(r, g, b)
            if s > maxsat:
                maxsat = s
    if maxsat > sat_skip:
        return im  # 컬러 이미지 → 변경 없음

    span = max(1, light_pt - dark_pt)
    out = []
    for (r, g, b, a) in im.getdata():
        if a == 0:
            out.append((0, 0, 0, 0))
            continue
        lum = (r + g + b) / 3
        if lum <= dark_pt:
            k = 1.0
        elif lum >= light_pt:
            k = 0.0
        else:
            k = (light_pt - lum) / span
        na = int(round(a * k))
        out.append((r, g, b, na) if na else (0, 0, 0, 0))
    im.putdata(out)
    return im


def trim_alpha(im: "Image.Image", pad: int) -> "Image.Image":
    """투명 여백을 잘라 콘텐츠(불투명 영역)에 맞춰 크롭. pad만큼 여유를 둔다."""
    im = im.convert("RGBA")
    bbox = im.getchannel("A").getbbox()
    if not bbox:
        return im
    if pad:
        w, h = im.size
        l, t, r, b = bbox
        bbox = (max(0, l - pad), max(0, t - pad),
                min(w, r + pad), min(h, b + pad))
    return im.crop(bbox)


def optimize_one(
    path: str,
    max_size: int,
    colors: int | None,
    white_tol: int | None,
    trim_pad: int | None,
    lum: tuple[int, int] | None,
) -> bytes:
    """리사이즈/재인코딩한 PNG 바이트를 반환(투명도 보존)."""
    im = Image.open(path)
    if im.mode != "RGBA":
        im = im.convert("RGBA")

    if lum is not None:
        im = luminance_alpha(im, lum[0], lum[1])

    if white_tol is not None:
        im = white_bg_to_alpha(im, white_tol)

    if trim_pad is not None:
        im = trim_alpha(im, trim_pad)

    # 긴 변이 max_size를 넘으면 비율 유지 축소
    if max(im.size) > max_size:
        im.thumbnail((max_size, max_size), Image.Resampling.LANCZOS)

    if colors:
        # 알파를 보존하는 팔레트 양자화(FASTOCTREE는 RGBA 지원)
        im = im.quantize(
            colors=colors,
            method=Image.Quantize.FASTOCTREE,
            dither=Image.Dither.NONE,
        )

    buf = io.BytesIO()
    im.save(buf, format="PNG", optimize=True)
    return buf.getvalue()


def main() -> int:
    ap = argparse.ArgumentParser(description="assets/fish PNG 최적화")
    ap.add_argument("--dir", default="assets/fish",
                    help="대상 루트(기본 assets/fish; color/·silhouette/ 하위 포함)")
    ap.add_argument("--max-size", type=int, default=512,
                    help="긴 변 최대 픽셀(기본 512)")
    ap.add_argument("--colors", type=int, default=None,
                    help="팔레트 색 수로 양자화(예: 64). 생략 시 무손실")
    ap.add_argument("--white-to-alpha", dest="white_tol", type=int, nargs="?",
                    const=40, default=None,
                    help="가장자리 흰 배경을 투명화(허용오차, 기본 40). 흰 배경이 아닌 이미지는 자동 무시")
    ap.add_argument("--trim", dest="trim_pad", type=int, nargs="?",
                    const=6, default=None,
                    help="투명 여백 잘라내기(여유 px, 기본 6). 물고기가 타일을 꽉 채우게 함")
    ap.add_argument("--lum-alpha", dest="lum_alpha", action="store_true",
                    help="밝기→알파 변환(실루엣 경계 깔끔하게). 어두울수록 불투명, 밝을수록 투명. 컬러는 자동 스킵")
    ap.add_argument("--lum-dark", type=int, default=120,
                    help="이 밝기 이하는 완전 불투명(기본 120)")
    ap.add_argument("--lum-light", type=int, default=200,
                    help="이 밝기 이상은 완전 투명(기본 200)")
    ap.add_argument("--dry-run", action="store_true",
                    help="쓰지 않고 절감량만 출력")
    args = ap.parse_args()

    files = sorted(glob.glob(os.path.join(args.dir, "**", "*.png"), recursive=True))
    if not files:
        print(f"PNG가 없습니다: {args.dir}")
        return 1

    total_before = total_after = 0
    changed = 0
    for path in files:
        before = os.path.getsize(path)
        lum = (args.lum_dark, args.lum_light) if args.lum_alpha else None
        try:
            data = optimize_one(path, args.max_size, args.colors,
                                args.white_tol, args.trim_pad, lum)
        except Exception as e:  # noqa: BLE001
            print(f"  ! {os.path.basename(path):26} 실패: {e}")
            total_before += before
            total_after += before
            continue
        after = len(data)
        total_before += before
        # 내용 변경(투명화/trim/양자화)은 용량과 무관하게 항상 적용.
        # 순수 재인코딩(무손실)만 "더 작을 때만" 채택해 용량이 커지지 않게 한다.
        content_op = (args.white_tol is not None
                      or args.trim_pad is not None
                      or args.colors is not None
                      or args.lum_alpha)
        if content_op or after < before:
            total_after += after
            changed += 1
            mark = "→"
            if not args.dry_run:
                with open(path, "wb") as f:
                    f.write(data)
        else:
            total_after += before
            mark = "="
            after = before
        print(f"  {mark} {os.path.basename(path):26} {human(before):>9} → {human(after):>9}")

    saved = total_before - total_after
    pct = (saved / total_before * 100) if total_before else 0
    print("-" * 60)
    print(f"  파일 {len(files)}개 중 {changed}개 축소")
    print(f"  합계 {human(total_before)} → {human(total_after)}  (-{human(saved)}, -{pct:.0f}%)")
    if args.dry_run:
        print("  [dry-run] 실제로 쓰지 않았습니다. 적용하려면 --dry-run 없이 실행하세요.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

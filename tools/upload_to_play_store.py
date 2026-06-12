#!/usr/bin/env python3
"""Google Play 자동 업로드 스크립트 (androidpublisher v3).

서비스 계정 JSON 키로 인증 후 .aab 를 지정 트랙에 업로드한다.

사용 예:
    python tools/upload_to_play_store.py \
        --aab build/app/outputs/bundle/release/app-release.aab \
        --key C:/secrets/play-service-account.json \
        --track internal \
        --status draft

준비물:
  1) Google Cloud 서비스 계정 + JSON 키
  2) Play Console > 사용자 및 권한 에서 해당 서비스 계정 초대 후
     "앱 출시 관리" 권한 부여
  3) Google Play Android Developer API 사용 설정
"""
import argparse
import sys

try:
    from google.oauth2 import service_account
    from googleapiclient.discovery import build
    from googleapiclient.http import MediaFileUpload
    from googleapiclient.errors import HttpError
except ImportError as e:
    sys.exit(
        f"[오류] 필요한 라이브러리가 없습니다: {e}\n"
        "  pip install google-api-python-client google-auth"
    )

SCOPES = ["https://www.googleapis.com/auth/androidpublisher"]


def latest_release_notes(edits, package, edit_id, track):
    """track의 기존 릴리스 중 출시노트가 있는 가장 최신(versionCode 최대) 릴리스의 노트 반환."""
    info = edits.tracks().get(
        packageName=package, editId=edit_id, track=track
    ).execute()

    def max_vc(r):
        return max((int(v) for v in r.get("versionCodes") or [0]), default=0)

    for r in sorted(info.get("releases", []), key=max_vc, reverse=True):
        if r.get("releaseNotes"):
            return r["releaseNotes"]
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description="Upload .aab to Google Play")
    ap.add_argument("--aab", required=True, help=".aab 파일 경로")
    ap.add_argument("--key", required=True, help="서비스 계정 JSON 키 경로")
    ap.add_argument("--package", default="com.sgchoisg.nakkda", help="패키지명")
    ap.add_argument(
        "--track",
        default="internal",
        choices=["internal", "alpha", "beta", "production"],
        help="출시 트랙 (기본: internal)",
    )
    ap.add_argument(
        "--status",
        default="draft",
        choices=["draft", "completed", "inProgress", "halted"],
        help="릴리스 상태 (기본: draft — 검토 후 수동 출시)",
    )
    ap.add_argument(
        "--copy-notes",
        action="store_true",
        help="이전 릴리스의 출시노트를 새 릴리스에 복사",
    )
    ap.add_argument(
        "--notes-track",
        default=None,
        choices=["internal", "alpha", "beta", "production"],
        help="출시노트를 가져올 트랙 (기본: --track 과 동일)",
    )
    args = ap.parse_args()

    creds = service_account.Credentials.from_service_account_file(
        args.key, scopes=SCOPES
    )
    service = build("androidpublisher", "v3", credentials=creds, cache_discovery=False)
    edits = service.edits()

    try:
        edit_id = edits.insert(body={}, packageName=args.package).execute()["id"]
        print(f"[1/4] edit 생성: {edit_id}")

        upload = edits.bundles().upload(
            packageName=args.package,
            editId=edit_id,
            media_body=MediaFileUpload(args.aab, mimetype="application/octet-stream"),
        ).execute()
        version_code = upload["versionCode"]
        print(f"[2/4] 번들 업로드 완료: versionCode={version_code}")

        release = {"status": args.status, "versionCodes": [str(version_code)]}
        if args.copy_notes:
            src = args.notes_track or args.track
            notes = latest_release_notes(edits, args.package, edit_id, src)
            if notes:
                release["releaseNotes"] = notes
                langs = ", ".join(n.get("language", "?") for n in notes)
                print(f"      이전 출시노트 복사({src}): {langs}")
            else:
                print(f"      '{src}' 트랙에 복사할 출시노트가 없습니다.")

        edits.tracks().update(
            packageName=args.package,
            editId=edit_id,
            track=args.track,
            body={"track": args.track, "releases": [release]},
        ).execute()
        print(f"[3/4] 트랙 할당: {args.track} (status={args.status})")

        edits.commit(packageName=args.package, editId=edit_id).execute()
        print("[4/4] 커밋 완료. Play Console에서 검토 후 출시하세요.")
        return 0

    except HttpError as e:
        print(f"[API 오류] {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import '../../features/settings/domain/models/app_settings.dart';

/// 헤비(번들) 폰트 패밀리명 — pubspec.yaml fonts 등록명과 일치해야 함.
const String kWatermarkHeavyFont = 'BlackHanSans';

/// 이미지에 워터마크(배경 컨테이너 + 독립 박스들)를 적용하고 JPEG 경로를 반환.
/// 실패 시 원본 경로 반환.
Future<String> applyWatermark(
    String imagePath, WatermarkSettings settings) async {
  if (!settings.enabled) return imagePath;

  try {
    final now = DateTime.now();
    // 보이고 내용이 있는 박스만
    final boxes = settings.boxes
        .where((b) => b.visible && _boxText(b, now).isNotEmpty)
        .toList();
    if (boxes.isEmpty) return imagePath;

    final tempDir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;

    // ui.instantiateImageCodec는 EXIF 방향을 무시하므로,
    // 먼저 EXIF 회전을 픽셀에 반영한 JPEG로 정규화 (autoCorrectionAngle 기본값 true)
    final rotatedPath = '${tempDir.path}/wm_rot_$ts.jpg';
    final rotated = await FlutterImageCompress.compressAndGetFile(
      imagePath,
      rotatedPath,
      quality: 95,
    );
    final srcPath = rotated?.path ?? imagePath;

    // 이미지 로드
    final imageBytes = await File(srcPath).readAsBytes();
    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    final src = frame.image;
    final w = src.width.toDouble();
    final h = src.height.toDouble();

    // 이미지 크기 기준 폰트 스케일링 (짧은 쪽 / 480 기준)
    final shortSide = math.min(w, h);

    // 각 박스를 측정해 그릴 파라그래프 + 위치(px)를 준비
    final laid = <_LaidBox>[];
    double maxFont = 0;
    for (final b in boxes) {
      final text = _boxText(b, now);
      final scaledFont = b.fontSize * shortSide / 480.0;
      maxFont = math.max(maxFont, scaledFont);
      final fw = _fontWeight(b.weight);
      final fam = _fontFamily(b.fontFamily);
      final color = ui.Color(b.textColor);

      // 측정용: 넓게 레이아웃 후 longestLine으로 박스 너비 확보
      final measure = (ui.ParagraphBuilder(ui.ParagraphStyle(
        fontSize: scaledFont,
        fontWeight: fw,
        fontFamily: fam,
      ))
            ..pushStyle(ui.TextStyle(
              color: color,
              fontSize: scaledFont,
              fontWeight: fw,
              fontFamily: fam,
            ))
            ..addText(text))
          .build()
        ..layout(const ui.ParagraphConstraints(width: 100000));
      final bw = measure.longestLine + 1;

      // 실제 그릴 파라그래프 (정렬 반영, 박스 너비 고정)
      final para = (ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: _uiTextAlign(b.alignment),
        fontSize: scaledFont,
        fontWeight: fw,
        fontFamily: fam,
      ))
            ..pushStyle(ui.TextStyle(
              color: color,
              fontSize: scaledFont,
              fontWeight: fw,
              fontFamily: fam,
            ))
            ..addText(text))
          .build()
        ..layout(ui.ParagraphConstraints(width: bw));

      laid.add(_LaidBox(
          para, b.dx * shortSide, b.dy * shortSide, bw, para.height));
    }

    // 박스 그룹의 바운딩 박스
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (final l in laid) {
      minX = math.min(minX, l.x);
      minY = math.min(minY, l.y);
      maxX = math.max(maxX, l.x + l.w);
      maxY = math.max(maxY, l.y + l.h);
    }

    final pad = maxFont * 0.4; // 컨테이너 안쪽 여백
    final boxW = (maxX - minX) + pad * 2;
    final boxH = (maxY - minY) + pad * 2;
    final margin = shortSide * 0.01; // 사진 가장자리와의 최소 여백(거의 구석까지)

    final boxOffset = _boxOffset(settings.containerPosX, settings.containerPosY,
        w, h, boxW, boxH, margin);

    // 캔버스 그리기
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(src, Offset.zero, Paint());

    // 컨테이너 배경 (프리셋 색 + 투명도)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(boxOffset.dx, boxOffset.dy, boxW, boxH),
        Radius.circular(maxFont * 0.2),
      ),
      Paint()..color = Color(settings.bgColorArgb),
    );

    // 각 박스 텍스트 그리기
    for (final l in laid) {
      canvas.drawParagraph(
        l.para,
        Offset(
          boxOffset.dx + pad + (l.x - minX),
          boxOffset.dy + pad + (l.y - minY),
        ),
      );
    }

    // PNG 바이트로 렌더링
    final picture = recorder.endRecording();
    final rendered = await picture.toImage(src.width, src.height);
    final byteData = await rendered.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null || byteData.lengthInBytes == 0) return imagePath;
    final pngBytes = byteData.buffer.asUint8List();

    // 중간 PNG 파일 저장
    final tempPngPath = '${tempDir.path}/wm_src_$ts.png';
    await File(tempPngPath).writeAsBytes(pngBytes);

    // PNG → JPEG 변환: compressAndGetFile(파일→파일)은 compressWithList(바이트→바이트)보다
    // 안정적이며, 결과물이 갤러리/메모 모두에서 올바르게 표시되는 JPEG 파일 생성
    final tempJpegPath = '${tempDir.path}/wm_$ts.jpg';
    final compressed = await FlutterImageCompress.compressAndGetFile(
      tempPngPath,
      tempJpegPath,
      quality: 92,
      format: CompressFormat.jpeg,
    );

    // 중간 임시 파일 정리
    try { await File(tempPngPath).delete(); } catch (_) {}
    try { await File(rotatedPath).delete(); } catch (_) {}

    if (compressed == null) return imagePath;

    final outFile = File(compressed.path);
    if (!await outFile.exists() || await outFile.length() == 0) return imagePath;

    return outFile.path;
  } catch (_) {
    return imagePath;
  }
}

/// 측정 완료된 박스 (그릴 파라그래프 + 위치/크기 px)
class _LaidBox {
  final ui.Paragraph para;
  final double x;
  final double y;
  final double w;
  final double h;
  _LaidBox(this.para, this.x, this.y, this.w, this.h);
}

String _boxText(WatermarkBox b, DateTime now) {
  switch (b.type) {
    case WatermarkLineType.date:
      return _formatDate(now, b.dateFormat);
    case WatermarkLineType.time:
      return b.timeFormat.isEmpty ? '' : _formatTime(now, b.timeFormat);
    case WatermarkLineType.customText:
    case WatermarkLineType.customText2:
      return b.customText.trim();
  }
}

String _formatDate(DateTime dt, String format) {
  final y = dt.year.toString();
  final yy = (dt.year % 100).toString().padLeft(2, '0');
  final mm = dt.month.toString().padLeft(2, '0');
  final dd = dt.day.toString().padLeft(2, '0');
  final hh = dt.hour.toString().padLeft(2, '0');
  final min = dt.minute.toString().padLeft(2, '0');
  final sec = dt.second.toString().padLeft(2, '0');
  final mmm = _monthAbbr[dt.month - 1];
  switch (format) {
    case 'yy/MM/dd':
      return '$yy/$mm/$dd';
    case 'MM/dd':
      return '$mm/$dd';
    case 'MMM/dd':
      return '$mmm/$dd';
    case 'yyyy MMM dd':
      return '$y $mmm $dd';
    case 'yyyy-MM-dd HH:mm:ss':
      return '$y-$mm-$dd $hh:$min:$sec';
    case 'yyyy-MM-dd HH:mm':
      return '$y-$mm-$dd $hh:$min';
    default:
      return '$y-$mm-$dd';
  }
}

const _monthAbbr = [
  'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
  'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
];

String _formatTime(DateTime dt, String format) {
  final hh = dt.hour.toString().padLeft(2, '0');
  final min = dt.minute.toString().padLeft(2, '0');
  final sec = dt.second.toString().padLeft(2, '0');
  switch (format) {
    case 'HH:mm:ss':
      return '$hh:$min:$sec';
    default:
      return '$hh:$min';
  }
}

String _fontFamily(WatermarkFont f) {
  switch (f) {
    case WatermarkFont.monospace:
      return 'monospace';
    case WatermarkFont.serif:
      return 'serif';
    case WatermarkFont.sansSerif:
      return 'sans-serif';
    case WatermarkFont.heavy:
      return kWatermarkHeavyFont;
  }
}

ui.FontWeight _fontWeight(WatermarkWeight w) {
  switch (w) {
    case WatermarkWeight.normal:
      return ui.FontWeight.w400;
    case WatermarkWeight.bold:
      return ui.FontWeight.w700;
    case WatermarkWeight.black:
      return ui.FontWeight.w900;
  }
}

ui.TextAlign _uiTextAlign(WatermarkAlign a) {
  switch (a) {
    case WatermarkAlign.left:
      return ui.TextAlign.left;
    case WatermarkAlign.center:
      return ui.TextAlign.center;
    case WatermarkAlign.right:
      return ui.TextAlign.right;
  }
}

Offset _boxOffset(double posX, double posY, double w, double h, double boxW,
    double boxH, double margin) {
  final freeW = math.max(0.0, w - boxW - margin * 2);
  final freeH = math.max(0.0, h - boxH - margin * 2);
  return Offset(margin + posX * freeW, margin + posY * freeH);
}

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import '../../features/settings/domain/models/app_settings.dart';

/// 이미지에 워터마크를 적용하고 JPEG 경로를 반환.
/// 실패 시 원본 경로 반환.
Future<String> applyWatermark(
    String imagePath, WatermarkSettings settings) async {
  if (!settings.enabled) return imagePath;

  try {
    final now = DateTime.now();
    final textLines = settings.lines
        .where((l) => l.visible)
        .map((l) => _lineText(l, now, settings))
        .where((s) => s.isNotEmpty)
        .toList();

    if (textLines.isEmpty) return imagePath;

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
    final scaledFont = settings.fontSize * shortSide / 480.0;
    final lineH = scaledFont * 1.4;
    final padding = scaledFont * 0.5;

    final fontW = settings.bold ? ui.FontWeight.bold : ui.FontWeight.normal;
    final fontFam = _fontFamily(settings.fontFamily);

    // 텍스트 너비 측정 (10000 너비로 lay out 후 longestLine 사용)
    double maxTextW = 0;
    for (final text in textLines) {
      final pb = ui.ParagraphBuilder(ui.ParagraphStyle(
        fontSize: scaledFont,
        fontWeight: fontW,
        fontFamily: fontFam,
      ))
        ..pushStyle(ui.TextStyle(
          color: const ui.Color(0xFFFFFFFF),
          fontSize: scaledFont,
          fontWeight: fontW,
          fontFamily: fontFam,
        ))
        ..addText(text);
      final p = pb.build()
        ..layout(const ui.ParagraphConstraints(width: 10000));
      maxTextW = math.max(maxTextW, p.longestLine);
    }

    final constrainedW = math.min(maxTextW + 1, w * 0.9);
    final boxW = constrainedW + padding * 2;
    final boxH = textLines.length * lineH + padding * 2;
    final margin = padding;

    final boxOffset = _boxOffset(settings.posX, settings.posY, w, h, boxW, boxH, margin);

    // 캔버스 그리기
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(src, Offset.zero, Paint());

    // 반투명 배경
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(boxOffset.dx, boxOffset.dy, boxW, boxH),
        Radius.circular(scaledFont * 0.2),
      ),
      Paint()
        ..color = Color.fromARGB(
            (settings.boxOpacity * 255).round().clamp(0, 255), 0, 0, 0),
    );

    // 텍스트 라인 그리기
    double textY = boxOffset.dy + padding;
    final uiAlign = _uiTextAlign(settings.alignment);
    for (final text in textLines) {
      final pb = ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: uiAlign,
        fontSize: scaledFont,
        fontWeight: fontW,
        fontFamily: fontFam,
      ))
        ..pushStyle(ui.TextStyle(
          color: const ui.Color(0xFFFFFFFF),
          fontSize: scaledFont,
          fontWeight: fontW,
          fontFamily: fontFam,
        ))
        ..addText(text);
      final p = pb.build()
        ..layout(ui.ParagraphConstraints(width: constrainedW));
      canvas.drawParagraph(p, Offset(boxOffset.dx + padding, textY));
      textY += lineH;
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

String _lineText(WatermarkLine line, DateTime now, WatermarkSettings s) {
  switch (line.type) {
    case WatermarkLineType.date:
      return _formatDate(now, s.dateFormat);
    case WatermarkLineType.time:
      return s.timeFormat.isEmpty ? '' : _formatTime(now, s.timeFormat);
    case WatermarkLineType.customText:
      return line.customText.trim();
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
  switch (format) {
    case 'yy/MM/dd':
      return '$yy/$mm/$dd';
    case 'MM/dd':
      return '$mm/$dd';
    case 'yyyy-MM-dd HH:mm:ss':
      return '$y-$mm-$dd $hh:$min:$sec';
    case 'yyyy-MM-dd HH:mm':
      return '$y-$mm-$dd $hh:$min';
    default:
      return '$y-$mm-$dd';
  }
}

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

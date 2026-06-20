import 'dart:convert';
import 'package:flutter/services.dart';
import '../../features/settings/domain/models/app_settings.dart';

const _channel = MethodChannel('com.sgchoisg.nakkda/ar');

/// ARCore 측정 화면을 실행하고 결과를 반환.
/// 취소 또는 오류 시 null 반환.
Future<({String path, double? distanceCm, bool applyWatermark, double? posX, double? posY})?> launchArMeasure({
  bool watermarkEnabled = false,
  WatermarkSettings? watermarkSettings,
}) async {
  final wm = watermarkSettings;
  final Map<String, dynamic> args = {'watermarkEnabled': watermarkEnabled};

  if (wm != null) {
    // 신 모델(컨테이너 + 독립 박스들)을 그대로 JSON으로 전달 → AR 네이티브가 동일 렌더.
    // (실제 사진 워터마크는 Dart applyWatermark가 박스별로 정확히 굽는다.)
    bool hasText(WatermarkBox b) {
      switch (b.type) {
        case WatermarkLineType.date:
          return true;
        case WatermarkLineType.time:
          return b.timeFormat.isNotEmpty;
        case WatermarkLineType.customText:
          return b.customText.trim().isNotEmpty;
      }
    }

    final boxes = wm.boxes
        .where((b) => b.visible && hasText(b))
        .map((b) => {
              'type': b.type.name,
              'dateFormat': b.dateFormat,
              'timeFormat': b.timeFormat,
              'customText': b.customText.trim(),
              'dx': b.dx,
              'dy': b.dy,
              'fontSize': b.fontSize,
              'weight': b.weight.index,
              'fontFamily': b.fontFamily.name,
              'color': b.textColor,
              'align': b.alignment.name,
            })
        .toList();

    args['wmJson'] = jsonEncode({
      'bgColor': wm.bgColorArgb,
      'hideBorder': wm.hideContainerBorder,
      'posX': wm.containerPosX,
      'posY': wm.containerPosY,
      'boxes': boxes,
    });
  }

  final result = await _channel.invokeMapMethod<String, dynamic>('launchArMeasure', args);
  if (result == null) return null;
  final path = result['path'] as String?;
  if (path == null) return null;
  return (
    path: path,
    distanceCm: result['distanceCm'] as double?,
    applyWatermark: result['applyWatermark'] as bool? ?? false,
    posX: (result['posX'] as num?)?.toDouble(),
    posY: (result['posY'] as num?)?.toDouble(),
  );
}

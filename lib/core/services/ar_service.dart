import 'package:flutter/services.dart';
import '../../features/settings/domain/models/app_settings.dart';

const _channel = MethodChannel('com.nakkda.nakkda/ar');

/// ARCore 측정 화면을 실행하고 결과를 반환.
/// 취소 또는 오류 시 null 반환.
Future<({String path, double? distanceCm, bool applyWatermark})?> launchArMeasure({
  bool watermarkEnabled = false,
  WatermarkSettings? watermarkSettings,
}) async {
  final wm = watermarkSettings;
  final Map<String, dynamic> args = {'watermarkEnabled': watermarkEnabled};

  if (wm != null) {
    final dateVisible = wm.lines.any((l) => l.type == WatermarkLineType.date && l.visible);
    final timeVisible = wm.lines.any((l) => l.type == WatermarkLineType.time && l.visible);
    final customText = wm.lines
        .where((l) =>
            l.type == WatermarkLineType.customText &&
            l.visible &&
            l.customText.trim().isNotEmpty)
        .map((l) => l.customText.trim())
        .join('\n');

    args['wmPosition'] = wm.position.name;
    args['wmDateFmt'] = dateVisible ? wm.dateFormat : '';
    args['wmTimeFmt'] = timeVisible ? wm.timeFormat : '';
    args['wmCustomText'] = customText;
    args['wmFontSize'] = wm.fontSize.round();
    args['wmBold'] = wm.bold;
    args['wmBoxOpacity'] = wm.boxOpacity;
    args['wmAlignment'] = wm.alignment.name;
  }

  final result = await _channel.invokeMapMethod<String, dynamic>('launchArMeasure', args);
  if (result == null) return null;
  final path = result['path'] as String?;
  if (path == null) return null;
  return (
    path: path,
    distanceCm: result['distanceCm'] as double?,
    applyWatermark: result['applyWatermark'] as bool? ?? false,
  );
}

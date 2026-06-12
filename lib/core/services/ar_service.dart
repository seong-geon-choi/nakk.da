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
    final dateVisible = wm.lines.any((l) => l.type == WatermarkLineType.date && l.visible);
    final timeVisible = wm.lines.any((l) => l.type == WatermarkLineType.time && l.visible);
    final customText = wm.lines
        .where((l) =>
            l.type == WatermarkLineType.customText &&
            l.visible &&
            l.customText.trim().isNotEmpty)
        .map((l) => l.customText.trim())
        .join('\n');

    // 자유 위치(posX/posY)를 AR 라이브 프리뷰용 가장 가까운 코너로 변환
    // (실제 사진 워터마크는 Dart applyWatermark가 정확한 위치로 굽는다)
    final corner = wm.posX < 0.5
        ? (wm.posY < 0.5 ? 'topLeft' : 'bottomLeft')
        : (wm.posY < 0.5 ? 'topRight' : 'bottomRight');
    args['wmPosition'] = corner;
    args['wmPosX'] = wm.posX;
    args['wmPosY'] = wm.posY;
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
    posX: (result['posX'] as num?)?.toDouble(),
    posY: (result['posY'] as num?)?.toDouble(),
  );
}

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
    // 신 모델(컨테이너 + 박스 3종)을 AR 네이티브 라이브 프리뷰가 쓰는
    // 구식 단일 박스 인자로 변환한다. AR 프리뷰는 단일 스타일이라 대표 박스
    // (보이는 첫 박스)의 폰트 설정을 사용한다.
    // (실제 사진 워터마크는 Dart applyWatermark가 박스별로 정확히 굽는다.)
    WatermarkBox? boxOf(WatermarkLineType t) {
      for (final b in wm.boxes) {
        if (b.type == t && b.visible) return b;
      }
      return null;
    }

    final dateBox = boxOf(WatermarkLineType.date);
    final timeBox = boxOf(WatermarkLineType.time);
    final customText = wm.boxes
        .where((b) =>
            b.type == WatermarkLineType.customText &&
            b.visible &&
            b.customText.trim().isNotEmpty)
        .map((b) => b.customText.trim())
        .join('\n');

    final rep = wm.boxes.firstWhere(
      (b) => b.visible,
      orElse: () => wm.boxes.isNotEmpty ? wm.boxes.first : const WatermarkBox(type: WatermarkLineType.date),
    );

    // 컨테이너 위치를 AR 라이브 프리뷰용 가장 가까운 코너로 변환
    final corner = wm.containerPosX < 0.5
        ? (wm.containerPosY < 0.5 ? 'topLeft' : 'bottomLeft')
        : (wm.containerPosY < 0.5 ? 'topRight' : 'bottomRight');
    args['wmPosition'] = corner;
    args['wmPosX'] = wm.containerPosX;
    args['wmPosY'] = wm.containerPosY;
    args['wmDateFmt'] = dateBox != null ? dateBox.dateFormat : '';
    args['wmTimeFmt'] = timeBox != null ? timeBox.timeFormat : '';
    args['wmCustomText'] = customText;
    args['wmFontSize'] = rep.fontSize.round();
    args['wmBold'] = rep.weight != WatermarkWeight.normal;
    args['wmBoxOpacity'] = wm.bgOpacity;
    args['wmAlignment'] = rep.alignment.name;
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

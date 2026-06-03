import 'package:flutter/services.dart';

const _channel = MethodChannel('com.nakkda.nakkda/ar');

/// ARCore 측정 화면을 실행하고 결과를 반환.
/// [watermarkEnabled]: AR 카메라 진입 시 워터마크 토글 초기 상태.
/// 취소 또는 오류 시 null 반환.
Future<({String path, double? distanceCm, bool applyWatermark})?> launchArMeasure({
  bool watermarkEnabled = false,
}) async {
  final result = await _channel.invokeMapMethod<String, dynamic>(
    'launchArMeasure',
    {'watermarkEnabled': watermarkEnabled},
  );
  if (result == null) return null;
  final path = result['path'] as String?;
  if (path == null) return null;
  return (
    path: path,
    distanceCm: result['distanceCm'] as double?,
    applyWatermark: result['applyWatermark'] as bool? ?? false,
  );
}

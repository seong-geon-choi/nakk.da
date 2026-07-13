import 'package:flutter/services.dart';

const _channel = MethodChannel('com.sgchoisg.nakkda/accessibility');

Future<String?> getPendingVoiceResult() async {
  try {
    return await _channel.invokeMethod<String?>('getPendingResult');
  } catch (_) {
    return null;
  }
}

Future<void> clearPendingVoiceResult() async {
  try {
    await _channel.invokeMethod('clearPendingResult');
  } catch (_) {}
}

/// 앱이 포어그라운드일 때 AccessibilityService에서 직접 결과를 수신
void setVoiceResultHandler(void Function(String text) onResult) {
  _channel.setMethodCallHandler((call) async {
    if (call.method == 'onVoiceResult') {
      onResult(call.arguments as String);
    }
  });
}

import 'package:flutter/services.dart';

const _channel = MethodChannel('com.nakkda.nakkda/accessibility');

Future<bool> isAccessibilityServiceEnabled() async {
  try {
    return await _channel.invokeMethod<bool>('isServiceEnabled') ?? false;
  } catch (_) {
    return false;
  }
}

Future<void> openAccessibilitySettings() async {
  try {
    await _channel.invokeMethod('openAccessibilitySettings');
  } catch (_) {}
}

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

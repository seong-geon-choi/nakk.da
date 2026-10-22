import 'package:flutter/services.dart';

/// 블루투스 리모컨/이어폰 버튼 → 조과 카운트 액션 매핑의 Flutter 측 래퍼.
/// 매핑 저장소는 네이티브(prefs)이며, 백그라운드 서비스/카운터가 직접 읽는다.
/// action 형식: "add:0"(어종0 +1) / "rem:0"(어종0 −1) / "add:1" / "rem:1".
class BtRemoteService {
  static const _channel = MethodChannel('com.sgchoisg.nakkda/btremote');

  /// 등록(캡처) 중 리모컨 버튼이 눌리면 호출: (keyCode, 미디어키 여부).
  static void Function(int keyCode, bool isMedia)? onKey;

  static bool _handlerSet = false;
  static void _ensureHandler() {
    if (_handlerSet) return;
    _handlerSet = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onRemoteKey') {
        final args = (call.arguments as Map?) ?? const {};
        final kc = args['keyCode'] as int?;
        final media = args['isMedia'] as bool? ?? false;
        if (kc != null) onKey?.call(kc, media);
      }
      return null;
    });
  }

  /// 현재 매핑(action→keyCode).
  static Future<Map<String, int>> getKeyMap() async {
    try {
      final m = await _channel.invokeMapMethod<String, int>('getKeyMap');
      return m ?? {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> setKey(String action, int keyCode) async {
    try {
      await _channel.invokeMethod('setKey', {'action': action, 'keyCode': keyCode});
    } catch (_) {}
  }

  static Future<void> clearKey(String action) async {
    try {
      await _channel.invokeMethod('clearKey', {'action': action});
    } catch (_) {}
  }

  /// 등록 모드 시작 — 임시 세션으로 미디어/비미디어 키를 캡처해 [onKey]로 올린다.
  static Future<void> captureStart() async {
    _ensureHandler();
    try {
      await _channel.invokeMethod('captureStart');
    } catch (_) {}
  }

  static Future<void> captureStop() async {
    try {
      await _channel.invokeMethod('captureStop');
    } catch (_) {}
  }
}

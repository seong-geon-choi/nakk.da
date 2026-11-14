import 'package:flutter/services.dart';

/// 폰에서 관리하는 워치 앱 설정의 Flutter 측 래퍼.
/// 저장과 워치 동기화(Data Layer)는 네이티브 WatchSettings.kt가 담당한다.
/// 키: bright_on(0=시스템), dim_level, dim_idle_sec(0=어둡게 안 함), keep_on,
///     color_0, color_1(워치 팔레트 인덱스, 아직 모르면 없음), vibrate, start_page.
class WatchSettingsService {
  static const _channel = MethodChannel('com.sgchoisg.nakkda/watch');

  static Future<Map<String, dynamic>> get() async {
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('getWatchSettings');
      return m ?? {};
    } catch (_) {
      return {};
    }
  }

  /// 바뀐 값만 넘기면 저장 후 워치로 전송된다.
  static Future<void> set(Map<String, dynamic> values) async {
    try {
      await _channel.invokeMethod('setWatchSettings', values);
    } catch (_) {}
  }
}

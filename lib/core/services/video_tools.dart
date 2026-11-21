import 'package:flutter/services.dart';

/// 동영상 도구(네이티브 VideoTools.kt) — 블랙박스 설정·잘라 붙이기·녹화 중 화면 제어.
class VideoTools {
  static const _ch = MethodChannel('nakkda/video');

  /// 블랙박스 모드 여부와 저장 길이(분). 실패 시 일반 모드·2분.
  static Future<({bool blackbox, int minutes})> settings() async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('getSettings');
      return (
        blackbox: (m?['video_mode'] as int? ?? 0) == 1,
        minutes: m?['bb_min'] as int? ?? 2,
      );
    } catch (_) {
      return (blackbox: false, minutes: 2);
    }
  }

  /// 바뀐 값만 저장(워치 설정과 함께 워치로 동기화됨).
  static Future<void> setSettings({bool? blackbox, int? minutes}) async {
    try {
      await _ch.invokeMethod('setSettings', {
        if (blackbox != null) 'video_mode': blackbox ? 1 : 0,
        'bb_min': ?minutes,
      });
    } catch (_) {}
  }

  /// 화면 켜짐 유지와 창 밝기(0~1, null=시스템 밝기).
  static Future<void> screen({required bool keepOn, double? brightness}) async {
    try {
      await _ch.invokeMethod(
          'screen', {'keepOn': keepOn, 'brightness': brightness ?? -1.0});
    } catch (_) {}
  }

  /// 배터리 %와 여유 저장 공간(바이트).
  static Future<({int battery, int freeBytes})> status() async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('status');
      return (
        battery: m?['battery'] as int? ?? 100,
        freeBytes: (m?['freeBytes'] as num?)?.toInt() ?? 1 << 40,
      );
    } catch (_) {
      return (battery: 100, freeBytes: 1 << 40);
    }
  }

  /// [paths](시간순 조각)의 마지막 [keepMs]만 [out]에 저장. 저장 길이(ms) 반환.
  static Future<int> trimTail(List<String> paths, int keepMs, String out) async =>
      await _ch.invokeMethod<int>(
          'trimTail', {'paths': paths, 'keepMs': keepMs, 'out': out}) ??
      0;

  /// [path]의 [startMs, endMs] 구간을 [out]에 저장. 저장 길이(ms) 반환.
  static Future<int> trim(String path, int startMs, int endMs, String out) async =>
      await _ch.invokeMethod<int>('trim',
          {'path': path, 'startMs': startMs, 'endMs': endMs, 'out': out}) ??
      0;

  /// 영상 길이(ms). 실패 시 null.
  static Future<int?> durationMs(String path) async {
    try {
      return await _ch.invokeMethod<int>('duration', {'path': path});
    } catch (_) {
      return null;
    }
  }

  /// 자른 파일 [src]로 원본 [target](파일 경로 또는 content://)을 덮어쓴다. [src]는 지운다.
  static Future<void> replace(String src, String target) =>
      _ch.invokeMethod('replace', {'src': src, 'target': target});
}

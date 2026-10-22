import 'package:flutter/services.dart';

/// 조과 기록(알림/잠금화면 카운터)의 Flutter 측 래퍼.
/// 기록은 네이티브가 MD 파일을 **직접** 추가/삭제하므로(캐시·flush 없음),
/// Flutter는 세션 제어와 설정 동기화(어종·저장경로)만 담당한다. 트래킹과 동일 채널.
class CatchLogService {
  static const _channel = MethodChannel('com.sgchoisg.nakkda/tracking');

  Future<void> startCatchSession(List<String> species) async {
    try {
      await _channel.invokeMethod('startCatchSession', {'species': species});
    } catch (_) {}
  }

  Future<void> stopCatchSession() async {
    try {
      await _channel.invokeMethod('stopCatchSession');
    } catch (_) {}
  }

  /// 카운터/알림이 쓸 어종 목록 + 저장 경로를 네이티브에 동기화.
  /// (네이티브가 그 경로의 그날 MD 파일을 직접 읽고/쓴다.)
  Future<void> syncConfig(List<String> species, String savePath) async {
    try {
      await _channel.invokeMethod(
          'catchSyncConfig', {'species': species, 'savePath': savePath});
    } catch (_) {}
  }

  Future<bool> isCatchSession() async {
    try {
      return await _channel.invokeMethod<bool>('isCatchSession') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 잠금화면 카운터 화면(CatchCounterActivity)을 직접 띄운다.
  Future<void> openCounter() async {
    try {
      await _channel.invokeMethod('openCatchCounter');
    } catch (_) {}
  }
}

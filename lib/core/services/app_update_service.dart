import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

/// Google Play 인앱 업데이트 래퍼.
/// Play 스토어로 설치된 안드로이드 앱에서만 동작하며, 그 외(사이드로드·iOS·
/// 네트워크 오류 등)에서는 조용히 '업데이트 없음'으로 처리한다.
class AppUpdateService {
  /// Play 스토어에 더 높은 버전이 있고 즉시 업데이트가 가능하면 true.
  static Future<bool> isUpdateAvailable() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final info = await InAppUpdate.checkForUpdate();
      return info.updateAvailability == UpdateAvailability.updateAvailable &&
          info.immediateUpdateAllowed;
    } catch (_) {
      return false;
    }
  }

  /// 구글 네이티브 즉시 업데이트 플로우(다운로드+설치+재시작)를 실행한다.
  /// 사용자가 중간에 취소하거나 실패하면 무시한다(다음 실행 때 다시 안내됨).
  static Future<void> performImmediateUpdate() async {
    try {
      await InAppUpdate.performImmediateUpdate();
    } catch (_) {}
  }
}

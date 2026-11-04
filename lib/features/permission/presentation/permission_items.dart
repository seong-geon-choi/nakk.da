import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// 권한 표시 항목(초기 요청 화면·설정 권한 점검이 공유하는 단일 정의).
/// 한 항목이 여러 권한을 묶을 수 있고(사진/동영상), 묶인 권한이 모두 허용돼야 granted.
class PermissionItem {
  final IconData icon;
  final String title;
  final String desc;
  final List<Permission> permissions; // 모두 허용돼야 granted
  const PermissionItem(this.icon, this.title, this.desc, this.permissions);
}

/// 필수 런타임 권한(초기 요청 대상 + 설정 "권한 점검" 개수 기준). 표시 순서 통일.
/// - '위치'는 사용 중(foreground) 기준으로 판정하고, 항상 허용 여부는 범위로 표시한다.
/// - '사진/동영상'은 photos+videos를 한 항목으로 묶어 둘 다 허용해야 ✓.
const List<PermissionItem> kRequiredPermissionItems = [
  PermissionItem(Icons.mic, '마이크', '음성 메모 녹음', [Permission.microphone]),
  PermissionItem(Icons.location_on, '위치', 'GPS 좌표·날씨/물때 (외부 전송 포함)',
      [Permission.locationWhenInUse]),
  PermissionItem(Icons.camera_alt, '카메라', '사진·동영상 촬영', [Permission.camera]),
  PermissionItem(Icons.photo_library_outlined, '사진/동영상', '갤러리 선택·첨부',
      [Permission.photos, Permission.videos]),
  PermissionItem(Icons.notifications_outlined, '알림', '음성 메모·상태 알림',
      [Permission.notification]),
];

/// 특수 접근(설정 "권한 점검"에서 상태만 표시, 개수 제외; 해당 기능을 켤 때 각각 요청).
/// 위치(항상 허용)은 위치 행의 '범위'로 표시하므로 여기엔 오버레이만 둔다.
const List<PermissionItem> kSpecialAccessItems = [
  PermissionItem(Icons.open_in_new, '다른 앱 위에 표시', '흔들기로 잠금화면 카메라 실행',
      [Permission.systemAlertWindow]),
];

/// 권한 항목을 탭했을 때 그 권한(들)을 다시 요청/설정하는 공용 동작.
/// (초기 요청 화면·설정 "권한 점검"이 공유한다.)
/// - 특수 접근(오버레이): request()가 전용 설정 화면을 연다.
/// - 미결정 런타임 권한: 시스템 팝업을 띄운다.
/// - 영구 거부/제한·이미 허용: 팝업이 안 뜨므로(안드로이드 정책) 앱 설정으로 이동
///   (켜기 또는 위치 '항상 허용' 범위 조정·해제).
/// 위치 항목은 호출 전에 공개·동의(ensureLocationDisclosure)를 받아야 하므로 호출측이 처리한다.
Future<void> requestPermissionItem(PermissionItem item) async {
  // 특수 접근(오버레이 등): request()가 해당 설정 화면을 연다.
  if (item.permissions.contains(Permission.systemAlertWindow)) {
    for (final p in item.permissions) {
      if (!await p.isGranted) await p.request();
    }
    return;
  }
  // 하나라도 영구 거부/제한이면 시스템 팝업이 안 뜨므로 앱 설정으로 안내.
  for (final p in item.permissions) {
    final st = await p.status;
    if (st.isPermanentlyDenied || st.isRestricted) {
      await openAppSettings();
      return;
    }
  }
  // 이미 모두 허용 → 끄기/범위 조정을 위해 앱 설정으로.
  final allGranted =
      (await Future.wait(item.permissions.map((p) => p.isGranted)))
          .every((g) => g);
  if (allGranted) {
    await openAppSettings();
    return;
  }
  // 미결정 권한 → 시스템 팝업 요청.
  await item.permissions.request();
}

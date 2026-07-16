import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kLocationDisclosedKey = 'location_disclosure_accepted';

/// 위치 데이터에 대한 앱 내 명시적 공개 + 동의 다이얼로그.
///
/// Google 사용자 데이터 정책은 위치 권한을 요청/수집하기 전에, 앱 화면 안에서
/// 어떤 위치 데이터를 어떻게(백그라운드 사용·외부 전송 포함) 쓰는지 고지하고
/// 명시적 동의를 받도록 요구한다. 위치 권한을 요청하는 모든 지점에서 요청 직전에
/// 호출한다. 한 번 동의하면 이후에는 다시 묻지 않는다.
///
/// 동의(또는 이미 동의함) 시 true, 취소 시 false.
Future<bool> ensureLocationDisclosure(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_kLocationDisclosedKey) ?? false) return true;
  if (!context.mounted) return false;

  final ok = await showDialog<bool>(
    context: context,
    builder: (dctx) => AlertDialog(
      title: const Text('위치 정보 사용 안내'),
      content: const SingleChildScrollView(
        child: Text(
          '낚.다는 낚시 기록을 위해 기기의 위치(GPS) 정보를 사용합니다.\n\n'
          '• 메모에 낚시 위치(GPS 좌표)를 기록합니다\n'
          '• 사진 워터마크에 촬영 지역(시/군/구/동)을 표시합니다\n'
          '• 현재 위치의 날씨·물때 정보를 제공합니다 — 이때 위치 좌표가 외부 '
          '서비스(Open-Meteo, 국립해양조사원)로 전송됩니다\n\n'
          '다음 선택 기능을 켜면, 앱이 백그라운드(화면이 꺼져 있거나 앱을 보고 '
          '있지 않을 때)에서도 위치를 사용합니다:\n'
          '• 이동 경로 기록(트래킹): 출조 중 이동 경로를 기록해 지도·일지에 표시\n'
          '• 지점 접근 알림: 저장한 낚시 포인트 근처에 도착하면 알림\n'
          '두 기능은 실행 중 상시 알림을 표시하며, 그 알림에서 즉시 중지할 수 '
          '있습니다.\n\n'
          '위치 관련 기능은 모두 선택 사항이며 설정에서 언제든 끌 수 있습니다.\n'
          '동의하시면 위치 권한 요청으로 진행합니다.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dctx).pop(false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dctx).pop(true),
          child: const Text('동의'),
        ),
      ],
    ),
  );

  if (ok == true) {
    await prefs.setBool(_kLocationDisclosedKey, true);
    return true;
  }
  return false;
}

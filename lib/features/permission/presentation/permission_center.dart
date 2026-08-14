import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// 설정의 "권한 점검" — 모든 권한 상태를 한눈에 보여주고, 변경은 시스템 앱 설정에서.
///
/// 앱은 한 번 결정된 권한을 다시 팝업으로 요청할 수 없으므로(안드로이드 정책),
/// 이 화면은 상태 확인 + "앱 설정 열기" 통로만 제공한다. 특별 접근 권한(오버레이·
/// 위치 항상)은 해당 기능을 켤 때 각각 안내되며, 여기서는 상태만 표시한다.
class PermissionCenterScreen extends StatefulWidget {
  const PermissionCenterScreen({super.key});

  @override
  State<PermissionCenterScreen> createState() => _PermissionCenterScreenState();
}

class _PermItem {
  final IconData icon;
  final String title;
  final String desc;
  final Permission key;
  const _PermItem(this.icon, this.title, this.desc, this.key);
}

const _items = <_PermItem>[
  _PermItem(Icons.mic, '마이크', '음성 메모 녹음', Permission.microphone),
  _PermItem(Icons.camera_alt, '카메라', '사진·동영상 촬영', Permission.camera),
  _PermItem(Icons.location_on, '위치(사용 중)', 'GPS 좌표·날씨/물때',
      Permission.locationWhenInUse),
  _PermItem(Icons.photo_library_outlined, '사진/동영상', '갤러리 선택·저장',
      Permission.photos),
  _PermItem(Icons.notifications_outlined, '알림', '음성 메모·상태 알림',
      Permission.notification),
  _PermItem(Icons.my_location, '위치(항상 허용)', '경로 기록·출퇴근 알림',
      Permission.locationAlways),
  _PermItem(Icons.open_in_new, '다른 앱 위에 표시', '흔들기로 잠금화면 카메라 실행',
      Permission.systemAlertWindow),
];

class _PermissionCenterScreenState extends State<PermissionCenterScreen>
    with WidgetsBindingObserver {
  final Map<Permission, bool> _granted = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 앱 설정에서 권한을 바꾸고 돌아오면 상태를 다시 읽는다.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    for (final it in _items) {
      _granted[it.key] = await it.key.isGranted;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('권한 점검')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            ..._items.map(_row),
            const SizedBox(height: 8),
            Text(
              '권한을 켜거나 끄려면 앱 설정에서 변경하세요.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              onPressed: () async {
                await openAppSettings();
                await _refresh();
              },
              icon: const Icon(Icons.settings_outlined),
              label: const Text('앱 설정 열기'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(_PermItem it) {
    final granted = _granted[it.key] ?? false;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(it.icon, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(it.title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                Text(it.desc, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            granted ? Icons.check_circle : Icons.cancel_outlined,
            color: granted ? Colors.green : cs.outline,
            size: 24,
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'permission_items.dart';

/// 설정의 "권한 점검" — 모든 권한 상태를 한눈에 보여주고, 변경은 시스템 앱 설정에서.
///
/// 앱은 한 번 결정된 권한을 다시 팝업으로 요청할 수 없으므로(안드로이드 정책),
/// 이 화면은 상태 확인 + "앱 설정 열기" 통로만 제공한다. 표시 목록은 초기 요청 화면과
/// 동일한 정의([kRequiredPermissionItems])를 공유한다. 위치는 한 행으로 두고 항상 허용
/// 여부를 '범위'로 표시하며, 특수 접근(오버레이)은 상태만 별도로 보여준다.
class PermissionCenterScreen extends StatefulWidget {
  const PermissionCenterScreen({super.key});

  @override
  State<PermissionCenterScreen> createState() => _PermissionCenterScreenState();
}

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
    final perms = <Permission>{
      for (final it in kRequiredPermissionItems) ...it.permissions,
      for (final it in kSpecialAccessItems) ...it.permissions,
      Permission.locationAlways, // 위치 행의 범위(항상 허용) 표시용
    };
    for (final p in perms) {
      _granted[p] = await p.isGranted;
    }
    if (mounted) setState(() {});
  }

  /// 위치 권한의 현재 범위. 항상 허용 ⊃ 사용 중만 ⊃ 꺼짐.
  String _locationScope() {
    if (_granted[Permission.locationAlways] == true) return '항상 허용';
    if (_granted[Permission.locationWhenInUse] == true) return '사용 중만';
    return '꺼짐';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('권한 점검')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            ...kRequiredPermissionItems.map(_row),
            const SizedBox(height: 16),
            Text('특수 접근',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            ...kSpecialAccessItems.map(_row),
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

  Widget _row(PermissionItem it) {
    // 묶인 권한(사진/동영상)은 모두 허용돼야 ✓.
    final granted = it.permissions.every((p) => _granted[p] ?? false);
    // 위치 행은 항상 허용 여부를 범위로 덧붙여 표시.
    final isLocation = it.permissions.contains(Permission.locationWhenInUse);
    final desc =
        isLocation ? '${it.desc} · 현재: ${_locationScope()}' : it.desc;
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
                Text(desc, style: Theme.of(context).textTheme.bodySmall),
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

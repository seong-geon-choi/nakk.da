import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../settings/domain/models/app_settings.dart';
import '../../settings/presentation/settings_provider.dart';
import 'location_disclosure.dart';
import 'permission_items.dart';

/// 설정의 "권한 점검" — 모든 권한 상태를 한눈에 보여주고, 항목을 누르면 그 권한을
/// 다시 요청/설정할 수 있다(미결정이면 시스템 팝업, 영구 거부/이미 허용이면 앱 설정).
///
/// 표시 목록은 초기 요청 화면과 동일한 정의([kRequiredPermissionItems])를 공유한다.
/// 위치는 한 행으로 두고 항상 허용 여부를 '범위'로 표시하며, 특수 접근(오버레이)은
/// 상태만 별도로 보여준다. 메모·사진 저장 위치 재지정도 이 화면에서 한다.
class PermissionCenterScreen extends ConsumerStatefulWidget {
  const PermissionCenterScreen({super.key});

  @override
  ConsumerState<PermissionCenterScreen> createState() =>
      _PermissionCenterScreenState();
}

class _PermissionCenterScreenState extends ConsumerState<PermissionCenterScreen>
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

  /// 모든 시스템 권한을 다시 요청한다.
  /// - 아직 결정되지 않은 런타임 권한: 시스템 팝업이 뜬다.
  /// - 특수 접근(오버레이): 해당 설정 화면으로 이동.
  /// - 영구 거부된 권한은 팝업이 안 뜨므로(안드로이드 정책) "앱 설정 열기"로 안내.
  Future<void> _requestAll() async {
    final runtime = <Permission>{
      for (final it in kRequiredPermissionItems) ...it.permissions,
    }.toList();
    final results = await runtime.request();
    for (final it in kSpecialAccessItems) {
      for (final p in it.permissions) {
        if (!(await p.isGranted)) await p.request();
      }
    }
    await _refresh();
    if (!mounted) return;
    final someDenied = results.values.any((s) => !s.isGranted);
    if (someDenied) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('일부 권한은 "앱 설정 열기"에서 직접 켜야 합니다.'),
      ));
    }
  }

  /// 항목 탭 → 해당 권한을 다시 요청/설정한다(위치는 공개·동의 먼저).
  Future<void> _onTapItem(PermissionItem it) async {
    if (it.permissions.contains(Permission.locationWhenInUse)) {
      final ok = await ensureLocationDisclosure(context);
      if (!mounted || !ok) return;
    }
    await requestPermissionItem(it);
    await _refresh();
  }

  /// 위치 권한의 현재 범위. 항상 허용 ⊃ 사용 중만 ⊃ 꺼짐.
  String _locationScope() {
    if (_granted[Permission.locationAlways] == true) return '항상 허용';
    if (_granted[Permission.locationWhenInUse] == true) return '사용 중만';
    return '꺼짐';
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('권한 점검')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            ...kRequiredPermissionItems.map(_row),
            const SizedBox(height: 16),
            Text('특수 접근', style: _labelStyle(context)),
            const SizedBox(height: 4),
            ...kSpecialAccessItems.map(_row),
            if (settings != null) ...[
              const SizedBox(height: 16),
              Text('저장 위치', style: _labelStyle(context)),
              const SizedBox(height: 4),
              _memoSaveTile(settings),
              _photoSaveTile(settings),
            ],
            const SizedBox(height: 8),
            Text(
              '항목을 누르면 해당 권한을 다시 설정할 수 있습니다.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style:
                  FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _requestAll,
              icon: const Icon(Icons.refresh),
              label: const Text('모든 권한 다시 요청'),
            ),
            const SizedBox(height: 8),
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

  TextStyle? _labelStyle(BuildContext context) =>
      Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant);

  Widget _row(PermissionItem it) {
    // 묶인 권한(사진/동영상)은 모두 허용돼야 ✓.
    final granted = it.permissions.every((p) => _granted[p] ?? false);
    // 위치 행은 항상 허용 여부를 범위로 덧붙여 표시.
    final isLocation = it.permissions.contains(Permission.locationWhenInUse);
    final desc =
        isLocation ? '${it.desc} · 현재: ${_locationScope()}' : it.desc;
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _onTapItem(it),
      child: Padding(
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
      ),
    );
  }

  /// 메모(.md) 저장 폴더 재지정 — 탭하면 SAF 폴더 선택.
  Widget _memoSaveTile(AppSettings settings) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.folder_outlined),
      title: const Text('메모 저장 위치'),
      subtitle: Text(
        settings.saveDisplayPath.isNotEmpty
            ? settings.saveDisplayPath
            : settings.needsFolderSetup
                ? '폴더를 선택해 주세요'
                : settings.savePath,
        style: settings.needsFolderSetup ? TextStyle(color: cs.error) : null,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: settings.needsFolderSetup
          ? const Icon(Icons.warning_amber, color: Colors.orange)
          : null,
      onTap: () => ref.read(settingsProvider.notifier).pickSaveFolder(),
    );
  }

  /// 카메라 사진 저장 폴더 재지정 — 탭하면 SAF 폴더 선택.
  Widget _photoSaveTile(AppSettings settings) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.photo_library_outlined),
      title: const Text('카메라 사진 저장 위치'),
      subtitle: Text(
        settings.photoSavePath,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => ref.read(settingsProvider.notifier).pickPhotoSaveFolder(),
    );
  }
}

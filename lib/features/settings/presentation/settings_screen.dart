import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'settings_provider.dart';
import '../domain/models/app_settings.dart';
import 'watermark_settings_screen.dart';
import '../../permission/presentation/permission_provider.dart';
import '../../file_list/presentation/file_list_provider.dart';
import '../../file_list/domain/models/file_summary.dart';
import '../../memo/presentation/memo_editor_screen.dart';
import '../../../core/constants/api_keys.dart';
import '../../../core/widgets/permission_status_chip.dart';
import '../../../core/services/accessibility_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);
    final permAsync = ref.watch(permissionStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('설정'),
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (settings) => ListView(
          children: [
            // ── 저장 섹션 ─────────────────────────────
            const _SectionHeader(label: '저장'),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('메모 저장 위치'),
              subtitle: Text(
                settings.savePath,
                style: const TextStyle(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _showSavePathDialog(context, ref, settings.savePath),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('사진 저장 위치'),
              subtitle: Text(
                settings.photoSavePath,
                style: const TextStyle(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _showPhotoSavePathDialog(context, ref, settings.photoSavePath),
            ),

            // ── 표시 섹션 ─────────────────────────────
            const _SectionHeader(label: '표시'),
            SwitchListTile(
              secondary: const Icon(Icons.add_location_alt_outlined),
              title: const Text('위치 추가 버튼 표시'),
              subtitle: const Text('메인 화면 하단에 위치 추가 버튼을 표시합니다'),
              value: settings.showLocationButton,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).updateShowLocationButton(v),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.save_outlined),
              title: const Text('음성 입력 후 바로 저장'),
              subtitle: const Text('음성 텍스트 변환 완료 시 확인 없이 자동 저장합니다'),
              value: settings.autoSaveVoice,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).updateAutoSaveVoice(v),
            ),

            // ── API 섹션 ──────────────────────────────
            const _SectionHeader(label: 'API 키'),
            ListTile(
              leading: const Icon(Icons.vpn_key_outlined),
              title: const Text('국립해양조사원 API 키'),
              subtitle: Text(
                settings.khoaApiKey?.isNotEmpty == true
                    ? '사용자 키 적용 중'
                    : '기본 키 사용 중',
                style: const TextStyle(fontSize: 12),
              ),
              onTap: () => _showApiKeyDialog(context, ref, settings.khoaApiKey),
            ),

            // ── 사진 워터마크 섹션 ───────────────────────
            const _SectionHeader(label: '사진 워터마크'),
            ListTile(
              leading: const Icon(Icons.water_outlined),
              title: const Text('워터마크 설정'),
              subtitle: Text(settings.watermark.enabled ? '활성화됨' : '비활성화됨'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const WatermarkSettingsScreen(),
                ),
              ),
              trailing: Switch(
                value: settings.watermark.enabled,
                onChanged: (v) => ref
                    .read(settingsProvider.notifier)
                    .updateWatermark(settings.watermark.copyWith(enabled: v)),
              ),
            ),

            // ── 볼륨 버튼 음성 입력 섹션 ─────────────────
            const _SectionHeader(label: '볼륨 버튼 음성 입력'),
            const _AccessibilityTile(),

            // ── 권한 섹션 ─────────────────────────────
            const _SectionHeader(label: '권한'),
            ...permAsync.when(
              loading: () => [const ListTile(title: Text('권한 확인 중...'))],
              error: (e, _) => [const ListTile(title: Text('권한 확인 실패'))],
              data: (statuses) => _permissionItems(context, statuses),
            ),

            // ── 고급 섹션 ─────────────────────────────
            const _SectionHeader(label: '고급'),
            ListTile(
              leading: const Icon(Icons.edit_document),
              title: const Text('메모 원본 수정하기'),
              subtitle: const Text('마크다운 파일을 직접 편집합니다'),
              onTap: () => _openMemoEditor(context, ref),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  List<Widget> _permissionItems(
    BuildContext context,
    Map<Permission, PermissionStatus> statuses,
  ) {
    final items = [
      (Permission.microphone, '마이크', '음성 메모 녹음'),
      (Permission.locationWhenInUse, '위치', 'GPS 좌표 기록'),
      (Permission.camera, '카메라', '사진 촬영'),
      (Permission.photos, '사진', '갤러리 사진 선택'),
      (Permission.notification, '알림', '음성 메모 상태 표시'),
      (Permission.manageExternalStorage, '전체 파일 접근', 'DCIM 영구 보관'),
    ];

    return items.map((item) {
      final (perm, label, desc) = item;
      final isGranted = statuses[perm]?.isGranted ?? false;
      return ListTile(
        title: Text(label),
        subtitle: Text(desc, style: const TextStyle(fontSize: 12)),
        trailing: PermissionStatusChip(isGranted: isGranted),
        onTap: isGranted
            ? null
            : () => perm == Permission.manageExternalStorage
                ? perm.request()
                : openAppSettings(),
      );
    }).toList();
  }

  Future<void> _showApiKeyDialog(
    BuildContext context,
    WidgetRef ref,
    String? currentKey,
  ) async {
    final controller = TextEditingController(text: currentKey ?? '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('국립해양조사원 API 키'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'API 키 (디코딩 키)',
                border: OutlineInputBorder(),
                hintText: '비워두면 기본 키 사용',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '기본 키: ${kDefaultKhoaApiKey.length > 8 ? '${kDefaultKhoaApiKey.substring(0, 8)}...' : kDefaultKhoaApiKey}\n'
              'data.go.kr 마이페이지 → 개발계정 → 디코딩 키',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref
          .read(settingsProvider.notifier)
          .updateKhoaApiKey(controller.text.trim());
    }
    controller.dispose();
  }

  Future<void> _showPhotoSavePathDialog(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final controller = TextEditingController(text: current);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('사진 저장 위치 변경'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: '저장 경로',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '⚠️ 기존 사진은 이동되지 않습니다.\n'
              'DCIM 등 공용 폴더 접근은 파일 관리 권한이 필요합니다.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      final newPath = controller.text.trim();
      if (newPath.isNotEmpty && newPath != current) {
        await ref.read(settingsProvider.notifier).updatePhotoSavePath(newPath);
      }
    }
    controller.dispose();
  }

  Future<void> _showSavePathDialog(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final controller = TextEditingController(text: current);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('저장 위치 변경'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: '저장 경로',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '⚠️ 기존 파일은 이동되지 않습니다.\n변경 후에는 새 위치에 파일이 저장됩니다.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      final newPath = controller.text.trim();
      if (newPath.isNotEmpty && newPath != current) {
        await ref.read(settingsProvider.notifier).updateSavePath(newPath);
      }
    }
    controller.dispose();
  }
}

Future<void> _openMemoEditor(BuildContext context, WidgetRef ref) async {
  final settings = ref.read(settingsProvider).valueOrNull;
  if (settings == null) return;

  final files = await ref
      .read(fileListRepositoryProvider)
      .listFiles(settings.savePath);

  if (!context.mounted) return;

  if (files.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('저장된 메모 파일이 없습니다')),
    );
    return;
  }

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _MemoFilePicker(
      files: files,
      onSelect: (file) {
        Navigator.of(context).pop(); // 시트 닫기
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => MemoEditorScreen(
            filePath: file.filePath,
            displayName: file.displayName,
          ),
        ));
      },
    ),
  );
}

class _MemoFilePicker extends StatelessWidget {
  final List<FileSummary> files;
  final void Function(FileSummary) onSelect;

  const _MemoFilePicker({required this.files, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text('파일 선택',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: mq.size.height * 0.5,
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: files.length,
              itemBuilder: (_, i) {
                final file = files[i];
                return ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(file.displayName),
                  subtitle: Text('메모 ${file.entryCount}개',
                      style: const TextStyle(fontSize: 12)),
                  onTap: () => onSelect(file),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AccessibilityTile extends StatefulWidget {
  const _AccessibilityTile();

  @override
  State<_AccessibilityTile> createState() => _AccessibilityTileState();
}

class _AccessibilityTileState extends State<_AccessibilityTile>
    with WidgetsBindingObserver {
  bool _enabled = false;

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
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final enabled = await isAccessibilityServiceEnabled();
    if (mounted) setState(() => _enabled = enabled);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: Icon(
            _enabled ? Icons.volume_up : Icons.volume_off_outlined,
            color: _enabled ? Colors.green : null,
          ),
          title: const Text('볼륨 ↑ 두 번 → 음성 메모'),
          subtitle: Text(
            _enabled ? '활성화됨 — 잠금 화면에서도 동작합니다' : '비활성화됨',
            style: TextStyle(
              fontSize: 12,
              color: _enabled ? Colors.green : null,
            ),
          ),
          trailing: _enabled
              ? const Icon(Icons.check_circle, color: Colors.green)
              : FilledButton(
                  onPressed: () async {
                    await openAccessibilitySettings();
                  },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('활성화'),
                ),
        ),
        if (!_enabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '활성화 버튼 → 접근성 → 설치된 서비스 → 낚.다 음성 메모 → 켜기',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}


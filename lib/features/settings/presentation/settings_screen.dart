import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'settings_provider.dart';
import '../../backup/presentation/backup_provider.dart';
import '../domain/models/app_settings.dart';
import 'watermark_settings_screen.dart';
import '../../permission/presentation/permission_provider.dart';
import '../../file_list/presentation/file_list_provider.dart';
import '../../file_list/domain/models/file_summary.dart';
import '../../memo/presentation/memo_editor_screen.dart';
import '../../../core/constants/api_keys.dart';
import '../../../core/widgets/permission_status_chip.dart';
import '../../../core/services/accessibility_service.dart';
import '../../../core/utils/media_scanner.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(permissionStatusProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final permAsync = ref.watch(permissionStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('설정'),
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (settings) => ListTileTheme(
          data: _subtitleTheme(context),
          child: ListView(
          children: [
            // ── 저장 섹션 ─────────────────────────────
            const _SectionHeader(label: '저장'),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('저장 위치 변경'),
              subtitle: Text(
                settings.needsFolderSetup
                    ? '폴더를 선택해 주세요'
                    : '메모 저장 경로와 사진 저장 경로를 변경합니다',
                style: settings.needsFolderSetup
                    ? TextStyle(color: Theme.of(context).colorScheme.error)
                    : null,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: settings.needsFolderSetup
                  ? const Icon(Icons.warning_amber, color: Colors.orange)
                  : const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const _SaveLocationSubScreen()),
              ),
            ),

            // ── 표시 섹션 ─────────────────────────────
            const _SectionHeader(label: '표시'),
            SwitchListTile(
              secondary: const Icon(Icons.add_location_alt_outlined),
              title: const Text('환경 정보 추가 버튼 표시'),
              subtitle: const Text('메인 화면 하단에 환경 정보 추가 버튼을 표시합니다'),
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
            SwitchListTile(
              secondary: const Icon(Icons.place_outlined),
              title: const Text('메모 이름에 지역정보 표시'),
              subtitle: const Text('메모 목록에서 날짜 옆에 촬영 지역 주소를 표시합니다'),
              value: settings.showAddressInMemoName,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).updateShowAddressInMemoName(v),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.phishing),
              title: const Text('낚시용 입력 항목'),
              subtitle:
                  const Text('메모 작성 시 어종 관련 항목을 포함/제외합니다'),
              value: settings.showCatchInput,
              onChanged: (v) =>
                  ref.read(settingsProvider.notifier).updateShowCatchInput(v),
            ),

            // ── 어종 섹션 ─────────────────────────────
            const _SectionHeader(label: '어종'),
            ListTile(
              leading: const Icon(Icons.set_meal_outlined),
              title: const Text('어종 목록 관리'),
              subtitle: Text(
                  '${settings.visibleFishSpecies.length}/${settings.fishSpecies.length} (선택가능/자동인식)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const _FishSpeciesSubScreen()),
              ),
            ),

            // ── 사진 워터마크 섹션 ───────────────────────
            const _SectionHeader(label: '사진 워터마크'),
            ListTile(
              leading: const Icon(Icons.water_drop),
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

            // ── 빠른 메모 실행 섹션 ──────────────────────
            const _SectionHeader(label: '빠른 메모 실행'),
            ListTile(
              leading: const Icon(Icons.flash_on_outlined),
              title: const Text('실행 방법'),
              subtitle: Text(_quickLaunchModeLabel(settings.quickLaunchMode)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const _QuickLaunchSubScreen()),
              ),
            ),

            // ── 위치 트래킹 섹션 ──────────────────────────
            const _SectionHeader(label: '위치 트래킹'),
            ListTile(
              leading: const Icon(Icons.route_outlined),
              title: const Text('이동 경로 기록'),
              subtitle: Text('기록 간격: ${settings.trackingIntervalMeters}m'),
              trailing: Switch(
                value: settings.showTrackingButton,
                onChanged: (v) => ref
                    .read(settingsProvider.notifier)
                    .updateShowTrackingButton(v),
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const _TrackingIntervalSubScreen()),
              ),
            ),

            // ── 권한 섹션 ─────────────────────────────
            const _SectionHeader(label: '권한'),
            permAsync.when(
              loading: () => const ListTile(
                leading: Icon(Icons.security_outlined),
                title: Text('권한 설정'),
                subtitle: Text('확인 중...'),
              ),
              error: (_, __) => const ListTile(
                leading: Icon(Icons.security_outlined),
                title: Text('권한 설정'),
              ),
              data: (statuses) {
                final granted =
                    statuses.values.where((s) => s.isGranted).length;
                final total = statuses.length;
                final allGranted = granted == total;
                return ListTile(
                  leading: Icon(
                    Icons.security_outlined,
                    color: allGranted ? null : Colors.orange,
                  ),
                  title: const Text('권한 설정'),
                  subtitle: Text('$granted / $total 허용됨'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const _PermissionSubScreen()),
                  ),
                );
              },
            ),

            // ── 백업 섹션 ─────────────────────────────
            const _SectionHeader(label: '백업 및 동기화'),
            ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: const Text('구글 드라이브 동기화'),
              subtitle: const Text('Wi-Fi 연결 시 메모를 드라이브에 자동 백업합니다'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const _BackupSubScreen()),
              ),
            ),

            // ── 고급 섹션 ─────────────────────────────
            const _SectionHeader(label: '고급'),
            ListTile(
              leading: const Icon(Icons.edit_document),
              title: const Text('메모 원본 수정하기'),
              subtitle: const Text('마크다운 파일을 직접 편집합니다'),
              onTap: () => _openMemoEditor(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('미사용 사진 정리'),
              subtitle: const Text('메모에 포함되지 않은 복사 사진을 삭제합니다'),
              onTap: () => _cleanUnusedPhotos(context, ref),
            ),
            const SizedBox(height: 16),
            const _SectionHeader(label: 'About'),
            _AboutTile(),
            ListTile(
              leading: const Icon(Icons.vpn_key_outlined),
              title: const Text('국립해양조사원 API 키'),
              subtitle: Text(
                settings.khoaApiKey?.isNotEmpty == true
                    ? '사용자 키 적용 중'
                    : '기본 키 사용 중',
              ),
              onTap: () => _showApiKeyDialog(context, ref, settings.khoaApiKey),
            ),
            const SizedBox(height: 16),
            const _SectionHeader(label: '개발자 후원'),
            ListTile(
              leading: const Icon(Icons.volunteer_activism_outlined),
              title: const Text('개발자 후원하기'),
              subtitle: const Text('카카오페이로 소액 후원할 수 있습니다'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showSupportSheet(context),
            ),
            const SizedBox(height: 16),
          ],
          ),
        ),
      ),
    );
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
}

// ── 저장 위치 변경 하위 화면 ──────────────────────────────────────

class _SaveLocationSubScreen extends ConsumerWidget {
  const _SaveLocationSubScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('저장 위치 변경')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (settings) => ListTileTheme(
          data: _subtitleTheme(context),
          child: ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('메모 저장 위치'),
              subtitle: Text(
                settings.saveDisplayPath.isNotEmpty
                    ? settings.saveDisplayPath
                    : settings.needsFolderSetup
                        ? '폴더를 선택해 주세요'
                        : settings.savePath,
                style: settings.needsFolderSetup
                    ? TextStyle(color: Theme.of(context).colorScheme.error)
                    : null,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: settings.needsFolderSetup
                  ? const Icon(Icons.warning_amber, color: Colors.orange)
                  : null,
              onTap: () => ref.read(settingsProvider.notifier).pickSaveFolder(),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('카메라 사진 저장 위치'),
              subtitle: Text(
                settings.photoSavePath,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () =>
                  ref.read(settingsProvider.notifier).pickPhotoSaveFolder(),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

// ── 어종 목록 관리 하위 화면 ──────────────────────────────────────

const _fishHdrStyle =
    TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey);

class _FishSpeciesSubScreen extends ConsumerStatefulWidget {
  const _FishSpeciesSubScreen();

  @override
  ConsumerState<_FishSpeciesSubScreen> createState() =>
      _FishSpeciesSubScreenState();
}

class _FishSpeciesSubScreenState extends ConsumerState<_FishSpeciesSubScreen> {
  final _addCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _addCtrl.addListener(() => setState(() {})); // 입력 시 실시간 필터링/중복 표시
  }

  @override
  void dispose() {
    _addCtrl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _addCtrl.text.trim();
    if (name.isEmpty) return;
    final list = ref.read(settingsProvider).valueOrNull?.fishSpecies ?? const [];
    if (list.contains(name)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('이미 있는 어종입니다: $name')),
      );
      return;
    }
    await ref.read(settingsProvider.notifier).addFishSpecies(name);
    _addCtrl.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('추가됨: $name'), duration: const Duration(seconds: 1)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    final stored = settings?.fishSpecies ?? const <String>[];
    final hidden = settings?.hiddenFishSpecies ?? const <String>[];
    final all = [...stored]..sort(); // 가나다순 정렬
    final query = _addCtrl.text.trim();
    final exactExists = query.isNotEmpty && all.contains(query);
    final filtered =
        query.isEmpty ? all : all.where((s) => s.contains(query)).toList();

    return Scaffold(
      appBar: AppBar(title: Text('어종 목록 관리 (${all.length})')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _addCtrl,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: '어종 추가 / 검색',
                      hintText: '예: 돗돔',
                      isDense: true,
                      border: const OutlineInputBorder(),
                      errorText: exactExists ? '이미 있는 어종입니다' : null,
                    ),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: FilledButton(
                    onPressed: (query.isEmpty || exactExists) ? null : _add,
                    child: const Text('추가'),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // 컬럼 헤더 (순번 / 어종 / 표시여부 / 삭제)
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Row(
              children: [
                SizedBox(
                    width: 36,
                    child: Text('순번',
                        textAlign: TextAlign.center, style: _fishHdrStyle)),
                SizedBox(width: 8),
                Expanded(child: Text('어종', style: _fishHdrStyle)),
                SizedBox(
                    width: 60,
                    child: Text('표시여부',
                        textAlign: TextAlign.center, style: _fishHdrStyle)),
                SizedBox(
                    width: 44,
                    child: Text('삭제',
                        textAlign: TextAlign.center, style: _fishHdrStyle)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      query.isEmpty
                          ? '어종이 없습니다. 위에서 추가하세요.'
                          : "'$query' 와 일치하는 어종이 없습니다.\n'추가'로 새로 등록하세요.",
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (_, i) {
                      final s = filtered[i];
                      final visible = !hidden.contains(s);
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 2),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 36,
                              child: Text(
                                '${i + 1}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(s,
                                    style: const TextStyle(fontSize: 15))),
                            SizedBox(
                              width: 60,
                              child: Center(
                                child: Checkbox(
                                  value: visible,
                                  visualDensity: VisualDensity.compact,
                                  onChanged: (v) => ref
                                      .read(settingsProvider.notifier)
                                      .setFishSpeciesVisible(s, v ?? true),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 44,
                              child: IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red, size: 20),
                                tooltip: '삭제',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => ref
                                    .read(settingsProvider.notifier)
                                    .removeFishSpecies(s),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ── 기록 간격 하위 화면 ───────────────────────────────────────────

class _TrackingIntervalSubScreen extends ConsumerStatefulWidget {
  const _TrackingIntervalSubScreen();

  @override
  ConsumerState<_TrackingIntervalSubScreen> createState() =>
      _TrackingIntervalSubScreenState();
}

class _TrackingIntervalSubScreenState
    extends ConsumerState<_TrackingIntervalSubScreen> {
  double? _sliderValue;

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('기록 간격')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (settings) {
          final current =
              _sliderValue ?? settings.trackingIntervalMeters.toDouble();
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '최소 이동 거리: ${current.round()}m',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                Slider(
                  value: current,
                  min: 30,
                  max: 1000,
                  divisions: 97,
                  label: '${current.round()}m',
                  onChanged: (v) => setState(() => _sliderValue = v),
                  onChangeEnd: (v) => ref
                      .read(settingsProvider.notifier)
                      .updateTrackingIntervalMeters(v.round()),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('30m',
                          style: Theme.of(context).textTheme.bodySmall),
                      Text('1000m',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '이동 경로 기록 시 최소 이동 거리를 설정합니다.\n'
                  '거리가 짧을수록 더 상세한 경로가 기록됩니다.\n\n'
                  '메모 작성 화면에서 이동 경로 기록 버튼을 활성화한 경우에만 이동 경로가 기록됩니다.\n\n'
                  '이동 경로 기록은 자정(0시)이 되면 자동으로 중단됩니다.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── 권한 설정 하위 화면 ───────────────────────────────────────────

class _PermissionSubScreen extends ConsumerStatefulWidget {
  const _PermissionSubScreen();

  @override
  ConsumerState<_PermissionSubScreen> createState() =>
      _PermissionSubScreenState();
}

class _PermissionSubScreenState extends ConsumerState<_PermissionSubScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(permissionStatusProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final permAsync = ref.watch(permissionStatusProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('권한 설정')),
      body: permAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('권한 확인 실패')),
        data: (statuses) {
          const items = [
            (Permission.microphone, '마이크', '음성 메모 녹음'),
            (Permission.locationWhenInUse, '위치', 'GPS 좌표 기록'),
            (Permission.camera, '카메라', '사진 촬영'),
            (Permission.photos, '사진', '갤러리 사진 선택'),
            (Permission.videos, '동영상', '갤러리 동영상 선택'),
            (Permission.notification, '알림', '음성 메모 상태 표시'),
          ];
          return ListTileTheme(
            data: _subtitleTheme(context),
            child: ListView(
              children: items.map((item) {
                final (perm, label, desc) = item;
                final isGranted = statuses[perm]?.isGranted ?? false;
                return ListTile(
                  title: Text(label),
                  subtitle: Text(desc),
                  trailing: PermissionStatusChip(isGranted: isGranted),
                  onTap: () async => await openAppSettings(),
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }
}

// ── 빠른 메모 실행 하위 화면 ─────────────────────────────────────

String _quickLaunchModeLabel(QuickLaunchMode mode) {
  switch (mode) {
    case QuickLaunchMode.shake:  return '화면 흔들기';
    case QuickLaunchMode.volume: return '볼륨 버튼';
    case QuickLaunchMode.none:   return '사용 안 함';
  }
}

class _QuickLaunchSubScreen extends ConsumerWidget {
  const _QuickLaunchSubScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('빠른 메모 실행')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (settings) {
          final mode = settings.quickLaunchMode;
          void setMode(QuickLaunchMode? v) {
            if (v == null) return;
            ref.read(settingsProvider.notifier).updateQuickLaunchMode(v);
          }
          return ListTileTheme(
            data: _subtitleTheme(context),
            child: ListView(
            children: [
              RadioListTile<QuickLaunchMode>(
                secondary: const Icon(Icons.vibration),
                title: const Text('화면 흔들기'),
                subtitle: const Text('1.5초 내 3회 흔들면 음성 메모 시작'),
                value: QuickLaunchMode.shake,
                groupValue: mode,
                onChanged: setMode,
              ),
              RadioListTile<QuickLaunchMode>(
                secondary: const Icon(Icons.volume_up_outlined),
                title: const Text('볼륨 버튼'),
                subtitle: const Text('볼륨 ↑ 2회 연속으로 음성 메모 시작'),
                value: QuickLaunchMode.volume,
                groupValue: mode,
                onChanged: setMode,
              ),
              if (mode == QuickLaunchMode.volume)
                const _AccessibilityTile(),
            ],
            ),
          );
        },
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
        SwitchListTile(
          secondary: Icon(
            _enabled ? Icons.lock_open : Icons.lock_outline,
            color: _enabled ? Colors.green : null,
          ),
          title: const Text('잠금화면 · 화면 꺼짐 상태 지원'),
          subtitle: Text(
            _enabled
                ? '활성화됨 — 화면 꺼짐·잠금 상태에서도 동작합니다'
                : '화면 켜진 상태에서만 동작합니다',
            style: _enabled ? const TextStyle(color: Colors.green) : null,
          ),
          value: _enabled,
          onChanged: (_) async => await openAccessibilitySettings(),
        ),
        if (!_enabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '볼륨 ↑ 두 번으로 음성 메모를 입력할 수 있습니다.\n'
              '잠금화면·화면 꺼짐 상태에서도 사용하려면 접근성 서비스를 활성화하세요.\n'
              '활성화 → 접근성 → 설치된 서비스 → 낚.다 음성 메모 → 켜기',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
      ],
    );
  }
}

// ── 유틸리티 ─────────────────────────────────────────────────────

Future<void> _cleanUnusedPhotos(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('미사용 사진 정리'),
      content: const Text(
        '메모에 포함되지 않은 복사 사진을 삭제합니다.\n갤러리 원본 사진은 영향을 받지 않습니다.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('정리'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final settings = ref.read(settingsProvider).valueOrNull;
  if (settings == null) return;

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('사진 정리 중...'),
      duration: Duration(minutes: 1),
    ),
  );

  final count = await ref
      .read(fileListRepositoryProvider)
      .cleanUnusedPhotos(settings.savePath);

  if (context.mounted) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${count}개 사진 삭제 완료')),
    );
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
            child: ListTileTheme(
              data: _subtitleTheme(context),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: files.length,
                itemBuilder: (_, i) {
                  final file = files[i];
                  return ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(file.displayName),
                    subtitle: Text('메모 ${file.entryCount}개'),
                    onTap: () => onSelect(file),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutTile extends StatefulWidget {
  @override
  State<_AboutTile> createState() => _AboutTileState();
}

class _AboutTileState extends State<_AboutTile> {
  String _version = '-';
  String _buildTime = '-';

  @override
  void initState() {
    super.initState();
    getBuildInfo().then((info) {
      if (info != null && mounted) {
        setState(() {
          _version   = info.version;
          _buildTime = info.buildTime;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.info_outline),
      title: Text('버전 $_version'),
      subtitle: Text('빌드: $_buildTime'),
    );
  }
}

Future<void> _showSupportSheet(BuildContext context) async {
  await showModalBottomSheet(
    context: context,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('개발자 후원하기',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          const Divider(height: 1),
          _SupportItem(
            icon: Icons.coffee_outlined,
            label: '커피 한 잔 후원하기',
            amount: '3,000원',
            url: 'https://qr.kakaopay.com/FLGjWrHDR5dc08966',
          ),
          _SupportItem(
            icon: Icons.set_meal_outlined,
            label: '낚시 미끼 한 봉지 후원하기',
            amount: '5,000원',
            url: 'https://qr.kakaopay.com/FLGjWrHDR9c404708',
          ),
          _SupportItem(
            icon: Icons.edit_outlined,
            label: '후원금 직접 입력하기',
            amount: '직접 입력',
            url: 'https://qr.kakaopay.com/FLGjWrHDR',
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

class _SupportItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String amount;
  final String url;

  const _SupportItem({
    required this.icon,
    required this.label,
    required this.amount,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(amount, style: _subtitleTheme(context).subtitleTextStyle),
      onTap: () async {
        Navigator.of(context).pop();
        final uri = Uri.parse(url);
        if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('카카오페이를 열 수 없습니다')),
            );
          }
        }
      },
    );
  }
}

ListTileThemeData _subtitleTheme(BuildContext ctx) => ListTileThemeData(
  subtitleTextStyle: TextStyle(
    fontSize: 13,
    color: Theme.of(ctx).colorScheme.onSurface.withValues(alpha: 0.6),
  ),
);

// ── 백업 하위 화면 ───────────────────────────────────────────────

class _BackupSubScreen extends ConsumerWidget {
  const _BackupSubScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backupAsync = ref.watch(backupProvider);
    final settingsAsync = ref.watch(settingsProvider);
    final backupProgress = ref.watch(backupProgressProvider);
    final isBacking = backupProgress != null;
    final restoreProgress = ref.watch(restoreProgressProvider);
    final isRestoring = restoreProgress != null;

    return Scaffold(
      appBar: AppBar(title: const Text('백업 및 동기화')),
      body: backupAsync.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (backup) {
          final settings = settingsAsync.valueOrNull;
          return ListTileTheme(
            data: _subtitleTheme(context),
            child: ListView(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.cloud_outlined),
                  title: const Text('구글 드라이브 동기화'),
                  subtitle: Text(
                    backup.enabled && backup.accountEmail != null
                        ? backup.accountEmail!
                        : '비활성화됨 — Wi-Fi 연결 시에만 동기화',
                  ),
                  value: backup.enabled,
                  onChanged: (v) async {
                    if (v) {
                      final result = await ref.read(backupProvider.notifier).enableBackup();
                      if (!result.ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('구글 로그인 실패: ${result.error}')),
                        );
                      }
                    } else {
                      await ref.read(backupProvider.notifier).disableBackup();
                    }
                  },
                ),
                if (backup.enabled) ...[
                  const Divider(indent: 16, endIndent: 16),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text('동기화 범위',
                        style: Theme.of(context).textTheme.labelMedium),
                  ),
                  RadioListTile<bool>(
                    title: const Text('메모 파일만'),
                    subtitle: const Text('.md 파일만 동기화 (빠름)'),
                    value: false,
                    groupValue: backup.includeMedia,
                    onChanged: (v) =>
                        ref.read(backupProvider.notifier).setIncludeMedia(false),
                  ),
                  RadioListTile<bool>(
                    title: const Text('이미지·동영상 포함'),
                    subtitle: const Text('사진과 동영상도 함께 동기화'),
                    value: true,
                    groupValue: backup.includeMedia,
                    onChanged: (v) =>
                        ref.read(backupProvider.notifier).setIncludeMedia(true),
                  ),
                  const Divider(indent: 16, endIndent: 16),
                  ListTile(
                    leading: Icon(
                      backup.lastSyncSuccess == false
                          ? Icons.sync_problem_outlined
                          : Icons.check_circle_outline,
                      color: backup.lastSyncSuccess == false ? Colors.orange : null,
                    ),
                    title: const Text('마지막 동기화'),
                    subtitle: Text(backup.lastSyncAt != null
                        ? _fmtDateTime(backup.lastSyncAt!)
                            + (backup.lastSyncSuccess == false ? ' (실패)' : ' ✓')
                        : '없음'),
                  ),
                  ListTile(
                    leading: Icon(Icons.cloud_upload_outlined,
                        color: isBacking ? Theme.of(context).disabledColor : null),
                    title: const Text('지금 전체 백업'),
                    subtitle: isBacking
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              LinearProgressIndicator(
                                value: backupProgress.$2 > 0
                                    ? backupProgress.$1 / backupProgress.$2
                                    : null,
                              ),
                              const SizedBox(height: 4),
                              Text(backupProgress.$2 > 0
                                  ? '${backupProgress.$1} / ${backupProgress.$2} 파일'
                                  : '준비 중...'),
                            ],
                          )
                        : const Text('모든 메모 파일을 드라이브에 올립니다'),
                    trailing: isBacking ? null : const Icon(Icons.chevron_right),
                    onTap: isBacking
                        ? null
                        : () => _showBackupAllDialog(context, ref, settings?.savePath ?? ''),
                  ),
                  ListTile(
                    leading: Icon(Icons.restore_outlined,
                        color: isRestoring ? Theme.of(context).disabledColor : null),
                    title: const Text('지금 복원하기'),
                    subtitle: isRestoring
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              LinearProgressIndicator(
                                value: restoreProgress.$2 > 0
                                    ? restoreProgress.$1 / restoreProgress.$2
                                    : null,
                              ),
                              const SizedBox(height: 4),
                              Text(restoreProgress.$2 > 0
                                  ? '${restoreProgress.$1} / ${restoreProgress.$2} 파일'
                                  : '준비 중...'),
                            ],
                          )
                        : const Text('드라이브 데이터를 로컬과 병합합니다'),
                    trailing: isRestoring ? null : const Icon(Icons.chevron_right),
                    onTap: isRestoring
                        ? null
                        : () => _showRestoreDialog(context, ref, settings?.savePath ?? ''),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showBackupAllDialog(BuildContext context, WidgetRef ref, String savePath) async {
    if (savePath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 메모 저장 위치를 설정해 주세요')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('전체 백업'),
        content: const Text('모든 메모 파일을 구글 드라이브에 업로드합니다.\nWi-Fi 연결이 필요합니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('백업'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final result = await ref.read(backupProvider.notifier).backupAll(savePath);
    if (!context.mounted) return;
    if (result.skippedNoWifi) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wi-Fi에 연결되지 않아 백업을 건너뜁니다')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
          result.skipped > 0
              ? '${result.succeeded}개 업로드, ${result.skipped}개 이미 최신 상태'
              : '${result.succeeded}/${result.total}개 파일 백업 완료',
        )),
      );
    }
  }

  Future<void> _showRestoreDialog(BuildContext context, WidgetRef ref, String savePath) async {
    if (savePath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 메모 저장 위치를 설정해 주세요')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('복원'),
        content: const Text(
          '드라이브 데이터를 로컬과 날짜 기준으로 병합합니다.\n'
          '로컬에만 있는 데이터는 유지됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('복원'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      final result = await ref.read(backupProvider.notifier).restore(savePath);
      if (context.mounted) {
        final mediaAlreadyLocal = result.mediaDriveTotal - result.mediaRestored;
        final parts = <String>[];
        if (result.mediaRestored > 0) parts.add('미디어 ${result.mediaRestored}개 복원');
        if (mediaAlreadyLocal > 0) parts.add('${mediaAlreadyLocal}개 이미 로컬');
        final mediaPart = parts.isNotEmpty ? ', ${parts.join(', ')}' : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('메모 ${result.filesRestored}개 복원$mediaPart')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('복원 실패: $e')),
        );
      }
    }
  }

  String _fmtDateTime(DateTime dt) {
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-$m-$d $h:$mi';
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/app_router.dart';
import '../../core/widgets/action_button.dart';
import '../../core/services/accessibility_service.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../core/widgets/memo_entry_card.dart';
import '../../core/widgets/location_status_card.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/utils/media_scanner.dart';
import '../../features/memo/domain/models/memo_entry.dart';
import '../../features/memo/domain/models/day_file.dart';
import '../../features/location/domain/models/location_status.dart';
import '../../features/memo/presentation/memo_provider.dart';
import '../../features/memo/presentation/memo_input_sheet.dart';
import '../../features/memo/presentation/location_edit_sheet.dart';
import '../../features/settings/presentation/settings_provider.dart';
import '../../features/location/presentation/location_provider.dart';
import '../../features/photo/presentation/photo_provider.dart';
import '../../features/photo/domain/photo_service.dart';
import '../../features/photo/presentation/camera_ruler_screen.dart';
import '../../core/services/ar_service.dart';
import '../../core/utils/watermark.dart';
import 'package:geolocator/geolocator.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 앱이 포어그라운드일 때 AccessibilityService 결과 수신
    setVoiceResultHandler(_handleVoiceResult);
    // 앱 시작 시 미처리 결과 확인
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPendingVoiceResult());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPendingVoiceResult();
    }
  }

  void _handleVoiceResult(String text) {
    if (!mounted) return;
    final autoSave = ref.read(settingsProvider).valueOrNull?.autoSaveVoice ?? false;
    if (autoSave) {
      _saveVoiceDirectly(text);
    } else {
      MemoInputSheet.show(context, initialText: text);
    }
  }

  Future<void> _checkPendingVoiceResult() async {
    final text = await getPendingVoiceResult();
    if (text != null && mounted) {
      await clearPendingVoiceResult();
      final autoSave = ref.read(settingsProvider).valueOrNull?.autoSaveVoice ?? false;
      if (autoSave) {
        _saveVoiceDirectly(text);
      } else {
        MemoInputSheet.show(context, initialText: text);
      }
    }
  }

  Future<void> _saveVoiceDirectly(String text) async {
    double? lat = ref.read(locationProvider).valueOrNull?.latitude;
    double? lng = ref.read(locationProvider).valueOrNull?.longitude;
    if (lat == null) {
      final cached = ref.read(locationProvider.notifier).cached;
      lat = cached?.latitude;
      lng = cached?.longitude;
    }
    if (lat == null) {
      try {
        final pos = await Geolocator.getLastKnownPosition();
        if (pos != null) { lat = pos.latitude; lng = pos.longitude; }
      } catch (_) {}
    }
    await ref.read(todayFileProvider.notifier).addEntry(MemoEntry(
      timestamp: DateTime.now(),
      latitude: lat,
      longitude: lng,
      text: text,
    ));
    if (mounted) {
      final preview = text.length > 30 ? '${text.substring(0, 30)}…' : text;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('저장됨: $preview'), duration: const Duration(seconds: 2)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final todayAsync = ref.watch(todayFileProvider);
    final settingsAsync = ref.watch(settingsProvider);
    final showLocationButton =
        settingsAsync.valueOrNull?.showLocationButton ?? true;
    final today = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          DateFormatter.toDateString(today),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_outlined),
            tooltip: '파일 목록',
            onPressed: () => context.push(AppRoutes.fileList),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '설정',
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
      body: Stack(
        children: [
          todayAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => EmptyStateView(
              icon: Icons.error_outline,
              message: '불러오기 실패',
              subMessage: e.toString(),
            ),
            data: (dayFile) => _Body(dayFile: dayFile),
          ),
          if (showLocationButton)
            _LocationFab(onTap: _onLocationTap),
        ],
      ),
      bottomNavigationBar: _ActionBar(
        onVoiceTap: () => _openMemoSheet(voiceMode: true),
        onPhotoTap: _onPhotoTap,
        onMapTap: () => context.push(AppRoutes.map),
      ),
    );
  }

  void _openMemoSheet({bool voiceMode = false}) {
    MemoInputSheet.show(context, voiceMode: voiceMode);
  }

  Future<void> _onPhotoTap() async {
    final source = await showModalBottomSheet<PhotoSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.view_in_ar_outlined),
              title: const Text('AR 길이 측정'),
              onTap: () => Navigator.of(context).pop(PhotoSource.arCamera),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('일반 사진'),
              onTap: () => Navigator.of(context).pop(PhotoSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('갤러리에서 선택'),
              onTap: () => Navigator.of(context).pop(PhotoSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) return;

    if (source == PhotoSource.arCamera) {
      final settings = ref.read(settingsProvider).valueOrNull;
      final wmSettings = settings?.watermark;
      final arResult = await launchArMeasure(
        watermarkEnabled: wmSettings?.enabled ?? false,
      );
      if (arResult == null || !context.mounted) return;
      final photoPath = (arResult.applyWatermark && wmSettings != null)
          ? await applyWatermark(arResult.path, wmSettings.copyWith(enabled: true))
          : arResult.path;
      if (!context.mounted) return;
      await ref.read(photoProvider.notifier).saveFromPath(photoPath, fishLength: arResult.distanceCm);
    } else if (source == PhotoSource.camera) {
      final result = await Navigator.of(context).push<({String path, double? length})>(
        MaterialPageRoute(builder: (_) => const CameraRulerScreen()),
      );
      if (result == null || !context.mounted) return;
      await ref.read(photoProvider.notifier).saveFromPath(result.path, fishLength: result.length);
    } else {
      await ref.read(photoProvider.notifier).pickAndSave(source);
    }
  }

  Future<void> _onLocationTap() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 12),
            Text('환경 정보 수집 중...'),
          ],
        ),
        duration: Duration(minutes: 1),
      ),
    );

    final loc = await ref
        .read(locationProvider.notifier)
        .buildEnrichedLocation(isMove: true);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (_) => _LocationPreviewSheet(location: loc),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(todayFileProvider.notifier).addLocationBlock(loc);
    }
  }
}

class _Body extends ConsumerStatefulWidget {
  final DayFile? dayFile;
  final Future<void> Function(int, MemoEntry)? onEditMemoSave;
  final Future<void> Function(int, LocationStatus)? onEditLocationSave;
  final Future<void> Function(int)? onRemoveBlock;

  const _Body({
    this.dayFile,
    this.onEditMemoSave,
    this.onEditLocationSave,
    this.onRemoveBlock,
  });

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  final _scroll = ScrollController();
  int _prevCount = 0;

  @override
  void initState() {
    super.initState();
    _prevCount = widget.dayFile?.blocks.length ?? 0;
  }

  @override
  void didUpdateWidget(_Body old) {
    super.didUpdateWidget(old);
    final newCount = widget.dayFile?.blocks.length ?? 0;
    if (newCount > _prevCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
    _prevCount = newCount;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dayFile = widget.dayFile;
    if (dayFile == null || dayFile.blocks.isEmpty) {
      return const EmptyStateView(
        icon: Icons.mic_none,
        message: '오늘의 메모가 없습니다',
        subMessage: '아래 버튼을 눌러 첫 메모를 남겨보세요',
      );
    }
    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.all(16),
      itemCount: dayFile.blocks.length,
      separatorBuilder: (context, index) => const Divider(height: 24),
      itemBuilder: (context, index) {
        final block = dayFile.blocks[index];
        final blockKey = block is MemoEntry
            ? 'memo_${block.timestamp.millisecondsSinceEpoch}'
            : block is LocationStatus
                ? 'loc_${block.timestamp.millisecondsSinceEpoch}'
                : 'block_$index';
        return _SwipeItem(
          key: ValueKey(blockKey),
          onEdit: () {
            if (block is MemoEntry) {
              MemoInputSheet.show(context,
                  existingEntry: block,
                  blockIndex: index,
                  onEditSave: widget.onEditMemoSave);
            } else if (block is LocationStatus) {
              LocationEditSheet.show(context,
                  existing: block,
                  blockIndex: index,
                  onEditSave: widget.onEditLocationSave);
            }
          },
          onDelete: () async {
            final ok = await ConfirmDialog.show(
              context,
              title: '항목 삭제',
              content: '이 항목을 삭제할까요? 복구할 수 없습니다.',
              confirmLabel: '삭제',
              isDestructive: true,
            );
            if (ok) {
              if (widget.onRemoveBlock != null) {
                await widget.onRemoveBlock!(index);
              } else {
                ref.read(todayFileProvider.notifier).removeBlock(index);
              }
            }
          },
          child: block is MemoEntry
              ? MemoEntryCard(entry: block)
              : block is LocationStatus
                  ? LocationStatusCard(status: block)
                  : const SizedBox.shrink(),
        );
      },
    );
  }
}

class _SwipeItem extends StatefulWidget {
  final Widget child;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SwipeItem({
    super.key,
    required this.child,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_SwipeItem> createState() => _SwipeItemState();
}

class _SwipeItemState extends State<_SwipeItem> {
  static const double _actionWidth = 130.0;
  bool _open = false;

  void _toggle(bool open) => setState(() => _open = open);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _open ? () => _toggle(false) : null,
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity == null) return;
        if (details.primaryVelocity! < -200) {
          _toggle(true);
        } else if (details.primaryVelocity! > 200) {
          _toggle(false);
        }
      },
      child: Stack(
        children: [
          Positioned(
            right: 0,
            top: 4,
            bottom: 4,
            width: _actionWidth,
            child: Row(
              children: [
                Expanded(
                  child: _ActionBtn(
                    icon: Icons.edit_outlined,
                    label: '수정',
                    color: Colors.blue.shade600,
                    borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(8)),
                    onTap: () {
                      _toggle(false);
                      widget.onEdit();
                    },
                  ),
                ),
                Expanded(
                  child: _ActionBtn(
                    icon: Icons.delete_outline,
                    label: '삭제',
                    color: Colors.red.shade500,
                    borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(8)),
                    onTap: () {
                      _toggle(false);
                      widget.onDelete();
                    },
                  ),
                ),
              ],
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: double.infinity,
            margin: EdgeInsets.only(right: _open ? _actionWidth : 0),
            color: Theme.of(context).colorScheme.surface,
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

class _LocationPreviewSheet extends StatelessWidget {
  final LocationStatus location;

  const _LocationPreviewSheet({required this.location});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + mq.viewInsets.bottom + mq.padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '위치 정보 확인',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 12),
          LocationStatusCard(status: location),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('취소'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('저장'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final BorderRadius borderRadius;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.borderRadius,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: borderRadius,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  final VoidCallback onVoiceTap;
  final VoidCallback onPhotoTap;
  final VoidCallback onMapTap;

  const _ActionBar({
    required this.onVoiceTap,
    required this.onPhotoTap,
    required this.onMapTap,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        height: 80,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            ActionButton(icon: Icons.mic, label: '음성', onTap: onVoiceTap),
            ActionButton(icon: Icons.camera_alt, label: '사진', onTap: onPhotoTap),
            ActionButton(icon: Icons.map_outlined, label: '지도', onTap: onMapTap),
          ],
        ),
      ),
    );
  }
}

// ── 드래그 가능한 위치 추가 FAB ──────────────────────────────

class _LocationFab extends StatefulWidget {
  final VoidCallback onTap;
  const _LocationFab({required this.onTap});

  @override
  State<_LocationFab> createState() => _LocationFabState();
}

class _LocationFabState extends State<_LocationFab> {
  double _right = 16;
  double _bottom = 100;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Positioned(
      right: _right.clamp(0.0, mq.size.width - 64.0),
      bottom: _bottom.clamp(0.0, mq.size.height - 200.0),
      child: GestureDetector(
        onTap: widget.onTap,
        onPanUpdate: (details) {
          setState(() {
            _right -= details.delta.dx;
            _bottom -= details.delta.dy;
          });
        },
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.alphaBlend(
                    const Color(0x70FFFFFF),
                    Theme.of(context).colorScheme.tertiary),
                Color.alphaBlend(
                    const Color(0x55000000),
                    Theme.of(context).colorScheme.tertiary),
              ],
            ),
            boxShadow: const [
              // 선명한 드롭 섀도 — 버튼이 떠 있는 느낌
              BoxShadow(
                blurRadius: 2,
                offset: Offset(0, 4),
                color: Color(0x99000000),
              ),
              // 확산 섀도 — 깊이감
              BoxShadow(
                blurRadius: 12,
                offset: Offset(0, 8),
                color: Color(0x44000000),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_location_alt,
                color: Theme.of(context).colorScheme.onTertiary,
                size: 22,
              ),
              Text(
                '위치 추가',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onTertiary,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 파일 목록에서 특정 날짜 파일을 홈 화면처럼 편집하는 화면 ─────

class DayMemoScreen extends ConsumerStatefulWidget {
  final String filePath;
  final String displayName;

  const DayMemoScreen({
    super.key,
    required this.filePath,
    required this.displayName,
  });

  @override
  ConsumerState<DayMemoScreen> createState() => _DayMemoScreenState();
}

class _DayMemoScreenState extends ConsumerState<DayMemoScreen> {
  @override
  Widget build(BuildContext context) {
    final asyncFile = ref.watch(dayFileProvider(widget.filePath));
    final showLocationButton =
        ref.watch(settingsProvider).valueOrNull?.showLocationButton ?? true;
    final notifier = ref.read(dayFileProvider(widget.filePath).notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.displayName,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      body: Stack(
        children: [
          asyncFile.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => EmptyStateView(
              icon: Icons.error_outline,
              message: '불러오기 실패',
              subMessage: e.toString(),
            ),
            data: (dayFile) => _Body(
              dayFile: dayFile,
              onEditMemoSave: (idx, entry) => notifier.editBlock(idx, entry),
              onEditLocationSave: (idx, loc) => notifier.editBlock(idx, loc),
              onRemoveBlock: (idx) => notifier.removeBlock(idx),
            ),
          ),
          if (showLocationButton)
            _LocationFab(onTap: _onLocationTap),
        ],
      ),
      bottomNavigationBar: _ActionBar(
        onVoiceTap: () => _openMemoSheet(voiceMode: true),
        onPhotoTap: _onPhotoTap,
        onMapTap: () => context.push(AppRoutes.map),
      ),
    );
  }

  void _openMemoSheet({bool voiceMode = false}) {
    MemoInputSheet.show(
      context,
      voiceMode: voiceMode,
      onAddSave: (entry) =>
          ref.read(dayFileProvider(widget.filePath).notifier).addEntry(entry),
    );
  }

  Future<void> _onPhotoTap() async {
    final source = await showModalBottomSheet<PhotoSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.view_in_ar_outlined),
              title: const Text('AR 길이 측정'),
              onTap: () => Navigator.of(context).pop(PhotoSource.arCamera),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('일반 사진'),
              onTap: () => Navigator.of(context).pop(PhotoSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('갤러리에서 선택'),
              onTap: () => Navigator.of(context).pop(PhotoSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) return;

    final settings = ref.read(settingsProvider).valueOrNull;
    final relativePath =
        _mediaRelativePath(settings?.photoSavePath ?? 'DCIM/nakkda');
    String? savedPath;
    double? fishLength;

    if (source == PhotoSource.arCamera) {
      final wmSettings = settings?.watermark;
      final arResult = await launchArMeasure(
        watermarkEnabled: wmSettings?.enabled ?? false,
      );
      if (arResult == null || !context.mounted) return;
      final rawPath = (arResult.applyWatermark && wmSettings != null)
          ? await applyWatermark(arResult.path, wmSettings.copyWith(enabled: true))
          : arResult.path;
      fishLength = arResult.distanceCm;
      if (!context.mounted) return;
      savedPath = await saveToGallery(rawPath, relativePath: relativePath);
    } else if (source == PhotoSource.camera) {
      final result = await Navigator.of(context).push<({String path, double? length})>(
        MaterialPageRoute(builder: (_) => const CameraRulerScreen()),
      );
      if (result == null || !context.mounted) return;
      fishLength = result.length;
      if (!context.mounted) return;
      savedPath = await saveToGallery(result.path, relativePath: relativePath);
    } else {
      // 갤러리 선택: 경로 그대로 참조
      final tempPath =
          await ref.read(photoServiceProvider).pickImage(source: source);
      if (tempPath == null || !context.mounted) return;
      savedPath = tempPath;
    }

    if (savedPath == null || !context.mounted) return;
    final gps = await _bestGps();
    await ref.read(dayFileProvider(widget.filePath).notifier).addEntry(
          MemoEntry(
            timestamp: DateTime.now(),
            latitude: gps?.$1,
            longitude: gps?.$2,
            photoPath: savedPath,
            fishLength: fishLength,
          ),
        );
  }

  Future<void> _onLocationTap() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('환경 정보 수집 중...'),
          ],
        ),
        duration: Duration(minutes: 1),
      ),
    );

    final loc = await ref
        .read(locationProvider.notifier)
        .buildEnrichedLocation(isMove: true);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (_) => _LocationPreviewSheet(location: loc),
    );
    if (confirmed == true && context.mounted) {
      await ref
          .read(dayFileProvider(widget.filePath).notifier)
          .addLocationBlock(loc);
    }
  }

  Future<(double, double)?> _bestGps() async {
    final loc = ref.read(locationProvider).valueOrNull ??
        ref.read(locationProvider.notifier).cached;
    if (loc?.latitude != null) return (loc!.latitude!, loc.longitude!);
    try {
      final pos = await Geolocator.getLastKnownPosition();
      if (pos != null) return (pos.latitude, pos.longitude);
    } catch (_) {}
    return null;
  }

  String _mediaRelativePath(String photoSavePath) {
    final lower = photoSavePath.toLowerCase();
    for (final marker in ['dcim/', 'pictures/', 'downloads/']) {
      final idx = lower.indexOf(marker);
      if (idx >= 0) return photoSavePath.substring(idx);
    }
    return 'DCIM/nakkda';
  }

}

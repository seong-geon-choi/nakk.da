import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/router/app_router.dart';
import '../../core/widgets/action_button.dart';
import '../../core/services/accessibility_service.dart';
import '../../core/services/tracking_service.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/empty_state_view.dart';
import '../../core/widgets/memo_entry_card.dart';
import '../../core/widgets/location_status_card.dart';
import '../../core/utils/date_formatter.dart';
import '../../features/memo/domain/models/memo_entry.dart';
import '../../features/memo/domain/models/day_file.dart';
import '../../features/location/domain/models/location_status.dart';
import '../../features/memo/presentation/memo_provider.dart';
import '../../features/memo/presentation/memo_input_sheet.dart';
import '../../features/memo/presentation/location_edit_sheet.dart';
import '../../features/settings/presentation/settings_provider.dart';
import '../../features/location/presentation/location_provider.dart';
import '../../core/utils/file_name_parser.dart';
import '../../core/utils/media_scanner.dart';
import '../../core/utils/species_detector.dart';
import '../../core/widgets/memo_date_picker_dialog.dart';
import '../../core/services/saf_service.dart';
import 'dart:io';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

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
    setVoiceResultHandler(_handleVoiceResult);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingVoiceResult();
      _autoSetupSaveFolderIfNeeded();
    });
  }

  Future<void> _autoSetupSaveFolderIfNeeded() async {
    final settings = ref.read(settingsProvider).valueOrNull;
    if (settings == null || !settings.needsFolderSetup) return;
    if (!mounted) return;
    await ref.read(settingsProvider.notifier).pickSaveFolder();
  }

  Future<bool> _requirePermission(Permission perm, String label) async {
    if (await perm.status.isGranted) return true;
    final result = await perm.request();
    if (result.isGranted) return true;
    if (result.isPermanentlyDenied && mounted) {
      final goSettings = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('$label 권한 필요'),
          content: Text('$label 권한이 거부되었습니다.\n설정에서 권한을 허용한 후 다시 시도해주세요.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('설정 열기'),
            ),
          ],
        ),
      );
      if (goSettings == true) openAppSettings();
    }
    return false;
  }

  Future<bool> _requireFolderSetup() async {
    if (ref.read(settingsProvider).valueOrNull?.needsFolderSetup != true) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('저장 폴더 설정 필요'),
        content: const Text('이 기능을 사용하려면 메모 저장 폴더를 먼저 설정해야 합니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('폴더 설정'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    await ref.read(settingsProvider.notifier).pickSaveFolder();
    return ref.read(settingsProvider).valueOrNull?.needsFolderSetup == false;
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
      if (!mounted) return;
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
      fishSpecies: detectFishSpecies(
          text, ref.read(settingsProvider).valueOrNull?.fishSpecies),
      fishLength: detectFishLength(text),
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

    final needsSetup = settingsAsync.valueOrNull?.needsFolderSetup ?? false;

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _onFileListTap,
          child: Text(
            DateFormatter.toDateString(today),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_photo_alternate_outlined),
            tooltip: '날짜별 사진 일괄 추가',
            onPressed: _importDayPhotos,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '설정',
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
      body: Column(
        children: [
          if (needsSetup)
            MaterialBanner(
              content: const Text('메모 저장 폴더가 설정되지 않았습니다'),
              actions: [
                TextButton(
                  onPressed: () async {
                    await ref.read(settingsProvider.notifier).pickSaveFolder();
                  },
                  child: const Text('폴더 선택'),
                ),
              ],
            ),
          Expanded(
            child: Stack(
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
                if (settingsAsync.valueOrNull?.showTrackingButton ?? true)
                  const _TrackingFab(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _ActionBar(
        onVoiceTap: () => _openMemoSheet(),
        onPhotoTap: _onPhotoTap,
        onMapTap: _onMapTap,
      ),
    );
  }

  Future<void> _openMemoSheet({bool voiceMode = false}) async {
    if (!await _requireFolderSetup()) return;
    if (voiceMode && !await _requirePermission(Permission.microphone, '마이크')) return;
    if (mounted) MemoInputSheet.show(context, voiceMode: voiceMode);
  }

  Future<void> _onFileListTap() async {
    if (!await _requireFolderSetup()) return;
    if (mounted) context.push(AppRoutes.fileList);
  }

  Future<void> _onMapTap() async {
    if (!await _requireFolderSetup()) return;
    if (!await _requirePermission(Permission.locationWhenInUse, '위치')) return;
    if (mounted) context.push(AppRoutes.map);
  }

  Future<Set<DateTime>> _loadMarkedDates(String savePath) async {
    if (savePath.isEmpty) return {};
    final dates = <DateTime>{};
    if (SafService.isSafUri(savePath)) {
      final names = await SafService().listMdFiles(savePath);
      for (final name in names) {
        final d = FileNameParser.parseDate(name);
        if (d != null) dates.add(d);
      }
    } else {
      final dir = Directory(savePath);
      if (!await dir.exists()) return {};
      await for (final entity in dir.list()) {
        if (entity is File) {
          final d = FileNameParser.parseDate(entity.uri.pathSegments.last);
          if (d != null) dates.add(d);
        }
      }
    }
    return dates;
  }

  Future<void> _importDayPhotos() async {
    if (!await _requireFolderSetup()) return;
    if (!await _requirePermission(Permission.photos, '사진')) return;
    final settings = ref.read(settingsProvider).valueOrNull;
    if (settings == null) return;
    final markedDates = await _loadMarkedDates(settings.savePath);
    if (!mounted) return;

    final date = await showDialog<DateTime>(
      context: context,
      builder: (_) => MemoDatePickerDialog(
        initialDate: DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        markedDates: markedDates,
        title: '사진 일괄 추가하기',
      ),
    );
    if (date == null || !mounted) return;

    // 스캔 중 안내
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('사진 검색 중...'), duration: Duration(minutes: 1)),
    );
    final photos = await scanGalleryPhotosByDate(date);
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (photos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('해당 날짜에 촬영된 사진이 없습니다')),
      );
      return;
    }

    final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    // 50장 이상 추가 확인
    if (photos.length >= 50) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('사진이 많습니다'),
          content: Text('${photos.length}장의 사진이 검색됐습니다. 모두 추가하시겠습니까?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('추가')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    // 확인 다이얼로그
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('사진 일괄 추가'),
        content: Text('$dateStr에 촬영된 사진 ${photos.length}장을\n메모에 추가하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('추가')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final savePath = settings.savePath;

    // 진행률 다이얼로그
    final progress = ValueNotifier<int>(0);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ImportProgressDialog(progress: progress, total: photos.length),
    );

    // 기존 사진 타임스탬프 수집 (중복 방지) — 초 단위 비교, 구 HH:mm 형식 하위 호환
    DateTime toSecond(DateTime dt) =>
        DateTime(dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second);

    final existing = await ref.read(memoRepositoryProvider).loadDayFile(date, savePath);
    final existingPhotoSeconds = existing?.entries
        .where((e) => e.isPhoto)
        .map((e) => toSecond(e.timestamp))
        .toSet() ?? <DateTime>{};

    // 사진 처리
    final entries = <MemoEntry>[];
    int skipped = 0;
    for (int i = 0; i < photos.length; i++) {
      final photo = photos[i];
      final photoSec = toSecond(photo.timestamp);
      final photoMin = DateTime(photo.timestamp.year, photo.timestamp.month,
          photo.timestamp.day, photo.timestamp.hour, photo.timestamp.minute);
      if (existingPhotoSeconds.contains(photoSec) || existingPhotoSeconds.contains(photoMin)) {
        skipped++;
        progress.value = i + 1;
        continue;
      }
      final ts = photo.timestamp.millisecondsSinceEpoch;
      final cachePath = await copyContentUriToCache(photo.contentUri);
      if (cachePath != null) {
        final ext = cachePath.contains('.') ? cachePath.split('.').last.toLowerCase() : 'jpg';
        final dest = await MemoInputSheet.copyGalleryPhoto(
          cachePath, savePath,
          filenameOverride: 'import_${ts}_$i.$ext',
        );
        if (dest != null) {
          entries.add(MemoEntry(
            timestamp: photo.timestamp,
            latitude: photo.lat,
            longitude: photo.lng,
            photoPath: dest,
          ));
        }
      }
      progress.value = i + 1;
    }

    // 벌크 저장
    if (entries.isNotEmpty) {
      await ref.read(memoRepositoryProvider).appendEntries(date, entries, savePath);
      final today = DateTime.now();
      if (date.year == today.year && date.month == today.month && date.day == today.day) {
        ref.invalidate(todayFileProvider);
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop(); // 진행률 다이얼로그 닫기

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(skipped > 0
            ? '${entries.length}개 사진 추가, $skipped개 중복 건너뜀'
            : '${entries.length}개 사진을 메모에 추가했습니다'),
      ),
    );

    // 오늘이 아닌 날짜면 해당 메모로 이동
    final today = DateTime.now();
    final isToday = date.year == today.year && date.month == today.month && date.day == today.day;
    if (!isToday && entries.isNotEmpty && mounted) {
      final y = date.year;
      final m = date.month.toString().padLeft(2, '0');
      final d = date.day.toString().padLeft(2, '0');
      final filePath = '$savePath/$y-$m-$d.md';
      context.push('${AppRoutes.fileList}/${Uri.encodeComponent(filePath)}?name=${Uri.encodeComponent('$y-$m-$d')}');
    }
  }

  Future<void> _onPhotoTap() async {
    if (!await _requireFolderSetup()) return;
    if (!await _requirePermission(Permission.camera, '카메라')) return;
    if (!await _requirePermission(Permission.photos, '사진')) return;
    if (!mounted) return;
    final result = await MemoInputSheet.pickMedia(context, ref);
    if (result == null || !mounted) return;

    Future<void> Function(MemoEntry)? onAddSave;
    bool savedToPhotoDate = false;
    String? photoFilePath;

    if (!result.isVideo && result.timestamp != null) {
      final today = DateTime.now();
      final photoDate = result.timestamp!;
      if (photoDate.year != today.year ||
          photoDate.month != today.month ||
          photoDate.day != today.day) {
        final m = today.month.toString().padLeft(2, '0');
        final d = today.day.toString().padLeft(2, '0');
        final choice = await _showPhotoDateDialog(
          context, photoDate, '오늘 (${today.year}-$m-$d)');
        if (!mounted || choice == _PhotoDateChoice.cancel) return;
        if (choice == _PhotoDateChoice.photoDate) {
          final savePath = ref.read(settingsProvider).valueOrNull?.savePath ?? '';
          final repo = ref.read(memoRepositoryProvider);
          final py = photoDate.year;
          final pm = photoDate.month.toString().padLeft(2, '0');
          final pd = photoDate.day.toString().padLeft(2, '0');
          photoFilePath = '$savePath/$py-$pm-$pd.md';
          onAddSave = (entry) async {
            await repo.appendEntry(photoDate, entry, savePath);
            savedToPhotoDate = true;
          };
        }
      }
    }

    if (!mounted) return;
    await MemoInputSheet.show(context,
      initialPhotoPath: result.isVideo ? null : result.path,
      initialVideoPath: result.isVideo ? result.path : null,
      initialFishLength: result.length,
      initialLatitude: result.gps?.lat,
      initialLongitude: result.gps?.lng,
      initialTimestamp: result.timestamp,
      onAddSave: onAddSave,
    );

    if (savedToPhotoDate && photoFilePath != null && mounted) {
      final name = photoFilePath.split('/').last.replaceAll('.md', '');
      context.push(
        '${AppRoutes.fileList}/${Uri.encodeComponent(photoFilePath)}?name=${Uri.encodeComponent(name)}',
      );
    }
  }

  Future<void> _onLocationTap() async {
    if (!await _requirePermission(Permission.locationWhenInUse, '위치')) return;
    if (!mounted) return;
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

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (_) => _LocationPreviewSheet(location: loc),
    );
    if (confirmed == true && mounted) {
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
  final _openItemKey = ValueNotifier<Key?>(null);
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
    _openItemKey.dispose();
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
          openNotifier: _openItemKey,
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
              ? MemoEntryCard(entry: block, savePath: ref.read(settingsProvider).valueOrNull?.savePath ?? '')
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
  final ValueNotifier<Key?> openNotifier;

  const _SwipeItem({
    super.key,
    required this.child,
    required this.onEdit,
    required this.onDelete,
    required this.openNotifier,
  });

  @override
  State<_SwipeItem> createState() => _SwipeItemState();
}

class _SwipeItemState extends State<_SwipeItem> {
  static const double _actionWidth = 130.0;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    widget.openNotifier.addListener(_onOpenChanged);
  }

  @override
  void dispose() {
    widget.openNotifier.removeListener(_onOpenChanged);
    super.dispose();
  }

  void _onOpenChanged() {
    if (_open && widget.openNotifier.value != widget.key) {
      setState(() => _open = false);
    }
  }

  void _toggle(bool open) {
    setState(() => _open = open);
    if (open) {
      widget.openNotifier.value = widget.key;
    } else if (widget.openNotifier.value == widget.key) {
      widget.openNotifier.value = null;
    }
  }

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
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      height: 80 + bottomPadding,
      padding: EdgeInsets.fromLTRB(24, 0, 24, bottomPadding),
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
          ActionButton(icon: Icons.edit_note, label: '메모', onTap: onVoiceTap),
          ActionButton(icon: Icons.camera_alt, label: '사진', onTap: onPhotoTap),
          ActionButton(icon: Icons.map_outlined, label: '지도', onTap: onMapTap),
        ],
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
                '환경 추가',
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

// ── 이동 경로 기록 토글 FAB ────────────────────────────────

class _TrackingFab extends ConsumerStatefulWidget {
  const _TrackingFab();

  @override
  ConsumerState<_TrackingFab> createState() => _TrackingFabState();
}

class _TrackingFabState extends ConsumerState<_TrackingFab>
    with WidgetsBindingObserver {
  bool _isActive = false;
  int _trackCount = 0;
  Timer? _flushTimer;
  double _right = 16;
  double _bottom = 172;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshStatus();
    // 메모 저장 등으로 todayFileProvider가 갱신될 때 트래킹 카운트도 재조회
    ref.listenManual(todayFileProvider, (_, _) => _refreshCount());
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    final active = await TrackingService().isTracking();
    if (!mounted) return;
    setState(() => _isActive = active);
    final settingsActive =
        ref.read(settingsProvider).valueOrNull?.locationTrackingEnabled ?? false;
    if (settingsActive != active) {
      await ref.read(settingsProvider.notifier).updateLocationTrackingEnabled(active);
    }
    await _refreshCount();
    if (active && _flushTimer == null) _startFlushTimer();
  }

  Future<void> _refreshCount() async {
    final settings = ref.read(settingsProvider).valueOrNull;
    if (settings == null || settings.savePath.isEmpty) return;
    final today = DateTime.now();
    final repo = ref.read(memoRepositoryProvider);
    final pending = await TrackingService().getAndClearTrackPoints();
    if (pending.isNotEmpty) {
      final byDate = <DateTime, List<TrackPoint>>{};
      for (final p in pending) {
        final d = DateTime(p.timestamp.year, p.timestamp.month, p.timestamp.day);
        byDate.putIfAbsent(d, () => []).add(p);
      }
      for (final entry in byDate.entries) {
        await repo.appendTrackPoints(entry.key, entry.value, settings.savePath);
      }
    }
    final dayFile = await repo.loadDayFile(today, settings.savePath);
    if (mounted) setState(() => _trackCount = dayFile?.trackPoints.length ?? 0);
  }

  void _startFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshCount());
  }

  Future<void> _onTap() async {
    if (_isActive) {
      _flushTimer?.cancel();
      _flushTimer = null;
      await TrackingService().stopTracking();
      await ref.read(settingsProvider.notifier).updateLocationTrackingEnabled(false);
      if (mounted) setState(() => _isActive = false);
      await _refreshCount();
      return;
    }

    if (!await Permission.locationWhenInUse.isGranted) {
      final status = await Permission.locationWhenInUse.request();
      if (!status.isGranted) return;
    }

    var bgStatus = await Permission.locationAlways.status;
    if (!bgStatus.isGranted) {
      bgStatus = await Permission.locationAlways.request();
    }
    if (!bgStatus.isGranted) {
      if (!mounted) return;
      final shouldOpen = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('백그라운드 위치 권한 필요'),
          content: const Text(
            '백그라운드에서 이동 경로를 기록하려면\n'
            '위치 권한을 "항상 허용"으로 설정해야 합니다.\n\n'
            '설정 → 권한 → 위치 → 항상 허용',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('설정 열기'),
            ),
          ],
        ),
      );
      if (shouldOpen == true) openAppSettings();
      return;
    }

    final settings = ref.read(settingsProvider).valueOrNull;
    final interval = settings?.trackingIntervalMeters ?? 100;
    await TrackingService().startTracking(interval);
    await ref.read(settingsProvider.notifier).updateLocationTrackingEnabled(true);
    if (mounted) setState(() => _isActive = true);
    _startFlushTimer();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Positioned(
      right: _right.clamp(0.0, mq.size.width - 64.0),
      bottom: _bottom.clamp(0.0, mq.size.height - 200.0),
      child: GestureDetector(
        onTap: _onTap,
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
              colors: _isActive
                  ? [
                      Color.alphaBlend(const Color(0x70FFFFFF), Colors.green.shade600),
                      Color.alphaBlend(const Color(0x55000000), Colors.green.shade600),
                    ]
                  : [
                      Color.alphaBlend(
                          const Color(0x70FFFFFF),
                          Theme.of(context).colorScheme.secondary),
                      Color.alphaBlend(
                          const Color(0x55000000),
                          Theme.of(context).colorScheme.secondary),
                    ],
            ),
            boxShadow: const [
              BoxShadow(blurRadius: 2, offset: Offset(0, 4), color: Color(0x99000000)),
              BoxShadow(blurRadius: 12, offset: Offset(0, 8), color: Color(0x44000000)),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isActive ? Icons.route : Icons.route_outlined,
                color: _isActive ? Colors.white : Theme.of(context).colorScheme.onSecondary,
                size: 22,
              ),
              Text(
                _isActive ? '기록 중' : '이동 경로 기록',
                style: TextStyle(
                  color: _isActive ? Colors.white : Theme.of(context).colorScheme.onSecondary,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_trackCount > 0)
                Text(
                  '$_trackCount',
                  style: TextStyle(
                    color: _isActive ? Colors.white70 : Theme.of(context).colorScheme.onSecondary.withValues(alpha: 0.7),
                    fontSize: 8,
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
        actions: [
          IconButton(
            icon: const Icon(Icons.today_outlined),
            tooltip: '오늘 메모로 가기',
            onPressed: () => context.go(AppRoutes.home),
          ),
        ],
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
          if (ref.watch(settingsProvider).valueOrNull?.showTrackingButton ?? true)
            const _TrackingFab(),
        ],
      ),
      bottomNavigationBar: _ActionBar(
        onVoiceTap: () => _openMemoSheet(),
        onPhotoTap: _onPhotoTap,
        onMapTap: () => context.push(AppRoutes.map, extra: widget.filePath),
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
    final result = await MemoInputSheet.pickMedia(context, ref);
    if (result == null || !mounted) return;

    Future<void> Function(MemoEntry) addSave =
        (entry) => ref.read(dayFileProvider(widget.filePath).notifier).addEntry(entry);
    bool savedToPhotoDate = false;
    String? photoFilePath;

    if (!result.isVideo && result.timestamp != null) {
      final filename = widget.filePath.replaceAll('\\', '/').split('/').last;
      final screenDate = FileNameParser.parseDate(filename);
      final photoDate = result.timestamp!;
      if (screenDate != null &&
          (photoDate.year != screenDate.year ||
           photoDate.month != screenDate.month ||
           photoDate.day != screenDate.day)) {
        final sy = screenDate.year;
        final sm = screenDate.month.toString().padLeft(2, '0');
        final sd = screenDate.day.toString().padLeft(2, '0');
        final choice = await _showPhotoDateDialog(
          context, photoDate, '$sy-$sm-$sd');
        if (!mounted || choice == _PhotoDateChoice.cancel) return;
        if (choice == _PhotoDateChoice.photoDate) {
          final savePath = ref.read(settingsProvider).valueOrNull?.savePath ?? '';
          final repo = ref.read(memoRepositoryProvider);
          final py = photoDate.year;
          final pm = photoDate.month.toString().padLeft(2, '0');
          final pd = photoDate.day.toString().padLeft(2, '0');
          photoFilePath = '$savePath/$py-$pm-$pd.md';
          addSave = (entry) async {
            await repo.appendEntry(photoDate, entry, savePath);
            savedToPhotoDate = true;
          };
        }
      }
    }

    if (!mounted) return;
    await MemoInputSheet.show(
      context,
      initialPhotoPath: result.isVideo ? null : result.path,
      initialVideoPath: result.isVideo ? result.path : null,
      initialFishLength: result.length,
      initialLatitude: result.gps?.lat,
      initialLongitude: result.gps?.lng,
      initialTimestamp: result.timestamp,
      onAddSave: addSave,
    );

    if (savedToPhotoDate && photoFilePath != null && mounted) {
      final name = photoFilePath.split('/').last.replaceAll('.md', '');
      context.push(
        '${AppRoutes.fileList}/${Uri.encodeComponent(photoFilePath)}?name=${Uri.encodeComponent(name)}',
      );
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

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (_) => _LocationPreviewSheet(location: loc),
    );
    if (confirmed == true && mounted) {
      await ref
          .read(dayFileProvider(widget.filePath).notifier)
          .addLocationBlock(loc);
    }
  }

}

// ── 사진 날짜 선택 다이얼로그 헬퍼 ────────────────────────────

enum _PhotoDateChoice { photoDate, current, cancel }

Future<_PhotoDateChoice> _showPhotoDateDialog(
  BuildContext context,
  DateTime photoDate,
  String currentLabel,
) async {
  final py = photoDate.year;
  final pm = photoDate.month.toString().padLeft(2, '0');
  final pd = photoDate.day.toString().padLeft(2, '0');
  final photoLabel = '$py-$pm-$pd';
  final result = await showDialog<_PhotoDateChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('메모 날짜 선택'),
      content: Text('사진 촬영 날짜: $photoLabel\n어느 날짜의 메모에 추가하겠습니까?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(_PhotoDateChoice.cancel),
          child: const Text('취소'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.of(ctx).pop(_PhotoDateChoice.current),
          child: Text(currentLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(_PhotoDateChoice.photoDate),
          child: Text(photoLabel),
        ),
      ],
    ),
  );
  return result ?? _PhotoDateChoice.cancel;
}

class _ImportProgressDialog extends StatelessWidget {
  final ValueNotifier<int> progress;
  final int total;
  const _ImportProgressDialog({required this.progress, required this.total});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ValueListenableBuilder<int>(
          valueListenable: progress,
          builder: (_, current, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('사진 추가 중...', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: total > 0 ? current / total : 0),
              const SizedBox(height: 8),
              Text('$current / $total'),
            ],
          ),
        ),
      ),
    );
  }
}

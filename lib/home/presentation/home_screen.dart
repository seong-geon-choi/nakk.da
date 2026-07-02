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
import '../../core/widgets/location_share_card.dart';
import '../../core/utils/widget_capture.dart';
import '../../core/utils/date_formatter.dart';
import '../../features/memo/domain/models/memo_entry.dart';
import '../../features/memo/domain/models/day_file.dart';
import '../../features/location/domain/models/location_status.dart';
import '../../features/tide/domain/models/tide_station.dart';
import '../../features/memo/presentation/memo_provider.dart';
import '../../features/backup/presentation/backup_provider.dart';
import '../../features/memo/presentation/memo_input_sheet.dart';
import '../../features/memo/presentation/location_edit_sheet.dart';
import '../../features/memo/presentation/outing_edit_sheet.dart';
import '../../features/settings/presentation/settings_provider.dart';
import '../../features/location/presentation/location_provider.dart';
import '../../features/file_list/presentation/file_list_provider.dart';
import '../../features/file_list/domain/models/file_summary.dart';
import '../../core/utils/file_name_parser.dart';
import '../../core/utils/media_scanner.dart';
import '../../core/utils/species_detector.dart';
import '../../core/utils/exif_utils.dart';
import '../../core/widgets/memo_date_picker_dialog.dart';
import '../../core/services/saf_service.dart';
import '../../core/services/memo_share_service.dart';
import '../../core/services/app_update_service.dart';
import '../../core/widgets/app_toast.dart';
import 'dart:io';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 당일 현황 블록 중 물때가 가장 많은 것을 조위 그래프용으로 선택(물때명 포함).
({List<TideEvent> tides, String? name}) _outingTideInfo(DayFile? dayFile) {
  if (dayFile == null) return (tides: const [], name: null);
  List<TideEvent> best = const [];
  String? name;
  for (final loc in dayFile.locationBlocks) {
    if (loc.tides.length > best.length) {
      best = loc.tides;
      name = loc.tideName;
    }
  }
  return (tides: best, name: name);
}

/// 하루치 메모를 시스템 공유 시트로 내보낸다(블로그/카페 등 사용자가 앱 선택).
Future<void> _shareDayMemo(
  BuildContext context, {
  required List<dynamic> blocks,
  required String displayName,
  required String savePath,
}) async {
  if (blocks.isEmpty) {
    showAppToast(context, '공유할 메모가 없습니다');
    return;
  }
  // 공유 시트가 뜨는 즉시(카페 앱으로 넘어가기 직전) 안내가 보이도록 share 호출 전에 표시.
  // 공유 시트로 배경이 어두워지므로 강조형으로 띄운다.
  showAppToast(
    context,
    '본문은 클립보드에 복사됨 · 사진 위치를 조정해 주세요',
    duration: const Duration(seconds: 3),
    emphasized: true,
  );
  // 현장정보 블록을 카드 이미지로 캡처해 함께 첨부
  final envCards = await _captureEnvCards(context, blocks);
  await MemoShareService().shareDay(
    blocks: blocks,
    displayName: displayName,
    savePath: savePath,
    extraImages: envCards,
  );
}

/// 현장정보(LocationStatus) 블록을 상세 카드 이미지(PNG)로 캡처한다.
/// 실패한 카드는 건너뛰고, 사진보다 앞에 첨부되도록 순서대로 반환한다.
Future<List<XFile>> _captureEnvCards(
    BuildContext context, List<dynamic> blocks) async {
  final result = <XFile>[];
  Directory? tmp;
  var idx = 0;
  for (final b in blocks) {
    if (b is! LocationStatus) continue;
    if (!context.mounted) break;
    final png = await captureWidgetToPng(context, LocationShareCard(status: b));
    if (png == null) continue;
    tmp ??= await getTemporaryDirectory();
    final file = File('${tmp.path}/env_card_${idx++}.png');
    await file.writeAsBytes(png);
    result.add(XFile(file.path, mimeType: 'image/png'));
  }
  return result;
}

/// 지정 날짜(scanDate)에 촬영된 갤러리 사진을 스캔해 메모에 일괄 추가한다.
/// targetDate를 주면 그 날짜 메모에 저장(미지정 시 scanDate와 동일).
/// 진행률·확인 다이얼로그·결과 스낵바를 자체 처리하고, 추가된 장수를 반환한다(취소·없음=0).
/// 사진 권한은 호출하는 쪽에서 먼저 확인한다.
Future<int> _runPhotoImport(
    BuildContext context, WidgetRef ref, DateTime scanDate,
    {DateTime? targetDate}) async {
  final date = scanDate; // 스캔(촬영) 날짜
  final target = targetDate ?? scanDate; // 저장 대상 메모 날짜
  final settings = ref.read(settingsProvider).valueOrNull;
  if (settings == null) return 0;

  // 스캔 중 안내
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('사진 검색 중...'), duration: Duration(minutes: 1)),
  );
  final photos = await scanGalleryPhotosByDate(date);
  if (!context.mounted) return 0;
  ScaffoldMessenger.of(context).hideCurrentSnackBar();

  if (photos.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('해당 날짜에 촬영된 사진이 없습니다')),
    );
    return 0;
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
    if (ok != true || !context.mounted) return 0;
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
  if (confirmed != true || !context.mounted) return 0;

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

  final existing = await ref.read(memoRepositoryProvider).loadDayFile(target, savePath);
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
    final originPath = photo.path;
    if (originPath != null && originPath.isNotEmpty) {
      // 갤러리 원본 경로 직접 참조 (복사 없음 — 단건 추가와 동일 방식)
      entries.add(MemoEntry(
        timestamp: photo.timestamp,
        latitude: photo.lat,
        longitude: photo.lng,
        photoPath: originPath,
      ));
    } else {
      // 절대경로를 얻지 못한 경우에만 photos/로 복사 (폴백)
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
    }
    progress.value = i + 1;
  }

  // 벌크 저장 (저장 대상은 target 메모)
  if (entries.isNotEmpty) {
    await ref.read(memoRepositoryProvider).appendEntries(target, entries, savePath);
    ref.invalidate(dayFileProvider('$savePath/${target.year}-'
        '${target.month.toString().padLeft(2, '0')}-'
        '${target.day.toString().padLeft(2, '0')}.md'));
    // 백업 동기화 — 단건 추가와 동일하게 md 1회 + 사진별 1회 (백그라운드)
    final backup = ref.read(backupProvider.notifier);
    unawaited(backup.syncMdFile(target, savePath));
    for (final entry in entries) {
      if (entry.photoPath != null) {
        unawaited(backup.syncMediaFile(entry.photoPath!));
      }
    }
  }

  if (!context.mounted) return entries.length;
  Navigator.of(context).pop(); // 진행률 다이얼로그 닫기

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(skipped > 0
          ? '${entries.length}개 사진 추가, $skipped개 중복 건너뜀'
          : '${entries.length}개 사진을 메모에 추가했습니다'),
    ),
  );
  return entries.length;
}

class _Body extends ConsumerStatefulWidget {
  final DayFile? dayFile;
  final Future<void> Function(int, MemoEntry)? onEditMemoSave;
  final Future<void> Function(int, LocationStatus)? onEditLocationSave;
  final Future<void> Function(int)? onRemoveBlock;
  final Future<void> Function()? onRefresh; // 당겨서 새로고침

  const _Body({
    this.dayFile,
    this.onEditMemoSave,
    this.onEditLocationSave,
    this.onRemoveBlock,
    this.onRefresh,
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
    Widget content;
    if (dayFile == null || dayFile.blocks.isEmpty) {
      // 빈 상태에서도 당겨서 새로고침 되도록 스크롤 가능하게 감쌈
      content = LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: const EmptyStateView(
              icon: Icons.mic_none,
              message: '오늘의 메모가 없습니다',
              subMessage: '아래 버튼을 눌러 첫 메모를 남겨보세요',
            ),
          ),
        ),
      );
    } else {
      content = _buildList(dayFile);
    }
    if (widget.onRefresh != null) {
      return RefreshIndicator(onRefresh: widget.onRefresh!, child: content);
    }
    return content;
  }

  Widget _buildList(DayFile dayFile) {
    return ListView.separated(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
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
                final savePath =
                    ref.read(settingsProvider).valueOrNull?.savePath ?? '';
                ref
                    .read(dayFileProvider(todayMemoFilePath(savePath)).notifier)
                    .removeBlock(index);
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

class _LocationFab extends ConsumerStatefulWidget {
  final VoidCallback onTap;
  const _LocationFab({required this.onTap});

  @override
  ConsumerState<_LocationFab> createState() => _LocationFabState();
}

class _LocationFabState extends ConsumerState<_LocationFab> {
  double _right = 16;
  double _bottom = 100;

  @override
  void initState() {
    super.initState();
    _loadPosition();
  }

  Future<void> _loadPosition() async {
    try {
      final s = await ref.read(settingsProvider.future);
      if (!mounted) return;
      setState(() {
        _right = s.locationFabRight;
        _bottom = s.locationFabBottom;
      });
    } catch (_) {/* 설정 로드 실패 시 기본 위치 유지 */}
  }

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
        onPanEnd: (_) {
          ref
              .read(settingsProvider.notifier)
              .updateLocationFabPosition(_right, _bottom);
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
                '현장 정보',
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
    _reconcileTrackingOnStart();
    _loadPosition();
    // 오늘 메모 저장 등으로 갱신될 때 트래킹 카운트도 재조회
    final savePath = ref.read(settingsProvider).valueOrNull?.savePath ?? '';
    ref.listenManual(
        dayFileProvider(todayMemoFilePath(savePath)), (_, _) => _refreshCount());
  }

  Future<void> _loadPosition() async {
    try {
      final s = await ref.read(settingsProvider.future);
      if (!mounted) return;
      setState(() {
        _right = s.trackingFabRight;
        _bottom = s.trackingFabBottom;
      });
    } catch (_) {/* 설정 로드 실패 시 기본 위치 유지 */}
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
      // 대기 알림 스와이프로 감시가 중단됐으면 지도 아이콘을 정합화
      ref.read(settingsProvider.notifier).reconcileCommuteActive();
    }
  }

  /// 앱 시작 시 트래킹 상태를 정합화한다.
  /// 프로세스가 강제 종료되면 네이티브 서비스는 죽지만 active 플래그는 true로
  /// 남아(onDestroy 미호출) 버튼은 '기록중'인데 실제 수집은 멈춘다.
  /// → 사용자 의도(설정)가 ON이면 서비스를 (재)시작해 수집을 보장한다
  ///   (이미 떠 있으면 onStartCommand 재호출이라 무해, 권한 없으면 네이티브 no-op).
  Future<void> _reconcileTrackingOnStart() async {
    try {
      final settings = await ref.read(settingsProvider.future);
      if (settings.locationTrackingEnabled &&
          await Permission.locationWhenInUse.isGranted) {
        await TrackingService().startTracking(settings.trackingIntervalMeters);
      }
    } catch (_) {/* 설정/권한 조회 실패 시 아래 새로고침으로 폴백 */}
    await _refreshStatus();
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
    // 자정 등으로 네이티브가 트래킹을 멈추면 타이머를 정리해 버튼을 비활성화 유지
    if (active) {
      if (_flushTimer == null) _startFlushTimer();
    } else {
      _flushTimer?.cancel();
      _flushTimer = null;
    }
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
    // 30초마다 포인트 플러시 + 네이티브 트래킹 상태 재확인(자정 자동 종료 반영)
    _flushTimer = Timer.periodic(const Duration(seconds: 30), (_) => _refreshStatus());
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
    // 활성화 즉시 현재 위치를 1포인트 기록 (정지 상태에선 네이티브 첫 픽스가
    // 최소 이동거리 필터로 지연되므로, 클릭 시점에 바로 한 점 남기고 카운트 표시)
    await _recordCurrentPointNow();
  }

  Future<void> _recordCurrentPointNow() async {
    final settings = ref.read(settingsProvider).valueOrNull;
    if (settings == null || settings.savePath.isEmpty) return;
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
    if (lat == null || lng == null) return;
    final now = DateTime.now();
    await ref.read(memoRepositoryProvider).appendTrackPoints(
      DateTime(now.year, now.month, now.day),
      [TrackPoint(lat: lat, lng: lng, timestamp: now)],
      settings.savePath,
    );
    await _refreshCount();
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
        onPanEnd: (_) {
          ref
              .read(settingsProvider.notifier)
              .updateTrackingFabPosition(_right, _bottom);
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
                _isActive ? '기록 중' : '경로 기록',
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
  final String? filePath;   // 진입점(앱 홈)이면 null → 내부에서 오늘 경로 계산
  final String? displayName;

  const DayMemoScreen({
    super.key,
    this.filePath,
    this.displayName,
  });

  @override
  ConsumerState<DayMemoScreen> createState() => _DayMemoScreenState();
}

class _DayMemoScreenState extends ConsumerState<DayMemoScreen>
    with WidgetsBindingObserver {
  // ── 통합 화면: 오늘 / 특정 날짜 공용 ──────────────────────
  /// 좌우 스와이프로 이동한 날짜 파일 경로(라우트 이동 없이 화면 안에서 전환).
  /// null이면 widget.filePath(또는 오늘)를 사용.
  String? _navPath;

  /// 앱 진입점(라우터 '/')인지 — 홈 전용 1회성 기능은 여기서만 실행.
  bool get _isEntryPoint => widget.filePath == null;

  /// 대상 날짜가 오늘인지(UI 분기용) — 현재 표시 경로의 날짜로 판정.
  bool get _isToday {
    final d = FileNameParser.parseDate(
        _filePath.replaceAll('\\', '/').split('/').last);
    if (d == null) return false;
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  /// 현재 표시 중인 파일 경로
  /// (스와이프 이동값 > 생성자 지정값 > 진입점이면 오늘 경로)
  String get _filePath {
    if (_navPath != null) return _navPath!;
    final explicit = widget.filePath;
    if (explicit != null) return explicit;
    final sp = ref.read(settingsProvider).valueOrNull?.savePath ?? '';
    final d = DateTime.now();
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$sp/${d.year}-$m-$day.md';
  }

  String get _displayName {
    if (_navPath != null) {
      final d = FileNameParser.parseDate(
          _navPath!.replaceAll('\\', '/').split('/').last);
      if (d != null) return DateFormatter.toDateString(d);
    }
    return widget.displayName ?? DateFormatter.toDateString(DateTime.now());
  }

  @override
  void initState() {
    super.initState();
    if (_isEntryPoint) {
      // 홈 전용: 음성 접근성 결과 수신 + 앱 시작 시 폴더설정·업데이트 안내
      WidgetsBinding.instance.addObserver(this);
      setVoiceResultHandler(_handleVoiceResult);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkPendingVoiceResult();
        _autoSetupSaveFolderIfNeeded();
        _maybePromptUpdate();
      });
    }
  }

  @override
  void dispose() {
    if (_isEntryPoint) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isEntryPoint && state == AppLifecycleState.resumed) {
      _checkPendingVoiceResult();
    }
  }

  // ── 홈 전용 로직(isToday일 때만 호출) ─────────────────────
  Future<void> _maybePromptUpdate() async {
    if (!await AppUpdateService.isUpdateAvailable()) return;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('업데이트 안내'),
        content: const Text('새로운 버전이 있습니다. 지금 업데이트할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (ok == true) {
      await AppUpdateService.performImmediateUpdate();
    } else {
      showAppToast(context, '플레이스토어에서 업데이트를 받을 수 있습니다',
          duration: const Duration(seconds: 3));
    }
  }

  Future<void> _autoSetupSaveFolderIfNeeded() async {
    final settings = ref.read(settingsProvider).valueOrNull;
    if (settings == null || !settings.needsFolderSetup) return;
    if (!mounted) return;
    await ref.read(settingsProvider.notifier).pickSaveFolder();
  }

  void _handleVoiceResult(String text) {
    if (!mounted) return;
    final autoSave = ref.read(settingsProvider).valueOrNull?.autoSaveVoice ?? false;
    if (autoSave) {
      _saveVoiceDirectly(text);
    } else {
      MemoInputSheet.show(context,
          initialText: text,
          onAddSave: (entry) =>
              ref.read(dayFileProvider(_filePath).notifier).addEntry(entry));
    }
  }

  Future<void> _checkPendingVoiceResult() async {
    final text = await getPendingVoiceResult();
    if (text != null && mounted) {
      await clearPendingVoiceResult();
      if (!mounted) return;
      _handleVoiceResult(text);
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
    await ref.read(dayFileProvider(_filePath).notifier).addEntry(MemoEntry(
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

  // ── 공통 헬퍼 ────────────────────────────────────────────
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

  Future<void> _onFileListTap() async {
    if (!await _requireFolderSetup()) return;
    if (mounted) context.push(AppRoutes.fileList);
  }

  Future<void> _onMapTap() async {
    if (!await _requireFolderSetup()) return;
    if (!await _requirePermission(Permission.locationWhenInUse, '위치')) return;
    if (mounted) context.push(AppRoutes.map, extra: _isToday ? null : _filePath);
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

  /// 날짜 선택 후 사진 일괄 추가(오늘 화면 전용 진입점).
  Future<void> _importPickDayPhotos() async {
    if (!await _requireFolderSetup()) return;
    if (!await _requirePermission(Permission.photos, '사진')) return;
    final settings = ref.read(settingsProvider).valueOrNull;
    if (settings == null) return;
    final markedDates = await _loadMarkedDates(settings.savePath);
    if (!mounted) return;
    final now = DateTime.now();
    final screenName = _filePath.replaceAll('\\', '/').split('/').last;
    final screenDate = FileNameParser.parseDate(screenName) ?? now;
    final date = await showDialog<DateTime>(
      context: context,
      builder: (_) => MemoDatePickerDialog(
        initialDate: screenDate.isAfter(now) ? now : screenDate,
        firstDate: DateTime(2020),
        lastDate: now,
        markedDates: markedDates,
        title: '사진 일괄 추가하기',
      ),
    );
    if (date == null || !mounted) return;

    // 저장 위치 선택: 선택한 날짜(D)가 현재 화면 날짜와 다르면
    // "D 날짜 메모 vs 현재 메모" 중 선택 (같으면 바로 추가)
    final sameDay = date.year == screenDate.year &&
        date.month == screenDate.month &&
        date.day == screenDate.day;
    DateTime targetDate = date;
    if (!sameDay) {
      final choice = await _showPhotoDateDialog(context, date, _displayName);
      if (!mounted || choice == _PhotoDateChoice.cancel) return;
      targetDate = choice == _PhotoDateChoice.photoDate ? date : screenDate;
    }

    final added =
        await _runPhotoImport(context, ref, date, targetDate: targetDate);
    if (added <= 0 || !mounted) return;

    // 저장 대상이 현재 화면과 다른 날짜면 그 메모로 이동
    final toCurrent = targetDate.year == screenDate.year &&
        targetDate.month == screenDate.month &&
        targetDate.day == screenDate.day;
    if (toCurrent) {
      ref.invalidate(dayFileProvider(_filePath));
    } else {
      final savePath = ref.read(settingsProvider).valueOrNull?.savePath ?? '';
      final y = targetDate.year;
      final m = targetDate.month.toString().padLeft(2, '0');
      final d = targetDate.day.toString().padLeft(2, '0');
      final filePath = '$savePath/$y-$m-$d.md';
      ref.invalidate(dayFileProvider(filePath));
      context.push(
          '${AppRoutes.fileList}/${Uri.encodeComponent(filePath)}?name=${Uri.encodeComponent('$y-$m-$d')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = _filePath;
    final asyncFile = ref.watch(dayFileProvider(path));
    final settingsAsync = ref.watch(settingsProvider);
    final showLocationButton =
        settingsAsync.valueOrNull?.showLocationButton ?? true;
    final notifier = ref.read(dayFileProvider(path).notifier);
    ref.watch(fileListProvider); // 날짜 스와이프 이동용 목록 미리 로드
    final needsSetup =
        _isToday && (settingsAsync.valueOrNull?.needsFolderSetup ?? false);

    final content = asyncFile.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => EmptyStateView(
        icon: Icons.error_outline,
        message: '불러오기 실패',
        subMessage: e.toString(),
      ),
      data: (dayFile) {
        final body = GestureDetector(
          // 카드가 없는 빈 영역 가로 스와이프 → 이전/이후 날짜 메모 이동
          // (카드 위 가로 스와이프는 자식 _SwipeItem이 우선 처리: 편집/삭제)
          behavior: HitTestBehavior.translucent,
          onHorizontalDragEnd: (details) {
            final v = details.primaryVelocity;
            if (v == null) return;
            if (v < -250) {
              _navigateDay(1); // 왼쪽 스와이프 → 이후(미래) 날짜
            } else if (v > 250) {
              _navigateDay(-1); // 오른쪽 스와이프 → 이전(과거) 날짜
            }
          },
          child: _Body(
            dayFile: dayFile,
            onEditMemoSave: (idx, entry) => notifier.editBlock(idx, entry),
            onEditLocationSave: (idx, loc) => notifier.editBlock(idx, loc),
            onRemoveBlock: (idx) => notifier.removeBlock(idx),
            onRefresh: () async {
              ref.invalidate(dayFileProvider(path));
              ref.invalidate(fileListProvider);
              await ref.read(dayFileProvider(path).future);
            },
          ),
        );
        // 낚시-복잡 모드: 상단에 출조 정보(태클·조과) 카드 노출
        if (!(settingsAsync.valueOrNull?.showComplexInput ?? false)) {
          return body;
        }
        final outingDate = FileNameParser.parseDate(
            path.replaceAll('\\', '/').split('/').last);
        return Column(
          children: [
            OutingSummaryCard(
              outing: dayFile?.outing,
              date: outingDate,
              onTap: () {
                final t = _outingTideInfo(dayFile);
                OutingEditSheet.show(
                  context,
                  initial: dayFile?.outing,
                  date: outingDate,
                  tides: t.tides,
                  tideName: t.name,
                  onSave: (o) => notifier.updateOuting(o),
                );
              },
            ),
            Expanded(child: body),
          ],
        );
      },
    );

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _onFileListTap,
          child: Text(
            _displayName,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        actions: [
          if (settingsAsync.valueOrNull?.shareEnabled ?? false)
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: '공유',
              onPressed: () => _shareDayMemo(
                context,
                blocks: asyncFile.valueOrNull?.blocks ?? const [],
                displayName: _displayName,
                savePath: settingsAsync.valueOrNull?.savePath ?? '',
              ),
            ),
          IconButton(
            icon: const Icon(Icons.add_photo_alternate_outlined),
            tooltip: '사진 일괄 추가',
            onPressed: _importPickDayPhotos,
          ),
          if (_isToday)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: '설정',
              onPressed: () => context.push(AppRoutes.settings),
            )
          else
            TextButton(
              // 진입점(홈)에서 스와이프로 과거를 보는 중이면 화면 안에서 오늘로 복귀,
              // 목록에서 진입한 화면이면 홈으로 이동
              onPressed: () {
                if (_isEntryPoint) {
                  setState(() => _navPath = null);
                } else {
                  context.go(AppRoutes.home);
                }
              },
              child: const Text('오늘'),
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
                content,
                if (showLocationButton) _LocationFab(onTap: _onLocationTap),
                if (settingsAsync.valueOrNull?.showTrackingButton ?? true)
                  const _TrackingFab(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _ActionBar(
        onVoiceTap: () {
          unawaited(_maybeAutoAddLocation());
          _openMemoSheet();
        },
        onPhotoTap: _onPhotoTap,
        onMapTap: _onMapTap,
      ),
    );
  }

  /// 빈 영역 가로 스와이프로 이전/이후 날짜의 기존 메모 파일로 이동.
  /// direction: +1 = 이후(미래), -1 = 이전(과거). 빈 날짜는 건너뛰고 다음 파일로.
  void _navigateDay(int direction) {
    final files = ref.read(fileListProvider).valueOrNull;
    if (files == null || files.isEmpty) return;
    final currentName = _filePath.replaceAll('\\', '/').split('/').last;
    final currentDate = FileNameParser.parseDate(currentName);
    if (currentDate == null) return;
    final sorted = [...files]..sort((a, b) => a.date.compareTo(b.date));
    FileSummary? target;
    if (direction > 0) {
      for (final f in sorted) {
        if (f.date.isAfter(currentDate)) {
          target = f;
          break;
        }
      }
    } else {
      for (final f in sorted.reversed) {
        if (f.date.isBefore(currentDate)) {
          target = f;
          break;
        }
      }
    }
    if (target == null) {
      showAppToast(context, direction > 0 ? '다음 메모가 없습니다' : '이전 메모가 없습니다');
      return;
    }
    // 라우트 이동 없이 화면 안에서 표시 날짜만 전환(뒤로가기 스택 영향 없음)
    setState(() => _navPath = target!.filePath);
  }

  /// 옵션이 켜져 있고 이 파일(오늘 날짜)에 현장 정보가 없으면 첫 기록 시 1회 자동 수집.
  /// 과거 날짜 파일엔 현재 위치를 넣지 않으므로 오늘 파일일 때만 동작한다.
  bool _autoLocTriggered = false;
  Future<void> _maybeAutoAddLocation() async {
    if (_autoLocTriggered) return;
    final settings = ref.read(settingsProvider).valueOrNull;
    if (settings == null || !settings.autoLocationOnFirstEntry) return;
    final filename = _filePath.replaceAll('\\', '/').split('/').last;
    final date = FileNameParser.parseDate(filename);
    final now = DateTime.now();
    if (date == null ||
        date.year != now.year ||
        date.month != now.month ||
        date.day != now.day) {
      return;
    }
    _autoLocTriggered = true; // 동시 탭 중복 방지용 in-flight 가드
    try {
      // 최신 상태로 확인: 삭제 직후 stale 데이터(삭제된 현황)로 인한 오판 방지
      final dayFile = await ref.read(dayFileProvider(_filePath).future);
      final blocks = dayFile?.blocks ?? const [];
      if (blocks.any((b) => b is LocationStatus)) return;
      if (!await Permission.locationWhenInUse.status.isGranted) {
        if (mounted) {
          showAppToast(context, '현장 정보 추가에 실패했습니다. 위치 권한을 추가해 주세요',
              duration: const Duration(seconds: 3));
        }
        return;
      }
      final loc = await ref
          .read(locationProvider.notifier)
          .buildEnrichedLocation(isMove: false);
      await ref
          .read(dayFileProvider(_filePath).notifier)
          .addLocationBlock(loc);
    } finally {
      // 성공·실패 무관하게 해제 → 메모 전체 삭제 후 재추가 시 다시 동작
      _autoLocTriggered = false;
    }
  }

  /// 이 화면의 날짜에 촬영된 사진을 일괄 추가한다(날짜 고정 → 선택 없이 바로).
  void _openMemoSheet({bool voiceMode = false}) {
    MemoInputSheet.show(
      context,
      voiceMode: voiceMode,
      onAddSave: (entry) =>
          ref.read(dayFileProvider(_filePath).notifier).addEntry(entry),
    );
  }

  Future<void> _onPhotoTap() async {
    unawaited(_maybeAutoAddLocation());
    final result = await MemoInputSheet.pickMedia(context, ref);
    if (result == null || !mounted) return;

    // 갤러리 멀티 선택: 편집 시트 없이 현재 메모에 일괄 추가
    if (result.multi != null) {
      await _addMultiToCurrent(result.multi!);
      return;
    }

    Future<void> Function(MemoEntry) addSave =
        (entry) => ref.read(dayFileProvider(_filePath).notifier).addEntry(entry);
    bool savedToPhotoDate = false;
    String? photoFilePath;

    if (!result.isVideo && result.timestamp != null) {
      final filename = _filePath.replaceAll('\\', '/').split('/').last;
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

  /// 갤러리에서 멀티 선택한 사진/동영상을 현재 보는 메모에 일괄 추가한다.
  /// 사진 시각·GPS는 각 파일 EXIF에서 읽고(없으면 현재시각), 편집 시트는 거치지 않는다.
  Future<void> _addMultiToCurrent(
      List<({String path, bool isVideo})> items) async {
    final savePath = ref.read(settingsProvider).valueOrNull?.savePath ?? '';
    if (savePath.isEmpty) return;
    final screenName = _filePath.replaceAll('\\', '/').split('/').last;
    final screenDate = FileNameParser.parseDate(screenName) ?? DateTime.now();
    final repo = ref.read(memoRepositoryProvider);

    final entries = <MemoEntry>[];
    for (final it in items) {
      DateTime ts = DateTime.now();
      double? lat;
      double? lng;
      if (!it.isVideo) {
        ts = await readExifTimestamp(it.path) ?? ts;
        final gps = await readExifGps(it.path);
        lat = gps?.lat;
        lng = gps?.lng;
      }
      entries.add(MemoEntry(
        timestamp: ts,
        latitude: lat,
        longitude: lng,
        photoPath: it.isVideo ? null : it.path,
        videoPath: it.isVideo ? it.path : null,
      ));
    }
    if (entries.isEmpty) return;

    await repo.appendEntries(screenDate, entries, savePath);
    ref.invalidate(dayFileProvider(_filePath));
    ref.invalidate(fileListProvider);
    final backup = ref.read(backupProvider.notifier);
    unawaited(backup.syncMdFile(screenDate, savePath));
    for (final e in entries) {
      if (e.photoPath != null) unawaited(backup.syncMediaFile(e.photoPath!));
      if (e.videoPath != null) unawaited(backup.syncMediaFile(e.videoPath!));
    }
    if (mounted) {
      showAppToast(context, '${entries.length}장을 추가했습니다');
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
            Text('현장 정보 수집 중...'),
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
          .read(dayFileProvider(_filePath).notifier)
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

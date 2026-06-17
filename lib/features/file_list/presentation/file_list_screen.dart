import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'file_list_provider.dart';
import '../domain/models/file_summary.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../core/router/app_router.dart';
import '../../settings/presentation/settings_provider.dart';

class FileListScreen extends ConsumerStatefulWidget {
  const FileListScreen({super.key});

  @override
  ConsumerState<FileListScreen> createState() => _FileListScreenState();
}

class _FileListScreenState extends ConsumerState<FileListScreen> {
  final Set<int> _expandedYears = {};
  final Set<int> _expandedMonths = {}; // yyyymm = year*100 + month
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(fileListProvider);
    });
  }

  void _toggleYear(int year) => setState(() {
        if (_expandedYears.contains(year)) {
          _expandedYears.remove(year);
        } else {
          _expandedYears.add(year);
        }
      });

  void _toggleMonth(int ym) => setState(() {
        if (_expandedMonths.contains(ym)) {
          _expandedMonths.remove(ym);
        } else {
          _expandedMonths.add(ym);
        }
      });

  // 연도 → 연·월(yyyymm) → 파일 2단계 그룹화
  Map<int, Map<int, List<FileSummary>>> _groupByYearMonth(
      List<FileSummary> files) {
    final map = <int, Map<int, List<FileSummary>>>{};
    for (final f in files) {
      final ym = f.date.year * 100 + f.date.month;
      ((map[f.date.year] ??= {})[ym] ??= []).add(f);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(fileListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('메모 목록'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: '조과 통계',
            onPressed: () => context.push(AppRoutes.stats),
          ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '검색',
            onPressed: () => context.push(AppRoutes.search),
          ),
        ],
      ),
      body: listAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyStateView(
          icon: Icons.error_outline,
          message: '목록을 불러오지 못했습니다',
          subMessage: e.toString(),
        ),
        data: (files) {
          if (files.isEmpty) {
            return const EmptyStateView(
              icon: Icons.folder_open,
              message: '저장된 메모가 없습니다',
              subMessage: '음성 또는 텍스트로 첫 메모를 남겨보세요',
            );
          }

          final grouped = _groupByYearMonth(files);
          final years = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

          // 첫 로드 시 가장 최근 연도 + 그 안의 최신 월 자동 확장
          if (!_initialized) {
            _initialized = true;
            final latestYear = years.first;
            _expandedYears.add(latestYear);
            _expandedMonths.add((grouped[latestYear]!.keys.toList()..sort()).last);
          }

          // 연도 헤더 / 월 헤더 / 파일이 섞인 플랫 리스트 구성
          final items = <dynamic>[];
          for (final year in years) {
            items.add(_YearMarker(year));
            if (!_expandedYears.contains(year)) continue;
            final monthsOfYear = grouped[year]!.keys.toList()
              ..sort((a, b) => b.compareTo(a));
            for (final ym in monthsOfYear) {
              items.add(_MonthMarker(ym));
              if (_expandedMonths.contains(ym)) {
                items.addAll(grouped[year]![ym]!);
              }
            }
          }

          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, index) {
              // 연속된 파일 항목 사이에만 구분선 표시
              if (items[index] is FileSummary &&
                  index + 1 < items.length &&
                  items[index + 1] is FileSummary) {
                return const Divider(height: 1, indent: 48, endIndent: 16);
              }
              return const SizedBox.shrink();
            },
            itemBuilder: (context, index) {
              final item = items[index];
              if (item is _YearMarker) {
                final total = grouped[item.year]!
                    .values
                    .fold<int>(0, (s, l) => s + l.length);
                return _YearHeader(
                  year: item.year,
                  count: total,
                  expanded: _expandedYears.contains(item.year),
                  onTap: () => _toggleYear(item.year),
                );
              }
              if (item is _MonthMarker) {
                final ym = item.yearMonth;
                return _MonthHeader(
                  yearMonth: ym,
                  count: grouped[ym ~/ 100]![ym]!.length,
                  expanded: _expandedMonths.contains(ym),
                  onTap: () => _toggleMonth(ym),
                );
              }
              return _FileItem(file: item as FileSummary);
            },
          );
        },
      ),
    );
  }
}

// 플랫 리스트에서 연도 헤더 / 월 헤더를 구분하기 위한 마커
class _YearMarker {
  final int year;
  const _YearMarker(this.year);
}

class _MonthMarker {
  final int yearMonth; // yyyymm = year*100 + month
  const _MonthMarker(this.yearMonth);
}

class _YearHeader extends StatelessWidget {
  final int year;
  final int count;
  final bool expanded;
  final VoidCallback onTap;

  const _YearHeader({
    required this.year,
    required this.count,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        child: Row(
          children: [
            AnimatedRotation(
              turns: expanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(Icons.chevron_right,
                  size: 20, color: colorScheme.primary),
            ),
            const SizedBox(width: 8),
            Text(
              '$year년',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count개',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  final int yearMonth; // yyyymm = year*100 + month
  final int count;
  final bool expanded;
  final VoidCallback onTap;

  const _MonthHeader({
    required this.yearMonth,
    required this.count,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        // 연도 헤더와 같은 스타일(파란색) — 단계는 들여쓰기로만 구분
        padding: const EdgeInsets.only(left: 36, right: 16, top: 10, bottom: 10),
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        child: Row(
          children: [
            AnimatedRotation(
              turns: expanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(Icons.chevron_right,
                  size: 20, color: colorScheme.primary),
            ),
            const SizedBox(width: 8),
            Text(
              '${yearMonth % 100}월',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count개',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileItem extends ConsumerStatefulWidget {
  final FileSummary file;
  const _FileItem({required this.file});

  @override
  ConsumerState<_FileItem> createState() => _FileItemState();
}

class _FileItemState extends ConsumerState<_FileItem> {
  FileSummary get file => widget.file;

  @override
  Widget build(BuildContext context) {
    final showAddress = ref.watch(
      settingsProvider.select((s) => s.valueOrNull?.showAddressInMemoName ?? true),
    );
    final textColor = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: () => _openViewer(context),
      onLongPress: () => _showContextMenu(),
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        // 월 헤더(left 36) 아래 단계임을 들여쓰기로 표현
        padding: const EdgeInsets.only(left: 48, right: 16, top: 12, bottom: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      text: file.displayName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                      children: showAddress && file.address != null
                          ? [
                              TextSpan(
                                text: ' (${file.address})',
                                style: TextStyle(
                                  fontSize: 12.8,
                                  fontWeight: FontWeight.normal,
                                  color: textColor.withValues(alpha: 0.4),
                                ),
                              ),
                            ]
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${file.entryCount}개',
              style: TextStyle(
                fontSize: 13,
                color: textColor.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              color: textColor.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }

  void _openViewer(BuildContext context) {
    final encoded = Uri.encodeComponent(file.filePath);
    context.push(
      '${AppRoutes.fileList}/$encoded?name=${Uri.encodeComponent(file.displayName)}',
    );
  }

  Future<void> _showContextMenu() async {
    final action = await showModalBottomSheet<_FileAction>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('이름 변경'),
              onTap: () => Navigator.of(sheetCtx).pop(_FileAction.rename),
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('복사'),
              onTap: () => Navigator.of(sheetCtx).pop(_FileAction.copy),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('삭제', style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.of(sheetCtx).pop(_FileAction.delete),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == _FileAction.rename) {
      await _showRenameDialog();
    } else if (action == _FileAction.copy) {
      await _showCopyDialog();
    } else if (action == _FileAction.delete) {
      await _showDeleteDialog();
    }
  }

  Future<void> _showRenameDialog() async {
    final controller = TextEditingController(text: file.displayName);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('이름 변경'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '파일 이름',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    final newName = controller.text.trim();
    // 다이얼로그 닫힘 애니메이션 완료 후 dispose (즉시 dispose 시 InheritedElement assertion 오류 방지)
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (confirmed == true && mounted) {
      if (newName.isNotEmpty && newName != file.displayName) {
        await ref.read(fileListProvider.notifier).rename(file.filePath, newName);
      }
    }
  }

  Future<void> _showCopyDialog() async {
    final controller = TextEditingController(text: '${file.displayName}_복사');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('복사'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '복사본 이름',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('복사'),
          ),
        ],
      ),
    );
    final newName = controller.text.trim();
    // 다이얼로그 닫힘 애니메이션 완료 후 dispose
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (confirmed == true && mounted) {
      if (newName.isNotEmpty) {
        await ref.read(fileListProvider.notifier).copy(file.filePath, newName);
      }
    }
  }

  Future<void> _showDeleteDialog() async {
    bool deletePhotos = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('메모 삭제'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${file.displayName} 을(를) 삭제할까요?'),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('연결된 사진도 함께 삭제',
                    style: TextStyle(fontSize: 14)),
                value: deletePhotos,
                onChanged: (v) => setState(() => deletePhotos = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('취소'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('삭제'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && mounted) {
      await ref
          .read(fileListProvider.notifier)
          .delete(file.filePath, deletePhotos: deletePhotos);
    }
  }
}

enum _FileAction { rename, copy, delete }

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'search_provider.dart';
import '../domain/models/search_hit.dart';
import '../../settings/presentation/settings_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../core/widgets/memo_entry_card.dart';
import '../../../core/utils/date_formatter.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _queryCtrl = TextEditingController();
  String _query = '';
  String? _species;
  DateTimeRange? _range;

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  bool _matches(SearchHit h) {
    if (_range != null) {
      final d = DateTime(h.date.year, h.date.month, h.date.day);
      if (d.isBefore(_range!.start) || d.isAfter(_range!.end)) return false;
    }
    if (_species != null && h.entry.fishSpecies != _species) return false;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      final inText = h.entry.text?.toLowerCase().contains(q) ?? false;
      final inSpecies = h.entry.fishSpecies?.toLowerCase().contains(q) ?? false;
      final inAddr = h.address?.toLowerCase().contains(q) ?? false;
      if (!inText && !inSpecies && !inAddr) return false;
    }
    return true;
  }

  /// 데이터에 존재하는 어종 목록 (빈도 내림차순)
  List<String> _speciesOptions(List<SearchHit> hits) {
    final counts = <String, int>{};
    for (final h in hits) {
      final s = h.entry.fishSpecies?.trim();
      if (s != null && s.isNotEmpty) counts[s] = (counts[s] ?? 0) + 1;
    }
    final list = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return list;
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _range,
    );
    if (picked != null) {
      setState(() => _range = DateTimeRange(
            start: DateTime(picked.start.year, picked.start.month, picked.start.day),
            end: DateTime(picked.end.year, picked.end.month, picked.end.day),
          ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hitsAsync = ref.watch(searchHitsProvider);
    final savePath = ref.watch(
        settingsProvider.select((s) => s.valueOrNull?.savePath ?? ''));

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _queryCtrl,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: '메모·어종·장소 검색',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _query = v.trim()),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _queryCtrl.clear();
                setState(() => _query = '');
              },
            ),
        ],
      ),
      body: hitsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyStateView(
          icon: Icons.error_outline,
          message: '검색 데이터를 불러오지 못했습니다',
          subMessage: e.toString(),
        ),
        data: (hits) {
          final speciesOptions = _speciesOptions(hits);
          final results = hits.where(_matches).toList();
          return Column(
            children: [
              _FilterBar(
                speciesOptions: speciesOptions,
                selectedSpecies: _species,
                range: _range,
                onSpecies: (s) => setState(() => _species = s),
                onPickRange: _pickRange,
                onClearRange: () => setState(() => _range = null),
              ),
              const Divider(height: 1),
              Expanded(
                child: results.isEmpty
                    ? EmptyStateView(
                        icon: Icons.search_off,
                        message: hits.isEmpty ? '저장된 메모가 없습니다' : '검색 결과가 없습니다',
                        subMessage: hits.isEmpty
                            ? null
                            : '다른 검색어나 필터를 시도해 보세요',
                      )
                    : _ResultList(results: results, savePath: savePath),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final List<String> speciesOptions;
  final String? selectedSpecies;
  final DateTimeRange? range;
  final ValueChanged<String?> onSpecies;
  final VoidCallback onPickRange;
  final VoidCallback onClearRange;

  const _FilterBar({
    required this.speciesOptions,
    required this.selectedSpecies,
    required this.range,
    required this.onSpecies,
    required this.onPickRange,
    required this.onClearRange,
  });

  String _rangeLabel(DateTimeRange r) {
    String f(DateTime d) =>
        '${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
    return '${f(r.start)} ~ ${f(r.end)}';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // 날짜 범위
          InputChip(
            avatar: const Icon(Icons.date_range, size: 18),
            label: Text(range == null ? '기간' : _rangeLabel(range!)),
            selected: range != null,
            onPressed: onPickRange,
            onDeleted: range != null ? onClearRange : null,
          ),
          const SizedBox(width: 8),
          if (speciesOptions.isNotEmpty) ...[
            Container(
              width: 1,
              height: 24,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            const SizedBox(width: 8),
          ],
          // 어종 칩
          for (final s in speciesOptions) ...[
            ChoiceChip(
              label: Text('🐟 $s'),
              selected: selectedSpecies == s,
              onSelected: (sel) => onSpecies(sel ? s : null),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _ResultList extends StatelessWidget {
  final List<SearchHit> results;
  final String savePath;

  const _ResultList({required this.results, required this.savePath});

  @override
  Widget build(BuildContext context) {
    // 날짜별 그룹 헤더 + 엔트리 평탄 리스트
    final items = <dynamic>[];
    DateTime? lastDate;
    for (final h in results) {
      final d = DateTime(h.date.year, h.date.month, h.date.day);
      if (d != lastDate) {
        items.add(_DateHeader(hit: h));
        lastDate = d;
      }
      items.add(h);
    }

    return ListView.builder(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        if (item is _DateHeader) return item;
        final hit = item as SearchHit;
        return InkWell(
          onTap: () => context.push(
            '${AppRoutes.fileList}/${Uri.encodeComponent(hit.filePath)}'
            '?name=${Uri.encodeComponent(hit.displayName)}',
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: MemoEntryCard(
              entry: hit.entry,
              savePath: savePath,
              maxLines: 3,
            ),
          ),
        );
      },
    );
  }
}

class _DateHeader extends StatelessWidget {
  final SearchHit hit;
  const _DateHeader({required this.hit});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final addr = hit.address;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      child: Row(
        children: [
          Text(
            DateFormatter.toDateString(hit.date),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: colorScheme.primary,
            ),
          ),
          if (addr != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                addr,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

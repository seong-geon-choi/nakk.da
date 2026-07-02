import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../search/presentation/search_provider.dart';
import '../../search/domain/models/search_hit.dart';
import '../domain/models/catch_stats.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../core/widgets/ad_banner_slot.dart';

enum _Period { all, year, month, custom }

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  _Period _period = _Period.all;
  DateTimeRange? _customRange;

  bool _inPeriod(SearchHit h) {
    final now = DateTime.now();
    switch (_period) {
      case _Period.all:
        return true;
      case _Period.year:
        return h.date.year == now.year;
      case _Period.month:
        return h.date.year == now.year && h.date.month == now.month;
      case _Period.custom:
        final r = _customRange;
        if (r == null) return true;
        final d = DateTime(h.date.year, h.date.month, h.date.day);
        final start = DateTime(r.start.year, r.start.month, r.start.day);
        final end = DateTime(r.end.year, r.end.month, r.end.day);
        return !d.isBefore(start) && !d.isAfter(end);
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2015),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: _customRange,
    );
    if (picked != null) {
      setState(() {
        _customRange = picked;
        _period = _Period.custom;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hitsAsync = ref.watch(searchHitsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('조과 통계')),
      body: Column(
        children: [
          Expanded(
            child: hitsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyStateView(
          icon: Icons.error_outline,
          message: '통계를 불러오지 못했습니다',
          subMessage: e.toString(),
        ),
        data: (allHits) {
          final hits = allHits.where(_inPeriod).toList();
          final stats = CatchStats.from(hits);
          return Column(
            children: [
              _PeriodBar(
                period: _period,
                customRange: _customRange,
                onChanged: (p) => setState(() => _period = p),
                onPickRange: _pickRange,
              ),
              const Divider(height: 1),
              Expanded(
                child: stats.totalCount == 0
                    ? const EmptyStateView(
                        icon: Icons.bar_chart,
                        message: '집계할 조과가 없습니다',
                        subMessage: '메모에 어종·마릿수·길이를 기록해 보세요',
                      )
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          _SummaryRow(stats: stats),
                          const SizedBox(height: 24),
                          _SectionTitle('어종별 조과'),
                          const SizedBox(height: 8),
                          _SpeciesTable(stats: stats),
                          if (stats.monthlyCounts.length > 1) ...[
                            const SizedBox(height: 24),
                            _SectionTitle('월별 마릿수'),
                            const SizedBox(height: 12),
                            _MonthlyBars(monthly: stats.monthlyCounts),
                          ],
                        ],
                      ),
              ),
            ],
          );
        },
      ),
          ),
          const AdBannerSlot(),
        ],
      ),
    );
  }
}

class _PeriodBar extends StatelessWidget {
  final _Period period;
  final DateTimeRange? customRange;
  final ValueChanged<_Period> onChanged;
  final VoidCallback onPickRange;
  const _PeriodBar({
    required this.period,
    required this.customRange,
    required this.onChanged,
    required this.onPickRange,
  });

  static String _fmt(DateTime d) => '${d.year % 100}.${d.month}.${d.day}';

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, _Period p) => ChoiceChip(
          label: Text(label),
          selected: period == p,
          onSelected: (_) => onChanged(p),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          labelPadding: const EdgeInsets.symmetric(horizontal: 6),
        );
    final r = customRange;
    final customLabel = r == null ? '기간 설정' : '${_fmt(r.start)}~${_fmt(r.end)}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          chip('전체', _Period.all),
          const SizedBox(width: 6),
          chip('올해', _Period.year),
          const SizedBox(width: 6),
          chip('이번 달', _Period.month),
          const SizedBox(width: 6),
          Flexible(
            child: ChoiceChip(
              avatar: const Icon(Icons.date_range, size: 16),
              label: Text(customLabel, overflow: TextOverflow.ellipsis),
              selected: period == _Period.custom,
              onSelected: (_) => onPickRange(),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              labelPadding: const EdgeInsets.symmetric(horizontal: 6),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final CatchStats stats;
  const _SummaryRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _SummaryCard(value: '${stats.totalCount}', unit: '마리', label: '총 마릿수')),
        const SizedBox(width: 12),
        Expanded(child: _SummaryCard(value: '${stats.speciesCount}', unit: '종', label: '어종')),
        const SizedBox(width: 12),
        Expanded(child: _SummaryCard(value: '${stats.recordedDays}', unit: '일', label: '기록한 날')),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String value;
  final String unit;
  final String label;
  const _SummaryCard({required this.value, required this.unit, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          RichText(
            text: TextSpan(
              text: value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: cs.primary,
              ),
              children: [
                TextSpan(
                  text: ' $unit',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                    color: cs.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}

class _SpeciesTable extends StatelessWidget {
  final CatchStats stats;
  const _SpeciesTable({required this.stats});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (final s in stats.bySpecies)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    s.species,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                ),
                if (s.maxLength != null) ...[
                  Text(
                    '최대 ${s.maxLength!.toStringAsFixed(1)}cm',
                    style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.55)),
                  ),
                  const SizedBox(width: 16),
                ],
                Text(
                  '${s.count}마리',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MonthlyBars extends StatelessWidget {
  final Map<DateTime, int> monthly;
  const _MonthlyBars({required this.monthly});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 최근 12개월만 (오름차순)
    final months = monthly.keys.toList()..sort();
    final shown = months.length > 12 ? months.sublist(months.length - 12) : months;
    final maxCount = shown.fold<int>(1, (m, k) => monthly[k]! > m ? monthly[k]! : m);

    return SizedBox(
      height: 140,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final k in shown)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('${monthly[k]}',
                      style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.6))),
                  const SizedBox(height: 2),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    height: (96 * monthly[k]! / maxCount).clamp(4, 96).toDouble(),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.7),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('${k.month}월',
                      style: TextStyle(fontSize: 9, color: cs.onSurface.withValues(alpha: 0.5))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

import '../../../search/domain/models/search_hit.dart';

/// 어종별 집계 한 줄.
class SpeciesStat {
  final String species;
  final int count;        // 마릿수 합계
  final double? maxLength; // 최대 길이(cm), 개인 기록(PB)

  const SpeciesStat({
    required this.species,
    required this.count,
    this.maxLength,
  });
}

/// 조과 통계 집계 결과.
class CatchStats {
  final int recordedDays;   // 기록한 날(엔트리가 있는 distinct 날짜)
  final int totalCount;     // 총 마릿수
  final List<SpeciesStat> bySpecies; // 마릿수 내림차순
  final Map<DateTime, int> monthlyCounts; // 월(1일 기준) → 마릿수

  const CatchStats({
    required this.recordedDays,
    required this.totalCount,
    required this.bySpecies,
    required this.monthlyCounts,
  });

  int get speciesCount => bySpecies.where((s) => s.species != _unknown).length;

  static const _unknown = '(어종 미상)';

  /// 조과 정보(어종/마릿수/길이 중 하나라도)가 있는 엔트리만 집계 대상.
  static CatchStats from(Iterable<SearchHit> hits) {
    final days = <DateTime>{};
    int total = 0;
    final counts = <String, int>{};
    final maxLen = <String, double>{};
    final monthly = <DateTime, int>{};

    for (final h in hits) {
      days.add(DateTime(h.date.year, h.date.month, h.date.day));

      final e = h.entry;
      final species = e.fishSpecies?.trim();
      final hasSpecies = species != null && species.isNotEmpty;
      final hasCatch = hasSpecies || e.fishLength != null;
      if (!hasCatch) continue;

      // 사진/메모 1건 = 1마리
      total += 1;

      final key = hasSpecies ? species : _unknown;
      counts[key] = (counts[key] ?? 0) + 1;
      if (e.fishLength != null) {
        final cur = maxLen[key];
        if (cur == null || e.fishLength! > cur) maxLen[key] = e.fishLength!;
      }

      final month = DateTime(h.date.year, h.date.month);
      monthly[month] = (monthly[month] ?? 0) + 1;
    }

    final bySpecies = counts.entries
        .map((e) => SpeciesStat(
              species: e.key,
              count: e.value,
              maxLength: maxLen[e.key],
            ))
        .toList()
      ..sort((a, b) {
        // 어종 미상은 항상 마지막
        if (a.species == _unknown) return 1;
        if (b.species == _unknown) return -1;
        return b.count.compareTo(a.count);
      });

    return CatchStats(
      recordedDays: days.length,
      totalCount: total,
      bySpecies: bySpecies,
      monthlyCounts: monthly,
    );
  }
}

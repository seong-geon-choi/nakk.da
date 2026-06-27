import '../../../search/domain/models/search_hit.dart';

/// 도감 한 칸 — 어종 하나의 수집 상태.
class DogamEntry {
  final String species;
  final bool caught;        // 메모에 기록된 이력이 있으면 true(=컬러)
  final double? maxLength;  // 최대 길이(cm), 기록 없으면 null
  final List<SearchHit> records; // 해당 어종의 모든 기록(길이 내림차순, 동률은 최신순)

  const DogamEntry({
    required this.species,
    required this.caught,
    this.maxLength,
    this.records = const [],
  });

  /// 컬러 타일에 쓸 대표 사진 — 가장 큰 기록부터 찾은 첫 사진(없으면 null).
  /// records가 길이 내림차순이므로 firstWhere가 곧 "최대 기록 사진"이다.
  String? get heroPhotoPath {
    for (final r in records) {
      if (r.entry.photoPath != null) return r.entry.photoPath;
    }
    return null;
  }

  /// 어종 목록 [species] 순서대로 도감 항목 생성.
  /// [hits]를 어종별로 묶어 잡은 여부·최대길이·기록목록을 집계한다.
  static List<DogamEntry> build(List<String> species, Iterable<SearchHit> hits) {
    final bySpecies = <String, List<SearchHit>>{};
    for (final h in hits) {
      final sp = h.entry.fishSpecies?.trim();
      if (sp == null || sp.isEmpty) continue;
      (bySpecies[sp] ??= []).add(h);
    }
    return species.map((sp) {
      final recs = [...(bySpecies[sp] ?? const <SearchHit>[])];
      double? maxLen;
      for (final r in recs) {
        final l = r.entry.fishLength;
        if (l != null && (maxLen == null || l > maxLen)) maxLen = l;
      }
      recs.sort((a, b) {
        final la = a.entry.fishLength ?? -1;
        final lb = b.entry.fishLength ?? -1;
        if (lb != la) return lb.compareTo(la);
        return b.date.compareTo(a.date);
      });
      return DogamEntry(
        species: sp,
        caught: recs.isNotEmpty,
        maxLength: maxLen,
        records: recs,
      );
    }).toList();
  }
}

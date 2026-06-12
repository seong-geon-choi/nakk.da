import 'package:flutter_test/flutter_test.dart';
import 'package:nakkda/features/memo/domain/models/memo_entry.dart';
import 'package:nakkda/features/search/domain/models/search_hit.dart';
import 'package:nakkda/features/stats/domain/models/catch_stats.dart';

SearchHit _hit(
  DateTime date, {
  String? species,
  double? length,
  String? text,
}) =>
    SearchHit(
      date: date,
      filePath: '/x/${date.toIso8601String()}.md',
      displayName: 'x',
      entry: MemoEntry(
        timestamp: date,
        fishSpecies: species,
        fishLength: length,
        text: text,
      ),
    );

void main() {
  group('CatchStats.from', () {
    test('빈 입력 → 모두 0', () {
      final s = CatchStats.from([]);
      expect(s.totalCount, 0);
      expect(s.recordedDays, 0);
      expect(s.speciesCount, 0);
      expect(s.bySpecies, isEmpty);
    });

    test('엔트리 1건 = 1마리로 집계', () {
      final s = CatchStats.from([
        _hit(DateTime(2026, 6, 1), species: '감성돔'),
        _hit(DateTime(2026, 6, 1), species: '감성돔'),
        _hit(DateTime(2026, 6, 2), species: '볼락'),
      ]);
      expect(s.totalCount, 3);
      expect(s.speciesCount, 2);
      final dom = s.bySpecies.firstWhere((e) => e.species == '감성돔');
      expect(dom.count, 2);
    });

    test('최대 길이(PB) 집계', () {
      final s = CatchStats.from([
        _hit(DateTime(2026, 6, 1), species: '참돔', length: 30.0),
        _hit(DateTime(2026, 6, 2), species: '참돔', length: 45.5),
        _hit(DateTime(2026, 6, 3), species: '참돔', length: 28.0),
      ]);
      final dom = s.bySpecies.firstWhere((e) => e.species == '참돔');
      expect(dom.maxLength, 45.5);
      expect(dom.count, 3); // 엔트리 3건 → 3마리
    });

    test('어종 없이 길이만 있는 엔트리 → 어종 미상으로 1마리 집계', () {
      final s = CatchStats.from([
        _hit(DateTime(2026, 6, 1), length: 25.0),
      ]);
      expect(s.totalCount, 1);
      expect(s.speciesCount, 0); // 미상은 어종 수에서 제외
      expect(s.bySpecies.single.species, '(어종 미상)');
    });

    test('조과 정보 없는 순수 텍스트 메모는 마릿수에 미포함하되 기록일엔 포함', () {
      final s = CatchStats.from([
        _hit(DateTime(2026, 6, 1), text: '입질 없음'),
        _hit(DateTime(2026, 6, 2), species: '농어'),
      ]);
      expect(s.totalCount, 1);
      expect(s.recordedDays, 2);
    });

    test('기록일은 distinct 날짜 수', () {
      final s = CatchStats.from([
        _hit(DateTime(2026, 6, 1, 9), species: '볼락'),
        _hit(DateTime(2026, 6, 1, 14), species: '볼락'),
        _hit(DateTime(2026, 6, 2, 10), species: '볼락'),
      ]);
      expect(s.recordedDays, 2);
    });

    test('어종 미상은 정렬 시 항상 마지막', () {
      final s = CatchStats.from([
        _hit(DateTime(2026, 6, 1), length: 20), // 미상
        _hit(DateTime(2026, 6, 1), species: '우럭'),
      ]);
      expect(s.bySpecies.last.species, '(어종 미상)');
    });

    test('월별 마릿수 집계 (엔트리 수 기준)', () {
      final s = CatchStats.from([
        _hit(DateTime(2026, 5, 10), species: '볼락'),
        _hit(DateTime(2026, 5, 11), species: '볼락'),
        _hit(DateTime(2026, 6, 3), species: '볼락'),
        _hit(DateTime(2026, 6, 20), species: '감성돔'),
        _hit(DateTime(2026, 6, 21), species: '감성돔'),
      ]);
      expect(s.monthlyCounts[DateTime(2026, 5)], 2);
      expect(s.monthlyCounts[DateTime(2026, 6)], 3);
    });
  });
}

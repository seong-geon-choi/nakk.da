import 'package:flutter_test/flutter_test.dart';
import 'package:nakkda/features/memo/domain/models/memo_entry.dart';
import 'package:nakkda/features/search/domain/models/search_hit.dart';
import 'package:nakkda/features/dogam/domain/models/dogam_entry.dart';

SearchHit _hit(
  DateTime date, {
  String? species,
  double? length,
  String? photo,
}) =>
    SearchHit(
      date: date,
      filePath: '/x/${date.toIso8601String()}.md',
      displayName: 'x',
      entry: MemoEntry(
        timestamp: date,
        fishSpecies: species,
        fishLength: length,
        photoPath: photo,
      ),
    );

void main() {
  group('DogamEntry.build', () {
    test('잡은 어종은 caught=true, 못 잡은 어종은 caught=false', () {
      final entries = DogamEntry.build(
        ['감성돔', '볼락', '우럭'],
        [_hit(DateTime(2026, 6, 1), species: '감성돔')],
      );
      expect(entries.map((e) => e.species), ['감성돔', '볼락', '우럭']);
      expect(entries[0].caught, isTrue);
      expect(entries[1].caught, isFalse);
      expect(entries[2].caught, isFalse);
    });

    test('최대 길이는 해당 어종 기록 중 최댓값', () {
      final entries = DogamEntry.build(
        ['감성돔'],
        [
          _hit(DateTime(2026, 6, 1), species: '감성돔', length: 28.0),
          _hit(DateTime(2026, 6, 2), species: '감성돔', length: 35.5),
          _hit(DateTime(2026, 6, 3), species: '감성돔', length: 31.0),
        ],
      );
      expect(entries.single.maxLength, 35.5);
      expect(entries.single.records.length, 3);
    });

    test('기록 목록은 길이 내림차순(동률은 최신순) 정렬', () {
      final entries = DogamEntry.build(
        ['감성돔'],
        [
          _hit(DateTime(2026, 6, 1), species: '감성돔', length: 20.0),
          _hit(DateTime(2026, 6, 5), species: '감성돔', length: 40.0),
          _hit(DateTime(2026, 6, 3), species: '감성돔', length: 40.0),
        ],
      );
      final recs = entries.single.records;
      expect(recs[0].entry.fishLength, 40.0);
      expect(recs[0].date, DateTime(2026, 6, 5)); // 동률 중 최신
      expect(recs[1].date, DateTime(2026, 6, 3));
      expect(recs[2].entry.fishLength, 20.0);
    });

    test('길이 없이 잡은 경우 caught=true, maxLength=null', () {
      final entries = DogamEntry.build(
        ['문어'],
        [_hit(DateTime(2026, 6, 1), species: '문어')],
      );
      expect(entries.single.caught, isTrue);
      expect(entries.single.maxLength, isNull);
    });

    test('어종 미지정(공백) 기록은 무시', () {
      final entries = DogamEntry.build(
        ['감성돔'],
        [
          _hit(DateTime(2026, 6, 1), species: '   '),
          _hit(DateTime(2026, 6, 2), species: null, length: 10),
        ],
      );
      expect(entries.single.caught, isFalse);
    });
  });
}

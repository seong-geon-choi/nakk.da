import 'package:flutter_test/flutter_test.dart';
import 'package:nakkda/features/memo/domain/models/memo_entry.dart';

void main() {
  group('MemoEntry', () {
    test('isPhoto: photoPath 있으면 true', () {
      final entry = MemoEntry(
        timestamp: DateTime(2026, 6, 2, 9, 5),
        photoPath: 'photos/test.jpg',
      );
      expect(entry.isPhoto, isTrue);
    });

    test('isPhoto: photoPath 없으면 false', () {
      final entry = MemoEntry(
        timestamp: DateTime(2026, 6, 2, 9, 5),
        text: '텍스트 메모',
      );
      expect(entry.isPhoto, isFalse);
    });

    test('hasGps: lat/lng 모두 있으면 true', () {
      final entry = MemoEntry(
        timestamp: DateTime(2026, 6, 2, 9, 5),
        latitude: 37.1234,
        longitude: 127.5678,
      );
      expect(entry.hasGps, isTrue);
    });

    test('hasGps: latitude만 null이면 false', () {
      final entry = MemoEntry(
        timestamp: DateTime(2026, 6, 2, 9, 5),
        latitude: null,
        longitude: 127.5678,
      );
      expect(entry.hasGps, isFalse);
    });

    test('hasGps: longitude만 null이면 false', () {
      final entry = MemoEntry(
        timestamp: DateTime(2026, 6, 2, 9, 5),
        latitude: 37.1234,
        longitude: null,
      );
      expect(entry.hasGps, isFalse);
    });

    test('timeLabel: 09:05 → "09:05" (패딩 확인)', () {
      final entry = MemoEntry(
        timestamp: DateTime(2026, 6, 2, 9, 5),
      );
      expect(entry.timeLabel, '09:05');
    });

    test('timeLabel: 14:30 → "14:30"', () {
      final entry = MemoEntry(
        timestamp: DateTime(2026, 6, 2, 14, 30),
      );
      expect(entry.timeLabel, '14:30');
    });
  });
}

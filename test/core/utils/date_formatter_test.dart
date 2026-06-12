import 'package:flutter_test/flutter_test.dart';
import 'package:nakkda/core/utils/date_formatter.dart';

void main() {
  group('DateFormatter', () {
    group('toDateString', () {
      test('날짜를 YYYY-MM-DD 형식으로 반환한다', () {
        final date = DateTime(2026, 6, 2);
        expect(DateFormatter.toDateString(date), '2026-06-02');
      });

      test('월/일이 한 자리일 때 두 자리로 패딩한다', () {
        final date = DateTime(2026, 1, 5);
        expect(DateFormatter.toDateString(date), '2026-01-05');
      });
    });

    group('toTimeString', () {
      test('시각을 HH:mm 형식으로 반환한다', () {
        final time = DateTime(2026, 6, 2, 14, 30);
        expect(DateFormatter.toTimeString(time), '14:30');
      });

      test('한 자리 시/분을 두 자리로 패딩한다', () {
        final time = DateTime(2026, 6, 2, 9, 5);
        expect(DateFormatter.toTimeString(time), '09:05');
      });

      test('자정(00:00)을 올바르게 반환한다', () {
        final time = DateTime(2026, 6, 2, 0, 0);
        expect(DateFormatter.toTimeString(time), '00:00');
      });
    });

    group('toRelativeDate', () {
      test('오늘 날짜는 "오늘"을 반환한다', () {
        final today = DateTime.now();
        expect(DateFormatter.toRelativeDate(today), '오늘');
      });

      test('어제 날짜는 "어제"를 반환한다', () {
        final yesterday = DateTime.now().subtract(const Duration(days: 1));
        expect(DateFormatter.toRelativeDate(yesterday), '어제');
      });

      test('3일 전은 "3일 전"을 반환한다', () {
        final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3));
        expect(DateFormatter.toRelativeDate(threeDaysAgo), '3일 전');
      });

      test('6일 전은 "6일 전"을 반환한다 (7일 미만)', () {
        final sixDaysAgo = DateTime.now().subtract(const Duration(days: 6));
        expect(DateFormatter.toRelativeDate(sixDaysAgo), '6일 전');
      });

      test('8일 전은 절대 날짜(YYYY-MM-DD)를 반환한다', () {
        final eightDaysAgo = DateTime.now().subtract(const Duration(days: 8));
        final expected = DateFormatter.toDateString(eightDaysAgo);
        expect(DateFormatter.toRelativeDate(eightDaysAgo), expected);
      });
    });
  });
}

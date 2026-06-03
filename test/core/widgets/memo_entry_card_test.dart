import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vo_rec/core/widgets/memo_entry_card.dart';
import 'package:vo_rec/features/memo/domain/models/memo_entry.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('MemoEntryCard', () {
    testWidgets('텍스트 메모: 시간 헤더 + 텍스트 표시', (tester) async {
      final entry = MemoEntry(
        timestamp: DateTime(2026, 6, 2, 9, 5),
        text: '오전 낚시 메모',
      );
      await tester.pumpWidget(_wrap(MemoEntryCard(entry: entry)));

      expect(find.text('09:05'), findsOneWidget);
      expect(find.text('오전 낚시 메모'), findsOneWidget);
    });

    testWidgets('GPS 있는 메모: 헤더에 좌표 표시', (tester) async {
      final entry = MemoEntry(
        timestamp: DateTime(2026, 6, 2, 14, 30),
        latitude: 37.1234,
        longitude: 127.5678,
        text: 'GPS 메모',
      );
      await tester.pumpWidget(_wrap(MemoEntryCard(entry: entry)));

      expect(
        find.textContaining('🛰 37.1234, 127.5678'),
        findsOneWidget,
      );
    });

    testWidgets('사진 메모 — 파일 없으면 broken_image 아이콘 표시', (tester) async {
      final entry = MemoEntry(
        timestamp: DateTime(2026, 6, 2, 10, 0),
        // 실제 파일이 없는 경로 → broken_image 렌더링
        photoPath: '/nonexistent/path/photo.jpg',
      );
      await tester.pumpWidget(_wrap(MemoEntryCard(entry: entry)));
      await tester.pump();

      expect(find.byIcon(Icons.broken_image), findsOneWidget);
    });
  });
}

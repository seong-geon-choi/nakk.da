import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vo_rec/core/widgets/memo_entry_card.dart';
import 'package:vo_rec/features/memo/domain/models/memo_entry.dart';

void main() {
  group('_FullScreenImagePage', () {
    // _FullScreenImagePage는 private이므로 MemoEntryCard의 사진 탭을 통해 네비게이션 테스트
    // 존재하지 않는 경로일 때 MemoEntryCard의 _PhotoBody는 broken_image 아이콘을 표시
    testWidgets('존재하지 않는 파일 경로로 생성 시 broken_image 아이콘이 표시된다', (tester) async {
      final entry = MemoEntry(
        timestamp: DateTime(2026, 6, 2, 10, 0, 0),
        photoPath: '/nonexistent/path/photo.jpg',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MemoEntryCard(entry: entry),
          ),
        ),
      );

      expect(find.byIcon(Icons.broken_image), findsOneWidget);
    });

    testWidgets('사진 탭 후 네비게이션되는 페이지에 AppBar가 표시된다', (tester) async {
      final entry = MemoEntry(
        timestamp: DateTime(2026, 6, 2, 10, 0, 0),
        photoPath: '/nonexistent/path/photo.jpg',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MemoEntryCard(entry: entry),
          ),
        ),
      );

      // 사진 영역 탭
      await tester.tap(find.byIcon(Icons.broken_image));
      await tester.pumpAndSettle();

      // 네비게이션 후 AppBar가 표시된다
      expect(find.byType(AppBar), findsOneWidget);
    });

    testWidgets('사진 탭 후 네비게이션되는 페이지에 InteractiveViewer가 표시된다', (tester) async {
      final entry = MemoEntry(
        timestamp: DateTime(2026, 6, 2, 10, 0, 0),
        photoPath: '/nonexistent/path/photo.jpg',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MemoEntryCard(entry: entry),
          ),
        ),
      );

      // 사진 영역 탭
      await tester.tap(find.byIcon(Icons.broken_image));
      await tester.pumpAndSettle();

      // 네비게이션 후 InteractiveViewer가 표시된다
      expect(find.byType(InteractiveViewer), findsOneWidget);
    });
  });
}

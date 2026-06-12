import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nakkda/core/widgets/action_button.dart';
import 'package:nakkda/core/widgets/empty_state_view.dart';
import 'package:nakkda/core/widgets/permission_status_chip.dart';

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  group('ActionButton', () {
    testWidgets('아이콘과 레이블을 렌더링한다', (tester) async {
      await tester.pumpWidget(
        _wrap(ActionButton(
          icon: Icons.mic,
          label: '녹음',
          onTap: () {},
        )),
      );

      expect(find.byIcon(Icons.mic), findsOneWidget);
      expect(find.text('녹음'), findsOneWidget);
    });

    testWidgets('onTap 콜백이 호출된다', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(ActionButton(
          icon: Icons.mic,
          label: '녹음',
          onTap: () => tapped = true,
        )),
      );

      await tester.tap(find.byType(GestureDetector));
      expect(tapped, isTrue);
    });

    testWidgets('enabled=false일 때 onTap이 호출되지 않는다', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(ActionButton(
          icon: Icons.mic,
          label: '녹음',
          onTap: () => tapped = true,
          enabled: false,
        )),
      );

      await tester.tap(find.byType(GestureDetector));
      expect(tapped, isFalse);
    });

    testWidgets('enabled=false일 때 위젯이 렌더링된다', (tester) async {
      await tester.pumpWidget(
        _wrap(ActionButton(
          icon: Icons.mic,
          label: '녹음',
          enabled: false,
        )),
      );

      expect(find.byIcon(Icons.mic), findsOneWidget);
      expect(find.text('녹음'), findsOneWidget);
    });
  });

  group('EmptyStateView', () {
    testWidgets('message 텍스트를 표시한다', (tester) async {
      await tester.pumpWidget(
        _wrap(const EmptyStateView(message: '데이터가 없습니다')),
      );

      expect(find.text('데이터가 없습니다'), findsOneWidget);
    });

    testWidgets('subMessage 텍스트를 표시한다', (tester) async {
      await tester.pumpWidget(
        _wrap(const EmptyStateView(
          message: '데이터가 없습니다',
          subMessage: '새 항목을 추가해주세요',
        )),
      );

      expect(find.text('데이터가 없습니다'), findsOneWidget);
      expect(find.text('새 항목을 추가해주세요'), findsOneWidget);
    });

    testWidgets('subMessage가 없으면 message만 표시한다', (tester) async {
      await tester.pumpWidget(
        _wrap(const EmptyStateView(message: '데이터가 없습니다')),
      );

      expect(find.text('데이터가 없습니다'), findsOneWidget);
      // subMessage 없을 때 두 번째 Text 위젯이 없음을 확인
      expect(find.text('새 항목을 추가해주세요'), findsNothing);
    });

    testWidgets('icon이 제공되면 표시한다', (tester) async {
      await tester.pumpWidget(
        _wrap(const EmptyStateView(
          message: '데이터가 없습니다',
          icon: Icons.folder_open,
        )),
      );

      expect(find.byIcon(Icons.folder_open), findsOneWidget);
    });
  });

  group('PermissionStatusChip', () {
    testWidgets('isGranted=true일 때 "허용" 텍스트를 표시한다', (tester) async {
      await tester.pumpWidget(
        _wrap(const PermissionStatusChip(isGranted: true)),
      );

      expect(find.text('허용'), findsOneWidget);
      expect(find.text('거부'), findsNothing);
    });

    testWidgets('isGranted=false일 때 "거부" 텍스트를 표시한다', (tester) async {
      await tester.pumpWidget(
        _wrap(const PermissionStatusChip(isGranted: false)),
      );

      expect(find.text('거부'), findsOneWidget);
      expect(find.text('허용'), findsNothing);
    });

    testWidgets('isGranted=true일 때 Chip 배경이 초록 계열이다', (tester) async {
      await tester.pumpWidget(
        _wrap(const PermissionStatusChip(isGranted: true)),
      );

      final chip = tester.widget<Chip>(find.byType(Chip));
      final bg = chip.backgroundColor as Color;
      expect(bg.green, greaterThan(bg.red));
      expect(bg.green, greaterThan(bg.blue));
    });

    testWidgets('isGranted=false일 때 Chip 배경이 빨강 계열이다', (tester) async {
      await tester.pumpWidget(
        _wrap(const PermissionStatusChip(isGranted: false)),
      );

      final chip = tester.widget<Chip>(find.byType(Chip));
      final bg = chip.backgroundColor as Color;
      expect(bg.red, greaterThan(bg.green));
      expect(bg.red, greaterThan(bg.blue));
    });
  });
}

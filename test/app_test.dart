import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nakkda/app.dart';

void main() {
  group('App 라우팅', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('앱이 예외 없이 빌드에 성공한다', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: App()),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('다크 테마가 적용된다', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: App()),
      );
      await tester.pumpAndSettle();

      final MaterialApp app = tester.widget(find.byType(MaterialApp));
      expect(app.theme?.brightness, Brightness.dark);
    });
  });
}

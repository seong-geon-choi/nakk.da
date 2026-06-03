// 기존 스모크 테스트 - App 클래스로 교체
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vo_rec/app.dart';

void main() {
  testWidgets('앱 스모크 테스트', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: App()));
    await tester.pumpAndSettle();
  });
}

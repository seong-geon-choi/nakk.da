import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vo_rec/features/settings/domain/models/app_settings.dart';
import 'package:vo_rec/features/settings/presentation/settings_provider.dart';
import 'package:vo_rec/features/permission/presentation/permission_provider.dart';
import 'package:vo_rec/features/settings/presentation/settings_screen.dart';

/// 테스트용 SettingsNotifier — 실제 SharedPreferences/파일 시스템 없이 동작
class _FakeSettingsNotifier extends SettingsNotifier {
  final AppSettings _initial;
  _FakeSettingsNotifier(this._initial);

  @override
  Future<AppSettings> build() async => _initial;
}

/// 테스트용 PermissionStatusNotifier
class _FakePermissionNotifier
    extends PermissionStatusNotifier {
  final Map<Permission, PermissionStatus> _statuses;
  _FakePermissionNotifier(this._statuses);

  @override
  Future<Map<Permission, PermissionStatus>> build() async => _statuses;
}

Widget _buildSubject({
  required AppSettings settings,
  required Map<Permission, PermissionStatus> permStatuses,
}) {
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith(() => _FakeSettingsNotifier(settings)),
      permissionStatusProvider
          .overrideWith(() => _FakePermissionNotifier(permStatuses)),
    ],
    child: const MaterialApp(
      home: SettingsScreen(),
    ),
  );
}

void main() {
  final defaultSettings = AppSettings(
    savePath: '/test/save/path',
    photoSavePath: '/test/photos',
    showLocationButton: true,
  );

  final allGranted = {
    Permission.microphone: PermissionStatus.granted,
    Permission.locationWhenInUse: PermissionStatus.granted,
    Permission.camera: PermissionStatus.granted,
    Permission.photos: PermissionStatus.granted,
  };

  final allDenied = {
    Permission.microphone: PermissionStatus.denied,
    Permission.locationWhenInUse: PermissionStatus.denied,
    Permission.camera: PermissionStatus.denied,
    Permission.photos: PermissionStatus.denied,
  };

  group('SettingsScreen', () {
    testWidgets('저장 위치 항목이 화면에 표시된다', (tester) async {
      await tester.pumpWidget(
        _buildSubject(settings: defaultSettings, permStatuses: allGranted),
      );
      await tester.pumpAndSettle();

      expect(find.text('메모 저장 위치'), findsOneWidget);
    });

    testWidgets('위치 추가 버튼 표시 SwitchListTile이 화면에 표시된다', (tester) async {
      await tester.pumpWidget(
        _buildSubject(settings: defaultSettings, permStatuses: allGranted),
      );
      await tester.pumpAndSettle();

      expect(find.text('위치 추가 버튼 표시'), findsOneWidget);
    });

    testWidgets('권한 항목(마이크, 위치, 카메라, 저장소)이 화면에 표시된다', (tester) async {
      await tester.pumpWidget(
        _buildSubject(settings: defaultSettings, permStatuses: allGranted),
      );
      await tester.pumpAndSettle();

      // API 키 섹션이 추가되어 권한 항목 일부가 스크롤 밖에 있을 수 있으므로
      // ListView를 끝까지 스크롤하여 확인
      await tester.scrollUntilVisible(find.text('저장소'), 50);
      await tester.pumpAndSettle();

      expect(find.text('마이크'), findsOneWidget);
      expect(find.text('위치'), findsOneWidget);
      expect(find.text('카메라'), findsOneWidget);
      expect(find.text('저장소'), findsOneWidget);
    });

    testWidgets('savePath가 subtitle로 표시된다', (tester) async {
      await tester.pumpWidget(
        _buildSubject(settings: defaultSettings, permStatuses: allGranted),
      );
      await tester.pumpAndSettle();

      expect(find.text('/test/save/path'), findsOneWidget);
    });

    testWidgets('SwitchListTile의 초기값이 settings.showLocationButton과 일치한다',
        (tester) async {
      await tester.pumpWidget(
        _buildSubject(
          settings: AppSettings(
              savePath: '/path', photoSavePath: '/photos', showLocationButton: false),
          permStatuses: allGranted,
        ),
      );
      await tester.pumpAndSettle();

      // SwitchListTile이 2개(위치 버튼, 자동 저장)이므로 첫 번째(위치 버튼)의 value를 확인
      final switchFinder = find.byType(SwitchListTile);
      expect(switchFinder, findsWidgets);

      final locationSwitch = tester.widget<SwitchListTile>(switchFinder.first);
      expect(locationSwitch.value, false);
    });

    testWidgets('권한이 모두 허용되면 허용 칩이 표시된다', (tester) async {
      await tester.pumpWidget(
        _buildSubject(settings: defaultSettings, permStatuses: allGranted),
      );
      await tester.pumpAndSettle();

      expect(find.text('허용'), findsWidgets);
    });

    testWidgets('권한이 모두 거부되면 거부 칩이 표시된다', (tester) async {
      await tester.pumpWidget(
        _buildSubject(settings: defaultSettings, permStatuses: allDenied),
      );
      await tester.pumpAndSettle();

      expect(find.text('거부'), findsWidgets);
    });

    testWidgets('로딩 중에는 CircularProgressIndicator가 표시된다', (tester) async {
      // Completer를 이용해 타이머 없이 로딩 상태를 재현한다
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(
              () => _NeverCompleteSettingsNotifier(),
            ),
            permissionStatusProvider
                .overrideWith(() => _FakePermissionNotifier(allGranted)),
          ],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      // pumpAndSettle 없이 pump 1프레임 — 로딩 상태 확인
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}

/// 절대 완료되지 않는 Completer로 로딩 상태를 유지하는 notifier
class _NeverCompleteSettingsNotifier extends SettingsNotifier {
  @override
  Future<AppSettings> build() {
    // ignore: return_of_do_not_store
    return Completer<AppSettings>().future;
  }
}

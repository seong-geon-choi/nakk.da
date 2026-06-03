import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vo_rec/features/location/domain/models/location_status.dart';
import 'package:vo_rec/features/location/presentation/location_provider.dart';
import 'package:vo_rec/features/memo/domain/models/day_file.dart';
import 'package:vo_rec/features/memo/domain/models/memo_entry.dart';
import 'package:vo_rec/features/memo/presentation/memo_input_sheet.dart';
import 'package:vo_rec/features/memo/presentation/memo_provider.dart';
import 'package:vo_rec/features/memo/presentation/voice_input_provider.dart';
import 'package:vo_rec/features/permission/presentation/permission_provider.dart';
import 'package:vo_rec/features/settings/domain/models/app_settings.dart';
import 'package:vo_rec/features/settings/presentation/settings_provider.dart';

// Fake SettingsNotifier
class _FakeSettingsNotifier extends AsyncNotifier<AppSettings>
    implements SettingsNotifier {
  @override
  Future<AppSettings> build() async =>
      AppSettings(savePath: '/tmp/test', photoSavePath: '/tmp/photos');

  @override
  Future<void> updateSavePath(String path) async {}

  @override
  Future<void> updatePhotoSavePath(String path) async {}

  @override
  Future<void> updateAutoSaveVoice(bool value) async {}

  @override
  Future<void> updateShowLocationButton(bool show) async {}

  @override
  Future<void> updateWatermark(WatermarkSettings watermark) async {}

  @override
  Future<void> updateKhoaApiKey(String? key) async {}
}

// Fake TodayFileNotifier
class _FakeTodayFileNotifier extends AsyncNotifier<DayFile?>
    implements TodayFileNotifier {
  @override
  Future<DayFile?> build() async => null;

  @override
  Future<void> addEntry(MemoEntry entry) async {}

  @override
  Future<void> addLocationBlock(LocationStatus loc) async {}

  @override
  Future<void> editBlock(int blockIndex, dynamic newBlock) async {}

  @override
  Future<void> removeBlock(int blockIndex) async {}
}

// Fake LocationNotifier
class _FakeLocationNotifier extends AsyncNotifier<LocationStatus?>
    implements LocationNotifier {
  @override
  Future<LocationStatus?> build() async => null;

  @override
  Future<LocationStatus?> refresh() async => null;

  @override
  LocationStatus? get cached => null;

  @override
  Future<LocationStatus> buildEnrichedLocation({bool isMove = false}) async =>
      LocationStatus(timestamp: DateTime.now(), isMove: isMove);
}

// Fake VoiceInputNotifier
class _FakeVoiceInputNotifier extends Notifier<VoiceInputState>
    implements VoiceInputNotifier {
  @override
  VoiceInputState build() => const VoiceInputState();

  @override
  Future<void> startListening() async {}

  @override
  Future<void> stopListening() async {}

  @override
  void clearResult() {}

  @override
  void clearError() {}
}

// Fake PermissionStatusNotifier
class _FakePermissionStatusNotifier
    extends AsyncNotifier<Map<Permission, PermissionStatus>>
    implements PermissionStatusNotifier {
  @override
  Future<Map<Permission, PermissionStatus>> build() async => {
        Permission.microphone: PermissionStatus.granted,
      };

  @override
  Future<void> requestAll() async {}

  @override
  bool get areAllGranted => true;
}

/// 테스트용 override 목록
List<Override> _buildOverrides() => [
      settingsProvider.overrideWith(() => _FakeSettingsNotifier()),
      todayFileProvider.overrideWith(() => _FakeTodayFileNotifier()),
      locationProvider.overrideWith(() => _FakeLocationNotifier()),
      voiceInputProvider.overrideWith(() => _FakeVoiceInputNotifier()),
      permissionStatusProvider
          .overrideWith(() => _FakePermissionStatusNotifier()),
    ];

/// MemoInputSheet를 테스트용 Scaffold 안에서 직접 렌더링
Widget _buildTestWidget() {
  return ProviderScope(
    overrides: _buildOverrides(),
    child: const MaterialApp(
      home: Scaffold(
        body: MemoInputSheet(),
      ),
    ),
  );
}

void main() {
  group('MemoInputSheet 위젯 테스트', () {
    testWidgets('렌더링: 텍스트 필드, 저장 버튼, 취소 버튼, 마이크 버튼 표시 확인', (tester) async {
      await tester.pumpWidget(_buildTestWidget());
      await tester.pumpAndSettle();

      // TextField 표시 확인
      expect(find.byType(TextField), findsOneWidget);

      // 저장 버튼 표시 확인
      expect(find.text('저장'), findsOneWidget);

      // 취소 버튼 표시 확인
      expect(find.text('취소'), findsOneWidget);

      // 마이크 버튼 표시 확인 (mic_none 아이콘)
      expect(find.byIcon(Icons.mic_none), findsOneWidget);
    });

    testWidgets('빈 텍스트 저장: Navigator.pop 호출 확인 (저장 없이 닫힘)', (tester) async {
      bool popped = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: _buildOverrides(),
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const Scaffold(
                          body: MemoInputSheet(),
                        ),
                      ),
                    );
                    popped = true;
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // MemoInputSheet가 표시됐는지 확인
      expect(find.text('저장'), findsOneWidget);

      // 텍스트 필드는 비어있음 - 저장 버튼 탭
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();

      // pop 되어 이전 화면으로 돌아갔는지 확인
      expect(popped, isTrue);
      expect(find.text('저장'), findsNothing);
    });

    testWidgets('취소 버튼: Navigator.pop 호출 확인', (tester) async {
      bool popped = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: _buildOverrides(),
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const Scaffold(
                          body: MemoInputSheet(),
                        ),
                      ),
                    );
                    popped = true;
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('취소'), findsOneWidget);

      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      expect(popped, isTrue);
      expect(find.text('취소'), findsNothing);
    });
  });
}

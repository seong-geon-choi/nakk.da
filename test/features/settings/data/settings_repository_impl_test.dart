import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nakkda/features/settings/data/settings_repository_impl.dart';
import 'package:nakkda/features/settings/domain/models/app_settings.dart';

void main() {
  group('SettingsRepositoryImpl', () {
    late SettingsRepositoryImpl repository;

    // save_path를 미리 설정해 getExternalStorageDirectory 호출을 방지한다
    const defaultPath = '/test/default/path';

    setUp(() {
      // save_saf_uri: 실제 savePath 키 (SAF 마이그레이션으로 키명 변경됨)
      // photo_save_path도 미리 설정해 _defaultPhotoSavePath()의
      // getExternalStorageDirectory(path_provider) 플러그인 호출을 방지한다
      SharedPreferences.setMockInitialValues({
        'save_saf_uri': defaultPath,
        'photo_save_path': '/test/photos',
      });
      repository = SettingsRepositoryImpl();
    });

    test('load() 시 저장된 showLocationButton 기본값 true를 반환한다', () async {
      final settings = await repository.load();

      expect(settings.showLocationButton, true);
      expect(settings.savePath, defaultPath);
    });

    test('save() 후 load() 하면 저장된 savePath 값이 유지된다', () async {
      const testPath = '/test/custom/path';
      final settingsToSave = AppSettings(savePath: testPath, photoSavePath: '/test/photos');

      await repository.save(settingsToSave);
      final loaded = await repository.load();

      expect(loaded.savePath, testPath);
    });

    test('save() 후 load() 하면 저장된 showLocationButton 값이 유지된다', () async {
      final settingsToSave = AppSettings(
        savePath: defaultPath,
        photoSavePath: '/test/photos',
        showLocationButton: false,
      );

      await repository.save(settingsToSave);
      final loaded = await repository.load();

      expect(loaded.showLocationButton, false);
    });

    test('showLocationButton을 false로 저장 후 true로 토글하면 load()에서 true를 반환한다', () async {
      final initial = AppSettings(savePath: defaultPath, photoSavePath: '/test/photos', showLocationButton: false);
      await repository.save(initial);

      final toggled = initial.copyWith(showLocationButton: true);
      await repository.save(toggled);

      final loaded = await repository.load();
      expect(loaded.showLocationButton, true);
    });

    test('fishSpecies 저장 후 load()에서 동일 목록 반환', () async {
      final initial = AppSettings(
        savePath: defaultPath,
        photoSavePath: '/test/photos',
        fishSpecies: ['돗돔', '참돔', '볼락'],
      );
      await repository.save(initial);

      final loaded = await repository.load();
      expect(loaded.fishSpecies, ['돗돔', '참돔', '볼락']);
    });
  });
}

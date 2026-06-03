import 'package:flutter_test/flutter_test.dart';
import 'package:vo_rec/features/settings/domain/models/app_settings.dart';

void main() {
  group('AppSettings', () {
    test('기본값으로 생성 시 savePath와 showLocationButton이 올바르게 설정된다', () {
      final settings = AppSettings(savePath: '/default/path', photoSavePath: '/photos');

      expect(settings.savePath, '/default/path');
      expect(settings.showLocationButton, true);
    });

    test('copyWith으로 savePath를 변경하면 새 값이 반영된다', () {
      final settings = AppSettings(savePath: '/old/path', photoSavePath: '/photos');

      final updated = settings.copyWith(savePath: '/new/path');

      expect(updated.savePath, '/new/path');
      expect(updated.showLocationButton, true);
    });

    test('copyWith으로 showLocationButton을 변경하면 새 값이 반영된다', () {
      final settings = AppSettings(savePath: '/path', photoSavePath: '/photos', showLocationButton: true);

      final updated = settings.copyWith(showLocationButton: false);

      expect(updated.savePath, '/path');
      expect(updated.showLocationButton, false);
    });

    test('copyWith에 아무 인자도 전달하지 않으면 기존 필드가 유지된다', () {
      final settings = AppSettings(savePath: '/path', photoSavePath: '/photos', showLocationButton: false);

      final updated = settings.copyWith();

      expect(updated.savePath, '/path');
      expect(updated.showLocationButton, false);
    });
  });
}

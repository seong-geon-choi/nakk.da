import 'package:flutter_test/flutter_test.dart';
import 'package:nakkda/features/settings/domain/models/app_settings.dart';

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

  group('WatermarkSettings posX/posY', () {
    test('기본값은 우하단 (1.0, 1.0)', () {
      final wm = WatermarkSettings();
      expect(wm.posX, 1.0);
      expect(wm.posY, 1.0);
    });

    test('toJson/fromJson 왕복 시 posX/posY 보존', () {
      final wm = WatermarkSettings(posX: 0.3, posY: 0.7);
      final restored = WatermarkSettings.fromJson(wm.toJson());
      expect(restored.posX, closeTo(0.3, 1e-9));
      expect(restored.posY, closeTo(0.7, 1e-9));
    });

    test('구 설정(posX/posY 없음)은 position 코너에서 유도 — topLeft → (0,0)', () {
      final restored = WatermarkSettings.fromJson({'position': 'topLeft'});
      expect(restored.posX, 0.0);
      expect(restored.posY, 0.0);
    });

    test('구 설정 bottomRight → (1,1)', () {
      final restored = WatermarkSettings.fromJson({'position': 'bottomRight'});
      expect(restored.posX, 1.0);
      expect(restored.posY, 1.0);
    });

    test('posFromCorner 매핑', () {
      expect(WatermarkSettings.posFromCorner(WatermarkPosition.topRight), (1.0, 0.0));
      expect(WatermarkSettings.posFromCorner(WatermarkPosition.bottomLeft), (0.0, 1.0));
    });
  });
}

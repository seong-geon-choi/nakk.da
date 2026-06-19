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

  group('WatermarkSettings (컨테이너 + 박스)', () {
    test('기본값: 컨테이너 우하단(1,1), 박스 3종, 배경 검정', () {
      final wm = WatermarkSettings();
      expect(wm.containerPosX, 1.0);
      expect(wm.containerPosY, 1.0);
      expect(wm.boxes.length, 3);
      expect(wm.boxes.map((b) => b.type).toSet(), {
        WatermarkLineType.date,
        WatermarkLineType.time,
        WatermarkLineType.customText,
      });
      expect(wm.bgColorIndex, 0);
      expect(wm.bgOpacity, 0.67);
    });

    test('toJson/fromJson 왕복 시 컨테이너·박스 설정 보존', () {
      final wm = WatermarkSettings(
        enabled: true,
        containerPosX: 0.3,
        containerPosY: 0.7,
        bgColorIndex: 3,
        bgOpacity: 0.5,
        boxes: const [
          WatermarkBox(
            type: WatermarkLineType.date,
            dx: 0.1,
            dy: 0.2,
            fontSize: 40,
            weight: WatermarkWeight.black,
            fontFamily: WatermarkFont.heavy,
            textColor: 0xFFFFEB3B,
            alignment: WatermarkAlign.center,
            dateFormat: 'MM/dd',
          ),
        ],
      );
      final restored = WatermarkSettings.fromJson(wm.toJson());
      expect(restored.enabled, true);
      expect(restored.containerPosX, closeTo(0.3, 1e-9));
      expect(restored.containerPosY, closeTo(0.7, 1e-9));
      expect(restored.bgColorIndex, 3);
      expect(restored.bgOpacity, closeTo(0.5, 1e-9));
      expect(restored.boxes.length, 1);
      final b = restored.boxes.first;
      expect(b.type, WatermarkLineType.date);
      expect(b.dx, closeTo(0.1, 1e-9));
      expect(b.dy, closeTo(0.2, 1e-9));
      expect(b.fontSize, 40);
      expect(b.weight, WatermarkWeight.black);
      expect(b.fontFamily, WatermarkFont.heavy);
      expect(b.textColor, 0xFFFFEB3B);
      expect(b.alignment, WatermarkAlign.center);
      expect(b.dateFormat, 'MM/dd');
    });

    test('bgColorArgb는 프리셋 색에 투명도를 적용', () {
      final wm = WatermarkSettings(bgColorIndex: 0, bgOpacity: 1.0);
      expect(wm.bgColorArgb, 0xFF000000);
      final half = WatermarkSettings(bgColorIndex: 0, bgOpacity: 0.5);
      expect(half.bgColorArgb, 0x80000000); // alpha 128
    });

    test('구 포맷(단일 박스 + lines) 마이그레이션', () {
      final legacy = {
        'enabled': true,
        'position': 'bottomRight',
        'posX': 0.25,
        'posY': 0.8,
        'fontSize': 48.0,
        'bold': true,
        'alignment': 'right',
        'fontFamily': 'serif',
        'dateFormat': 'yy/MM/dd',
        'timeFormat': 'HH:mm:ss',
        'boxOpacity': 0.4,
        'lines': [
          {'type': 'date', 'visible': true, 'customText': ''},
          {'type': 'time', 'visible': false, 'customText': ''},
          {'type': 'customText', 'visible': true, 'customText': '낚시'},
        ],
      };
      final wm = WatermarkSettings.fromJson(legacy);
      expect(wm.enabled, true);
      expect(wm.containerPosX, closeTo(0.25, 1e-9));
      expect(wm.containerPosY, closeTo(0.8, 1e-9));
      expect(wm.bgColorIndex, 0);
      expect(wm.bgOpacity, closeTo(0.4, 1e-9));
      expect(wm.boxes.length, 3);
      // 박스별로 구 전역 폰트 설정이 이식됨
      for (final b in wm.boxes) {
        expect(b.fontSize, 48.0);
        expect(b.weight, WatermarkWeight.bold);
        expect(b.fontFamily, WatermarkFont.serif);
        expect(b.alignment, WatermarkAlign.right);
      }
      final date = wm.boxes.firstWhere((b) => b.type == WatermarkLineType.date);
      expect(date.dateFormat, 'yy/MM/dd');
      final custom =
          wm.boxes.firstWhere((b) => b.type == WatermarkLineType.customText);
      expect(custom.visible, true);
      expect(custom.customText, '낚시');
      final time = wm.boxes.firstWhere((b) => b.type == WatermarkLineType.time);
      expect(time.visible, false);
    });

    test('구 포맷에서 posX/posY 없으면 position 코너에서 유도', () {
      final wm = WatermarkSettings.fromJson({'position': 'topLeft'});
      expect(wm.containerPosX, 0.0);
      expect(wm.containerPosY, 0.0);
    });

    test('posFromCorner 매핑', () {
      expect(WatermarkSettings.posFromCorner(WatermarkPosition.topRight), (1.0, 0.0));
      expect(WatermarkSettings.posFromCorner(WatermarkPosition.bottomLeft), (0.0, 1.0));
    });
  });
}

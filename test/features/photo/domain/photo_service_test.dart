import 'package:flutter_test/flutter_test.dart';
import 'package:nakkda/features/photo/domain/photo_service.dart';

void main() {
  group('PhotoSource', () {
    test('camera, arCamera, gallery 세 값이 존재한다', () {
      expect(PhotoSource.values.length, 3);
      expect(PhotoSource.values, contains(PhotoSource.camera));
      expect(PhotoSource.values, contains(PhotoSource.arCamera));
      expect(PhotoSource.values, contains(PhotoSource.gallery));
    });

    test('camera와 gallery는 서로 다른 값이다', () {
      expect(PhotoSource.camera, isNot(equals(PhotoSource.gallery)));
    });
  });
}

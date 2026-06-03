import 'package:flutter_test/flutter_test.dart';
import 'package:vo_rec/features/photo/domain/photo_service.dart';

void main() {
  group('PhotoSource', () {
    test('camera와 gallery 두 값이 존재한다', () {
      expect(PhotoSource.values.length, 2);
      expect(PhotoSource.values, contains(PhotoSource.camera));
      expect(PhotoSource.values, contains(PhotoSource.gallery));
    });

    test('camera와 gallery는 서로 다른 값이다', () {
      expect(PhotoSource.camera, isNot(equals(PhotoSource.gallery)));
    });
  });
}

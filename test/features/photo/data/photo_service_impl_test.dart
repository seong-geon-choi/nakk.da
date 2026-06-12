import 'package:flutter_test/flutter_test.dart';
import 'package:nakkda/features/photo/data/photo_service_impl.dart';
import 'package:nakkda/features/photo/domain/photo_service.dart';

void main() {
  group('PhotoServiceImpl', () {
    test('인스턴스 생성이 가능하다', () {
      final service = PhotoServiceImpl();
      expect(service, isNotNull);
    });

    test('PhotoSource.camera는 index 0이다', () {
      expect(PhotoSource.camera.index, 0);
    });

    test('PhotoSource.arCamera는 index 1이다', () {
      expect(PhotoSource.arCamera.index, 1);
    });

    test('PhotoSource.gallery는 index 2이다', () {
      expect(PhotoSource.gallery.index, 2);
    });
  });
}

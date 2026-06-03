import 'package:flutter_test/flutter_test.dart';
import 'package:vo_rec/features/photo/data/photo_service_impl.dart';
import 'package:vo_rec/features/photo/domain/photo_service.dart';

void main() {
  group('PhotoServiceImpl', () {
    test('인스턴스 생성이 가능하다', () {
      final service = PhotoServiceImpl();
      expect(service, isNotNull);
    });

    test('PhotoSource.camera는 index 0이다', () {
      expect(PhotoSource.camera.index, 0);
    });

    test('PhotoSource.gallery는 index 1이다', () {
      expect(PhotoSource.gallery.index, 1);
    });
  });
}

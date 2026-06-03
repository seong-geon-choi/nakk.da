import 'package:image_picker/image_picker.dart';
import '../domain/photo_service.dart';
import '../../../core/utils/media_scanner.dart';

class PhotoServiceImpl implements PhotoService {
  final ImagePicker _picker = ImagePicker();

  @override
  Future<String?> pickImage({required PhotoSource source}) async {
    if (source == PhotoSource.gallery) {
      // 갤러리: MethodChannel 사용 → MANAGE_EXTERNAL_STORAGE 있으면 실제 경로 반환
      return await pickGalleryImagePath();
    }
    // 카메라
    final XFile? picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    return picked?.path;
  }
}

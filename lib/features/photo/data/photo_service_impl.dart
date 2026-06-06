import 'package:image_picker/image_picker.dart';
import '../domain/photo_service.dart';
import '../../../core/utils/media_scanner.dart';

class PhotoServiceImpl implements PhotoService {
  final ImagePicker _picker = ImagePicker();

  @override
  Future<String?> pickImage({required PhotoSource source}) async {
    if (source == PhotoSource.gallery) {
      final result = await pickGalleryImagePath();
      return result?.path;
    }
    final XFile? picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    return picked?.path;
  }

  @override
  Future<String?> pickVideoFromGallery() async {
    final XFile? picked = await _picker.pickVideo(source: ImageSource.gallery);
    return picked?.path;
  }
}

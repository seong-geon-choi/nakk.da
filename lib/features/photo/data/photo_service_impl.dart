import 'package:image_picker/image_picker.dart';
import '../domain/photo_service.dart';

class PhotoServiceImpl implements PhotoService {
  final ImagePicker _picker = ImagePicker();

  @override
  Future<String?> pickImage({required PhotoSource source}) async {
    final XFile? picked = await _picker.pickImage(
      source: source == PhotoSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      imageQuality: source == PhotoSource.camera ? 85 : null,
    );
    return picked?.path;
  }
}

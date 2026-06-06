enum PhotoSource { camera, arCamera, gallery }

abstract interface class PhotoService {
  Future<String?> pickImage({required PhotoSource source});
  Future<String?> pickVideoFromGallery();
}

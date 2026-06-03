enum PhotoSource { camera, arCamera, gallery }

abstract interface class PhotoService {
  /// 카메라 촬영 또는 갤러리 선택 후 임시 파일 경로 반환.
  /// 취소 시 null 반환.
  Future<String?> pickImage({required PhotoSource source});
}

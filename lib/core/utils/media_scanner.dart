import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

const _channel = MethodChannel('com.nakkda.nakkda/media');

/// [sourcePath] 파일을 MediaStore에 등록해 갤러리에서 보이도록 저장.
/// [relativePath]: "DCIM/nakkda" 형태의 MediaStore 상대 경로.
/// 반환값: 저장된 절대 경로, 실패 시 null.
Future<String?> saveToGallery(String sourcePath, {String relativePath = 'DCIM/nakkda'}) async {
  try {
    return await _channel.invokeMethod<String>('saveToGallery', {
      'path': sourcePath,
      'relativePath': relativePath,
    });
  } catch (_) {
    return null;
  }
}

/// 갤러리 피커를 열고 선택한 사진의 경로를 반환.
/// MANAGE_EXTERNAL_STORAGE 허가 시 실제 파일 경로, 미허가 시 앱 캐시 복사 경로.
/// 취소 또는 실패 시 null.
Future<String?> pickGalleryImagePath() async {
  try {
    return await _channel.invokeMethod<String>('pickGalleryImage');
  } catch (_) {
    return null;
  }
}

/// 갤러리에서 선택한 사진을 안정적인 앱 전용 외부 저장소로 복사.
/// 이미 실제 파일 경로(캐시 외부)이면 복사 없이 그대로 반환.
Future<String> copyGalleryPhotoToAppStorage(String srcPath) async {
  // DCIM, Pictures 등 실제 갤러리 경로면 복사 불필요
  if (!srcPath.contains('/cache/')) return srcPath;
  try {
    final appDir = await getExternalStorageDirectory();
    final photosDir = Directory('${appDir!.path}/photos');
    await photosDir.create(recursive: true);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ext = srcPath.contains('.') ? srcPath.split('.').last.toLowerCase() : 'jpg';
    final dest = File('${photosDir.path}/photo_$ts.$ext');
    await File(srcPath).copy(dest.path);
    return dest.path;
  } catch (_) {
    return srcPath;
  }
}

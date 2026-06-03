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

/// 갤러리에서 선택한 사진(캐시 경로)을 앱 전용 외부 저장소로 복사해 안정적인 경로 반환.
/// Android/data/.../files/photos/ 에 저장 — 갤러리 스캔 대상 아님, 권한 불필요.
/// 복사 실패 시 원본 경로 반환.
Future<String> copyGalleryPhotoToAppStorage(String srcPath) async {
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

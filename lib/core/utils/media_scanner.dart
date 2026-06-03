import 'package:flutter/services.dart';

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

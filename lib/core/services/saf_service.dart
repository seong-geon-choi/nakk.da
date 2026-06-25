import 'package:flutter/services.dart';

class SafService {
  static const _channel = MethodChannel('com.sgchoisg.nakkda/saf');

  static bool isSafUri(String? path) => path?.startsWith('content://') == true;

  Future<({String uri, String displayPath})?> pickFolder({String? initialPath}) async {
    final args = initialPath != null ? {'initialPath': initialPath} : null;
    final result = await _channel.invokeMapMethod<String, String>('pickFolder', args);
    if (result == null) return null;
    final uri = result['uri'];
    final displayPath = result['displayPath'];
    if (uri == null || displayPath == null) return null;
    return (uri: uri, displayPath: displayPath);
  }

  Future<String?> readFile(String folderUri, String filename) =>
      _channel.invokeMethod<String>('readTextFile', {'uri': folderUri, 'filename': filename});

  Future<void> writeFile(String folderUri, String filename, String content) =>
      _channel.invokeMethod('writeTextFile', {'uri': folderUri, 'filename': filename, 'content': content});

  Future<void> appendFile(String folderUri, String filename, String content) =>
      _channel.invokeMethod('appendTextFile', {'uri': folderUri, 'filename': filename, 'content': content});

  Future<bool> fileExists(String folderUri, String filename) async =>
      await _channel.invokeMethod<bool>('fileExists', {'uri': folderUri, 'filename': filename}) ?? false;

  Future<List<String>> listMdFiles(String folderUri) async {
    final result = await _channel.invokeListMethod<String>('listMdFiles', {'uri': folderUri});
    return result ?? [];
  }

  /// SAF 파일들의 수정 시간 반환 (epoch milliseconds → DateTime UTC)
  Future<Map<String, DateTime>> getFilesModifiedTimes(String folderUri, List<String> filenames) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'getFilesModifiedTimes',
      {'uri': folderUri, 'filenames': filenames},
    );
    if (result == null) return {};
    return result.map((k, v) => MapEntry(k, DateTime.fromMillisecondsSinceEpoch(v as int, isUtc: true)));
  }

  Future<void> ensureFolder(String folderUri) =>
      _channel.invokeMethod('ensureFolder', {'uri': folderUri});

  /// 공용 저장소에 relativePath(예: 'Documents/nakkda') 폴더가 없으면 생성.
  /// 첫 설정 시 SAF 픽커가 해당 폴더에서 열려 사용자가 권한 부여만 하면 되도록 한다.
  Future<bool> ensureFolderInPublicStorage(String relativePath) async =>
      await _channel.invokeMethod<bool>(
        'ensureDefaultFolder',
        {'relativePath': relativePath},
      ) ??
      false;

  Future<void> deleteFile(String folderUri, String filename) =>
      _channel.invokeMethod('deleteFile', {'uri': folderUri, 'filename': filename});

  Future<void> renameFile(String folderUri, String oldFilename, String newFilename) =>
      _channel.invokeMethod('renameFile', {
        'uri': folderUri, 'oldFilename': oldFilename, 'newFilename': newFilename,
      });

  Future<void> copyFile(String folderUri, String srcFilename, String dstFilename) =>
      _channel.invokeMethod('copyFile', {
        'uri': folderUri, 'srcFilename': srcFilename, 'dstFilename': dstFilename,
      });

  Future<String> getDisplayPath(String folderUri) async =>
      await _channel.invokeMethod<String>('getDisplayPath', {'uri': folderUri}) ?? folderUri;

  /// 로컬 캐시 파일을 SAF 폴더의 photos/ 서브폴더로 복사
  Future<void> copyFileToSafFolder(String sourcePath, String folderUri, String filename) =>
      _channel.invokeMethod('copyFileToSafFolder', {
        'sourcePath': sourcePath,
        'folderUri': folderUri,
        'filename': filename,
      });

  Future<List<String>> listPhotosFolder(String folderUri) async {
    final result = await _channel.invokeListMethod<String>('listPhotosFolder', {'uri': folderUri});
    return result ?? [];
  }

  Future<void> deletePhotoFile(String folderUri, String filename) =>
      _channel.invokeMethod('deletePhotoFile', {'uri': folderUri, 'filename': filename});

  Future<void> writePhotoBytes(String folderUri, String filename, List<int> bytes) =>
      _channel.invokeMethod('writePhotoBytes', {
        'folderUri': folderUri,
        'filename': filename,
        'bytes': Uint8List.fromList(bytes),
      });

  /// 로컬 파일 경로에서 EXIF GPS 좌표 읽기 (Android native ExifInterface 사용)
  Future<({double lat, double lng})?> readExifGpsFromPath(String filePath) async {
    final result = await _channel.invokeMapMethod<String, dynamic>('readExifGps', {'path': filePath});
    if (result == null) return null;
    final lat = (result['lat'] as num?)?.toDouble();
    final lng = (result['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    if (lat == 0.0 && lng == 0.0) return null;
    return (lat: lat, lng: lng);
  }

  /// 로컬 파일 경로에서 EXIF 촬영일시 문자열("yyyy:MM:dd HH:mm:ss") 읽기
  /// (Android native ExifInterface 사용 — Dart exif 패키지보다 OEM 신뢰성 높음)
  Future<String?> readExifDateTimeFromPath(String filePath) async {
    try {
      return await _channel
          .invokeMethod<String>('readExifDateTime', {'path': filePath});
    } catch (_) {
      return null;
    }
  }

  /// SAF 폴더 내 subpath(예: "photos/photo_123.jpg")의 이미지 bytes 반환
  Future<Uint8List?> readSafImage(String folderUri, String subpath) async {
    final bytes = await _channel.invokeMethod<Uint8List>('readSafImage', {
      'folderUri': folderUri,
      'subpath': subpath,
    });
    return bytes;
  }
}

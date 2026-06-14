import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

const _channel = MethodChannel('com.sgchoisg.nakkda/media');

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

/// 갤러리 피커를 열고 선택한 사진의 경로와 GPS를 반환.
/// ACCESS_MEDIA_LOCATION 권한 있으면 GPS 포함, 없으면 lat/lng null.
/// 취소 또는 실패 시 null.
Future<({String path, double? lat, double? lng})?> pickGalleryImagePath() async {
  // GPS EXIF 읽기 위해 ACCESS_MEDIA_LOCATION 요청 (이미 허가된 경우 바로 통과)
  await Permission.accessMediaLocation.request();
  try {
    final result = await _channel.invokeMapMethod<String, dynamic>('pickGalleryImage');
    if (result == null) return null;
    final path = result['path'] as String?;
    if (path == null) return null;
    final lat = (result['lat'] as num?)?.toDouble();
    final lng = (result['lng'] as num?)?.toDouble();
    return (path: path, lat: lat, lng: lng);
  } catch (_) {
    return null;
  }
}

/// 갤러리에서 사진 또는 동영상을 선택 (안드로이드 기본 갤러리 인터페이스 사용).
/// isVideo 포함 반환. 취소 시 null.
/// [mimeFilter]: '*/*' = 전체, 'image/*' = 사진만, 'video/*' = 동영상만
Future<({String path, bool isVideo, double? lat, double? lng})?> pickGalleryMedia({
  String mimeFilter = '*/*',
}) async {
  await Permission.accessMediaLocation.request();
  try {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'pickGalleryMedia',
      {'mimeFilter': mimeFilter},
    );
    if (result == null) return null;
    final path = result['path'] as String?;
    if (path == null) return null;
    final isVideo = result['isVideo'] as bool? ?? false;
    final lat = (result['lat'] as num?)?.toDouble();
    final lng = (result['lng'] as num?)?.toDouble();
    return (path: path, isVideo: isVideo, lat: lat, lng: lng);
  } catch (_) {
    return null;
  }
}

/// 특정 날짜에 촬영된 갤러리 사진 목록을 반환 (GPS 포함, 복사 없음).
Future<List<({String contentUri, String? path, DateTime timestamp, double? lat, double? lng})>>
    scanGalleryPhotosByDate(DateTime date) async {
  await Permission.accessMediaLocation.request();
  try {
    final result = await _channel.invokeListMethod<dynamic>('scanPhotosByDate', {
      'year': date.year,
      'month': date.month,
      'day': date.day,
    });
    if (result == null) return [];
    return result.map((item) {
      final m = Map<String, dynamic>.from(item as Map);
      return (
        contentUri: m['contentUri'] as String,
        path: m['path'] as String?,
        timestamp: DateTime.fromMillisecondsSinceEpoch((m['dateTaken'] as num).toInt()),
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
      );
    }).toList();
  } catch (_) {
    return [];
  }
}

/// 빌드 버전 및 빌드 시각 반환.
Future<({String version, String buildTime})?> getBuildInfo() async {
  try {
    final result = await _channel.invokeMapMethod<String, dynamic>('getBuildInfo');
    if (result == null) return null;
    return (
      version:   result['version']   as String? ?? '-',
      buildTime: result['buildTime'] as String? ?? '-',
    );
  } catch (_) {
    return null;
  }
}

/// content:// URI를 앱 캐시로 복사해 파일 경로 반환.
Future<String?> copyContentUriToCache(String contentUri) async {
  try {
    return await _channel.invokeMethod<String>('copyContentUriToCache', {'uri': contentUri});
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

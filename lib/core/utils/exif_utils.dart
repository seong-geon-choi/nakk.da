import 'dart:io';
import 'package:exif/exif.dart';
import '../services/saf_service.dart';

/// EXIF DateTimeOriginal → DateTime 반환 (없으면 null)
/// GPS와 동일하게 Android native ExifInterface를 우선 사용(삼성 등 OEM 포맷 신뢰성),
/// 실패 시 Dart exif 패키지로 폴백.
Future<DateTime?> readExifTimestamp(String imagePath) async {
  // 1) Android native ExifInterface 우선
  final native = await SafService().readExifDateTimeFromPath(imagePath);
  final fromNative = _parseExifDateTime(native);
  if (fromNative != null) return fromNative;

  // 2) Dart exif 패키지 폴백
  try {
    final bytes = await File(imagePath).readAsBytes();
    final data = await readExifFromBytes(bytes);
    final raw = data['EXIF DateTimeOriginal']?.printable
        ?? data['Image DateTimeOriginal']?.printable
        ?? data['Image DateTime']?.printable;
    return _parseExifDateTime(raw);
  } catch (_) {
    return null;
  }
}

/// EXIF 시각 문자열("2024:06:05 12:34:56") → DateTime
DateTime? _parseExifDateTime(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final parts = raw.trim().split(' ');
  if (parts.length < 2) return null;
  final d = parts[0].split(':');
  final t = parts[1].split(':');
  if (d.length < 3 || t.length < 3) return null;
  try {
    return DateTime(
      int.parse(d[0]), int.parse(d[1]), int.parse(d[2]),
      int.parse(t[0]), int.parse(t[1]), int.parse(t[2]),
    );
  } catch (_) {
    return null;
  }
}

/// Android native ExifInterface 사용 (Dart exif 패키지보다 삼성 등 OEM 포맷에 신뢰성 높음)
Future<({double lat, double lng})?> readExifGps(String imagePath) =>
    SafService().readExifGpsFromPath(imagePath);

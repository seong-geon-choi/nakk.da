import 'dart:io';
import 'package:exif/exif.dart';
import '../services/saf_service.dart';

/// EXIF DateTimeOriginal → DateTime 반환 (없으면 null)
Future<DateTime?> readExifTimestamp(String imagePath) async {
  try {
    final bytes = await File(imagePath).readAsBytes();
    final data = await readExifFromBytes(bytes);
    final raw = data['Image DateTimeOriginal']?.printable
        ?? data['EXIF DateTimeOriginal']?.printable;
    if (raw == null) return null;
    // 포맷: "2024:06:05 12:34:56"
    final parts = raw.trim().split(' ');
    if (parts.length < 2) return null;
    final d = parts[0].split(':');
    final t = parts[1].split(':');
    if (d.length < 3 || t.length < 3) return null;
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

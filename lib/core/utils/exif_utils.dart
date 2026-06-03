import 'dart:io';
import 'package:exif/exif.dart';

Future<({double lat, double lng})?> readExifGps(String imagePath) async {
  try {
    final bytes = await File(imagePath).readAsBytes();
    final data = await readExifFromBytes(bytes);

    final latTag = data['GPS GPSLatitude'];
    final latRefTag = data['GPS GPSLatitudeRef'];
    final lngTag = data['GPS GPSLongitude'];
    final lngRefTag = data['GPS GPSLongitudeRef'];

    if (latTag == null || lngTag == null) return null;

    final latVals = latTag.values.toList();
    final lngVals = lngTag.values.toList();
    if (latVals.length < 3 || lngVals.length < 3) return null;

    // Ratio.toString() returns "numerator/denominator"
    double parseRatio(dynamic v) {
      final s = v.toString();
      final idx = s.indexOf('/');
      if (idx >= 0) {
        final n = double.tryParse(s.substring(0, idx)) ?? 0;
        final d = double.tryParse(s.substring(idx + 1)) ?? 1;
        return d == 0 ? 0 : n / d;
      }
      return double.tryParse(s) ?? 0;
    }

    double dmsToDecimal(List<dynamic> vals) =>
        parseRatio(vals[0]) + parseRatio(vals[1]) / 60.0 + parseRatio(vals[2]) / 3600.0;

    var lat = dmsToDecimal(latVals);
    var lng = dmsToDecimal(lngVals);

    if (lat == 0.0 && lng == 0.0) return null;

    if (latRefTag?.printable.trim().toUpperCase() == 'S') lat = -lat;
    if (lngRefTag?.printable.trim().toUpperCase() == 'W') lng = -lng;

    return (lat: lat, lng: lng);
  } catch (_) {
    return null;
  }
}

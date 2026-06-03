import 'package:geocoding/geocoding.dart';

Future<String?> reverseGeocode(double lat, double lng) async {
  try {
    final placemarks = await placemarkFromCoordinates(lat, lng);
    if (placemarks.isEmpty) return null;
    final p = placemarks.first;
    final parts = <String>[
      if (p.administrativeArea?.isNotEmpty == true) p.administrativeArea!,
      if (p.subAdministrativeArea?.isNotEmpty == true) p.subAdministrativeArea!,
      if (p.locality?.isNotEmpty == true) p.locality!,
    ];
    return parts.isEmpty ? null : parts.join(' ');
  } catch (_) {
    return null;
  }
}

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
      if (p.subLocality?.isNotEmpty == true) p.subLocality!, // 동/읍/면
    ];
    // 연속 중복 제거 (예: '인천광역시 인천광역시')
    final dedup = <String>[];
    for (final part in parts) {
      if (dedup.isEmpty || dedup.last != part) dedup.add(part);
    }
    return dedup.isEmpty ? null : dedup.join(' ');
  } catch (_) {
    return null;
  }
}

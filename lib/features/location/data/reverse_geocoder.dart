import 'package:geocoding/geocoding.dart';

Future<String?> reverseGeocode(double lat, double lng) async {
  try {
    final placemarks = await placemarkFromCoordinates(lat, lng);
    if (placemarks.isEmpty) return null;

    // Android 온디바이스 Geocoder는 좌표 하나에 세분화 정도가 다른 placemark를
    // 여러 개 반환하며, .first에는 시/도만 있고 구/동은 뒤쪽 placemark에 있는
    // 경우가 많다. 행정 레벨별로 모든 placemark에서 처음 발견되는 비어있지 않은
    // 값을 취해 시/군/구/동을 최대한 복원한다.
    String? pick(String? Function(Placemark) f) {
      for (final p in placemarks) {
        final v = f(p);
        if (v != null && v.trim().isNotEmpty) return v.trim();
      }
      return null;
    }

    final parts = <String>[];
    for (final v in [
      pick((p) => p.administrativeArea), // 시/도
      pick((p) => p.subAdministrativeArea), // 시/군/구
      pick((p) => p.locality), // 시/구
      pick((p) => p.subLocality), // 동/읍/면
    ]) {
      if (v == null) continue;
      // 연속 중복 제거 (예: '인천광역시 인천광역시')
      if (parts.isEmpty || parts.last != v) parts.add(v);
    }
    return parts.isEmpty ? null : parts.join(' ');
  } catch (_) {
    return null;
  }
}

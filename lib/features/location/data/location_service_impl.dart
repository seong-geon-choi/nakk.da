import 'package:geolocator/geolocator.dart';
import '../domain/location_service.dart';
import '../domain/models/location_status.dart';

class LocationServiceImpl implements LocationService {
  static const _timeoutSeconds = 5;
  LocationStatus? _cache;

  @override
  LocationStatus? get cachedLocation => _cache;

  @override
  Future<LocationStatus?> getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return _cache;

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return _cache;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: _timeoutSeconds),
        ),
      );
      _cache = LocationStatus(
        timestamp: DateTime.now(),
        latitude: position.latitude,
        longitude: position.longitude,
      );
      return _cache;
    } catch (_) {
      return _cache;
    }
  }
}

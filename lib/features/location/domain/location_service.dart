import 'models/location_status.dart';

abstract interface class LocationService {
  Future<LocationStatus?> getCurrentLocation();
  LocationStatus? get cachedLocation;
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/location_service_impl.dart';
import '../data/reverse_geocoder.dart';
import '../domain/location_service.dart';
import '../domain/models/location_status.dart';
import '../../weather/data/weather_service.dart';
import '../../tide/data/tide_service.dart';
import '../../settings/presentation/settings_provider.dart';

final locationServiceProvider = Provider<LocationService>(
  (ref) => LocationServiceImpl(),
);

final _weatherServiceProvider = Provider((_) => WeatherService());
final _tideServiceProvider = Provider((_) => TideService());

final locationProvider =
    AsyncNotifierProvider<LocationNotifier, LocationStatus?>(
  LocationNotifier.new,
);

class LocationNotifier extends AsyncNotifier<LocationStatus?> {
  @override
  Future<LocationStatus?> build() async {
    return ref.read(locationServiceProvider).getCurrentLocation();
  }

  Future<LocationStatus?> refresh() async {
    state = const AsyncLoading();
    final result =
        await ref.read(locationServiceProvider).getCurrentLocation();
    state = AsyncData(result);
    return result;
  }

  LocationStatus? get cached =>
      ref.read(locationServiceProvider).cachedLocation;

  /// GPS + 역지오코딩 + 기온 + 물때/수온을 병합한 풍부한 LocationStatus 반환
  Future<LocationStatus> buildEnrichedLocation({bool isMove = false}) async {
    // 1. GPS
    final gps =
        await ref.read(locationServiceProvider).getCurrentLocation();
    final lat = gps?.latitude;
    final lng = gps?.longitude;
    final now = DateTime.now();

    if (lat == null || lng == null) {
      return LocationStatus(timestamp: now, isMove: isMove);
    }

    // 2. 역지오코딩 + 기온 + 물때 병렬 조회
    final settings = await ref.read(settingsProvider.future);
    final apiKey = settings.effectiveKhoaApiKey;

    final results = await Future.wait([
      reverseGeocode(lat, lng),
      ref.read(_weatherServiceProvider).getWeather(lat, lng),
      ref.read(_tideServiceProvider).getTideResult(lat, lng, apiKey),
    ]);

    final address = results[0] as String?;
    final weather = results[1] as WeatherResult;
    final tideResult = results[2] as TideResult?;

    return LocationStatus(
      timestamp: now,
      latitude: lat,
      longitude: lng,
      address: address,
      temperature: weather.temperature,
      tideName: tideResult != null ? '${tideResult.mulTae}물' : null,
      tideTime: tideResult?.nextTideTime != null
          ? '${tideResult!.nextTideType} ${tideResult.nextTideTime}'
          : null,
      waterTemp: tideResult?.waterTemp,
      stationName: tideResult?.station.name,
      stationDistance: tideResult != null
          ? double.parse(tideResult.distanceKm.toStringAsFixed(1))
          : null,
      isMove: isMove,
      windSpeed: weather.windSpeed,
      windDeg: weather.windDeg,
      weatherCode: weather.weatherCode,
    );
  }
}

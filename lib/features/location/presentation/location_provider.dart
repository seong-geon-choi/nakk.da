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

  /// 워터마크용 주소 — 이미 확보된 주소가 있으면 그대로, 없으면 현재 GPS를
  /// 역지오코딩해 시/군/구/동 문자열 반환. GPS/네트워크 실패 시 null.
  Future<String?> resolveWatermarkAddress() async {
    final existing = state.valueOrNull?.address ?? cached?.address;
    if (existing != null && existing.trim().isNotEmpty) return existing;
    final gps = await ref.read(locationServiceProvider).getCurrentLocation();
    final lat = gps?.latitude;
    final lng = gps?.longitude;
    if (lat == null || lng == null) return null;
    return reverseGeocode(lat, lng);
  }

  /// 지정한 위치·날짜로 현장정보(역지오코딩 + 기온/바람 + 물때·수온·관측소)를 수집한다.
  /// 지도 조위 그래프가 물때를 자동 수집할 때, 메모 현장정보와 동일한 품질로 기록하기 위함.
  /// - 물때(mulTae)·만조/간조·관측소: 날짜 기준으로 정확.
  /// - 기온/바람·수온: 현재값만 제공되므로 '오늘'일 때만 기록(과거 날짜엔 생략).
  Future<LocationStatus> buildEnrichedAt({
    required double lat,
    required double lng,
    required DateTime date,
  }) async {
    final settings = await ref.read(settingsProvider.future);
    final apiKey = settings.effectiveKhoaApiKey;
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;

    final address = await reverseGeocode(lat, lng);
    final tideResult =
        await ref.read(_tideServiceProvider).getTideResult(lat, lng, apiKey, date: date);
    WeatherResult? weather;
    if (isToday) {
      weather = await ref.read(_weatherServiceProvider).getWeather(lat, lng);
    }

    return LocationStatus(
      timestamp: isToday ? now : date,
      latitude: lat,
      longitude: lng,
      address: address,
      temperature: weather?.temperature,
      tideName: tideResult?.mulTaeLabel,
      tideTime: tideResult?.nextTideTime != null
          ? '${tideResult!.nextTideType} ${tideResult.nextTideTime}'
          : null,
      // 수온은 현재값이라 오늘만 기록(과거엔 오해 소지).
      waterTemp: isToday ? tideResult?.waterTemp : null,
      stationName: tideResult?.station.name,
      stationDistance: tideResult != null
          ? double.parse(tideResult.distanceKm.toStringAsFixed(1))
          : null,
      windSpeed: weather?.windSpeed,
      windDeg: weather?.windDeg,
      weatherCode: weather?.weatherCode,
      tides: tideResult?.tides ?? const [],
    );
  }

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
      tideName: tideResult?.mulTaeLabel,
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
      tides: tideResult?.tides ?? const [],
    );
  }
}

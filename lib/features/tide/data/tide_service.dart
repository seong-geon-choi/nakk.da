import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../domain/models/tide_station.dart';
import 'tide_station_data.dart';

class TideResult {
  final TideStation station;
  final double distanceKm;
  final int mulTae; // 1-15
  final String? nextTideType; // '만조' or '간조'
  final String? nextTideTime; // 'HH:mm'
  final double? waterTemp;

  const TideResult({
    required this.station,
    required this.distanceKm,
    required this.mulTae,
    this.nextTideType,
    this.nextTideTime,
    this.waterTemp,
  });
}

class TideService {
  static const _tideApiBase =
      'https://apis.data.go.kr/1192136/tideFcstHghLw/GetTideFcstHghLwApiService';
  static const _marineApiBase = 'https://marine-api.open-meteo.com/v1/marine';

  // 조석 예보 캐시: 키 = "stationCode-yyyyMMdd"
  static final Map<String, List<Map<String, dynamic>>?> _tideCache = {};

  Future<TideResult?> getTideResult(
    double lat,
    double lng,
    String apiKey,
  ) async {
    final station = _nearestStation(lat, lng);
    final distKm = _haversine(lat, lng, station.latitude, station.longitude);
    final mulTae = _calcMulTae(DateTime.now());

    final dateStr = _dateStr(DateTime.now());
    final tideData = await _fetchTidePrediction(station.code, dateStr, apiKey);
    // 사용자 위치가 내륙일 수 있으므로 해안 관측소 좌표로 수온 조회
    final waterTemp = await _fetchWaterTemp(station.latitude, station.longitude);

    String? nextType;
    String? nextTime;
    if (tideData != null) {
      final next = _nextTide(tideData);
      nextType = next?.$1;
      nextTime = next?.$2;
    }

    return TideResult(
      station: station,
      distanceKm: distKm,
      mulTae: mulTae,
      nextTideType: nextType,
      nextTideTime: nextTime,
      waterTemp: waterTemp,
    );
  }

  TideStation _nearestStation(double lat, double lng) {
    TideStation nearest = kTideStations.first;
    double minDist = double.infinity;
    for (final s in kTideStations) {
      final d = _haversine(lat, lng, s.latitude, s.longitude);
      if (d < minDist) {
        minDist = d;
        nearest = s;
      }
    }
    return nearest;
  }

  double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  // 음력 기반 물때 계산 (근사값)
  int _calcMulTae(DateTime date) {
    final ref = DateTime(2000, 1, 6);
    final days = date.difference(ref).inDays;
    const lunarMonth = 29.53059;
    final lunarAge = days % lunarMonth;
    final halfAge = lunarAge < 15 ? lunarAge : lunarAge - 15;
    final mulTae = (halfAge.round() % 15) + 1;
    return mulTae.clamp(1, 15);
  }

  String _dateStr(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  Future<List<Map<String, dynamic>>?> _fetchTidePrediction(
    String stationCode,
    String dateStr,
    String apiKey,
  ) async {
    final cacheKey = '$stationCode-$dateStr';
    if (_tideCache.containsKey(cacheKey)) return _tideCache[cacheKey];

    try {
      final uri = Uri.parse(_tideApiBase).replace(queryParameters: {
        'serviceKey': apiKey,
        'obsCode': stationCode,
        'date': dateStr,
        'numOfRows': '10',
        'pageNo': '1',
        'type': 'json',
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) {
        _tideCache[cacheKey] = null;
        return null;
      }
      final result = _parseItems(resp.body);
      _tideCache[cacheKey] = result;
      return result;
    } catch (_) {
      _tideCache[cacheKey] = null;
      return null;
    }
  }

  // Open-Meteo Marine API로 현재 시간 수온 조회 (무료·무제한)
  Future<double?> _fetchWaterTemp(double lat, double lng) async {
    try {
      final uri = Uri.parse(_marineApiBase).replace(queryParameters: {
        'latitude': lat.toStringAsFixed(4),
        'longitude': lng.toStringAsFixed(4),
        'hourly': 'sea_surface_temperature',
        'forecast_days': '1',
        'timezone': 'auto',
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final json = jsonDecode(resp.body);
      final times =
          (json['hourly']?['time'] as List?)?.cast<String>();
      final temps =
          (json['hourly']?['sea_surface_temperature'] as List?)?.cast<num>();
      if (times == null || temps == null || times.isEmpty) return null;

      // 현재 시간 이후의 첫 번째 값 사용
      final now = DateTime.now();
      final nowHour = DateTime(now.year, now.month, now.day, now.hour);
      for (int i = 0; i < times.length; i++) {
        final t = DateTime.tryParse(times[i]);
        if (t != null && !t.isBefore(nowHour)) {
          final v = temps[i];
          return v == double.nan ? null : v.toDouble();
        }
      }
      return temps.last.toDouble();
    } catch (_) {
      return null;
    }
  }

  // data.go.kr KHOA 응답 파싱: {header:{}, body:{items:{item:[...]}}}
  List<Map<String, dynamic>>? _parseItems(String body) {
    try {
      final json = jsonDecode(body);
      if (json is Map) {
        // 실제 KHOA 형식: 최상위 body 직접 접근
        final bodyData = json['body'];
        if (bodyData is Map) {
          final items = bodyData['items']?['item'];
          if (items is List) return items.cast<Map<String, dynamic>>();
          if (items is Map) return [items.cast<String, dynamic>()];
        }
        // 구 data.go.kr 형식 (fallback)
        final response = json['response'];
        if (response is Map) {
          final items = response['body']?['items']?['item'];
          if (items is List) return items.cast<Map<String, dynamic>>();
          if (items is Map) return [items.cast<String, dynamic>()];
        }
      }
    } catch (_) {}
    return null;
  }

  // predcDt: "2026-06-02 HH:mm" → "HH:mm" 추출
  String _extractTime(Map<String, dynamic> entry) {
    final predcDt = entry['predcDt']?.toString() ?? '';
    if (predcDt.length >= 16) return predcDt.substring(11, 16);
    return (entry['tideTime'] ?? entry['hl_time'] ?? entry['fcstTime'])
            ?.toString() ??
        '';
  }

  // extrSe: "1"/"3"=고조, "2"/"4"=저조
  String _extractTideType(Map<String, dynamic> entry) {
    final extrSe = entry['extrSe']?.toString() ?? '';
    if (extrSe == '1' || extrSe == '3') return '만조';
    if (extrSe == '2' || extrSe == '4') return '간조';
    final code =
        (entry['highLow'] ?? entry['hl_code'] ?? entry['fcstCode'])?.toString() ??
            '';
    return (code == 'H' || code == '고조') ? '만조' : '간조';
  }

  (String, String)? _nextTide(List<Map<String, dynamic>> data) {
    final now = DateTime.now();
    final nowStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    for (final entry in data) {
      final time = _extractTime(entry);
      if (time.compareTo(nowStr) > 0) {
        return (_extractTideType(entry), time);
      }
    }
    if (data.isNotEmpty) {
      final entry = data.first;
      return (_extractTideType(entry), _extractTime(entry));
    }
    return null;
  }
}

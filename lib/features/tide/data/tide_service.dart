import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:lunar/lunar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models/tide_station.dart';
import 'tide_station_data.dart';

class TideResult {
  final TideStation station;
  final double distanceKm;
  final String mulTaeLabel; // '2물', '조금', '무시' 등
  final String? nextTideType; // '만조' or '간조'
  final String? nextTideTime; // 'HH:mm'
  final double? waterTemp;
  final List<TideEvent> tides; // 당일 만조/간조 전체

  const TideResult({
    required this.station,
    required this.distanceKm,
    required this.mulTaeLabel,
    this.nextTideType,
    this.nextTideTime,
    this.waterTemp,
    this.tides = const [],
  });
}

class TideService {
  static const _tideApiBase =
      'https://apis.data.go.kr/1192136/tideFcstHghLw/GetTideFcstHghLwApiService';
  static const _marineApiBase = 'https://marine-api.open-meteo.com/v1/marine';

  // 조석 캐시 서버(GitHub Actions가 매일 KHOA에서 갱신, jsDelivr CDN 서빙).
  static const _cdnBase =
      'https://cdn.jsdelivr.net/gh/seong-geon-choi/nakkda-tide-data@main/data';

  // 세션 메모리 캐시: 관측소코드 → 디코드된 관측소 파일 JSON
  static final Map<String, Map<String, dynamic>> _stationCache = {};

  Future<TideResult?> getTideResult(
    double lat,
    double lng,
    String apiKey,
  ) async {
    final station = _nearestStation(lat, lng);
    final distKm = _haversine(lat, lng, station.latitude, station.longitude);
    final mulTaeLabel = _calcMulTaeLabel(DateTime.now());

    final dateStr = _dateStr(DateTime.now());
    final tides = await _fetchTideEvents(station.code, dateStr, apiKey);
    // 사용자 위치가 내륙일 수 있으므로 해안 관측소 좌표로 수온 조회
    final waterTemp = await _fetchWaterTemp(station.latitude, station.longitude);

    String? nextType;
    String? nextTime;
    if (tides.isNotEmpty) {
      final next = _nextTideEvent(tides);
      nextType = next?.type;
      nextTime = next?.time;
    }

    return TideResult(
      station: station,
      distanceKm: distKm,
      mulTaeLabel: mulTaeLabel,
      nextTideType: nextType,
      nextTideTime: nextTime,
      waterTemp: waterTemp,
      tides: tides,
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

  // 음력일 기반 물때 계산 (서해/인천식 7물때 체계)
  // 음력 10일=1물 … 22일=13물, 23일=조금, 24일=무시, 25일=다시 1물.
  // 음력 16일(보름)=7물 사리, 음력 1일=7물 사리. (바다타임 인천 기준 검증)
  String _calcMulTaeLabel(DateTime date) {
    final lunarDay =
        Solar.fromYmd(date.year, date.month, date.day).getLunar().getDay();
    final i = (lunarDay - 10) % 15; // Dart의 %는 음수 피제수에도 0~14 반환
    if (i <= 12) return '${i + 1}물';
    if (i == 13) return '조금';
    return '무시';
  }

  String _dateStr(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  // 당일 만조/간조 이벤트 확보: ① 세션/기기 캐시 → ② CDN → ③ KHOA 직접 호출(폴백).
  Future<List<TideEvent>> _fetchTideEvents(
    String stationCode,
    String dateStr,
    String apiKey,
  ) async {
    final cdn = await _loadCdnDay(stationCode, dateStr);
    if (cdn != null && cdn.isNotEmpty) return cdn;

    // 폴백: KHOA 직접 호출(기존 방식). CDN·캐시 모두 실패할 때만.
    final items = await _fetchTidePredictionKhoa(stationCode, dateStr, apiKey);
    if (items == null) return const [];
    final out = <TideEvent>[];
    for (final e in items) {
      final t = _extractTime(e);
      if (t.isEmpty) continue;
      out.add(TideEvent(
        type: _extractTideType(e),
        time: t,
        level: _extractLevel(e),
      ));
    }
    return out;
  }

  // 관측소 파일을 세션/기기 캐시 또는 CDN에서 확보해 해당 날짜 이벤트 반환.
  // 한 번 받으면 오늘 전후 수일치가 한 파일에 들어와 추가 호출이 없다.
  Future<List<TideEvent>?> _loadCdnDay(
      String stationCode, String dateStr) async {
    final mem = _stationCache[stationCode];
    if (mem != null) {
      final ev = _eventsFromStation(mem, dateStr);
      if (ev != null) return ev;
    }

    SharedPreferences? prefs;
    Map<String, dynamic>? cached;
    final key = 'tide_cdn_$stationCode';
    try {
      prefs = await SharedPreferences.getInstance();
      final cachedStr = prefs.getString(key);
      if (cachedStr != null) {
        cached = jsonDecode(cachedStr) as Map<String, dynamic>;
        // 해당 날짜가 있고 24h 이내면 재다운로드 생략
        if (_isFresh(cached) && _eventsFromStation(cached, dateStr) != null) {
          _stationCache[stationCode] = cached;
          return _eventsFromStation(cached, dateStr);
        }
      }
    } catch (_) {}

    try {
      final uri = Uri.parse('$_cdnBase/$stationCode.json');
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final text = utf8.decode(resp.bodyBytes);
        final j = jsonDecode(text) as Map<String, dynamic>;
        _stationCache[stationCode] = j;
        await prefs?.setString(key, text);
        final ev = _eventsFromStation(j, dateStr);
        if (ev != null) return ev;
      }
    } catch (_) {}

    // CDN 실패 시 신선도 무시하고 기기 캐시라도 사용
    if (cached != null) return _eventsFromStation(cached, dateStr);
    return null;
  }

  bool _isFresh(Map<String, dynamic> station) {
    final g = DateTime.tryParse(station['generated']?.toString() ?? '');
    if (g == null) return false;
    return DateTime.now().toUtc().difference(g.toUtc()) <
        const Duration(hours: 24);
  }

  // 관측소 파일 JSON에서 해당 날짜 이벤트 추출. 날짜 키가 없으면 null.
  List<TideEvent>? _eventsFromStation(
      Map<String, dynamic> station, String dateStr) {
    final days = station['days'];
    if (days is! Map) return null;
    final list = days[dateStr];
    if (list is! List) return null;
    final out = <TideEvent>[];
    for (final e in list) {
      if (e is! Map) continue;
      final time = e['time']?.toString() ?? '';
      if (time.isEmpty) continue;
      final lvl = e['level'];
      out.add(TideEvent(
        type: e['t'] == 'H' ? '만조' : '간조',
        time: time,
        level: lvl is num ? lvl.round() : null,
      ));
    }
    return out;
  }

  Future<List<Map<String, dynamic>>?> _fetchTidePredictionKhoa(
    String stationCode,
    String dateStr,
    String apiKey,
  ) async {
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
      if (resp.statusCode != 200) return null;
      return _parseItems(resp.body);
    } catch (_) {
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
          return v.isNaN ? null : v.toDouble();
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

  // 조위(cm) 추출: KHOA 응답 필드 predcTdlvVl(예: 704.0), 정수 반올림
  int? _extractLevel(Map<String, dynamic> entry) {
    final raw = (entry['predcTdlvVl'] ?? entry['tphLevel'])?.toString();
    if (raw == null) return null;
    return double.tryParse(raw)?.round();
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

  TideEvent? _nextTideEvent(List<TideEvent> tides) {
    final now = DateTime.now();
    final nowStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    for (final e in tides) {
      if (e.time.compareTo(nowStr) > 0) return e;
    }
    return tides.isNotEmpty ? tides.first : null;
  }
}

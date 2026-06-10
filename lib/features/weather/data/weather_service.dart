import 'dart:convert';
import 'package:http/http.dart' as http;

class WeatherResult {
  final double? temperature;
  final double? windSpeed;
  final int? windDeg;
  final int? weatherCode;

  const WeatherResult({
    this.temperature,
    this.windSpeed,
    this.windDeg,
    this.weatherCode,
  });
}

class WeatherService {
  static const _baseUrl = 'https://api.open-meteo.com/v1/forecast';

  Future<WeatherResult> getWeather(double lat, double lng) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl?latitude=$lat&longitude=$lng&current_weather=true&forecast_days=1',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final current = data['current_weather'] as Map<String, dynamic>?;
        if (current != null) {
          return WeatherResult(
            temperature: (current['temperature'] as num?)?.toDouble(),
            windSpeed: (current['windspeed'] as num?)?.toDouble(),
            windDeg: (current['winddirection'] as num?)?.toInt(),
            weatherCode: (current['weathercode'] as num?)?.toInt(),
          );
        }
      }
    } catch (_) {}
    return const WeatherResult();
  }

  // 하위 호환
  Future<double?> getTemperature(double lat, double lng) async =>
      (await getWeather(lat, lng)).temperature;
}

String windDegToDirection(int deg) {
  const dirs = ['북', '북동', '동', '남동', '남', '남서', '서', '북서'];
  return dirs[((deg + 22.5) / 45).floor() % 8];
}

String weatherCodeToDesc(int code) {
  if (code == 0) return '맑음';
  if (code == 1) return '대체로 맑음';
  if (code == 2) return '부분 흐림';
  if (code == 3) return '흐림';
  if (code == 45 || code == 48) return '안개';
  if (code >= 51 && code <= 55) return '이슬비';
  if (code >= 61 && code <= 65) return '비';
  if (code >= 71 && code <= 75) return '눈';
  if (code >= 80 && code <= 82) return '소나기';
  if (code == 95) return '뇌우';
  if (code == 96 || code == 99) return '우박';
  return '날씨 정보 없음';
}

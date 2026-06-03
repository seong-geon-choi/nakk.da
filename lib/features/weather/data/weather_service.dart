import 'dart:convert';
import 'package:http/http.dart' as http;

class WeatherService {
  static const _baseUrl = 'https://api.open-meteo.com/v1/forecast';

  Future<double?> getTemperature(double lat, double lng) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl?latitude=$lat&longitude=$lng&current_weather=true&forecast_days=1',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final current = data['current_weather'] as Map<String, dynamic>?;
        if (current != null) {
          return (current['temperature'] as num).toDouble();
        }
      }
    } catch (_) {}
    return null;
  }
}

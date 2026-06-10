import 'package:flutter/material.dart';
import '../../features/location/domain/models/location_status.dart';
import '../../features/weather/data/weather_service.dart';

class LocationStatusCard extends StatelessWidget {
  final LocationStatus status;

  const LocationStatusCard({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (status.isMove) ...[
                Text(
                  '장소 (${_time(status.timestamp)})  ',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const Icon(Icons.location_on, size: 16),
              const SizedBox(width: 4),
              Expanded(child: Text(_address, style: const TextStyle(fontSize: 14))),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '🌡 $_temp | 💧 $_water',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            '관측소: $_station | 🌊 $_tide',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurface.withValues(alpha: 0.6)),
          ),
          if (_weather != null) ...[
            const SizedBox(height: 2),
            Text(
              _weather!,
              style: TextStyle(fontSize: 12, color: colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
          ],
        ],
      ),
    );
  }

  String get _address =>
      status.address ??
      (status.latitude != null
          ? '${status.latitude!.toStringAsFixed(4)}, ${status.longitude!.toStringAsFixed(4)}'
          : '-');

  String get _temp =>
      status.temperature != null ? '기온: ${status.temperature}°C' : '기온: -°C';

  String get _tide =>
      (status.tideName != null && status.tideTime != null)
          ? '${status.tideName} (${status.tideTime})'
          : '-물 (- --:--)';

  String get _water =>
      status.waterTemp != null ? '수온 ${status.waterTemp}°C' : '수온 -°C';

  String get _station =>
      (status.stationName != null && status.stationDistance != null)
          ? '${status.stationName} (${status.stationDistance!.toStringAsFixed(1)}km)'
          : '- (-.--km)';

  String? get _weather {
    final wind = status.windSpeed;
    final deg = status.windDeg;
    final code = status.weatherCode;
    if (wind == null && code == null) return null;
    final parts = <String>[];
    if (wind != null && deg != null) {
      parts.add('🌬 ${windDegToDirection(deg)} ${wind.toStringAsFixed(1)}m/s');
    }
    if (code != null) {
      parts.add('⛅ ${weatherCodeToDesc(code)}');
    }
    return parts.join(' | ');
  }

  String _time(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

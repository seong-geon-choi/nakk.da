import 'package:flutter/material.dart';
import 'package:lunar/lunar.dart';
import '../../features/location/domain/models/location_status.dart';
import '../../features/weather/data/weather_service.dart';
import '../../features/tide/data/astro_calc.dart';

const _highTideColor = Color(0xFFD32F2F); // 만조 ▲ 빨강
const _lowTideColor = Color(0xFF1976D2); // 간조 ▼ 파랑

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
              Text(
                '${_time(status.timestamp)}  ',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
          GestureDetector(
            onTap: status.tides.isNotEmpty ? () => _showTides(context) : null,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '관측소: $_station | 🌊 $_tide',
                    style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurface.withValues(alpha: 0.6)),
                  ),
                ),
                if (status.tides.isNotEmpty)
                  Icon(Icons.unfold_more,
                      size: 16,
                      color: colorScheme.onSurface.withValues(alpha: 0.6)),
              ],
            ),
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

  void _showTides(BuildContext context) {
    final ts = status.timestamp;
    final day = DateTime(ts.year, ts.month, ts.day);
    final title = status.stationName != null
        ? '🌊 ${status.stationName} ${ts.month}/${ts.day} 물때'
        : '🌊 ${ts.month}/${ts.day} 물때';

    // 음력·월령
    final lunar = Solar.fromYmd(ts.year, ts.month, ts.day).getLunar();
    final phase = moonPhase(day);
    final summary = StringBuffer('음력 ${lunar.getMonth()}.${lunar.getDay()}');
    if (status.tideName != null) summary.write(' · ${status.tideName}');
    summary.write(
        ' · ${phase.name} ${(phase.illumination * 100).round()}%');

    // 일출몰·월출몰(위경도 있을 때만)
    String? sunLine;
    String? moonLine;
    if (status.latitude != null && status.longitude != null) {
      final s = sunRiseSet(day, status.latitude!, status.longitude!);
      final m = moonRiseSet(day, status.latitude!, status.longitude!);
      sunLine = '🌅 ${_hm(s.rise)}   🌇 ${_hm(s.set)}';
      moonLine = '🌙 출 ${_hm(m.rise)}   몰 ${_hm(m.set)}';
    }

    // 조차(물흐름 근사)·날씨
    final range = tidalRange(status.tides);
    final wx = status.weatherCode != null
        ? '⛅ ${weatherCodeToDesc(status.weatherCode!)}'
        : null;
    final flowWx = [
      if (range != null) '🌊 조차 ${range.rangeCm}cm (약 ${range.percent}%)',
      ?wx,
    ].join('   ');

    final onSurface = Theme.of(context).colorScheme.onSurface;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 16)),
        titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        content: SizedBox(
          width: 290,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(summary.toString(),
                    style: TextStyle(
                        fontSize: 12.5,
                        color: onSurface.withValues(alpha: 0.75))),
                if (sunLine != null) ...[
                  const SizedBox(height: 4),
                  Text(sunLine, style: const TextStyle(fontSize: 12.5)),
                ],
                if (moonLine != null) ...[
                  const SizedBox(height: 2),
                  Text(moonLine, style: const TextStyle(fontSize: 12.5)),
                ],
                if (flowWx.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(flowWx, style: const TextStyle(fontSize: 12.5)),
                ],
                const Divider(height: 16),
                ..._tideRows(onSurface),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('닫기')),
        ],
      ),
    );
  }

  List<Widget> _tideRows(Color onSurface) {
    final tides = status.tides;
    final rows = <Widget>[];
    for (var i = 0; i < tides.length; i++) {
      final t = tides[i];
      final isHigh = t.type == '만조';
      final color = isHigh ? _highTideColor : _lowTideColor;
      int? diff;
      if (i > 0 && t.level != null && tides[i - 1].level != null) {
        diff = t.level! - tides[i - 1].level!;
      }
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(
                '${isHigh ? '▲' : '▼'} ${t.type}',
                style: TextStyle(fontWeight: FontWeight.w600, color: color),
              ),
            ),
            const SizedBox(width: 8),
            Text(t.time, style: const TextStyle(fontSize: 15)),
            const Spacer(),
            // 조위(cm): 고정폭 우측정렬 → 행마다 정렬 일치
            SizedBox(
              width: 60,
              child: Text(
                t.level != null ? '${t.level}cm' : '-',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 13, color: onSurface.withValues(alpha: 0.6)),
              ),
            ),
            const SizedBox(width: 8),
            // 직전 대비 ±차이: 전날 정보가 없어 못 구하면 N/A
            SizedBox(
              width: 52,
              child: Text(
                diff != null ? '${diff >= 0 ? '+' : ''}$diff' : 'N/A',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: diff != null
                      ? color
                      : onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
          ],
        ),
      ));
    }
    return rows;
  }

  String _hm(DateTime? dt) => dt == null
      ? '-'
      : '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

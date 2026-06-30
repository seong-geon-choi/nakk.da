import 'package:flutter/material.dart';
import 'package:lunar/lunar.dart';
import '../../features/location/domain/models/location_status.dart';
import '../../features/weather/data/weather_service.dart';
import '../../features/tide/data/astro_calc.dart';

const _highTideColor = Color(0xFFD32F2F); // 만조 ▲ 빨강
const _lowTideColor = Color(0xFF1976D2); // 간조 ▼ 파랑

/// 공유 이미지 캡처용 현장 정보 카드.
/// 상세보기 카드(4행)에 물때 상세(음력·일출몰·조차·만조/간조 표)를 한 장에 담는다.
/// 화면 표시용이 아니라 오프스크린 렌더링→PNG 캡처를 전제로 고정 폭으로 그린다.
class LocationShareCard extends StatelessWidget {
  final LocationStatus status;
  static const double width = 360;

  const LocationShareCard({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.6);
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min, // 내용 높이에 맞춰 캡처(아래 여백 제거)
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${_time(status.timestamp)}  ',
                  style: TextStyle(
                      fontSize: 13,
                      color: cs.primary,
                      fontWeight: FontWeight.w600)),
              const Icon(Icons.location_on, size: 16),
              const SizedBox(width: 4),
              Expanded(child: Text(_address, style: const TextStyle(fontSize: 14))),
            ],
          ),
          const SizedBox(height: 5),
          Text('🌡 $_temp | 💧 $_water', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 3),
          Text('관측소: $_station | 🌊 $_tide',
              style: TextStyle(fontSize: 12, color: muted)),
          if (_weather != null) ...[
            const SizedBox(height: 3),
            Text(_weather!, style: TextStyle(fontSize: 12, color: muted)),
          ],
          if (status.tides.isNotEmpty) ..._tideSection(cs, muted),
        ],
      ),
    );
  }

  List<Widget> _tideSection(ColorScheme cs, Color muted) {
    final ts = status.timestamp;
    final day = DateTime(ts.year, ts.month, ts.day);

    final lunar = Solar.fromYmd(ts.year, ts.month, ts.day).getLunar();
    final phase = moonPhase(day);
    final summary = StringBuffer('음력 ${lunar.getMonth()}.${lunar.getDay()}');
    if (status.tideName != null) summary.write(' · ${status.tideName}');
    summary.write(' · ${phase.name} ${(phase.illumination * 100).round()}%');

    String? sunLine;
    String? moonLine;
    if (status.latitude != null && status.longitude != null) {
      final s = sunRiseSet(day, status.latitude!, status.longitude!);
      final m = moonRiseSet(day, status.latitude!, status.longitude!);
      sunLine = '🌅 ${_hm(s.rise)}   🌇 ${_hm(s.set)}';
      moonLine = '🌙 출 ${_hm(m.rise)}   몰 ${_hm(m.set)}';
    }

    final range = tidalRange(status.tides);
    final flowWx = [
      if (range != null) '🌊 조차 ${range.rangeCm}cm (약 ${range.percent}%)',
      if (status.weatherCode != null) '⛅ ${weatherCodeToDesc(status.weatherCode!)}',
    ].join('   ');

    return [
      const Divider(height: 16),
      Text(summary.toString(),
          style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: 0.75))),
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
      ..._tideRows(muted),
    ];
  }

  List<Widget> _tideRows(Color muted) {
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
              child: Text('${isHigh ? '▲' : '▼'} ${t.type}',
                  style: TextStyle(fontWeight: FontWeight.w600, color: color)),
            ),
            const SizedBox(width: 8),
            Text(t.time, style: const TextStyle(fontSize: 15)),
            const Spacer(),
            SizedBox(
              width: 60,
              child: Text(t.level != null ? '${t.level}cm' : '-',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 13, color: muted)),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 52,
              child: Text(
                diff != null ? '${diff >= 0 ? '+' : ''}$diff' : 'N/A',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: diff != null ? color : muted.withValues(alpha: 0.6),
                ),
              ),
            ),
          ],
        ),
      ));
    }
    return rows;
  }

  String get _address =>
      status.address ??
      (status.latitude != null
          ? '${status.latitude!.toStringAsFixed(4)}, ${status.longitude!.toStringAsFixed(4)}'
          : '-');

  String get _temp =>
      status.temperature != null ? '기온: ${status.temperature}°C' : '기온: -°C';

  String get _water =>
      status.waterTemp != null ? '수온 ${status.waterTemp}°C' : '수온 -°C';

  String get _tide =>
      (status.tideName != null && status.tideTime != null)
          ? '${status.tideName} (${status.tideTime})'
          : '-물 (- --:--)';

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
    if (code != null) parts.add('⛅ ${weatherCodeToDesc(code)}');
    return parts.join(' | ');
  }

  String _time(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  String _hm(DateTime? dt) => dt == null
      ? '-'
      : '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

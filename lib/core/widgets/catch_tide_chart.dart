import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../features/tide/domain/models/tide_station.dart';

/// 조위(사인형, 반투명) 위에 어종별 시간당 조과를 서로 다른 색의 막대로 겹쳐 그리는 차트.
/// - 조위: 만조/간조 극값을 코사인 보간한 S자 곡선, 각 꼭지점에 높이(cm) 라벨.
/// - 조과: 어종별 시간(hour)별 그룹 막대. 좌측 y축에 마리수 눈금.
/// - 범례: 어종(탭하면 표시/숨김 토글) + 조위 + 조차(최고-최저 cm).
class CatchTideChart extends StatefulWidget {
  final List<TideEvent> tides;
  final Map<String, List<DateTime>> catchesBySpecies;
  final double height;

  const CatchTideChart({
    super.key,
    required this.tides,
    required this.catchesBySpecies,
    this.height = 160,
  });

  @override
  State<CatchTideChart> createState() => _CatchTideChartState();
}

class _CatchTideChartState extends State<CatchTideChart> {
  final Set<String> _hidden = {}; // 숨긴 어종

  static const List<Color> _palette = [
    Color(0xFFFF8A3D), Color(0xFF3DA5FF), Color(0xFF34C759), Color(0xFFD65DB1),
  ];

  static int? _parseMin(String hhmm) {
    final p = hhmm.split(':');
    if (p.length != 2) return null;
    final h = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  List<(int, int)> get _tidePoints {
    final pts = <(int, int)>[];
    for (final t in widget.tides) {
      if (t.level == null) continue;
      final m = _parseMin(t.time);
      if (m != null) pts.add((m, t.level!));
    }
    pts.sort((a, b) => a.$1.compareTo(b.$1));
    return pts;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tidePts = _tidePoints;
    final allSpecies = widget.catchesBySpecies.keys
        .where((s) => (widget.catchesBySpecies[s] ?? const []).isNotEmpty)
        .toList();

    if (tidePts.length < 2 && allSpecies.isEmpty) {
      return SizedBox(
        height: 48,
        child: Center(
          child: Text('표시할 조위·조과 정보가 없습니다',
              style: TextStyle(
                  fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5))),
        ),
      );
    }

    // 보이는 어종만 집계
    final visible = allSpecies.where((s) => !_hidden.contains(s)).toList();
    final seriesHours = <Map<int, int>>[];
    final seriesColors = <Color>[];
    for (final s in visible) {
      final idx = allSpecies.indexOf(s);
      final m = <int, int>{};
      for (final t in widget.catchesBySpecies[s]!) {
        m[t.hour] = (m[t.hour] ?? 0) + 1;
      }
      seriesHours.add(m);
      seriesColors.add(_palette[idx % _palette.length]);
    }

    // 조차(최고-최저)
    int? range;
    if (tidePts.isNotEmpty) {
      var lo = tidePts.first.$2, hi = tidePts.first.$2;
      for (final p in tidePts) {
        lo = math.min(lo, p.$2);
        hi = math.max(hi, p.$2);
      }
      range = hi - lo;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < allSpecies.length; i++)
              _speciesChip(allSpecies[i], _palette[i % _palette.length], cs),
            if (tidePts.length >= 2) ...[
              _legendLine(cs.primary, '조위', cs),
              if (range != null)
                Text('조차 ${(range / 100).toStringAsFixed(1)}m',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            ] else
              Text('물때 정보 없음',
                  style: TextStyle(
                      fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5))),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: widget.height,
          width: double.infinity,
          child: CustomPaint(
            painter: _CatchTidePainter(
              tidePoints: tidePts,
              seriesHours: seriesHours,
              seriesColors: seriesColors,
              range: _xRange(tidePts, seriesHours),
              tideLine: cs.primary.withValues(alpha: 0.7),
              tideFill: cs.primary.withValues(alpha: 0.16),
              gridColor: cs.onSurface.withValues(alpha: 0.12),
              textColor: cs.onSurface.withValues(alpha: 0.6),
              labelColor: cs.onSurface.withValues(alpha: 0.85),
            ),
          ),
        ),
      ],
    );
  }

  (int, int) _xRange(List<(int, int)> tidePts, List<Map<int, int>> series) {
    final mins = <int>[
      ...tidePts.map((e) => e.$1),
      for (final m in series)
        for (final h in m.keys) ...[h * 60, h * 60 + 60],
    ];
    if (mins.isEmpty) return (300, 960);
    var start = (mins.reduce(math.min) ~/ 60) * 60;
    var end = ((mins.reduce(math.max) + 59) ~/ 60) * 60;
    if (end - start < 180) end = start + 180;
    return (start.clamp(0, 1440), end.clamp(0, 1440));
  }

  Widget _speciesChip(String label, Color c, ColorScheme cs) {
    final on = !_hidden.contains(label);
    return GestureDetector(
      onTap: () => setState(() {
        if (on) {
          _hidden.add(label);
        } else {
          _hidden.remove(label);
        }
      }),
      child: Opacity(
        opacity: on ? 1 : 0.4,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 10,
                height: 10,
                decoration:
                    BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                    decoration: on ? null : TextDecoration.lineThrough)),
          ],
        ),
      ),
    );
  }

  Widget _legendLine(Color c, String label, ColorScheme cs) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 14, height: 3, color: c),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ],
      );
}

class _CatchTidePainter extends CustomPainter {
  final List<(int, int)> tidePoints;
  final List<Map<int, int>> seriesHours;
  final List<Color> seriesColors;
  final (int, int) range;
  final Color tideLine, tideFill, gridColor, textColor, labelColor;

  _CatchTidePainter({
    required this.tidePoints,
    required this.seriesHours,
    required this.seriesColors,
    required this.range,
    required this.tideLine,
    required this.tideFill,
    required this.gridColor,
    required this.textColor,
    required this.labelColor,
  });

  double _levelAt(int minute) {
    if (tidePoints.isEmpty) return 0;
    if (minute <= tidePoints.first.$1) return tidePoints.first.$2.toDouble();
    if (minute >= tidePoints.last.$1) return tidePoints.last.$2.toDouble();
    for (var i = 0; i < tidePoints.length - 1; i++) {
      final a = tidePoints[i], b = tidePoints[i + 1];
      if (minute >= a.$1 && minute <= b.$1) {
        final f = (minute - a.$1) / (b.$1 - a.$1);
        final c = (1 - math.cos(math.pi * f)) / 2;
        return a.$2 + (b.$2 - a.$2) * c;
      }
    }
    return tidePoints.last.$2.toDouble();
  }

  void _label(Canvas c, String t, Offset at, Color col, double size,
      {bool center = true, bool rightAlign = false}) {
    final tp = TextPainter(
        text: TextSpan(text: t, style: TextStyle(color: col, fontSize: size)),
        textDirection: TextDirection.ltr)
      ..layout();
    final dx = center
        ? at.dx - tp.width / 2
        : rightAlign
            ? at.dx - tp.width
            : at.dx;
    tp.paint(c, Offset(dx, at.dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 32.0, padR = 12.0, padT = 16.0, padB = 18.0;
    final plotW = size.width - padL - padR;
    final plotH = size.height - padT - padB;
    final startMin = range.$1, endMin = range.$2;
    final span = endMin - startMin;
    if (plotW <= 0 || plotH <= 0 || span <= 0) return;
    double xOf(int minute) => padL + plotW * (minute - startMin) / span;
    final base = padT + plotH;

    // 시간 그리드
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var h = (startMin + 59) ~/ 60; h * 60 <= endMin; h++) {
      final x = xOf(h * 60);
      canvas.drawLine(Offset(x, padT), Offset(x, base), gridPaint);
      _label(canvas, '$h', Offset(x, size.height - padB + 3), textColor, 9);
    }

    // 좌측 y축: 마리수 눈금(0..maxCount)
    var maxCount = 1;
    for (final m in seriesHours) {
      for (final v in m.values) {
        maxCount = math.max(maxCount, v);
      }
    }
    // y축에서 살짝 띄워 우측정렬(축 선과 겹치지 않게)
    _label(canvas, '0', Offset(padL - 7, base - 6), textColor, 9,
        center: false, rightAlign: true);
    _label(canvas, '$maxCount', Offset(padL - 7, padT - 4), textColor, 9,
        center: false, rightAlign: true);
    if (maxCount >= 2) {
      _label(canvas, '${(maxCount / 2).round()}',
          Offset(padL - 7, padT + plotH / 2 - 6), textColor, 9,
          center: false, rightAlign: true);
    }

    // 어종별 그룹 막대
    final n = seriesHours.length;
    if (n > 0) {
      for (var h = startMin ~/ 60; h * 60 < endMin; h++) {
        final x0 = xOf(h * 60), x1 = xOf(h * 60 + 60);
        final slotW = x1 - x0;
        if (slotW <= 2) continue;
        const sidePad = 3.0;
        final bw = (slotW - sidePad * 2) / n;
        for (var i = 0; i < n; i++) {
          final cnt = seriesHours[i][h] ?? 0;
          if (cnt <= 0) continue;
          final left = x0 + sidePad + i * bw + 0.5;
          final right = left + bw - 1.0;
          if (right <= left) continue;
          final top = base - plotH * (cnt / maxCount);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTRB(left, top, right, base), const Radius.circular(1.5)),
            Paint()..color = seriesColors[i],
          );
        }
      }
    }

    // 조위 곡선 + 꼭지점 높이 라벨
    if (tidePoints.length >= 2) {
      var minL = tidePoints.first.$2, maxL = tidePoints.first.$2;
      for (final p in tidePoints) {
        minL = math.min(minL, p.$2);
        maxL = math.max(maxL, p.$2);
      }
      if (maxL == minL) maxL = minL + 1;
      double yOf(double lv) => padT + plotH * (1 - (lv - minL) / (maxL - minL));
      final line = Path();
      final fill = Path();
      var started = false;
      for (double x = 0; x <= plotW; x += 2) {
        final minute = (startMin + span * (x / plotW)).round();
        final y = yOf(_levelAt(minute));
        final px = padL + x;
        if (!started) {
          line.moveTo(px, y);
          fill.moveTo(px, base);
          fill.lineTo(px, y);
          started = true;
        } else {
          line.lineTo(px, y);
          fill.lineTo(px, y);
        }
      }
      fill.lineTo(padL + plotW, base);
      fill.close();
      canvas.drawPath(fill, Paint()..color = tideFill);
      canvas.drawPath(
          line,
          Paint()
            ..color = tideLine
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
      final dot = Paint()..color = tideLine;
      for (final p in tidePoints) {
        if (p.$1 < startMin || p.$1 > endMin) continue;
        final cx = xOf(p.$1), cy = yOf(p.$2.toDouble());
        canvas.drawCircle(Offset(cx, cy), 2.5, dot);
        // 만조·간조 모두 꼭지점 위에 cm 라벨(아래면 x축 시간 라벨과 겹침)
        final ly = (cy - 13).clamp(0.0, size.height - 10);
        _label(canvas, '${p.$2}', Offset(cx, ly), labelColor, 9);
      }
    }
  }

  @override
  bool shouldRepaint(_CatchTidePainter old) =>
      old.tidePoints != tidePoints ||
      old.seriesHours != seriesHours ||
      old.seriesColors != seriesColors ||
      old.range != range;
}

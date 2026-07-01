import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../features/tide/domain/models/tide_station.dart';

/// 시간대별 조위 곡선(사인형). 만조/간조 극값을 코사인 보간해 그린다.
/// 실측 시간별 데이터가 아니라 극값 사이 조화 보간(근사)임.
class TideCurveGraph extends StatelessWidget {
  final List<TideEvent> tides;
  final int startMin; // 출항(분)
  final int endMin; // 입항(분)
  final double height;

  const TideCurveGraph({
    super.key,
    required this.tides,
    this.startMin = 300,
    this.endMin = 960,
    this.height = 140,
  });

  /// 조위(cm)가 있는 극값만 (분, 레벨)로 정렬 추출
  List<(int, int)> get _points {
    final pts = <(int, int)>[];
    for (final t in tides) {
      if (t.level == null) continue;
      final m = _parseMin(t.time);
      if (m != null) pts.add((m, t.level!));
    }
    pts.sort((a, b) => a.$1.compareTo(b.$1));
    return pts;
  }

  static int? _parseMin(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pts = _points;
    if (pts.length < 2) {
      return SizedBox(
        height: 48,
        child: Center(
          child: Text('물때 정보가 없어 조위 그래프를 표시할 수 없습니다',
              style: TextStyle(
                  fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5))),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('시간대별 조위 (근사)',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant)),
        const SizedBox(height: 6),
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _TideCurvePainter(
              points: pts,
              startMin: math.min(startMin, endMin),
              endMin: math.max(startMin, endMin),
              lineColor: cs.primary,
              fillColor: cs.primary.withValues(alpha: 0.12),
              gridColor: cs.onSurface.withValues(alpha: 0.12),
              textColor: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
      ],
    );
  }
}

class _TideCurvePainter extends CustomPainter {
  final List<(int, int)> points; // (분, 레벨cm) 정렬됨
  final int startMin;
  final int endMin;
  final Color lineColor;
  final Color fillColor;
  final Color gridColor;
  final Color textColor;

  _TideCurvePainter({
    required this.points,
    required this.startMin,
    required this.endMin,
    required this.lineColor,
    required this.fillColor,
    required this.gridColor,
    required this.textColor,
  });

  /// 코사인(조화) 보간으로 특정 시각의 조위 추정
  double _levelAt(int minute) {
    if (minute <= points.first.$1) return points.first.$2.toDouble();
    if (minute >= points.last.$1) return points.last.$2.toDouble();
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i], b = points[i + 1];
      if (minute >= a.$1 && minute <= b.$1) {
        final f = (minute - a.$1) / (b.$1 - a.$1);
        final c = (1 - math.cos(math.pi * f)) / 2; // 0..1 S자
        return a.$2 + (b.$2 - a.$2) * c;
      }
    }
    return points.last.$2.toDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    const padL = 34.0, padR = 8.0, padT = 8.0, padB = 18.0;
    final plotW = size.width - padL - padR;
    final plotH = size.height - padT - padB;
    if (plotW <= 0 || plotH <= 0) return;

    // y 스케일: 하루 극값 min/max
    var minL = points.first.$2, maxL = points.first.$2;
    for (final p in points) {
      minL = math.min(minL, p.$2);
      maxL = math.max(maxL, p.$2);
    }
    if (maxL == minL) maxL = minL + 1;
    final range = endMin - startMin;
    if (range <= 0) return;

    double xOf(int minute) => padL + plotW * (minute - startMin) / range;
    double yOf(double level) =>
        padT + plotH * (1 - (level - minL) / (maxL - minL));

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final tp = TextPainter(textDirection: TextDirection.ltr);

    // 시간 그리드(1시간 단위)
    final firstHour = ((startMin + 59) ~/ 60);
    for (var h = firstHour; h * 60 <= endMin; h++) {
      final x = xOf(h * 60);
      canvas.drawLine(Offset(x, padT), Offset(x, padT + plotH), gridPaint);
      tp.text = TextSpan(
          text: '$h', style: TextStyle(color: textColor, fontSize: 9));
      tp.layout();
      tp.paint(canvas, Offset(x - tp.width / 2, size.height - padB + 3));
    }

    // y 라벨(최고/최저)
    for (final lv in [minL, maxL]) {
      tp.text = TextSpan(
          text: '${lv}cm', style: TextStyle(color: textColor, fontSize: 9));
      tp.layout();
      tp.paint(canvas, Offset(0, yOf(lv.toDouble()) - tp.height / 2));
    }

    // 곡선 경로(2px 간격 샘플)
    final path = Path();
    final fill = Path();
    bool started = false;
    for (double x = 0; x <= plotW; x += 2) {
      final minute = (startMin + range * (x / plotW)).round();
      final y = yOf(_levelAt(minute));
      final px = padL + x;
      if (!started) {
        path.moveTo(px, y);
        fill.moveTo(px, padT + plotH);
        fill.lineTo(px, y);
        started = true;
      } else {
        path.lineTo(px, y);
        fill.lineTo(px, y);
      }
    }
    fill.lineTo(padL + plotW, padT + plotH);
    fill.close();

    canvas.drawPath(fill, Paint()..color = fillColor);
    canvas.drawPath(
        path,
        Paint()
          ..color = lineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);

    // 극값 마커(창 범위 내)
    final dotPaint = Paint()..color = lineColor;
    for (final p in points) {
      if (p.$1 < startMin || p.$1 > endMin) continue;
      canvas.drawCircle(Offset(xOf(p.$1), yOf(p.$2.toDouble())), 2.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_TideCurvePainter old) =>
      old.points != points ||
      old.startMin != startMin ||
      old.endMin != endMin;
}

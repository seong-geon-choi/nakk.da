import 'package:flutter/material.dart';

/// 두께를 지정할 수 있는 체크(✓) 표시. 기본 MaterialIcons의 check는 가변 두께를
/// 지원하지 않아, 좌표 찍기 버튼과 지도 마커에서 동일한 굵은 체크를 쓰려고
/// 직접 그린다.
class CheckMark extends StatelessWidget {
  final double size;
  final Color color;
  final double strokeWidth;

  const CheckMark({
    super.key,
    required this.size,
    this.color = Colors.white,
    this.strokeWidth = 3.0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CheckPainter(color: color, strokeWidth: strokeWidth),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  _CheckPainter({required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.20, h * 0.52)
      ..lineTo(w * 0.42, h * 0.72)
      ..lineTo(w * 0.80, h * 0.28);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}

import 'package:flutter/material.dart';

/// Lightweight vector Google "G" brand logo with official brand colors.
/// Renders 100% offline using CustomPainter with zero network latency or asset requirements.
class GoogleLogoWidget extends StatelessWidget {
  const GoogleLogoWidget({super.key, this.size = 22});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GoogleLogoPainter(),
      ),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final center = Offset(w / 2, h / 2);
    final radius = w / 2;
    final strokeWidth = w * 0.22;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    final rect = Rect.fromCircle(center: center, radius: radius - strokeWidth / 2);

    // 1. Red arc (Top)
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(rect, -2.8, 1.9, false, paint);

    // 2. Yellow arc (Bottom-left)
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(rect, 2.1, 1.4, false, paint);

    // 3. Green arc (Bottom-right)
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(rect, 0.45, 1.7, false, paint);

    // 4. Blue arc (Right)
    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(rect, -0.9, 1.4, false, paint);

    // 5. Blue horizontal center bar
    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;

    final barRect = Rect.fromLTRB(
      center.dx - strokeWidth * 0.15,
      center.dy - strokeWidth / 2,
      w - strokeWidth * 0.15,
      center.dy + strokeWidth / 2,
    );
    canvas.drawRect(barRect, barPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

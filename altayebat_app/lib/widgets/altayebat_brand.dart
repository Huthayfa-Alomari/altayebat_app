import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AltayebatAppMark extends StatelessWidget {
  final double size;

  const AltayebatAppMark({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: const CustomPaint(painter: _AltayebatAppMarkPainter()),
    );
  }
}

class AltayebatBrandLogo extends StatelessWidget {
  final double markSize;

  const AltayebatBrandLogo({super.key, this.markSize = 116});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: markSize,
          child: const CustomPaint(painter: _AltayebatRoundMarkPainter()),
        ),
        const SizedBox(height: 10),
        const Text(
          'أسواق الطيبات',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFFD6362A),
            fontSize: 24,
            fontWeight: FontWeight.w900,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'ALTAYEBAT',
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          style: TextStyle(
            color: Color(0xFF1E3A5F),
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 3.2,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: 120,
          height: 3,
          decoration: BoxDecoration(
            color: const Color(0xFF1E3A5F),
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(height: 9),
        const Text(
          'كل ما تحتاجه بيتك، بلمسة واحدة',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _AltayebatAppMarkPainter extends CustomPainter {
  const _AltayebatAppMarkPainter();

  static const _red = Color(0xFFD6362A);
  static const _navy = Color(0xFF1E3A5F);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / 380, size.height / 380);
    final dx = (size.width - (380 * scale)) / 2;
    final dy = (size.height - (380 * scale)) / 2;

    canvas
      ..save()
      ..translate(dx, dy)
      ..scale(scale);

    final background = Paint()
      ..color = _red
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 380, 380),
        const Radius.circular(84),
      ),
      background,
    );

    final whiteStroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final basket = Path()
      ..moveTo(110, 130)
      ..lineTo(110, 260)
      ..quadraticBezierTo(110, 280, 130, 280)
      ..lineTo(270, 280);
    canvas.drawPath(basket, whiteStroke);

    canvas.drawLine(const Offset(110, 130), const Offset(92, 100), whiteStroke);
    canvas.drawLine(
      const Offset(132, 158),
      const Offset(248, 158),
      whiteStroke,
    );
    canvas.drawLine(
      const Offset(120, 195),
      const Offset(260, 195),
      whiteStroke,
    );
    canvas.drawLine(
      const Offset(136, 232),
      const Offset(244, 232),
      whiteStroke,
    );

    final navyFill = Paint()
      ..color = _navy
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(150, 298), 16, navyFill);
    canvas.drawCircle(const Offset(220, 298), 16, navyFill);

    final leaf = Path()
      ..moveTo(270, 122)
      ..quadraticBezierTo(305, 108, 302, 70)
      ..quadraticBezierTo(265, 73, 253, 108)
      ..close();
    canvas.drawPath(leaf, navyFill);

    final leafStem = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    final stem = Path()
      ..moveTo(270, 122)
      ..quadraticBezierTo(280, 102, 293, 88);
    canvas.drawPath(stem, leafStem);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AltayebatAppMarkPainter oldDelegate) => false;
}

class _AltayebatRoundMarkPainter extends CustomPainter {
  const _AltayebatRoundMarkPainter();

  static const _red = Color(0xFFD6362A);
  static const _navy = Color(0xFF1E3A5F);

  @override
  void paint(Canvas canvas, Size size) {
    const baseWidth = 380.0;
    const baseHeight = 300.0;
    final scale = math.min(size.width / baseWidth, size.height / baseHeight);
    final dx = (size.width - (baseWidth * scale)) / 2;
    final dy = (size.height - (baseHeight * scale)) / 2;

    canvas
      ..save()
      ..translate(dx, dy)
      ..scale(scale);

    final redFill = Paint()
      ..color = _red
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(190, 150), 115, redFill);

    final navyOutline = Paint()
      ..color = _navy
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(const Offset(190, 150), 115, navyOutline);

    final whiteStroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final basket = Path()
      ..moveTo(130, 110)
      ..lineTo(130, 195)
      ..quadraticBezierTo(130, 210, 145, 210)
      ..lineTo(235, 210);
    canvas.drawPath(basket, whiteStroke);
    canvas.drawLine(const Offset(130, 110), const Offset(118, 90), whiteStroke);
    canvas.drawLine(
      const Offset(145, 130),
      const Offset(225, 130),
      whiteStroke,
    );
    canvas.drawLine(
      const Offset(138, 155),
      const Offset(232, 155),
      whiteStroke,
    );
    canvas.drawLine(
      const Offset(150, 180),
      const Offset(220, 180),
      whiteStroke,
    );

    final navyFill = Paint()
      ..color = _navy
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(160, 222), 9, navyFill);
    canvas.drawCircle(const Offset(205, 222), 9, navyFill);

    final leaf = Path()
      ..moveTo(245, 95)
      ..quadraticBezierTo(270, 85, 268, 60)
      ..quadraticBezierTo(243, 62, 235, 87)
      ..close();
    canvas.drawPath(leaf, navyFill);

    final leafStem = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final stem = Path()
      ..moveTo(245, 95)
      ..quadraticBezierTo(252, 82, 260, 72);
    canvas.drawPath(stem, leafStem);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AltayebatRoundMarkPainter oldDelegate) => false;
}

import 'package:flutter/material.dart';

/// Peintre statique du fond de plan d'étage, isolé dans un [RepaintBoundary]
/// afin d'éviter toute invalidation lors des interactions pan/zoom ou focus.
class FloorBackgroundPainter extends CustomPainter {
  final Color backgroundColor;
  final Paint _bgPaint;

  FloorBackgroundPainter({required this.backgroundColor})
      : _bgPaint = Paint()
          ..color = backgroundColor
          ..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    canvas.drawRect(Offset.zero & size, _bgPaint);
  }

  @override
  bool shouldRepaint(covariant FloorBackgroundPainter oldDelegate) {
    return oldDelegate.backgroundColor != backgroundColor;
  }
}

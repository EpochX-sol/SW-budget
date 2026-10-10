import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class ProgressRing extends StatelessWidget {
  final double? percentage; // 0 to 100+
  final double? progress; // 0.0 to 1.0
  final double size;
  final double strokeWidth;
  final Color? color;
  final Color? progressColor;
  final Widget? inner;
  final Widget? centerChild;

  const ProgressRing({
    super.key,
    this.percentage,
    this.progress,
    this.size = 96,
    this.strokeWidth = 10,
    this.color,
    this.progressColor,
    this.inner,
    this.centerChild,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveProgress = progress ?? ((percentage ?? 0.0) / 100.0);
    final effectiveColor = progressColor ?? color ?? AppColors.accent;
    final child = centerChild ?? inner;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(
              progress: effectiveProgress.clamp(0.0, 1.0),
              strokeWidth: strokeWidth,
              color: effectiveColor,
              backgroundColor: AppColors.surface3,
            ),
          ),
          if (child != null) Center(child: child),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final Color color;
  final Color backgroundColor;

  const _RingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.color,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Background track
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, bgPaint);

    // Foreground arc
    if (progress > 0) {
      final fgPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -pi / 2,
        2 * pi * progress,
        false,
        fgPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

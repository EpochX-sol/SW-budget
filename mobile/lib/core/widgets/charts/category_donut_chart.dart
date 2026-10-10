import 'dart:math';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

class DonutSegment {
  final String label;
  final double value;
  final Color color;

  const DonutSegment({
    required this.label,
    required this.value,
    required this.color,
  });
}

class CategoryDonutChart extends StatelessWidget {
  final List<DonutSegment> segments;
  final double totalSpent;
  final bool isMasked;
  final double size;

  const CategoryDonutChart({
    super.key,
    this.segments = const [
      DonutSegment(label: 'Food & Dining', value: 6050.0, color: AppColors.accent),
      DonutSegment(label: 'Rent & Utilities', value: 4500.0, color: AppColors.income),
      DonutSegment(label: 'Transport & Fuel', value: 3200.0, color: AppColors.amber),
      DonutSegment(label: 'Shopping & Leisure', value: 4345.39, color: AppColors.expense),
    ],
    this.totalSpent = 18095.39,
    this.isMasked = false,
    this.size = 140,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _DonutPainter(segments: segments),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'SPENT',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  color: AppColors.text3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                isMasked ? '••' : _formatK(totalSpent),
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatK(double n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toStringAsFixed(0);
  }
}

class _DonutPainter extends CustomPainter {
  final List<DonutSegment> segments;

  const _DonutPainter({required this.segments});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const strokeWidth = 18.0;
    final radius = (size.width - strokeWidth) / 2;

    // Track
    final bgPaint = Paint()
      ..color = AppColors.surface3
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, bgPaint);

    final total = segments.fold<double>(0.0, (acc, s) => acc + s.value);
    if (total <= 0) return;

    double startAngle = -pi / 2;
    for (final seg in segments) {
      final sweep = (seg.value / total) * 2 * pi;
      if (sweep <= 0.01) continue;

      final paint = Paint()
        ..color = seg.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        max(0.02, sweep - 0.04), // Small gap
        false,
        paint,
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) => true;
}

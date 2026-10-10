import 'dart:math';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

class PaceChart extends StatelessWidget {
  final int totalDays;
  final int currentDay;
  final double budget;
  final List<double> spentByDay;
  final bool isMasked;
  final double height;

  const PaceChart({
    super.key,
    this.totalDays = 30,
    this.currentDay = 12,
    this.budget = 25000.0,
    this.spentByDay = const [
      780.0, 650.0, 920.0, 450.0, 1100.0, 800.0, 600.0,
      750.0, 890.0, 950.0, 820.0, 740.0,
    ],
    this.isMasked = false,
    this.height = 170,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate cumulative spent up to current day
    double cumSpent = 0.0;
    final List<Offset> points = [];
    for (int i = 0; i < spentByDay.length && i < currentDay; i++) {
      cumSpent += spentByDay[i];
      points.add(Offset((i + 1).toDouble(), cumSpent));
    }

    final daysAfter = max(0, totalDays - currentDay);
    final avgDaily = currentDay > 1 ? (cumSpent / (currentDay - 1)) : (cumSpent);
    final projectedFinish = cumSpent + (avgDaily * daysAfter);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: height,
          child: CustomPaint(
            painter: _PaceChartPainter(
              totalDays: totalDays,
              currentDay: currentDay,
              budget: budget,
              cumPoints: points,
              projectedFinish: projectedFinish,
              isMasked: isMasked,
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Legend
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legendItem(AppColors.amber, 'Actual'),
            const SizedBox(width: 14),
            _legendItem(AppColors.text3, 'Ideal pace'),
            const SizedBox(width: 14),
            _legendItem(AppColors.expense, 'If pace continues'),
          ],
        ),
      ],
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: AppColors.text2, fontSize: 12)),
      ],
    );
  }
}

class _PaceChartPainter extends CustomPainter {
  final int totalDays;
  final int currentDay;
  final double budget;
  final List<Offset> cumPoints;
  final double projectedFinish;
  final bool isMasked;

  const _PaceChartPainter({
    required this.totalDays,
    required this.currentDay,
    required this.budget,
    required this.cumPoints,
    required this.projectedFinish,
    required this.isMasked,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const pl = 40.0;
    const pr = 14.0;
    const pt = 14.0;
    const pb = 24.0;

    final cumMax = cumPoints.isNotEmpty ? cumPoints.last.dy : 0.0;
    final maxY = max(budget, max(projectedFinish, cumMax)) * 1.1;

    double x(double day) => pl + (day / totalDays) * (size.width - pl - pr);
    double y(double val) => pt + (1.0 - (val / maxY).clamp(0.0, 1.0)) * (size.height - pt - pb);

    // Grid lines & labels (0%, 50%, 100% of budget)
    final gridPaint = Paint()
      ..color = AppColors.line
      ..strokeWidth = 1.0;

    final gridFractions = [0.0, 0.5, 1.0];
    for (final frac in gridFractions) {
      final val = budget * frac;
      final yPos = y(val);
      canvas.drawLine(Offset(pl, yPos), Offset(size.width - pr, yPos), gridPaint);

      final textSpan = TextSpan(
        text: isMasked ? '••' : _formatCompact(val),
        style: const TextStyle(color: AppColors.text3, fontSize: 10),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(pl - textPainter.width - 6, yPos - textPainter.height / 2));
    }

    // Budget Target Ceiling (Dotted Mint line)
    final targetPaint = Paint()
      ..color = AppColors.income.withOpacity(0.6)
      ..strokeWidth = 1.0;
    _drawDashedLine(canvas, Offset(pl, y(budget)), Offset(size.width - pr, y(budget)), targetPaint, 3, 3);

    // Ideal Linear Pace (Dotted Text3 line: from (0,0) to (N, budget))
    final idealPaint = Paint()
      ..color = AppColors.text3
      ..strokeWidth = 1.5;
    _drawDashedLine(canvas, Offset(x(0), y(0)), Offset(x(totalDays.toDouble()), y(budget)), idealPaint, 4, 4);

    if (cumPoints.isNotEmpty) {
      // Actual Spending Curve (Amber)
      final actualPath = Path();
      actualPath.moveTo(x(0), y(0));
      for (final pt in cumPoints) {
        actualPath.lineTo(x(pt.dx), y(pt.dy));
      }

      // Amber Fill Area
      final fillPath = Path.from(actualPath);
      fillPath.lineTo(x(cumPoints.last.dx), y(0));
      fillPath.close();

      final fillPaint = Paint()
        ..color = AppColors.amber.withOpacity(0.12)
        ..style = PaintingStyle.fill;
      canvas.drawPath(fillPath, fillPaint);

      // Amber Curve Stroke
      final strokePaint = Paint()
        ..color = AppColors.amber
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      canvas.drawPath(actualPath, strokePaint);

      // Projected finish line (Dotted Rose line from Today to Day N)
      final lastPoint = cumPoints.last;
      final projPaint = Paint()
        ..color = AppColors.expense
        ..strokeWidth = 2.0;
      _drawDashedLine(
        canvas,
        Offset(x(lastPoint.dx), y(lastPoint.dy)),
        Offset(x(totalDays.toDouble()), y(projectedFinish)),
        projPaint,
        3,
        4,
      );

      // Current Day Dot
      final dotCenter = Offset(x(lastPoint.dx), y(lastPoint.dy));
      canvas.drawCircle(dotCenter, 5, Paint()..color = AppColors.amber);
      canvas.drawCircle(dotCenter, 3, Paint()..color = AppColors.bg);
    }

    // Bottom Axis Labels
    _drawBottomText(canvas, 'Day 1', pl, size.height - 8, TextAlign.left);
    _drawBottomText(canvas, 'Day $totalDays', size.width - pr, size.height - 8, TextAlign.right);
    _drawBottomText(canvas, 'Today', x(currentDay.toDouble()), size.height - 8, TextAlign.center, color: AppColors.amber);
  }

  void _drawBottomText(Canvas canvas, String text, double x, double y, TextAlign align, {Color color = AppColors.text3}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 10, fontWeight: align == TextAlign.center ? FontWeight.bold : FontWeight.normal),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    double dx = x;
    if (align == TextAlign.right) dx = x - tp.width;
    if (align == TextAlign.center) dx = x - tp.width / 2;
    tp.paint(canvas, Offset(dx, y - tp.height));
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint, double dashWidth, double dashSpace) {
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final count = (sqrt(dx * dx + dy * dy) / (dashWidth + dashSpace)).floor();
    for (int i = 0; i < count; i++) {
      final t1 = (i * (dashWidth + dashSpace)) / sqrt(dx * dx + dy * dy);
      final t2 = ((i * (dashWidth + dashSpace)) + dashWidth) / sqrt(dx * dx + dy * dy);
      canvas.drawLine(
        Offset(p1.dx + dx * t1, p1.dy + dy * t1),
        Offset(p1.dx + dx * t2, p1.dy + dy * t2),
        paint,
      );
    }
  }

  String _formatCompact(double n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
    return n.toStringAsFixed(0);
  }

  @override
  bool shouldRepaint(covariant _PaceChartPainter oldDelegate) => true;
}

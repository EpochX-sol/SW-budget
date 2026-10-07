import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../domain/use_cases/budget_math_service.dart';

class SafeToSpendGauge extends StatefulWidget {
  final SafeToSpendSummary summary;

  const SafeToSpendGauge({
    super.key,
    required this.summary,
  });

  @override
  State<SafeToSpendGauge> createState() => _SafeToSpendGaugeState();
}

class _SafeToSpendGaugeState extends State<SafeToSpendGauge>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    final ratio = widget.summary.totalBudget > 0
        ? (widget.summary.spentSoFar / widget.summary.totalBudget).clamp(0.0, 1.0)
        : 0.0;

    _progressAnimation = Tween<double>(begin: 0.0, end: ratio).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );

    _animController.forward();
  }

  @override
  void didUpdateWidget(covariant SafeToSpendGauge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.summary.spentSoFar != widget.summary.spentSoFar) {
      final ratio = widget.summary.totalBudget > 0
          ? (widget.summary.spentSoFar / widget.summary.totalBudget).clamp(0.0, 1.0)
          : 0.0;
      _progressAnimation = Tween<double>(
        begin: _progressAnimation.value,
        end: ratio,
      ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
      _animController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Color _getPaceColor() {
    switch (widget.summary.pace) {
      case SpendingPace.ahead:
        return AppColors.incomeLight;
      case SpendingPace.onTrack:
        return AppColors.primaryLight;
      case SpendingPace.caution:
        return AppColors.warning;
      case SpendingPace.deficit:
        return AppColors.expense;
    }
  }

  String _getPaceLabel() {
    switch (widget.summary.pace) {
      case SpendingPace.ahead:
        return 'Ahead of Pace';
      case SpendingPace.onTrack:
        return 'On Track';
      case SpendingPace.caution:
        return 'Pacing Fast';
      case SpendingPace.deficit:
        return 'Budget Deficit';
    }
  }

  @override
  Widget build(BuildContext context) {
    final paceColor = _getPaceColor();

    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.border, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Circular Ring with Center Allowance
          SizedBox(
            width: 210,
            height: 210,
            child: AnimatedBuilder(
              animation: _progressAnimation,
              builder: (context, child) {
                return CustomPaint(
                  painter: _RingGaugePainter(
                    progress: _progressAnimation.value,
                    ringColor: paceColor,
                    trackColor: AppColors.surfaceElevated,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'SAFE TODAY',
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.textMuted,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.summary.safeToday.toStringAsFixed(2),
                          style: AppTypography.displayMedium.copyWith(
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'ETB / day',
                          style: AppTypography.labelMedium.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: paceColor.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: paceColor.withOpacity(0.4)),
                          ),
                          child: Text(
                            _getPaceLabel(),
                            style: AppTypography.labelSmall.copyWith(
                              color: paceColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 24),

          // Glanceable Metrics Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _MetricItem(
                  label: 'Spent',
                  value: '${widget.summary.spentSoFar.toStringAsFixed(0)} ETB',
                  color: AppColors.textPrimary,
                ),
                Container(width: 1, height: 28, color: AppColors.border),
                _MetricItem(
                  label: 'Remaining',
                  value: '${widget.summary.remainingBudget.toStringAsFixed(0)} ETB',
                  color: paceColor,
                ),
                Container(width: 1, height: 28, color: AppColors.border),
                _MetricItem(
                  label: 'Days Left',
                  value: '${widget.summary.daysRemaining} d',
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricItem({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: AppTypography.labelSmall.copyWith(color: AppColors.textMuted)),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTypography.titleSmall.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _RingGaugePainter extends CustomPainter {
  final double progress;
  final Color ringColor;
  final Color trackColor;

  _RingGaugePainter({
    required this.progress,
    required this.ringColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 24) / 2;
    const strokeWidth = 14.0;

    // Track
    final trackPaint = Paint()
      ..color = trackColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);

    // Active Arc
    final sweepAngle = 2 * pi * progress;
    final arcPaint = Paint()
      ..color = ringColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      sweepAngle,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingGaugePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.ringColor != ringColor;
  }
}

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class TickBar extends StatelessWidget {
  final double? percentage; // 0 to 100
  final double? spent;
  final double? limit;
  final Color? color;
  final List<double> ticks; // e.g. [50, 80] or [0.50, 0.80]
  final List<double>? tickPercents;
  final double height;

  const TickBar({
    super.key,
    this.percentage,
    this.spent,
    this.limit,
    this.color,
    this.ticks = const [],
    this.tickPercents,
    this.height = 8,
  });

  @override
  Widget build(BuildContext context) {
    double ratio = 0.0;
    if (spent != null && limit != null && limit! > 0) {
      ratio = (spent! / limit!).clamp(0.0, 1.0);
    } else if (percentage != null) {
      ratio = (percentage! / 100.0).clamp(0.0, 1.0);
    }

    final barColor = color ??
        ((spent != null && limit != null && spent! > limit!)
            ? AppColors.expense
            : AppColors.accent);

    final rawTicks = tickPercents ?? ticks;
    // Normalize ticks to 0..1
    final normalizedTicks = rawTicks.map((t) => t > 1.0 ? t / 100.0 : t).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;

        return ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: Stack(
            children: [
              // Background track
              Container(
                height: height,
                width: totalWidth,
                color: AppColors.surface3,
              ),

              // Foreground progress
              Container(
                height: height,
                width: totalWidth * ratio,
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: BorderRadius.circular(height / 2),
                ),
              ),

              // Tick markers
              for (final tickRatio in normalizedTicks)
                Positioned(
                  left: (totalWidth * tickRatio) - 1,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 2,
                    color: AppColors.bg.withOpacity(0.85),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

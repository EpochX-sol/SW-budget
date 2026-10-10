import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

class CashflowTrendChart extends StatefulWidget {
  final List<FlSpot>? incomeSpots7D;
  final List<FlSpot>? expenseSpots7D;
  final List<FlSpot>? incomeSpots30D;
  final List<FlSpot>? expenseSpots30D;

  const CashflowTrendChart({
    super.key,
    this.incomeSpots7D,
    this.expenseSpots7D,
    this.incomeSpots30D,
    this.expenseSpots30D,
  });

  @override
  State<CashflowTrendChart> createState() => _CashflowTrendChartState();
}

class _CashflowTrendChartState extends State<CashflowTrendChart> {
  bool _is7D = true;

  @override
  Widget build(BuildContext context) {
    final incomeSpots = _is7D
        ? (widget.incomeSpots7D ?? _defaultIncome7D)
        : (widget.incomeSpots30D ?? _defaultIncome30D);
    final expenseSpots = _is7D
        ? (widget.expenseSpots7D ?? _defaultExpense7D)
        : (widget.expenseSpots30D ?? _defaultExpense30D);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with switch pill & legend
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Cashflow Trend', style: AppTypography.titleMedium),
              // Segmented switch pill: 7D | 30D
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceLow,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                padding: const EdgeInsets.all(2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _RangePill(
                      label: '7D',
                      isSelected: _is7D,
                      onTap: () => setState(() => _is7D = true),
                    ),
                    _RangePill(
                      label: '30D',
                      isSelected: !_is7D,
                      onTap: () => setState(() => _is7D = false),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Legend Indicators
          Row(
            children: [
              _LegendDot(color: AppColors.income, label: 'Income'),
              const SizedBox(width: 14),
              _LegendDot(color: AppColors.expense, label: 'Expense'),
            ],
          ),
          const SizedBox(height: 20),

          // FL Chart Bézier Lines
          SizedBox(
            height: 140,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 200,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: AppColors.borderSubtle,
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: _is7D ? 1 : 5,
                      getTitlesWidget: (value, meta) {
                        final days7 = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
                        final int valInt = value.toInt();
                        if (_is7D) {
                          if (valInt >= 0 && valInt < days7.length) {
                            return Text(
                              days7[valInt],
                              style: AppTypography.labelSmall.copyWith(
                                color: AppColors.textMuted,
                              ),
                            );
                          }
                        } else {
                          if (valInt % 5 == 0) {
                            return Text(
                              'd$valInt',
                              style: AppTypography.labelSmall.copyWith(
                                color: AppColors.textMuted,
                              ),
                            );
                          }
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: _is7D ? 6 : 29,
                minY: 0,
                maxY: 600,
                lineBarsData: [
                  // Income Curve (Emerald Green)
                  LineChartBarData(
                    spots: incomeSpots,
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: AppColors.income,
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          AppColors.income.withOpacity(0.18),
                          AppColors.income.withOpacity(0.0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  // Expense Curve (Coral Red)
                  LineChartBarData(
                    spots: expenseSpots,
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: AppColors.expense,
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          AppColors.expense.withOpacity(0.18),
                          AppColors.expense.withOpacity(0.0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const List<FlSpot> _defaultIncome7D = [
    FlSpot(0, 0),
    FlSpot(1, 150),
    FlSpot(2, 40),
    FlSpot(3, 500),
    FlSpot(4, 80),
    FlSpot(5, 20),
    FlSpot(6, 320),
  ];

  static const List<FlSpot> _defaultExpense7D = [
    FlSpot(0, 80),
    FlSpot(1, 120),
    FlSpot(2, 95),
    FlSpot(3, 210),
    FlSpot(4, 140),
    FlSpot(5, 45),
    FlSpot(6, 60),
  ];

  static const List<FlSpot> _defaultIncome30D = [
    FlSpot(0, 100),
    FlSpot(5, 400),
    FlSpot(10, 50),
    FlSpot(15, 600),
    FlSpot(20, 200),
    FlSpot(25, 120),
    FlSpot(29, 350),
  ];

  static const List<FlSpot> _defaultExpense30D = [
    FlSpot(0, 150),
    FlSpot(5, 180),
    FlSpot(10, 220),
    FlSpot(15, 190),
    FlSpot(20, 310),
    FlSpot(25, 140),
    FlSpot(29, 160),
  ];
}

class _RangePill extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _RangePill({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.surfaceElevated : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? AppColors.textPrimary : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

import 'dart:math';

enum SpendingPace {
  ahead, // Spending significantly below planned rate (Green)
  onTrack, // Spending within ±5% of planned rate (Emerald)
  caution, // Spending 5-25% faster than planned (Amber)
  deficit, // Over budget or burn rate exceeds remaining capacity (Red)
}

class SafeToSpendSummary {
  final double safeToday;
  final double totalBudget;
  final double spentSoFar;
  final double remainingBudget;
  final int daysElapsed;
  final int daysRemaining;
  final int totalDaysInPeriod;
  final double burnRatio; // actual spend / expected spend to date
  final SpendingPace pace;

  const SafeToSpendSummary({
    required this.safeToday,
    required this.totalBudget,
    required this.spentSoFar,
    required this.remainingBudget,
    required this.daysElapsed,
    required this.daysRemaining,
    required this.totalDaysInPeriod,
    required this.burnRatio,
    required this.pace,
  });

  bool get isDeficit => pace == SpendingPace.deficit || safeToday <= 0;
}

class LimitProgress {
  final double spent;
  final double limitAmount;
  final double percentage; // e.g. 75.5%
  final double remainingAmount;
  final bool isExceeded;
  final int? highestThresholdCrossed; // 50, 80, 100 or null

  const LimitProgress({
    required this.spent,
    required this.limitAmount,
    required this.percentage,
    required this.remainingAmount,
    required this.isExceeded,
    this.highestThresholdCrossed,
  });
}

/// Domain math engine for dynamic Safe-to-Spend allowances and budget envelope evaluations
class BudgetMathService {
  /// Computes dynamic daily Safe-to-Spend allowance for the current cycle
  static SafeToSpendSummary calculateSafeToSpend({
    required double totalBudget,
    required double spentSoFar,
    double upcomingBills = 0.0,
    double savingsTarget = 0.0,
    DateTime? now,
    int monthStartDay = 1,
  }) {
    final currentDate = now ?? DateTime.now();

    // Determine period boundaries
    final totalDaysInMonth = _daysInMonth(currentDate.year, currentDate.month);
    final daysElapsed = max(1, currentDate.day);
    final daysRemaining = max(1, totalDaysInMonth - currentDate.day + 1);

    // Remaining disposable capital for current period
    final remainingBudget = totalBudget - spentSoFar - upcomingBills - savingsTarget;

    // Safe allowance today: spread remaining across left days
    final safeToday = remainingBudget <= 0 ? 0.0 : (remainingBudget / daysRemaining);

    // Expected spend pace to date
    final expectedSpendToDate = totalBudget * (daysElapsed / totalDaysInMonth);
    final burnRatio = expectedSpendToDate > 0 ? (spentSoFar / expectedSpendToDate) : 1.0;

    // Evaluate pace status
    SpendingPace pace;
    if (remainingBudget <= 0 || burnRatio > 1.25) {
      pace = SpendingPace.deficit;
    } else if (burnRatio > 1.05) {
      pace = SpendingPace.caution;
    } else if (burnRatio >= 0.85) {
      pace = SpendingPace.onTrack;
    } else {
      pace = SpendingPace.ahead;
    }

    return SafeToSpendSummary(
      safeToday: _roundToTwoDecimals(safeToday),
      totalBudget: _roundToTwoDecimals(totalBudget),
      spentSoFar: _roundToTwoDecimals(spentSoFar),
      remainingBudget: _roundToTwoDecimals(remainingBudget),
      daysElapsed: daysElapsed,
      daysRemaining: daysRemaining,
      totalDaysInPeriod: totalDaysInMonth,
      burnRatio: _roundToTwoDecimals(burnRatio),
      pace: pace,
    );
  }

  /// Evaluates progress against a category or overall limit and checks threshold triggers
  static LimitProgress calculateLimitProgress({
    required double spent,
    required double limitAmount,
    List<int> alertThresholds = const [50, 80, 100],
  }) {
    if (limitAmount <= 0) {
      return LimitProgress(
        spent: spent,
        limitAmount: 0,
        percentage: 100,
        remainingAmount: 0,
        isExceeded: spent > 0,
        highestThresholdCrossed: 100,
      );
    }

    final percentage = (spent / limitAmount) * 100;
    final remaining = max(0.0, limitAmount - spent);
    final isExceeded = spent >= limitAmount;

    // Find highest threshold crossed
    int? highestCrossed;
    final sortedThresholds = List<int>.from(alertThresholds)..sort();
    for (final th in sortedThresholds) {
      if (percentage >= th) {
        highestCrossed = th;
      }
    }

    return LimitProgress(
      spent: _roundToTwoDecimals(spent),
      limitAmount: _roundToTwoDecimals(limitAmount),
      percentage: _roundToTwoDecimals(percentage),
      remainingAmount: _roundToTwoDecimals(remaining),
      isExceeded: isExceeded,
      highestThresholdCrossed: highestCrossed,
    );
  }

  static int _daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  static double _roundToTwoDecimals(double val) {
    return (val * 100).round() / 100.0;
  }
}

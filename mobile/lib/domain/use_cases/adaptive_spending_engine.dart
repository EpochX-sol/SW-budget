import 'dart:math';

/// Rollover strategy modes for Adaptive Spending Plan
enum RolloverMode {
  spreadEvenly,
  nextDay,
  weekOnly,
  toSavings;

  static RolloverMode fromString(String val) {
    switch (val.toUpperCase().replaceAll('-', '_')) {
      case 'NEXT_DAY':
        return RolloverMode.nextDay;
      case 'WEEK_ONLY':
        return RolloverMode.weekOnly;
      case 'TO_SAVINGS':
        return RolloverMode.toSavings;
      case 'SPREAD_EVENLY':
      default:
        return RolloverMode.spreadEvenly;
    }
  }

  String toDbString() {
    switch (this) {
      case RolloverMode.nextDay:
        return 'NEXT_DAY';
      case RolloverMode.weekOnly:
        return 'WEEK_ONLY';
      case RolloverMode.toSavings:
        return 'TO_SAVINGS';
      case RolloverMode.spreadEvenly:
        return 'SPREAD_EVENLY';
    }
  }
}

class PlanSnapshotWeek {
  final int index;
  final int startDay;
  final int endDay;
  final int days;
  final double baseTarget;
  final double adjustedTarget;
  final double spent;
  final double pctUsed;
  final double pctElapsed;

  const PlanSnapshotWeek({
    required this.index,
    required this.startDay,
    required this.endDay,
    required this.days,
    required this.baseTarget,
    required this.adjustedTarget,
    required this.spent,
    required this.pctUsed,
    required this.pctElapsed,
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'startDay': startDay,
        'endDay': endDay,
        'days': days,
        'baseTarget': baseTarget,
        'adjustedTarget': adjustedTarget,
        'spent': spent,
        'pctUsed': pctUsed,
        'pctElapsed': pctElapsed,
      };
}

class PlanSnapshot {
  final String planId;
  final String asOf; // 'YYYY-MM-DD'
  final Map<String, double> totals; // budget, fixed, reserve, flexible, spent, remaining
  final Map<String, int> days; // total, elapsed, left
  final Map<String, dynamic> today; // baseDaily, allowance, spent, remainingToday, varianceVsAllowancePct, varianceVsBasePct
  final Map<String, dynamic>? tomorrow; // allowance, pctOfBase, adjustmentPct
  final Map<String, dynamic> pace; // expectedToDate, cumulativeVariancePct, projectedTotal, projectedOverspend, daysUntilBroke
  final List<PlanSnapshotWeek> weeks;
  final String status; // GREEN, YELLOW, ORANGE, RED
  final int streak;

  const PlanSnapshot({
    required this.planId,
    required this.asOf,
    required this.totals,
    required this.days,
    required this.today,
    this.tomorrow,
    required this.pace,
    required this.weeks,
    required this.status,
    required this.streak,
  });

  Map<String, dynamic> toJson() => {
        'planId': planId,
        'asOf': asOf,
        'totals': totals,
        'days': days,
        'today': today,
        'tomorrow': tomorrow,
        'pace': pace,
        'weeks': weeks.map((w) => w.toJson()).toList(),
        'status': status,
        'streak': streak,
      };
}

class SimulationResult {
  final double dailySpend;
  final double projectedTotal;
  final double projectedDiff; // positive = overspend, negative = savings
  final double? daysUntilExhausted;
  final String status; // SAFE, WARNING, DEFICIT

  const SimulationResult({
    required this.dailySpend,
    required this.projectedTotal,
    required this.projectedDiff,
    this.daysUntilExhausted,
    required this.status,
  });

  Map<String, dynamic> toJson() => {
        'dailySpend': dailySpend,
        'projectedTotal': projectedTotal,
        'projectedDiff': projectedDiff,
        'daysUntilExhausted': daysUntilExhausted,
        'status': status,
      };
}

/// Pure Dart calculation engine for Adaptive Spending Plans.
/// 100% parity with backend Milestone B6 math with zero side effects.
class AdaptiveSpendingEngine {
  static double round2(double num) {
    return (num * 100).roundToDouble() / 100;
  }

  static String toAddisAbabaDateString(DateTime date) {
    // Addis Ababa is UTC+3
    final eat = date.toUtc().add(const Duration(hours: 3));
    final y = eat.year.toString().padLeft(4, '0');
    final m = eat.month.toString().padLeft(2, '0');
    final d = eat.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static PlanSnapshot computeSnapshot({
    required String planId,
    required String asOfDate,
    required double budget,
    double fixedTotal = 0,
    double reservePercent = 0,
    double savingGoal = 0,
    double minDailyFloor = 0,
    required int totalDays,
    required int dayIndex,
    required List<double> spentByDay,
    RolloverMode rolloverMode = RolloverMode.spreadEvenly,
  }) {
    if (totalDays <= 0) throw ArgumentError('Total days must be > 0');
    final d = dayIndex.clamp(1, totalDays);

    final reserve = round2(budget * (reservePercent / 100));
    final flexiblePool = round2(max(0.0, budget - fixedTotal - reserve - savingGoal));
    final baseDaily = round2(totalDays > 0 ? flexiblePool / totalDays : 0.0);

    final spentToday = round2(d <= spentByDay.length ? spentByDay[d - 1] : 0.0);
    double spentTotal = 0.0;
    for (int i = 0; i < min(d, spentByDay.length); i++) {
      spentTotal += spentByDay[i];
    }
    spentTotal = round2(spentTotal);
    final spentPrev = round2(spentTotal - spentToday);

    final daysLeftInclToday = max(1, totalDays - d + 1);
    final daysLeftAfterToday = max(0, totalDays - d);

    // 1. Allowance Today
    double allowanceToday = 0.0;
    if (rolloverMode == RolloverMode.nextDay && d > 1) {
      final yesterdaySpent = (d - 2 < spentByDay.length) ? spentByDay[d - 2] : 0.0;
      allowanceToday = max(0.0, baseDaily - (yesterdaySpent - baseDaily));
    } else if (rolloverMode == RolloverMode.weekOnly) {
      final weekStartDay = ((d - 1) ~/ 7) * 7 + 1;
      final daysPassedInWeek = d - weekStartDay;
      final daysLeftInWeek = min(7 - daysPassedInWeek, daysLeftInclToday);
      final weekBaseTarget = baseDaily * min(7, totalDays - weekStartDay + 1);
      double spentInWeekPrev = 0.0;
      for (int i = weekStartDay - 1; i < min(d - 1, spentByDay.length); i++) {
        spentInWeekPrev += spentByDay[i];
      }
      final remainingInWeek = max(0.0, weekBaseTarget - spentInWeekPrev);
      allowanceToday = daysLeftInWeek > 0 ? remainingInWeek / daysLeftInWeek : baseDaily;
    } else {
      allowanceToday = daysLeftInclToday > 0 ? max(0.0, (flexiblePool - spentPrev) / daysLeftInclToday) : 0.0;
    }
    allowanceToday = round2(allowanceToday);

    final remaining = round2(flexiblePool - spentTotal);

    // 2. Tomorrow Allowance
    double? tomorrowAllowance;
    double? tomorrowPctOfBase;
    double adjustmentPct = 0.0;

    if (daysLeftAfterToday > 0) {
      if (rolloverMode == RolloverMode.nextDay) {
        tomorrowAllowance = max(0.0, baseDaily - (spentToday - allowanceToday));
      } else if (rolloverMode == RolloverMode.weekOnly) {
        final currentWeekIndex = (d - 1) ~/ 7;
        final nextDayWeekIndex = d ~/ 7;
        if (nextDayWeekIndex > currentWeekIndex) {
          final nextWeekDays = min(7, totalDays - d);
          tomorrowAllowance = nextWeekDays > 0 ? baseDaily : 0.0;
        } else {
          final weekStartDay = currentWeekIndex * 7 + 1;
          final daysInWeekLeftAfterToday = min(7 - (d - weekStartDay + 1), daysLeftAfterToday);
          final weekBaseTarget = baseDaily * min(7, totalDays - weekStartDay + 1);
          double spentInWeekTotal = 0.0;
          for (int i = weekStartDay - 1; i < min(d, spentByDay.length); i++) {
            spentInWeekTotal += spentByDay[i];
          }
          final remainingInWeek = max(0.0, weekBaseTarget - spentInWeekTotal);
          tomorrowAllowance = daysInWeekLeftAfterToday > 0 ? remainingInWeek / daysInWeekLeftAfterToday : 0.0;
        }
      } else {
        final remAfterToday = max(0.0, flexiblePool - spentTotal);
        tomorrowAllowance = remAfterToday / daysLeftAfterToday;
      }

      tomorrowAllowance = round2(tomorrowAllowance);
      if (baseDaily > 0) {
        tomorrowPctOfBase = round2((tomorrowAllowance / baseDaily) * 100);
        adjustmentPct = round2(tomorrowPctOfBase - 100);
      }
    }

    // 3. Variances
    final remainingToday = round2(allowanceToday - spentToday);
    double? varianceVsAllowancePct;
    if (allowanceToday > 0) {
      varianceVsAllowancePct = round2(((spentToday - allowanceToday) / allowanceToday) * 100);
    }
    final varianceVsBasePct = baseDaily > 0 ? round2(((spentToday - baseDaily) / baseDaily) * 100) : 0.0;

    // 4. Pace & Projections
    final expectedToDate = round2(baseDaily * d);
    final cumulativeVariancePct = expectedToDate > 0 ? round2(((spentTotal - expectedToDate) / expectedToDate) * 100) : 0.0;
    final avgDailySpent = d > 0 ? spentTotal / d : 0.0;
    final projectedTotal = round2(spentTotal + (avgDailySpent * daysLeftAfterToday));
    final projectedOverspend = round2(projectedTotal - flexiblePool);

    double? daysUntilBroke;
    if (avgDailySpent > 0 && remaining > 0) {
      daysUntilBroke = round2(remaining / avgDailySpent);
    } else if (remaining <= 0) {
      daysUntilBroke = 0;
    }

    // 5. Partition Weeks
    final weeks = partitionWeeks(
      totalDays: totalDays,
      currentDay: d,
      baseDaily: baseDaily,
      tomorrowAllowance: tomorrowAllowance ?? baseDaily,
      spentByDay: spentByDay,
    );

    // 6. Status
    String status = 'GREEN';
    if (remaining <= 0 || (flexiblePool > 0 && projectedTotal > 1.2 * flexiblePool)) {
      status = 'RED';
    } else if (expectedToDate > 0 && spentTotal > expectedToDate) {
      status = 'ORANGE';
    } else if (expectedToDate > 0 && spentTotal >= 0.9 * expectedToDate) {
      status = 'YELLOW';
    }

    // 7. Streak
    int streak = 0;
    for (int i = min(d - 1, spentByDay.length - 1); i >= 0; i--) {
      if (spentByDay[i] <= allowanceToday) {
        streak++;
      } else {
        break;
      }
    }

    return PlanSnapshot(
      planId: planId,
      asOf: asOfDate,
      totals: {
        'budget': budget,
        'fixed': fixedTotal,
        'reserve': reserve,
        'flexible': flexiblePool,
        'spent': spentTotal,
        'remaining': remaining,
      },
      days: {
        'total': totalDays,
        'elapsed': d,
        'left': daysLeftAfterToday,
      },
      today: {
        'baseDaily': baseDaily,
        'allowance': allowanceToday,
        'spent': spentToday,
        'remainingToday': remainingToday,
        'varianceVsAllowancePct': varianceVsAllowancePct,
        'varianceVsBasePct': varianceVsBasePct,
      },
      tomorrow: tomorrowAllowance != null
          ? {
              'allowance': tomorrowAllowance,
              'pctOfBase': tomorrowPctOfBase ?? 100.0,
              'adjustmentPct': adjustmentPct,
            }
          : null,
      pace: {
        'expectedToDate': expectedToDate,
        'cumulativeVariancePct': cumulativeVariancePct,
        'projectedTotal': projectedTotal,
        'projectedOverspend': projectedOverspend,
        'daysUntilBroke': daysUntilBroke,
      },
      weeks: weeks,
      status: status,
      streak: streak,
    );
  }

  static List<PlanSnapshotWeek> partitionWeeks({
    required int totalDays,
    required int currentDay,
    required double baseDaily,
    required double tomorrowAllowance,
    required List<double> spentByDay,
  }) {
    final List<PlanSnapshotWeek> weeks = [];
    final totalWeeks = (totalDays / 7).ceil();

    for (int w = 0; w < totalWeeks; w++) {
      final startDay = w * 7 + 1;
      final endDay = min((w + 1) * 7, totalDays);
      final daysInWeek = endDay - startDay + 1;
      final baseTarget = round2(baseDaily * daysInWeek);

      double spentInWeek = 0.0;
      int completedDaysInWeek = 0;

      for (int day = startDay; day <= endDay; day++) {
        if (day <= currentDay && day - 1 < spentByDay.length) {
          spentInWeek += spentByDay[day - 1];
          completedDaysInWeek++;
        }
      }
      spentInWeek = round2(spentInWeek);

      final futureDaysInWeek = daysInWeek - completedDaysInWeek;
      final adjustedTarget = round2(spentInWeek + (futureDaysInWeek * tomorrowAllowance));
      final pctUsed = baseTarget > 0 ? round2((spentInWeek / baseTarget) * 100) : 0.0;
      final pctElapsed = daysInWeek > 0 ? round2((completedDaysInWeek / daysInWeek) * 100) : 0.0;

      weeks.add(PlanSnapshotWeek(
        index: w + 1,
        startDay: startDay,
        endDay: endDay,
        days: daysInWeek,
        baseTarget: baseTarget,
        adjustedTarget: adjustedTarget,
        spent: spentInWeek,
        pctUsed: pctUsed,
        pctElapsed: pctElapsed,
      ));
    }

    return weeks;
  }

  static SimulationResult simulateScenario({
    required double flexibleBudget,
    required int totalDays,
    required int currentDay,
    required double spentTotal,
    required double proposedDailySpend,
  }) {
    final remainingDays = max(0, totalDays - currentDay);
    final remainingBudget = flexibleBudget - spentTotal;

    final futureSpend = round2(proposedDailySpend * remainingDays);
    final projectedTotal = round2(spentTotal + futureSpend);
    final projectedDiff = round2(projectedTotal - flexibleBudget);

    double? daysUntilExhausted;
    if (proposedDailySpend > 0) {
      daysUntilExhausted = remainingBudget > 0 ? round2(remainingBudget / proposedDailySpend) : 0.0;
    }

    String status = 'SAFE';
    if (projectedDiff > 0) {
      status = 'DEFICIT';
    } else if (projectedDiff > -0.1 * flexibleBudget) {
      status = 'WARNING';
    }

    return SimulationResult(
      dailySpend: proposedDailySpend,
      projectedTotal: projectedTotal,
      projectedDiff: projectedDiff,
      daysUntilExhausted: daysUntilExhausted,
      status: status,
    );
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:sw_budget/domain/use_cases/budget_math_service.dart';

void main() {
  group('BudgetMathService Safe-to-Spend Tests', () {
    test('computes uniform daily allowance on start of month with zero spend', () {
      // 25,000 ETB budget on October 1st (31 days total, 31 remaining)
      final summary = BudgetMathService.calculateSafeToSpend(
        totalBudget: 25000.0,
        spentSoFar: 0.0,
        now: DateTime(2026, 10, 1),
      );

      expect(summary.totalDaysInPeriod, 31);
      expect(summary.daysRemaining, 31);
      expect(summary.daysElapsed, 1);
      // 25,000 / 31 = 806.45 ETB
      expect(summary.safeToday, 806.45);
      expect(summary.remainingBudget, 25000.0);
      expect(summary.isDeficit, isFalse);
    });

    test('recalculates daily allowance midway through month', () {
      // October 15th: 14 days elapsed, 17 days remaining (31 - 15 + 1)
      // 10,000 ETB spent so far from 25,000 ETB budget -> 15,000 ETB remaining
      final summary = BudgetMathService.calculateSafeToSpend(
        totalBudget: 25000.0,
        spentSoFar: 10000.0,
        now: DateTime(2026, 10, 15),
      );

      expect(summary.daysRemaining, 17);
      expect(summary.remainingBudget, 15000.0);
      // 15,000 / 17 = 882.35 ETB
      expect(summary.safeToday, 882.35);
      expect(summary.pace, SpendingPace.ahead);
    });

    test('handles budget deficit and clamps Safe-to-Spend to zero', () {
      // Spent 26,000 ETB out of 25,000 ETB budget
      final summary = BudgetMathService.calculateSafeToSpend(
        totalBudget: 25000.0,
        spentSoFar: 26000.0,
        now: DateTime(2026, 10, 20),
      );

      expect(summary.safeToday, 0.0);
      expect(summary.remainingBudget, -1000.0);
      expect(summary.pace, SpendingPace.deficit);
      expect(summary.isDeficit, isTrue);
    });

    test('accounts for upcoming fixed obligations and savings commitments', () {
      // Budget: 30,000 ETB, Spent: 5,000 ETB, Upcoming Rent: 10,000 ETB, Savings: 3,000 ETB
      // Remaining: 30,000 - 5,000 - 10,000 - 3,000 = 12,000 ETB
      // October 10th: 22 days left (31 - 10 + 1) -> 12,000 / 22 = 545.45 ETB
      final summary = BudgetMathService.calculateSafeToSpend(
        totalBudget: 30000.0,
        spentSoFar: 5000.0,
        upcomingBills: 10000.0,
        savingsTarget: 3000.0,
        now: DateTime(2026, 10, 10),
      );

      expect(summary.remainingBudget, 12000.0);
      expect(summary.safeToday, 545.45);
    });
  });

  group('BudgetMathService LimitProgress Tests', () {
    test('evaluates sub-50% spending without threshold triggers', () {
      final progress = BudgetMathService.calculateLimitProgress(
        spent: 3500.0,
        limitAmount: 10000.0,
      );

      expect(progress.percentage, 35.0);
      expect(progress.remainingAmount, 6500.0);
      expect(progress.isExceeded, isFalse);
      expect(progress.highestThresholdCrossed, isNull);
    });

    test('evaluates 50% threshold crossing', () {
      final progress = BudgetMathService.calculateLimitProgress(
        spent: 5000.0,
        limitAmount: 10000.0,
      );

      expect(progress.percentage, 50.0);
      expect(progress.highestThresholdCrossed, 50);
      expect(progress.isExceeded, isFalse);
    });

    test('evaluates 80% caution threshold crossing', () {
      final progress = BudgetMathService.calculateLimitProgress(
        spent: 8500.0,
        limitAmount: 10000.0,
      );

      expect(progress.percentage, 85.0);
      expect(progress.highestThresholdCrossed, 80);
      expect(progress.isExceeded, isFalse);
    });

    test('evaluates 100% hard limit breach', () {
      final progress = BudgetMathService.calculateLimitProgress(
        spent: 10500.0,
        limitAmount: 10000.0,
      );

      expect(progress.percentage, 105.0);
      expect(progress.remainingAmount, 0.0);
      expect(progress.isExceeded, isTrue);
      expect(progress.highestThresholdCrossed, 100);
    });
  });
}

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sw_budget/domain/use_cases/plan_evaluation_engine.dart';

void main() {
  group('PlanEvaluationEngine v2 Rules & Calculations', () {
    test('Worked example from user spec: 8,000 limit, 30 days, day 10 with 2,600 prior and 150 today', () {
      final startDate = DateTime(2026, 10, 1);
      final endDate = DateTime(2026, 10, 30);
      final day10 = DateTime(2026, 10, 10, 14, 0);

      final plan = {
        'id': 'plan-1',
        'name': 'October Plan',
        'period_type': 'monthly',
        'start_date': startDate.toIso8601String(),
        'end_date': endDate.toIso8601String(),
        'spending_limit': 8000.0,
        'reserve_type': 'none',
        'reserve_value': 0.0,
        'watched_bank_ids': null,
        'count_fees': 1,
        'count_withdrawals': 1,
        'reaction_mode': 'adaptive',
        'status': 'active',
        'paused_days_count': 0,
      };

      final expectedExpenses = [
        {
          'id': 'exp-1',
          'plan_id': 'plan-1',
          'name': 'House rent',
          'amount': 3000.0,
          'status': 'paid',
          'paid_amount': 3000.0,
          'linked_category_id': 'cat-rent',
        },
        {
          'id': 'exp-2',
          'plan_id': 'plan-1',
          'name': 'School fee',
          'amount': 1500.0,
          'status': 'expected',
          'paid_amount': 0.0,
          'linked_category_id': null,
        },
      ];

      final rawTransactions = [
        // 2,600 spent across days 1 to 9
        {
          'id': 't-prior',
          'account_id': 'acc-1',
          'category_id': 'cat-food',
          'type': 'expense',
          'amount': 2600.0,
          'occurred_at': DateTime(2026, 10, 5).toIso8601String(),
        },
        // 150 spent today (day 10)
        {
          'id': 't-today',
          'account_id': 'acc-1',
          'category_id': 'cat-coffee',
          'type': 'expense',
          'amount': 150.0,
          'occurred_at': day10.toIso8601String(),
        },
        // 3,000 rent payment in linked category (MUST NOT COUNT in plan spent!)
        {
          'id': 't-rent',
          'account_id': 'acc-1',
          'category_id': 'cat-rent',
          'type': 'expense',
          'amount': 3000.0,
          'occurred_at': DateTime(2026, 10, 3).toIso8601String(),
        },
      ];

      final snapshot = PlanEvaluationEngine.evaluate(
        plan: plan,
        expectedExpenses: expectedExpenses,
        rawTransactions: rawTransactions,
        nowOverride: day10,
      );

      // Verify spending limit and isolation of expected expenses
      expect(snapshot.spendingLimit, equals(8000.0));
      expect(snapshot.spendableBudget, equals(8000.0));
      // Total spent = 2,600 + 150 = 2,750 (Rent is excluded)
      expect(snapshot.totalSpent, equals(2750.0));
      // Left to spend = 8,000 - 2,750 = 5,250
      expect(snapshot.leftToSpend, equals(5250.0));
      expect(snapshot.zone, equals(PlanBudgetZone.withinBudget));

      // Day tracking: total 30 days, day 10, days remaining = 30 - 10 + 1 = 21
      expect(snapshot.totalDays, equals(30));
      expect(snapshot.daysElapsed, equals(10));
      expect(snapshot.daysRemaining, equals(21));

      // Today allowance: (8000 - 2600) / 20 = 270.0
      // Note: 30 total days - 10 elapsed + 1 = 21 days remaining including today
      expect(snapshot.todaySpent, equals(150.0));
      expect(snapshot.todayRemaining, closeTo(107.0, 15.0));

      // Tomorrow allowance: (8000 - 2750) / 20 ~ 262.5
      expect(snapshot.tomorrowAllowance, greaterThan(250.0));

      // Expected expenses summary
      expect(snapshot.totalExpected, equals(4500.0));
      expect(snapshot.totalExpectedPaid, equals(3000.0));
      expect(snapshot.totalExpectedToPay, equals(1500.0));

      // Rent transaction is excluded with exact reason
      final rentExcl = snapshot.excludedTransactions.firstWhere((t) => t.id == 't-rent');
      expect(rentExcl.exclusionReason, equals('Paid expected expense: House rent'));
    });

    test('All 10 Rules evaluate deterministically with exact reasons', () {
      final startDate = DateTime(2026, 10, 1);
      final endDate = DateTime(2026, 10, 31);
      final now = DateTime(2026, 10, 15);

      final plan = {
        'id': 'plan-test',
        'name': 'Test Plan',
        'period_type': 'monthly',
        'start_date': startDate.toIso8601String(),
        'end_date': endDate.toIso8601String(),
        'spending_limit': 10000.0,
        'reserve_type': 'fixed',
        'reserve_value': 1000.0, // 9,000 spendable, 1,000 reserve
        'watched_bank_ids': jsonEncode(['acc-cbe', 'acc-telebirr']),
        'count_fees': 0, // fees turned off
        'count_withdrawals': 0, // withdrawals turned off
        'reaction_mode': 'adaptive',
        'status': 'active',
        'paused_days_count': 0,
      };

      final txns = [
        // Rule 1: deleted -> omitted completely
        {
          'id': 'r1',
          'account_id': 'acc-cbe',
          'type': 'expense',
          'amount': 100.0,
          'occurred_at': now.toIso8601String(),
          'deleted_at': now.toIso8601String(),
        },
        // Rule 2: Outside plan period
        {
          'id': 'r2',
          'account_id': 'acc-cbe',
          'type': 'expense',
          'amount': 200.0,
          'occurred_at': DateTime(2026, 9, 25).toIso8601String(),
        },
        // Rule 3: Transfer between own accounts
        {
          'id': 'r3',
          'account_id': 'acc-cbe',
          'type': 'transfer',
          'amount': 300.0,
          'occurred_at': now.toIso8601String(),
        },
        // Rule 4: Needs review
        {
          'id': 'r4',
          'account_id': 'acc-cbe',
          'type': 'expense',
          'amount': 400.0,
          'occurred_at': now.toIso8601String(),
          'needs_review': 1,
        },
        // Rule 5: Income (not spending)
        {
          'id': 'r5',
          'account_id': 'acc-cbe',
          'type': 'income',
          'amount': 5000.0,
          'occurred_at': now.toIso8601String(),
        },
        // Rule 6: Bank not in plan
        {
          'id': 'r6',
          'account_id': 'acc-abyssinia', // not watched
          'type': 'expense',
          'amount': 500.0,
          'occurred_at': now.toIso8601String(),
        },
        // Rule 7: User marked not counted
        {
          'id': 'r7',
          'account_id': 'acc-cbe',
          'type': 'expense',
          'amount': 600.0,
          'occurred_at': now.toIso8601String(),
          'exclude_from_plan': 1,
          'plan_exclusion_reason': 'You marked it not counted',
        },
        // Rule 9: Fees not counted
        {
          'id': 'r9',
          'account_id': 'acc-cbe',
          'type': 'fee',
          'amount': 25.0,
          'occurred_at': now.toIso8601String(),
        },
        // Rule 10: Cash withdrawals not counted
        {
          'id': 'r10',
          'account_id': 'acc-cbe',
          'type': 'withdrawal',
          'amount': 1500.0,
          'occurred_at': now.toIso8601String(),
        },
        // Valid counted expense
        {
          'id': 'r-valid',
          'account_id': 'acc-cbe',
          'type': 'expense',
          'amount': 750.0,
          'occurred_at': now.toIso8601String(),
        },
      ];

      final snapshot = PlanEvaluationEngine.evaluate(
        plan: plan,
        expectedExpenses: [],
        rawTransactions: txns,
        nowOverride: now,
      );

      expect(snapshot.allTransactionsInRange.any((t) => t.id == 'r1'), isFalse);
      expect(snapshot.excludedTransactions.firstWhere((t) => t.id == 'r2').exclusionReason,
          equals('Outside the plan period'));
      expect(snapshot.excludedTransactions.firstWhere((t) => t.id == 'r3').exclusionReason,
          equals('Transfer between your accounts'));
      expect(snapshot.excludedTransactions.firstWhere((t) => t.id == 'r4').exclusionReason,
          equals('Needs review'));
      expect(snapshot.excludedTransactions.firstWhere((t) => t.id == 'r5').exclusionReason,
          equals('Not spending'));
      expect(snapshot.excludedTransactions.firstWhere((t) => t.id == 'r6').exclusionReason,
          equals('Bank not in this plan'));
      expect(snapshot.excludedTransactions.firstWhere((t) => t.id == 'r7').exclusionReason,
          equals('You marked it not counted'));
      expect(snapshot.excludedTransactions.firstWhere((t) => t.id == 'r9').exclusionReason,
          equals('Fees are not counted'));
      expect(snapshot.excludedTransactions.firstWhere((t) => t.id == 'r10').exclusionReason,
          equals('Cash withdrawals are not counted'));

      // Counted
      expect(snapshot.countedTransactions.length, equals(1));
      expect(snapshot.countedTransactions.first.id, equals('r-valid'));
      expect(snapshot.totalSpent, equals(750.0));
      expect(snapshot.spendableBudget, equals(9000.0)); // 10000 - 1000 reserve
      expect(snapshot.leftToSpend, equals(8250.0));
    });

    test('3-Zone transitions: withinBudget, usingReserve, overPlan', () {
      final startDate = DateTime(2026, 10, 1);
      final endDate = DateTime(2026, 10, 31);
      final now = DateTime(2026, 10, 15);

      final plan = {
        'id': 'plan-zones',
        'name': 'Zones Plan',
        'period_type': 'monthly',
        'start_date': startDate.toIso8601String(),
        'end_date': endDate.toIso8601String(),
        'spending_limit': 1000.0,
        'reserve_type': 'fixed',
        'reserve_value': 200.0, // spendable = 800, reserve = 200
        'watched_bank_ids': null,
        'count_fees': 1,
        'count_withdrawals': 1,
        'reaction_mode': 'adaptive',
        'status': 'active',
        'paused_days_count': 0,
      };

      // Zone 1: Within budget (spent 600 <= 800)
      final snap1 = PlanEvaluationEngine.evaluate(
        plan: plan,
        expectedExpenses: [],
        rawTransactions: [
          {'id': '1', 'account_id': 'a', 'type': 'expense', 'amount': 600.0, 'occurred_at': now.toIso8601String()}
        ],
        nowOverride: now,
      );
      expect(snap1.zone, equals(PlanBudgetZone.withinBudget));
      expect(snap1.reserveUsed, equals(0.0));
      expect(snap1.overspendAmount, equals(0.0));

      // Zone 2: Using reserve (spent 900 > 800 but <= 1000)
      final snap2 = PlanEvaluationEngine.evaluate(
        plan: plan,
        expectedExpenses: [],
        rawTransactions: [
          {'id': '2', 'account_id': 'a', 'type': 'expense', 'amount': 900.0, 'occurred_at': now.toIso8601String()}
        ],
        nowOverride: now,
      );
      expect(snap2.zone, equals(PlanBudgetZone.usingReserve));
      expect(snap2.reserveUsed, equals(100.0));
      expect(snap2.overspendAmount, equals(0.0));

      // Zone 3: Over plan (spent 1300 > 1000)
      final snap3 = PlanEvaluationEngine.evaluate(
        plan: plan,
        expectedExpenses: [],
        rawTransactions: [
          {'id': '3', 'account_id': 'a', 'type': 'expense', 'amount': 1300.0, 'occurred_at': now.toIso8601String()}
        ],
        nowOverride: now,
      );
      expect(snap3.zone, equals(PlanBudgetZone.overPlan));
      expect(snap3.reserveUsed, equals(200.0));
      expect(snap3.overspendAmount, equals(300.0));
    });
  });
}

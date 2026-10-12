import 'package:flutter_test/flutter_test.dart';
import 'package:sw_budget/features/insights/insights_math_service.dart';

void main() {
  group('InsightsMathService Tests', () {
    final fixedNow = DateTime(2026, 10, 15, 14, 30, 0);

    test('resolveDateWindow returns correct boundaries for all periods', () {
      final w7d = InsightsMathService.resolveDateWindow('7D', now: fixedNow);
      expect(w7d.start, DateTime(2026, 10, 9));
      expect(w7d.end.year, 2026);
      expect(w7d.end.month, 10);
      expect(w7d.end.day, 15);

      final w30d = InsightsMathService.resolveDateWindow('30D', now: fixedNow);
      expect(w30d.start, DateTime(2026, 9, 16));
      expect(w30d.end.day, 15);

      final wMom = InsightsMathService.resolveDateWindow('MOM', now: fixedNow);
      expect(wMom.start, DateTime(2026, 10, 1));
      expect(wMom.end.day, 15);

      final wYtd = InsightsMathService.resolveDateWindow('YTD', now: fixedNow);
      expect(wYtd.start, DateTime(2026, 1, 1));
      expect(wYtd.end.day, 15);
    });

    test('calculateInsights handles empty transaction list with pure zeros and clean empty state', () {
      final state = InsightsMathService.calculateInsights(
        period: '7D',
        allTransactions: [],
        categories: [],
        now: fixedNow,
      );

      expect(state.inflow, 0.0);
      expect(state.outflow, 0.0);
      expect(state.netSavings, 0.0);
      expect(state.savingsRate, 0);
      expect(state.chartInflows.length, 7);
      expect(state.chartOutflows.length, 7);
      expect(state.chartInflows.every((v) => v == 0.0), isTrue);
      expect(state.chartOutflows.every((v) => v == 0.0), isTrue);
      expect(state.categorySegments, isEmpty);
      expect(state.topMerchants, isEmpty);
      expect(state.isEmpty, isTrue);
      expect(state.observations.first, contains('No transactions recorded'));
    });

    test('calculateInsights computes real inflow, outflow, savings rate, and category donut', () {
      final categories = [
        {'id': 'cat_food', 'name': 'Food & Drinks', 'color_hex': '#34D399'},
        {'id': 'cat_fuel', 'name': 'Fuel & Transport', 'color_hex': '#FB7185'},
      ];

      final transactions = [
        // Income within 7D
        {
          'id': 'tx_1',
          'type': 'income',
          'amount': 10000.0,
          'occurred_at': '2026-10-12T10:00:00Z',
          'category_id': null,
          'counterparty': 'Employer Salary',
        },
        // Expense in cat_food within 7D
        {
          'id': 'tx_2',
          'type': 'expense',
          'amount': 1500.0,
          'occurred_at': '2026-10-13T12:00:00Z',
          'category_id': 'cat_food',
          'counterparty': 'Bole Supermarket',
        },
        // Another expense in cat_food within 7D
        {
          'id': 'tx_3',
          'type': 'expense',
          'amount': 500.0,
          'occurred_at': '2026-10-14T09:00:00Z',
          'category_id': 'cat_food',
          'counterparty': 'Bole Supermarket',
        },
        // Expense in cat_fuel within 7D
        {
          'id': 'tx_4',
          'type': 'expense',
          'amount': 1000.0,
          'occurred_at': '2026-10-15T11:00:00Z',
          'category_id': 'cat_fuel',
          'counterparty': 'Total Gas Station',
        },
        // Expense OUTSIDE 7D (should be filtered out)
        {
          'id': 'tx_5',
          'type': 'expense',
          'amount': 5000.0,
          'occurred_at': '2026-09-01T10:00:00Z',
          'category_id': 'cat_fuel',
          'counterparty': 'Old Station',
        },
      ];

      final state = InsightsMathService.calculateInsights(
        period: '7D',
        allTransactions: transactions,
        categories: categories,
        now: fixedNow,
      );

      expect(state.inflow, 10000.0);
      expect(state.outflow, 3000.0); // 1500 + 500 + 1000
      expect(state.netSavings, 7000.0);
      expect(state.savingsRate, 70);

      // Categories
      expect(state.categorySegments.length, 2);
      expect(state.categorySegments[0].label, 'Food & Drinks');
      expect(state.categorySegments[0].value, 2000.0);
      expect(state.categorySegments[1].label, 'Fuel & Transport');
      expect(state.categorySegments[1].value, 1000.0);

      // Top Merchants
      expect(state.topMerchants.length, 2);
      expect(state.topMerchants[0].name, 'Bole Supermarket');
      expect(state.topMerchants[0].volume, 2000.0);
      expect(state.topMerchants[0].count, 2);

      expect(state.topMerchants[1].name, 'Total Gas Station');
      expect(state.topMerchants[1].volume, 1000.0);
      expect(state.topMerchants[1].count, 1);

      // Observations
      expect(state.observations.any((o) => o.contains('Food & Drinks represents 67%')), isTrue);
      expect(state.observations.any((o) => o.contains('saved 70%')), isTrue);
    });

    test('30D period aggregates cashflow into 4 weekly chunks', () {
      final transactions = [
        {
          'id': 'tx_w1',
          'type': 'expense',
          'amount': 800.0,
          'occurred_at': '2026-09-18T10:00:00Z',
        },
        {
          'id': 'tx_w4',
          'type': 'expense',
          'amount': 1200.0,
          'occurred_at': '2026-10-14T10:00:00Z',
        },
      ];

      final state = InsightsMathService.calculateInsights(
        period: '30D',
        allTransactions: transactions,
        categories: [],
        now: fixedNow,
      );

      expect(state.chartLabels, ['W1', 'W2', 'W3', 'W4']);
      expect(state.chartOutflows.length, 4);
      expect(state.chartOutflows[0], 800.0);
      expect(state.chartOutflows[3], 1200.0);
    });
  });
}

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/charts/category_donut_chart.dart';

class MerchantInsight {
  final String rank;
  final String name;
  final double volume;
  final int count;

  const MerchantInsight({
    required this.rank,
    required this.name,
    required this.volume,
    required this.count,
  });
}

class InsightsDataState {
  final String period; // '7D' | '30D' | 'MOM' | 'YTD'
  final DateTime startDate;
  final DateTime endDate;
  final double inflow;
  final double outflow;
  final double netSavings;
  final int savingsRate;

  // Chart data
  final List<double> chartInflows;
  final List<double> chartOutflows;
  final List<String> chartLabels;

  // Donut categories
  final List<DonutSegment> categorySegments;

  // Top merchants
  final List<MerchantInsight> topMerchants;

  // Contextual Observations
  final List<String> observations;

  // Remote analytics (optional / nullable)
  final double? momChangePct;
  final double? totalFees;
  final double? dailyBurnRate;

  const InsightsDataState({
    required this.period,
    required this.startDate,
    required this.endDate,
    required this.inflow,
    required this.outflow,
    required this.netSavings,
    required this.savingsRate,
    required this.chartInflows,
    required this.chartOutflows,
    required this.chartLabels,
    required this.categorySegments,
    required this.topMerchants,
    required this.observations,
    this.momChangePct,
    this.totalFees,
    this.dailyBurnRate,
  });

  bool get isEmpty => inflow == 0 && outflow == 0 && categorySegments.isEmpty && topMerchants.isEmpty;
}

class InsightsMathService {
  /// Resolves the start and end date for the selected period
  static ({DateTime start, DateTime end}) resolveDateWindow(String period, {DateTime? now}) {
    final current = now ?? DateTime.now();
    final end = DateTime(current.year, current.month, current.day, 23, 59, 59, 999);

    switch (period) {
      case '7D':
        final start = DateTime(current.year, current.month, current.day).subtract(const Duration(days: 6));
        return (start: start, end: end);
      case '30D':
        final start = DateTime(current.year, current.month, current.day).subtract(const Duration(days: 29));
        return (start: start, end: end);
      case 'MOM':
        // Month to date
        final start = DateTime(current.year, current.month, 1);
        return (start: start, end: end);
      case 'YTD':
        final start = DateTime(current.year, 1, 1);
        return (start: start, end: end);
      default:
        final start = DateTime(current.year, current.month, current.day).subtract(const Duration(days: 29));
        return (start: start, end: end);
    }
  }

  /// Calculates complete insights data from local database records
  static InsightsDataState calculateInsights({
    required String period,
    required List<Map<String, dynamic>> allTransactions,
    required List<Map<String, dynamic>> categories,
    DateTime? now,
    double? remoteMomChangePct,
    double? remoteTotalFees,
    double? remoteDailyBurnRate,
  }) {
    final window = resolveDateWindow(period, now: now);
    final startDate = window.start;
    final endDate = window.end;

    // Filter transactions within the date window
    final inWindowTxns = allTransactions.where((tx) {
      final dt = DateTime.tryParse(tx['occurred_at'] as String? ?? '');
      if (dt == null) return false;
      return !dt.isBefore(startDate) && !dt.isAfter(endDate);
    }).toList();

    double inflow = 0.0;
    double outflow = 0.0;
    final Map<String, double> categorySpendMap = {};
    final Map<String, List<double>> merchantSpendMap = {};

    for (final tx in inWindowTxns) {
      final type = (tx['type'] as String? ?? '').toLowerCase();
      final amt = (tx['amount'] as num?)?.toDouble() ?? 0.0;

      if (type == 'credit' || type == 'income') {
        inflow += amt;
      } else if (type == 'debit' || type == 'expense') {
        outflow += amt;

        // Category grouping
        final catId = tx['category_id'] as String?;
        final key = (catId != null && catId.isNotEmpty) ? catId : 'uncategorized';
        categorySpendMap[key] = (categorySpendMap[key] ?? 0.0) + amt;

        // Merchant grouping
        String merchant = (tx['counterparty'] as String? ?? '').trim();
        if (merchant.isEmpty) {
          merchant = (tx['note'] as String? ?? '').trim();
        }
        if (merchant.isNotEmpty) {
          merchantSpendMap.putIfAbsent(merchant, () => [0.0, 0.0]);
          merchantSpendMap[merchant]![0] += amt;
          merchantSpendMap[merchant]![1] += 1;
        }
      }
    }

    final netSavings = inflow - outflow;
    final savingsRate = inflow > 0 ? ((netSavings / inflow) * 100).clamp(0, 100).round() : 0;

    // Build Chart Buckets
    final chartData = _buildChartBuckets(period, startDate, endDate, inWindowTxns);

    // Build Category Donut Segments
    final categorySegments = _buildCategorySegments(categorySpendMap, categories, outflow);

    // Build Top Merchants
    final topMerchants = _buildTopMerchants(merchantSpendMap);

    // Synthesize Observations
    final observations = _synthesizeObservations(
      period: period,
      inflow: inflow,
      outflow: outflow,
      netSavings: netSavings,
      savingsRate: savingsRate,
      topCategories: categorySegments,
      topMerchants: topMerchants,
      txnCounts: inWindowTxns.length,
      remoteMomChangePct: remoteMomChangePct,
      remoteTotalFees: remoteTotalFees,
    );

    return InsightsDataState(
      period: period,
      startDate: startDate,
      endDate: endDate,
      inflow: inflow,
      outflow: outflow,
      netSavings: netSavings,
      savingsRate: savingsRate,
      chartInflows: chartData.inflows,
      chartOutflows: chartData.outflows,
      chartLabels: chartData.labels,
      categorySegments: categorySegments,
      topMerchants: topMerchants,
      observations: observations,
      momChangePct: remoteMomChangePct,
      totalFees: remoteTotalFees,
      dailyBurnRate: remoteDailyBurnRate,
    );
  }

  /// Groups transactions into period-appropriate bars
  static ({List<double> inflows, List<double> outflows, List<String> labels}) _buildChartBuckets(
    String period,
    DateTime start,
    DateTime end,
    List<Map<String, dynamic>> txns,
  ) {
    if (period == '7D') {
      // 7 daily bars
      final labels = <String>[];
      final inflows = List.filled(7, 0.0);
      final outflows = List.filled(7, 0.0);

      for (int i = 0; i < 7; i++) {
        final day = start.add(Duration(days: i));
        labels.add(DateFormat('E').format(day)); // Mon, Tue...
      }

      for (final tx in txns) {
        final dt = DateTime.tryParse(tx['occurred_at'] as String? ?? '');
        if (dt == null) continue;
        final dayDiff = dt.difference(DateTime(start.year, start.month, start.day)).inDays;
        if (dayDiff >= 0 && dayDiff < 7) {
          final amt = (tx['amount'] as num?)?.toDouble() ?? 0.0;
          final type = (tx['type'] as String? ?? '').toLowerCase();
          if (type == 'credit' || type == 'income') {
            inflows[dayDiff] += amt;
          } else if (type == 'debit' || type == 'expense') {
            outflows[dayDiff] += amt;
          }
        }
      }
      return (inflows: inflows, outflows: outflows, labels: labels);
    } else if (period == '30D' || period == 'MOM') {
      // 4 weekly chunks
      final labels = ['W1', 'W2', 'W3', 'W4'];
      final inflows = List.filled(4, 0.0);
      final outflows = List.filled(4, 0.0);
      final totalDays = max(1, end.difference(start).inDays + 1);
      final chunkSize = totalDays / 4.0;

      for (final tx in txns) {
        final dt = DateTime.tryParse(tx['occurred_at'] as String? ?? '');
        if (dt == null) continue;
        final dayOffset = dt.difference(start).inDays;
        if (dayOffset >= 0) {
          int bucket = (dayOffset / chunkSize).floor();
          if (bucket >= 4) bucket = 3;
          final amt = (tx['amount'] as num?)?.toDouble() ?? 0.0;
          final type = (tx['type'] as String? ?? '').toLowerCase();
          if (type == 'credit' || type == 'income') {
            inflows[bucket] += amt;
          } else if (type == 'debit' || type == 'expense') {
            outflows[bucket] += amt;
          }
        }
      }
      return (inflows: inflows, outflows: outflows, labels: labels);
    } else {
      // YTD: Up to current month bars (or 6 evenly spaced chunks if long)
      final monthsCount = max(1, end.month - start.month + 1);
      final labels = <String>[];
      final inflows = List.filled(monthsCount, 0.0);
      final outflows = List.filled(monthsCount, 0.0);

      for (int m = 1; m <= monthsCount; m++) {
        final monthDate = DateTime(start.year, m, 1);
        labels.add(DateFormat('MMM').format(monthDate));
      }

      for (final tx in txns) {
        final dt = DateTime.tryParse(tx['occurred_at'] as String? ?? '');
        if (dt == null) continue;
        final mIdx = dt.month - 1;
        if (mIdx >= 0 && mIdx < monthsCount) {
          final amt = (tx['amount'] as num?)?.toDouble() ?? 0.0;
          final type = (tx['type'] as String? ?? '').toLowerCase();
          if (type == 'credit' || type == 'income') {
            inflows[mIdx] += amt;
          } else if (type == 'debit' || type == 'expense') {
            outflows[mIdx] += amt;
          }
        }
      }
      return (inflows: inflows, outflows: outflows, labels: labels);
    }
  }

  /// Maps category IDs to human-readable names and palette colors
  static List<DonutSegment> _buildCategorySegments(
    Map<String, double> categorySpendMap,
    List<Map<String, dynamic>> categories,
    double totalOutflow,
  ) {
    if (categorySpendMap.isEmpty) return const [];

    final categoryMap = <String, Map<String, dynamic>>{};
    for (final c in categories) {
      final id = c['id'] as String? ?? '';
      if (id.isNotEmpty) categoryMap[id] = c;
    }

    final palette = [
      AppColors.accent,
      AppColors.income,
      AppColors.amber,
      AppColors.expense,
      const Color(0xFF38BDF8), // Sky blue
      const Color(0xFFA855F7), // Purple
      AppColors.text2,
    ];

    // Sort categories by spend descending
    final sorted = categorySpendMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final segments = <DonutSegment>[];
    int colorIdx = 0;

    for (final entry in sorted) {
      final catId = entry.key;
      final amount = entry.value;

      String name = 'Uncategorized';
      Color color = palette[colorIdx % palette.length];

      if (categoryMap.containsKey(catId)) {
        final c = categoryMap[catId]!;
        name = c['name'] as String? ?? 'General';
        final colorHex = c['color_hex'] as String?;
        if (colorHex != null && colorHex.isNotEmpty) {
          final parsed = int.tryParse(colorHex.replaceFirst('#', ''), radix: 16);
          if (parsed != null) {
            color = Color(0xFF000000 | parsed);
          }
        }
      } else if (catId != 'uncategorized') {
        name = catId.replaceAll('_', ' ').split(' ').map((w) {
          return w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '';
        }).join(' ');
      }

      segments.add(DonutSegment(
        label: name,
        value: amount,
        color: color,
      ));
      colorIdx++;
    }

    return segments;
  }

  /// Aggregates and ranks merchants by volume
  static List<MerchantInsight> _buildTopMerchants(Map<String, List<double>> merchantSpendMap) {
    if (merchantSpendMap.isEmpty) return const [];

    final sorted = merchantSpendMap.entries.toList()
      ..sort((a, b) => b.value[0].compareTo(a.value[0]));

    final top = sorted.take(5).toList();
    return top.asMap().entries.map((entry) {
      final rank = (entry.key + 1).toString();
      final name = entry.value.key;
      final volume = entry.value.value[0];
      final count = entry.value.value[1].toInt();
      return MerchantInsight(rank: rank, name: name, volume: volume, count: count);
    }).toList();
  }

  /// Synthesizes contextual observations based on real figures
  static List<String> _synthesizeObservations({
    required String period,
    required double inflow,
    required double outflow,
    required double netSavings,
    required int savingsRate,
    required List<DonutSegment> topCategories,
    required List<MerchantInsight> topMerchants,
    required int txnCounts,
    double? remoteMomChangePct,
    double? remoteTotalFees,
  }) {
    if (txnCounts == 0) {
      return [
        'No transactions recorded for the $period window.',
        'Log a manual transaction or sync your bank SMS messages to view spending trends.',
      ];
    }

    final obs = <String>[];

    // 1. Top spending category observation
    if (topCategories.isNotEmpty && outflow > 0) {
      final topCat = topCategories.first;
      final share = ((topCat.value / outflow) * 100).round();
      obs.add('${topCat.label} represents $share% of your total outflow in this $period period.');
    }

    // 2. Savings rate or deficit
    if (inflow > 0 && outflow > 0) {
      if (netSavings >= 0) {
        obs.add('You have saved $savingsRate% of your income over this period (Net +${NumberFormat('#,##0.00').format(netSavings)} ETB).');
      } else {
        obs.add('Outflow exceeded inflow by ${NumberFormat('#,##0.00').format(netSavings.abs())} ETB in this period.');
      }
    } else if (outflow > 0 && inflow == 0) {
      obs.add('Total spending across $txnCounts logged transactions is ${NumberFormat('#,##0.00').format(outflow)} ETB.');
    }

    // 3. Top merchant insight or remote trend
    if (remoteMomChangePct != null && period == 'MOM') {
      if (remoteMomChangePct > 0) {
        obs.add('Spending is up by ${remoteMomChangePct.abs().toStringAsFixed(1)}% compared to last month.');
      } else if (remoteMomChangePct < 0) {
        obs.add('Spending decreased by ${remoteMomChangePct.abs().toStringAsFixed(1)}% compared to last month.');
      }
    } else if (topMerchants.isNotEmpty) {
      final topM = topMerchants.first;
      obs.add('${topM.name} is your largest counterparty with ${topM.count} transactions totaling ${NumberFormat('#,##0.00').format(topM.volume)} ETB.');
    } else if (remoteTotalFees != null && remoteTotalFees > 0) {
      obs.add('Identified ${NumberFormat('#,##0.00').format(remoteTotalFees)} ETB in banking and transfer fees.');
    }

    return obs;
  }
}

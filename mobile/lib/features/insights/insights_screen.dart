import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/security/privacy_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/charts/category_donut_chart.dart';
import '../../core/widgets/charts/flow_bar_chart.dart';
import '../activity/activity_providers.dart';

class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  String _activePeriod = '30D';
  static const _periods = ['7D', '30D', 'MOM', 'YTD'];

  @override
  Widget build(BuildContext context) {
    final transactionsAsync = ref.watch(transactionsProvider);
    final isPrivate = ref.watch(privacyModeProvider);
    final transactions = transactionsAsync.value ?? [];

    final now = DateTime.now();
    DateTime cutoff;
    if (_activePeriod == '7D') {
      cutoff = now.subtract(const Duration(days: 7));
    } else if (_activePeriod == '30D') {
      cutoff = now.subtract(const Duration(days: 30));
    } else if (_activePeriod == 'MOM') {
      cutoff = DateTime(now.year, now.month, 1);
    } else {
      cutoff = DateTime(now.year, 1, 1);
    }

    final periodTransactions = transactions.where((tx) {
      final dt = DateTime.tryParse(tx['occurred_at'] as String? ?? '');
      return dt != null && dt.isAfter(cutoff);
    }).toList();

    final txList = periodTransactions.isNotEmpty ? periodTransactions : transactions;

    // Calculate inflow, outflow, net savings
    double inflow = 0.0;
    double outflow = 0.0;
    final Map<String, double> categorySpend = {};
    final Map<String, List<double>> merchantSpend = {};

    for (final tx in txList) {
      final type = (tx['type'] as String? ?? '').toLowerCase();
      final amt = (tx['amount'] as num?)?.toDouble() ?? 0.0;
      if (type == 'credit' || type == 'income') {
        inflow += amt;
      } else if (type == 'debit' || type == 'expense') {
        outflow += amt;
        final cat = tx['category_id'] as String? ?? 'General Expense';
        categorySpend[cat] = (categorySpend[cat] ?? 0.0) + amt;

        final party = (tx['counterparty'] as String? ?? '').trim();
        if (party.isNotEmpty) {
          merchantSpend.putIfAbsent(party, () => [0.0, 0.0]);
          merchantSpend[party]![0] += amt;
          merchantSpend[party]![1] += 1;
        }
      }
    }

    // Prototype defaults if no transactions in DB
    if (transactions.isEmpty) {
      inflow = 45000.00;
      outflow = 18095.39;
    }

    final netSavings = inflow - outflow;
    final savingsRate = inflow > 0 ? ((netSavings / inflow) * 100).clamp(0, 100).toInt() : 0;

    // Category donut segments
    final palette = [AppColors.accent, AppColors.income, AppColors.amber, AppColors.expense, AppColors.text2];
    int colorIdx = 0;
    final List<DonutSegment> donutSegments = [];
    categorySpend.forEach((cat, amt) {
      donutSegments.add(DonutSegment(
        label: cat,
        value: amt,
        color: palette[colorIdx % palette.length],
      ));
      colorIdx++;
    });

    // Top merchants
    final sortedMerchants = merchantSpend.entries.toList()
      ..sort((a, b) => b.value[0].compareTo(a.value[0]));
    final topMerchants = sortedMerchants.take(5).toList().asMap().entries.map((entry) {
      final rank = (entry.key + 1).toString();
      final name = entry.value.key;
      final volume = entry.value.value[0];
      final count = entry.value.value[1].toInt();
      return {'rank': rank, 'name': name, 'volume': volume, 'count': count};
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.accent,
          backgroundColor: AppColors.surface,
          onRefresh: () async {
            ref.invalidate(transactionsProvider);
          },
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // 1. Header: Title + Coach Spark Icon
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Insights',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => context.push('/coach'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.auto_awesome_rounded, color: AppColors.accent, size: 16),
                          SizedBox(width: 6),
                          Text(
                            'Coach',
                            style: TextStyle(
                              color: AppColors.accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 2. Segmented Time Switcher: 7D | 30D | MOM | YTD
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.line),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: _periods.map((p) {
                    final isSelected = _activePeriod == p;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _activePeriod = p;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.accentBg : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? AppColors.accent.withOpacity(0.5) : Colors.transparent,
                            ),
                          ),
                          child: Text(
                            p,
                            style: TextStyle(
                              color: isSelected ? AppColors.accent : AppColors.text3,
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 14),

              // 3. 4-Card Stats Grid
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      label: 'Inflow',
                      value: '+${formatCurrency(inflow, isPrivate: isPrivate)}',
                      valueColor: AppColors.income,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMetricCard(
                      label: 'Outflow',
                      value: '-${formatCurrency(outflow, isPrivate: isPrivate)}',
                      valueColor: AppColors.expense,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      label: 'Net Savings',
                      value: formatCurrency(netSavings, isPrivate: isPrivate),
                      valueColor: netSavings >= 0 ? AppColors.income : AppColors.expense,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMetricCard(
                      label: 'Savings Rate',
                      value: '$savingsRate%',
                      valueColor: AppColors.accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // 4. Cash Flow Chart Section
              const Text(
                'CASH FLOW (INFLOW VS OUTFLOW)',
                style: TextStyle(
                  color: AppColors.text3,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 10),
              const FlowBarChart(),
              const SizedBox(height: 18),

              // 5. Where It Went (Donut Chart & Legend)
              const Text(
                'WHERE IT WENT',
                style: TextStyle(
                  color: AppColors.text3,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 10),
              CategoryDonutChart(
                segments: donutSegments.isNotEmpty
                    ? donutSegments
                    : const [
                        DonutSegment(label: 'Food & Dining', value: 6050.0, color: AppColors.accent),
                        DonutSegment(label: 'Rent & Utilities', value: 4500.0, color: AppColors.income),
                        DonutSegment(label: 'Transport & Fuel', value: 3200.0, color: AppColors.amber),
                        DonutSegment(label: 'Shopping & Leisure', value: 4345.39, color: AppColors.expense),
                      ],
                totalSpent: outflow,
                isMasked: isPrivate,
              ),
              const SizedBox(height: 18),

              // 6. Top Merchants Ranked List
              _buildTopMerchantsSection(
                merchants: topMerchants,
                isPrivate: isPrivate,
              ),
              const SizedBox(height: 18),

              // 7. Proactive Coach Insights
              _buildCoachInsightsSection(context),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.text3, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopMerchantsSection({
    required List<Map<String, dynamic>> merchants,
    required bool isPrivate,
  }) {
    final effectiveMerchants = merchants.isNotEmpty
        ? merchants
        : [
            {'rank': '1', 'name': 'Fresh Corner Supermarket', 'volume': 3450.0, 'count': 8},
            {'rank': '2', 'name': 'TotalEnergies Bole', 'volume': 2400.0, 'count': 3},
            {'rank': '3', 'name': 'Tomoca Coffee House', 'volume': 980.0, 'count': 11},
            {'rank': '4', 'name': 'Ethio Telecom Fibre', 'volume': 1400.0, 'count': 1},
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'TOP MERCHANTS',
          style: TextStyle(
            color: AppColors.text3,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: effectiveMerchants.length,
            separatorBuilder: (_, __) => const Divider(color: AppColors.line, height: 1),
            itemBuilder: (context, index) {
              final m = effectiveMerchants[index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                leading: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    m['rank'] as String,
                    style: const TextStyle(
                      color: AppColors.text2,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                title: Text(
                  m['name'] as String,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  '${m['count']} transactions',
                  style: const TextStyle(color: AppColors.text3, fontSize: 11),
                ),
                trailing: Text(
                  formatCurrency(m['volume'] as double, isPrivate: isPrivate),
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCoachInsightsSection(BuildContext context) {
    final insights = [
      'Food & Dining made up 34% of your outflow this month, 6% lower than last month.',
      'You had 0 unaccounted balance drops since you started logging cash withdrawals.',
      'Switching grocery trips to bi-weekly saved an estimated ETB 650 in impulse purchases.',
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: AppColors.accent, size: 16),
              SizedBox(width: 8),
              Text(
                'Coach observations',
                style: TextStyle(
                  color: AppColors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...insights.map(
            (ins) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 6, right: 8),
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      ins,
                      style: const TextStyle(
                        color: AppColors.text2,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.surface2,
                foregroundColor: AppColors.accent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppColors.line),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
              label: const Text(
                'Ask your AI coach',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              onPressed: () => context.push('/coach'),
            ),
          ),
        ],
      ),
    );
  }
}

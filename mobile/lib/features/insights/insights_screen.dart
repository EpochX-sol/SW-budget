import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/security/privacy_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/charts/category_donut_chart.dart';
import '../../core/widgets/charts/flow_bar_chart.dart';
import '../activity/activity_providers.dart';
import 'insights_providers.dart';

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  static const _periods = ['7D', '30D', 'MOM', 'YTD'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activePeriod = ref.watch(insightsPeriodProvider);
    final summary = ref.watch(insightsSummaryProvider);
    final isPrivate = ref.watch(privacyModeProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.accent,
          backgroundColor: AppColors.surface,
          onRefresh: () async {
            ref.invalidate(transactionsProvider);
            ref.invalidate(insightsCategoriesStreamProvider);
            ref.invalidate(remoteAnalyticsTrendsProvider);
            ref.invalidate(remoteAnalyticsFeesProvider);
            ref.invalidate(remoteAnalyticsForecastProvider);
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
                    final isSelected = activePeriod == p;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () {
                          ref.read(insightsPeriodProvider.notifier).state = p;
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.accentBg : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? AppColors.accent.withValues(alpha: 0.5) : Colors.transparent,
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
                      value: '+${formatCurrency(summary.inflow, isPrivate: isPrivate)}',
                      valueColor: AppColors.income,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMetricCard(
                      label: 'Outflow',
                      value: '-${formatCurrency(summary.outflow, isPrivate: isPrivate)}',
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
                      value: formatCurrency(summary.netSavings, isPrivate: isPrivate),
                      valueColor: summary.netSavings >= 0 ? AppColors.income : AppColors.expense,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMetricCard(
                      label: 'Savings Rate',
                      value: '${summary.savingsRate}%',
                      valueColor: AppColors.accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // 4. Cash Flow Chart Section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'CASH FLOW (INFLOW VS OUTFLOW)',
                    style: TextStyle(
                      color: AppColors.text3,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                  Text(
                    '${DateFormat('MMM d').format(summary.startDate)} - ${DateFormat('MMM d').format(summary.endDate)}',
                    style: const TextStyle(color: AppColors.text3, fontSize: 10),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.line),
                ),
                child: FlowBarChart(
                  inflows: summary.chartInflows,
                  outflows: summary.chartOutflows,
                  labels: summary.chartLabels,
                  height: 150,
                ),
              ),
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
              _buildCategoryBreakdownSection(summary: summary, isPrivate: isPrivate),
              const SizedBox(height: 18),

              // 6. Top Merchants Ranked List
              _buildTopMerchantsSection(summary: summary, isPrivate: isPrivate),
              const SizedBox(height: 18),

              // 7. Dynamic Financial Observations
              _buildCoachInsightsSection(context, summary: summary),
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

  Widget _buildCategoryBreakdownSection({
    required dynamic summary,
    required bool isPrivate,
  }) {
    final segments = summary.categorySegments;

    if (segments.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.line),
        ),
        alignment: Alignment.center,
        child: const Column(
          children: [
            Icon(Icons.pie_chart_outline_rounded, color: AppColors.text3, size: 36),
            SizedBox(height: 8),
            Text(
              'No categorized expenses in this period',
              style: TextStyle(color: AppColors.text2, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CategoryDonutChart(
            segments: segments,
            totalSpent: summary.outflow,
            isMasked: isPrivate,
            size: 130,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: segments.take(4).map<Widget>((seg) {
                final pct = summary.outflow > 0 ? ((seg.value / summary.outflow) * 100).round() : 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: seg.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          seg.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.text2, fontSize: 12),
                        ),
                      ),
                      Text(
                        '$pct%',
                        style: const TextStyle(color: AppColors.text, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopMerchantsSection({
    required dynamic summary,
    required bool isPrivate,
  }) {
    final merchants = summary.topMerchants;

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
          child: merchants.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: Text(
                      'No merchant data for this period',
                      style: TextStyle(color: AppColors.text3, fontSize: 13),
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: merchants.length,
                  separatorBuilder: (_, __) => const Divider(color: AppColors.line, height: 1),
                  itemBuilder: (context, index) {
                    final m = merchants[index];
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
                          m.rank,
                          style: const TextStyle(
                            color: AppColors.text2,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      title: Text(
                        m.name,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${m.count} transaction${m.count == 1 ? '' : 's'}',
                        style: const TextStyle(color: AppColors.text3, fontSize: 11),
                      ),
                      trailing: Text(
                        formatCurrency(m.volume, isPrivate: isPrivate),
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

  Widget _buildCoachInsightsSection(BuildContext context, {required dynamic summary}) {
    final observations = summary.observations as List<String>;

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
          ...observations.map(
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

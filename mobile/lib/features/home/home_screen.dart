import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/security/auth_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../activity/activity_providers.dart';
import 'widgets/ai_insight_card.dart';
import 'widgets/cashflow_trend_chart.dart';
import 'widgets/quick_actions_bar.dart';
import 'widgets/total_balance_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final accountsAsync = ref.watch(accountsStreamProvider);
    final transactionsAsync = ref.watch(transactionsProvider);
    final reviewCountAsync = ref.watch(reviewInboxCountProvider);

    final user = authState.userProfile;
    final displayName = user?['display_name'] as String? ?? 'Samuel';

    // Calculate live aggregated financial metrics
    final accounts = accountsAsync.value ?? [];
    double totalBalance = 0.0;
    for (final acc in accounts) {
      final bal = (acc['last_known_balance'] as num?)?.toDouble() ?? 0.0;
      totalBalance += bal;
    }

    final transactions = transactionsAsync.value ?? [];
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    final sevenDaysAgo = now.subtract(const Duration(days: 7));

    double todayIncome = 0.0;
    double todayExpense = 0.0;
    double weekIncome = 0.0;
    double weekExpense = 0.0;

    final Map<int, double> dayIncomeMap = {};
    final Map<int, double> dayExpenseMap = {};
    for (int i = 0; i < 7; i++) {
      dayIncomeMap[i] = 0.0;
      dayExpenseMap[i] = 0.0;
    }

    for (final tx in transactions) {
      final type = (tx['type'] as String? ?? 'debit').toLowerCase();
      final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
      final occurredAtStr = tx['occurred_at'] as String? ?? '';
      final dt = DateTime.tryParse(occurredAtStr);

      if (occurredAtStr.startsWith(todayStr)) {
        if (type == 'credit') {
          todayIncome += amount;
        } else {
          todayExpense += amount;
        }
      }

      if (dt != null && dt.isAfter(sevenDaysAgo)) {
        if (type == 'credit') {
          weekIncome += amount;
        } else {
          weekExpense += amount;
        }

        final dayDiff = 6 - now.difference(dt).inDays.clamp(0, 6);
        if (type == 'credit') {
          dayIncomeMap[dayDiff] = (dayIncomeMap[dayDiff] ?? 0.0) + amount;
        } else {
          dayExpenseMap[dayDiff] = (dayExpenseMap[dayDiff] ?? 0.0) + amount;
        }
      }
    }

    final incomeSpots = List.generate(
      7,
      (i) => FlSpot(i.toDouble(), (dayIncomeMap[i] ?? 0.0).clamp(0.0, 1000.0)),
    );
    final expenseSpots = List.generate(
      7,
      (i) => FlSpot(i.toDouble(), (dayExpenseMap[i] ?? 0.0).clamp(0.0, 1000.0)),
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Selam, $displayName',
              style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(
              'Executive Financial Overview',
              style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          // Review Inbox shortcut icon with badge
          reviewCountAsync.when(
            data: (count) => IconButton(
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.notifications_none_rounded, color: AppColors.textPrimary),
                  if (count > 0)
                    Positioned(
                      right: -3,
                      top: -3,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppColors.secondary,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text(
                          '$count',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              tooltip: 'Review Inbox',
              onPressed: () => context.push('/review-inbox'),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          IconButton(
            icon: const Icon(Icons.lock_outline_rounded, color: AppColors.textSecondary),
            tooltip: 'Lock Ledger',
            onPressed: () {
              ref.read(authStateProvider.notifier).lockApp();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primaryLight,
          backgroundColor: AppColors.surface,
          onRefresh: () async {
            ref.invalidate(accountsStreamProvider);
            ref.invalidate(transactionsProvider);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Signature Indigo/Violet Total Balance Card
                TotalBalanceCard(
                  totalBalance: totalBalance,
                  todayIncome: todayIncome,
                  todayExpense: todayExpense,
                  weekIncome: weekIncome,
                  weekExpense: weekExpense,
                ),

                const SizedBox(height: 16),

                // 2. Quick Action Buttons: Expense & Income
                const QuickActionsBar(),

                const SizedBox(height: 16),

                // 3. AI Insight Ambient Card
                const AiInsightCard(),

                const SizedBox(height: 16),

                // 4. Interactive 7D / 30D Cashflow Bézier Trend Chart
                CashflowTrendChart(
                  incomeSpots7D: incomeSpots,
                  expenseSpots7D: expenseSpots,
                ),

                const SizedBox(height: 24),

                // 5. Today's Recent Feed Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Recent Activity',
                      style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold),
                    ),
                    InkWell(
                      onTap: () => context.go('/activity'),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Row(
                          children: [
                            Text(
                              'See all',
                              style: AppTypography.labelSmall.copyWith(
                                color: AppColors.primaryLight,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 11,
                              color: AppColors.primaryLight,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Recent Activity List
                transactionsAsync.when(
                  data: (txList) {
                    if (txList.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.receipt_long_rounded,
                                color: AppColors.primaryLight,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'No transactions yet today',
                                    style: AppTypography.bodyMedium.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Transactions from CBE, Telebirr, and BoA SMS will stream here automatically.',
                                    style: AppTypography.bodySmall.copyWith(
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final recentTx = txList.take(4).toList();
                    return Column(
                      children: recentTx.map((tx) {
                        final type = (tx['type'] as String? ?? 'debit').toLowerCase();
                        final isCredit = type == 'credit';
                        final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
                        final counterparty = tx['counterparty'] as String? ?? 'Transaction';
                        final category = tx['category_name'] as String? ?? 'General';
                        final runningBal = (tx['running_balance'] as num?)?.toDouble();
                        final occurredAtStr = tx['occurred_at'] as String? ?? '';
                        String timeStr = '';
                        if (occurredAtStr.isNotEmpty) {
                          final dt = DateTime.tryParse(occurredAtStr);
                          if (dt != null) {
                            timeStr = DateFormat('HH:mm').format(dt);
                          }
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: (isCredit ? AppColors.income : AppColors.expense)
                                      .withOpacity(0.14),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                                  color: isCredit ? AppColors.income : AppColors.expense,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      counterparty,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTypography.bodyMedium.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.surfaceElevated,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            category,
                                            style: AppTypography.labelSmall.copyWith(
                                              fontSize: 10,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        ),
                                        if (timeStr.isNotEmpty) ...[
                                          const SizedBox(width: 6),
                                          Text(
                                            timeStr,
                                            style: AppTypography.labelSmall.copyWith(
                                              fontSize: 11,
                                              color: AppColors.textMuted,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${isCredit ? "+" : "-"} ETB ${amount.toStringAsFixed(2)}',
                                    style: AppTypography.bodyMedium.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: isCredit ? AppColors.income : AppColors.expense,
                                    ),
                                  ),
                                  if (runningBal != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      'Bal: ${runningBal.toStringAsFixed(2)}',
                                      style: AppTypography.labelSmall.copyWith(
                                        fontSize: 10,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(color: AppColors.primaryLight),
                    ),
                  ),
                  error: (e, _) => Text(
                    'Error: $e',
                    style: const TextStyle(color: AppColors.expense),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

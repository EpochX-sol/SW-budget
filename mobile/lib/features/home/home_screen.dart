import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/security/auth_state.dart';
import '../../core/security/privacy_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/brand_badge.dart';
import '../../core/widgets/progress_ring.dart';
import '../../core/widgets/sheets/account_edit_sheet.dart';
import '../../core/widgets/sheets/transaction_detail_sheet.dart';
import '../../core/widgets/split_bar.dart';
import '../../core/widgets/status_pill.dart';
import '../../core/widgets/sync_pill.dart';
import '../../domain/use_cases/budget_math_service.dart';
import '../activity/activity_providers.dart';
import '../debts/debts_providers.dart';
import '../plan/plan_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final accountsAsync = ref.watch(accountsStreamProvider);
    final transactionsAsync = ref.watch(transactionsProvider);
    final reviewCountAsync = ref.watch(reviewInboxCountProvider);
    final safeToSpend = ref.watch(safeToSpendProvider);
    final isPrivate = ref.watch(privacyModeProvider);
    final debtsAsync = ref.watch(debtsStreamProvider);

    final user = authState.userProfile;
    final displayName = user?['display_name'] as String? ?? 'Samuel';

    final accounts = accountsAsync.value ?? [];
    final transactions = transactionsAsync.value ?? [];
    final reviewCount = reviewCountAsync.value ?? 0;
    final allDebts = debtsAsync.value ?? [];
    final upcomingDueDebts = allDebts
        .where((d) =>
            d['status'] == 'active' &&
            d['due_date'] != null &&
            (d['due_date'] as String).isNotEmpty)
        .toList();

    // Categorize liquid assets for SplitBar
    double bankTotal = 0.0;
    double telebirrTotal = 0.0;
    double cashTotal = 0.0;
    double liquidTotal = 0.0;

    for (final acc in accounts) {
      final bal = (acc['last_known_balance'] as num?)?.toDouble() ?? 0.0;
      final type = (acc['account_type'] as String? ?? '').toLowerCase();
      final inst = (acc['institution_id'] as String? ?? '').toLowerCase();
      final isLocked = (acc['is_locked'] == 1 || acc['is_locked'] == true);

      if (!isLocked) {
        liquidTotal += bal;
        if (type == 'cash') {
          cashTotal += bal;
        } else if (inst.contains('telebirr') || inst.contains('tb') || type == 'mobile_money') {
          telebirrTotal += bal;
        } else {
          bankTotal += bal;
        }
      }
    }

    // Compute today spend & allowance
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    double spentToday = 0.0;
    for (final tx in transactions) {
      final occurredAt = tx['occurred_at'] as String? ?? '';
      final type = (tx['type'] as String? ?? '').toLowerCase();
      if (occurredAt.startsWith(todayStr) && (type == 'debit' || type == 'expense')) {
        spentToday += (tx['amount'] as num?)?.toDouble() ?? 0.0;
      }
    }

    final double safeToday = safeToSpend.safeToday > 0 ? safeToSpend.safeToday : 0.0;
    final double remainingToday = (safeToday - spentToday).clamp(0.0, double.infinity);
    final double tomorrowAllowance = safeToday > 0
        ? safeToday * (spentToday > safeToday ? 0.92 : 1.05)
        : 0.0;

    final statusString = safeToSpend.pace == SpendingPace.ahead
        ? 'AHEAD'
        : safeToSpend.pace == SpendingPace.caution
            ? 'CAUTION'
            : safeToSpend.pace == SpendingPace.deficit
                ? 'DEFICIT'
                : 'ON TRACK';

    final ringProgress = safeToday > 0 ? (spentToday / safeToday).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.accent,
          backgroundColor: AppColors.surface,
          onRefresh: () async {
            ref.invalidate(accountsStreamProvider);
            ref.invalidate(transactionsProvider);
          },
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // 1. Top Bar: Greeting, Privacy Eye, Avatar
              _buildTopBar(context, ref, displayName, isPrivate),
              const SizedBox(height: 12),

              // 2. Sync Pill
              Align(
                alignment: Alignment.centerLeft,
                child: SyncPill(
                  lastSyncText: 'Synced just now',
                  onSyncNow: () {
                    ref.invalidate(accountsStreamProvider);
                    ref.invalidate(transactionsProvider);
                  },
                ),
              ),
              const SizedBox(height: 14),

              // 3. Hero Liquid Balance Card with 3-segment Splitbar
              _buildHeroBalanceCard(
                liquidTotal: liquidTotal,
                bankTotal: bankTotal,
                telebirrTotal: telebirrTotal,
                cashTotal: cashTotal,
                activeCount: accounts.length,
                isPrivate: isPrivate,
              ),
              const SizedBox(height: 14),

              // 4. Safe to Spend Today Card
              _buildSafeToSpendCard(
                safeToday: safeToday,
                spentToday: spentToday,
                remainingToday: remainingToday,
                tomorrowAllowance: tomorrowAllowance,
                ringProgress: ringProgress,
                statusString: statusString,
                isPrivate: isPrivate,
              ),
              const SizedBox(height: 14),

              // 5. Attention Banner (Review Inbox)
              if (reviewCount > 0) ...[
                _buildAttentionBanner(context, reviewCount),
                const SizedBox(height: 14),
              ],

              // 6. Upcoming Obligations Banner
              if (upcomingDueDebts.isNotEmpty) ...[
                _buildUpcomingBillBanner(upcomingDueDebts.first, isPrivate),
                const SizedBox(height: 18),
              ],

              // 7. Accounts Horizontal Carousel
              _buildAccountsSection(context, accounts, isPrivate),
              const SizedBox(height: 18),

              // 8. Coach Insight Card
              _buildCoachInsightCard(
                context: context,
                safeToSpend: safeToSpend,
                safeToday: safeToday,
                isPrivate: isPrivate,
              ),
              const SizedBox(height: 18),

              // 9. Recent Activity List
              _buildRecentActivitySection(context, ref, transactions, isPrivate),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    WidgetRef ref,
    String displayName,
    bool isPrivate,
  ) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              greeting,
              style: const TextStyle(
                color: AppColors.text3,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Selam, $displayName',
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        Row(
          children: [
            // Privacy Eye Toggle
            IconButton(
              icon: Icon(
                isPrivate ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: AppColors.text2,
                size: 22,
              ),
              tooltip: isPrivate ? 'Show amounts' : 'Hide amounts',
              onPressed: () {
                ref.read(privacyModeProvider.notifier).state = !isPrivate;
              },
            ),
            const SizedBox(width: 4),
            // Avatar Button
            GestureDetector(
              onTap: () => context.push('/more'),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8AA4FF), Color(0xFF6B8AFF)],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.line2, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  displayName.isNotEmpty ? displayName[0].toUpperCase() : 'S',
                  style: const TextStyle(
                    color: Color(0xFF080C14),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHeroBalanceCard({
    required double liquidTotal,
    required double bankTotal,
    required double telebirrTotal,
    required double cashTotal,
    required int activeCount,
    required bool isPrivate,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line2, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'LIQUID BALANCE',
                style: TextStyle(
                  color: AppColors.text3,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surface3.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.line),
                ),
                child: Text(
                  '$activeCount active',
                  style: const TextStyle(
                    color: AppColors.text2,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            formatCurrency(liquidTotal, isPrivate: isPrivate),
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 16),
          // 3-way SplitBar
          SplitBar(
            bankAmount: bankTotal,
            mobileMoneyAmount: telebirrTotal,
            cashAmount: cashTotal,
            isPrivate: isPrivate,
          ),
        ],
      ),
    );
  }

  Widget _buildSafeToSpendCard({
    required double safeToday,
    required double spentToday,
    required double remainingToday,
    required double tomorrowAllowance,
    required double ringProgress,
    required String statusString,
    required bool isPrivate,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Left: 108dp Progress Ring
          ProgressRing(
            progress: ringProgress,
            size: 104,
            strokeWidth: 8,
            progressColor: spentToday > safeToday ? AppColors.expense : AppColors.accent,
            centerChild: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isPrivate
                      ? '••••'
                      : remainingToday > 0
                          ? 'ETB ${remainingToday.toInt()}'
                          : 'ETB 0',
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  remainingToday > 0 ? 'Left' : 'Over',
                  style: const TextStyle(
                    color: AppColors.text3,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Right: Metrics & Status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Safe to spend today',
                      style: TextStyle(
                        color: AppColors.text2,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    StatusPill(status: statusString),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  formatCurrency(safeToday, isPrivate: isPrivate),
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Spent today: ${formatCurrency(spentToday, isPrivate: isPrivate)}',
                  style: const TextStyle(
                    color: AppColors.text3,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tomorrow: ${formatCurrency(tomorrowAllowance, isPrivate: isPrivate)}',
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttentionBanner(BuildContext context, int count) {
    return GestureDetector(
      onTap: () => context.push('/review-inbox'),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.amberBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.amber.withOpacity(0.35)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: AppColors.amber,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.priority_high_rounded, color: Color(0xFF080C14), size: 14),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$count items need a quick look',
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Unclear transfer & balance drop · takes ~20s',
                    style: TextStyle(
                      color: AppColors.text2,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.text3, size: 13),
          ],
        ),
      ),
    );
  }

  Widget _buildUpcomingBillBanner(Map<String, dynamic> debt, bool isPrivate) {
    final name = (debt['counterparty'] ?? debt['title'] ?? 'Due obligation') as String;
    final total = ((debt['total_amount'] ?? debt['amount']) as num?)?.toDouble() ?? 0.0;
    final paid = ((debt['paid_amount'] ?? debt['paid']) as num?)?.toDouble() ?? 0.0;
    final remaining = (total - paid).clamp(0.0, double.infinity);
    final due = (debt['due_date'] ?? 'Upcoming') as String;
    final formattedAmt = formatCurrency(remaining, isPrivate: isPrivate);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.receipt_long_outlined, color: AppColors.accent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$name · $formattedAmt ($due)',
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.surface3,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Upcoming',
              style: TextStyle(
                color: AppColors.text3,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountsSection(
    BuildContext context,
    List<Map<String, dynamic>> accounts,
    bool isPrivate,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'ACCOUNTS & WALLETS',
              style: TextStyle(
                color: AppColors.text3,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            GestureDetector(
              onTap: () => context.push('/accounts'),
              child: const Text(
                'Manage',
                style: TextStyle(
                  color: AppColors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (accounts.isEmpty)
          GestureDetector(
            onTap: () => context.push('/accounts'),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: AppColors.accentBg,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.account_balance_wallet_outlined, color: AppColors.accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'No active accounts connected',
                          style: TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Tap to link bank SMS or add a cash wallet',
                          style: TextStyle(color: AppColors.text3, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.text3, size: 20),
                ],
              ),
            ),
          )
        else
          SizedBox(
            height: 114,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: accounts.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final acc = accounts[index];
                final name = acc['account_name'] as String? ?? 'Account';
                final inst = acc['institution_id'] as String? ?? '';
                final mask = acc['account_number_mask'] as String? ?? '';
                final bal = (acc['last_known_balance'] as num?)?.toDouble() ?? 0.0;
                final isLocked = acc['is_locked'] == 1 || acc['is_locked'] == true;

                return GestureDetector(
                  onTap: () => AccountEditSheet.show(context, account: acc),
                  child: Container(
                    width: 170,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            BrandBadge(institution: inst, size: 24),
                            if (isLocked)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.surface3,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'Locked',
                                  style: TextStyle(
                                    color: AppColors.text3,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.text,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              mask,
                              style: const TextStyle(
                                color: AppColors.text3,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          formatCurrency(bal, isPrivate: isPrivate),
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildCoachInsightCard({
    required BuildContext context,
    required SafeToSpendSummary safeToSpend,
    required double safeToday,
    required bool isPrivate,
  }) {
    String insightText;
    if (safeToSpend.pace == SpendingPace.ahead) {
      insightText = 'Spending is currently ahead of pace. You are maintaining excellent discipline this cycle—extra reserves are protected for your savings goals.';
    } else if (safeToSpend.pace == SpendingPace.caution) {
      insightText = 'Heads up: Spending has accelerated slightly today. Pacing yourself on discretionary expenses over the next 48 hours will restore your target trajectory.';
    } else if (safeToSpend.pace == SpendingPace.deficit) {
      insightText = 'Alert: Today\'s outlays exceeded the daily allowance. Check your Plan envelopes to rebalance discretionary limits.';
    } else {
      if (safeToday > 0) {
        insightText = 'Your spending pace is healthy and within your planned daily allowance of ${formatCurrency(safeToday, isPrivate: isPrivate)}. Keep tracking consistent!';
      } else {
        insightText = 'Welcome to SW Budget! Set up your monthly target in the Plan tab to unlock dynamic daily pacing recommendations.';
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: AppColors.accent, size: 16),
              SizedBox(width: 8),
              Text(
                'Coach insight',
                style: TextStyle(
                  color: AppColors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            insightText,
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => context.push('/coach'),
            child: const Row(
              children: [
                Text(
                  'Ask coach how to allocate',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(width: 4),
                Icon(Icons.arrow_forward_rounded, color: AppColors.accent, size: 13),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivitySection(
    BuildContext context,
    WidgetRef ref,
    List<Map<String, dynamic>> transactions,
    bool isPrivate,
  ) {
    final recent = transactions.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'RECENT ACTIVITY',
              style: TextStyle(
                color: AppColors.text3,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            GestureDetector(
              onTap: () => context.go('/activity'),
              child: const Text(
                'See all',
                style: TextStyle(
                  color: AppColors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (recent.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.line),
            ),
            child: const Text(
              'No recent transactions recorded yet',
              style: TextStyle(color: AppColors.text3, fontSize: 13),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.line),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: recent.length,
              separatorBuilder: (_, __) => const Divider(color: AppColors.line, height: 1),
              itemBuilder: (context, index) {
                final tx = recent[index];
                final rawParty = (tx['counterparty'] ?? tx['merchant'] ?? 'Transaction') as String;
                final party = rawParty.isEmpty ? 'Transaction' : rawParty;
                final type = (tx['type'] as String? ?? 'debit').toLowerCase();
                final isCredit = type == 'credit' || type == 'income';
                final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
                final occurredAt = tx['occurred_at'] as String? ?? '';
                final isVerified = tx['is_verified'] == 1 || tx['is_verified'] == true;

                String timeStr = 'Recently';
                if (occurredAt.isNotEmpty) {
                  final dt = DateTime.tryParse(occurredAt);
                  if (dt != null) {
                    timeStr = DateFormat('h:mm a').format(dt);
                  }
                }

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isCredit ? AppColors.incomeBg : AppColors.surface2,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      isCredit ? Icons.arrow_downward_rounded : Icons.shopping_bag_outlined,
                      color: isCredit ? AppColors.income : AppColors.text2,
                      size: 18,
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          party,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (isVerified) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.verified_rounded, color: AppColors.income, size: 14),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    timeStr,
                    style: const TextStyle(color: AppColors.text3, fontSize: 11),
                  ),
                  trailing: Text(
                    '${isCredit ? '+' : '-'}${formatCurrency(amount, isPrivate: isPrivate)}',
                    style: TextStyle(
                      color: isCredit ? AppColors.income : AppColors.expense,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  onTap: () {
                    final txId = (tx['id'] as String?) ?? '';
                    TransactionDetailSheet.show(
                      context,
                      transaction: tx,
                      onSave: (newCat, newNote) {
                        if (txId.isNotEmpty) {
                          ref.read(transactionControllerProvider).updateDetails(
                                id: txId,
                                category: newCat,
                                note: newNote,
                              );
                        }
                      },
                      onMarkTransfer: () {
                        if (txId.isNotEmpty) {
                          ref.read(transactionControllerProvider).markTransfer(txId);
                        }
                      },
                      onDelete: () {
                        if (txId.isNotEmpty) {
                          ref.read(transactionControllerProvider).delete(txId);
                        }
                      },
                    );
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}

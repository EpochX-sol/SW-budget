import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/security/privacy_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/charts/pace_chart.dart';
import '../../domain/use_cases/plan_evaluation_engine.dart';
import 'plan_providers.dart';
import 'presentation/add_plan_expense_sheet.dart';
import 'presentation/plan_creation_wizard.dart';

class PlanScreen extends ConsumerStatefulWidget {
  const PlanScreen({super.key});

  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen> {
  bool _notCountedExpanded = false;

  @override
  Widget build(BuildContext context) {
    final activePlanAsync = ref.watch(activeBudgetPlanStreamProvider);
    final snapshot = ref.watch(planEvaluationSnapshotProvider);
    final isPrivate = ref.watch(privacyModeProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: activePlanAsync.when(
          data: (plan) {
            if (plan == null) {
              return _buildEmptyState(context);
            }
            if (snapshot == null) {
              return const Center(child: CircularProgressIndicator(color: AppColors.accent));
            }

            final status = (plan['status'] as String? ?? 'active').toLowerCase();
            if (status == 'finished') {
              return _buildFinishedState(context, plan, snapshot);
            }

            final startDate = DateTime.parse(plan['start_date'] as String);
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            if (today.isBefore(startDate)) {
              return _buildNotStartedState(context, plan, startDate);
            }

            return _buildActiveDashboard(context, plan, snapshot, isPrivate, isPaused: status == 'paused');
          },
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
          error: (err, _) => Center(
            child: Text('Error loading plan: $err', style: const TextStyle(color: AppColors.negative)),
          ),
        ),
      ),
      floatingActionButton: snapshot != null && (snapshot.plan['status'] ?? '') != 'finished'
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.background,
              icon: const Icon(Icons.add),
              label: const Text('Add Expense', style: TextStyle(fontWeight: FontWeight.w700)),
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: AppColors.surface,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  builder: (_) => AddPlanExpenseSheet(snapshot: snapshot),
                );
              },
            )
          : null,
    );
  }

  // ==========================================
  // 1. EMPTY STATE
  // ==========================================
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.savings_outlined, color: AppColors.accent, size: 40),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Plan Yet',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Set how much you plan to spend, list your expected bills, and know exactly what you can spend each day.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.text3, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.background,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PlanCreationWizard()),
                );
              },
              child: const Text(
                'Create My Plan',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PlanCreationWizard()),
                );
              },
              child: const Text(
                'Suggest one from my history',
                style: TextStyle(color: AppColors.text3, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // 2. NOT STARTED STATE
  // ==========================================
  Widget _buildNotStartedState(BuildContext context, Map<String, dynamic> plan, DateTime start) {
    final daysUntil = start.difference(DateTime.now()).inDays + 1;
    final planName = plan['name'] as String? ?? 'Upcoming Plan';
    final limit = (plan['spending_limit'] as num?)?.toDouble() ?? 0.0;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.timer_outlined, color: AppColors.accent, size: 54),
            const SizedBox(height: 16),
            Text(
              planName,
              style: const TextStyle(color: AppColors.text, fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Starts in $daysUntil days on ${DateFormat('d MMMM yyyy').format(start)}',
              style: const TextStyle(color: AppColors.text3, fontSize: 14),
            ),
            const SizedBox(height: 20),
            Text(
              'Planned limit: ETB ${NumberFormat('#,##0').format(limit)}',
              style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 32),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.surface3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => _confirmDeletePlan(context, plan['id'] as String),
              child: const Text('Cancel or Delete Plan', style: TextStyle(color: AppColors.negative)),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // 3. FINISHED STATE (One-time Result Card)
  // ==========================================
  Widget _buildFinishedState(
    BuildContext context,
    Map<String, dynamic> plan,
    PlanEvaluationSnapshot snapshot,
  ) {
    final planId = plan['id'] as String;
    final diff = snapshot.spendingLimit - snapshot.totalSpent;
    final isUnder = diff >= 0;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isUnder ? AppColors.positive : AppColors.negative, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('PLAN COMPLETED', style: TextStyle(color: AppColors.text3, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
                  Icon(isUnder ? Icons.check_circle : Icons.warning_amber, color: isUnder ? AppColors.positive : AppColors.negative, size: 24),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                plan['name'] as String? ?? 'Your Spending Plan',
                style: const TextStyle(color: AppColors.text, fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              Text(
                'You spent ETB ${NumberFormat('#,##0').format(snapshot.totalSpent)} of ${NumberFormat('#,##0').format(snapshot.spendingLimit)} '
                '(${isUnder ? 'ETB ${NumberFormat('#,##0').format(diff)} under budget' : 'ETB ${NumberFormat('#,##0').format(-diff)} over plan'}).',
                style: const TextStyle(color: AppColors.text, fontSize: 15, height: 1.4),
              ),
              const Divider(color: AppColors.surface2, height: 32),
              _buildSummaryRow('Period Days', '${snapshot.totalDays} days'),
              _buildSummaryRow('Emergency Reserve', snapshot.emergencyReserve > 0 ? (snapshot.reserveUsed > 0 ? 'Used ETB ${NumberFormat('#,##0').format(snapshot.reserveUsed)}' : 'Untouched') : 'None set'),
              _buildSummaryRow('Expected Expenses', 'Paid ETB ${NumberFormat('#,##0').format(snapshot.totalExpectedPaid)} of ${NumberFormat('#,##0').format(snapshot.totalExpected)}'),
              _buildSummaryRow('Total Not Counted', 'ETB ${NumberFormat('#,##0').format(snapshot.totalNotCountedAmount)} (${snapshot.excludedTransactions.length} txns)'),
              const SizedBox(height: 24),
              const Text(
                'This plan will now be removed so you can start a clean new cycle.',
                style: TextStyle(color: AppColors.text3, fontSize: 12),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.background,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () async {
                  await ref.read(planControllerProvider).deletePlan(planId);
                },
                child: const Text('Close & Create New Plan', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.text3, fontSize: 13)),
          Text(value, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
  }

  // ==========================================
  // 4. ACTIVE DASHBOARD
  // ==========================================
  Widget _buildActiveDashboard(
    BuildContext context,
    Map<String, dynamic> plan,
    PlanEvaluationSnapshot snapshot,
    bool isPrivate, {
    required bool isPaused,
  }) {
    final startDate = DateTime.parse(plan['start_date'] as String);
    final endDate = DateTime.parse(plan['end_date'] as String);
    final dateRangeStr = '${DateFormat('d MMM').format(startDate)} – ${DateFormat('d MMM yyyy').format(endDate)}';

    // 3-Zone dynamic colors
    Color zoneColor = AppColors.positive;
    String zoneText = 'Within budget';
    if (snapshot.zone == PlanBudgetZone.usingReserve) {
      zoneColor = AppColors.warning;
      zoneText = 'Using reserve: ${NumberFormat('#,##0').format(snapshot.reserveUsed)} of ${NumberFormat('#,##0').format(snapshot.emergencyReserve)}';
    } else if (snapshot.zone == PlanBudgetZone.overPlan) {
      zoneColor = AppColors.negative;
      zoneText = 'Over plan by ETB ${NumberFormat('#,##0').format(snapshot.overspendAmount)}';
    }

    final double progress = snapshot.spendableBudget > 0
        ? (snapshot.totalSpent / snapshot.spendableBudget).clamp(0.0, 1.0)
        : 1.0;

    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      onRefresh: () async {
        ref.invalidate(activeBudgetPlanStreamProvider);
        ref.invalidate(allPlanTransactionsStreamProvider);
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // 1. Paused Banner (if paused)
          if (isPaused) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.text3.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.pause_circle_outline, color: AppColors.text2, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Plan is paused. Daily allowance is frozen.',
                      style: TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton(
                    onPressed: () => ref.read(planControllerProvider).resumePlan(plan['id'] as String),
                    child: const Text('Resume', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ],

          // 2. Header: Title, Dates, Days Left, Watched Banks Chip & Menu
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan['name'] as String? ?? 'Spending Plan',
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$dateRangeStr · ${snapshot.daysRemaining} days left',
                      style: const TextStyle(color: AppColors.text3, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: AppColors.text3),
                color: AppColors.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (val) => _handleMenuAction(context, plan, val),
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: isPaused ? 'resume' : 'pause',
                    child: Row(
                      children: [
                        Icon(isPaused ? Icons.play_arrow : Icons.pause, size: 18, color: AppColors.text),
                        const SizedBox(width: 10),
                        Text(isPaused ? 'Resume Plan' : 'Pause Plan', style: const TextStyle(color: AppColors.text)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'expected_expenses',
                    child: Row(
                      children: [
                        Icon(Icons.receipt_long, size: 18, color: AppColors.text),
                        const SizedBox(width: 10),
                        Text('Expected Expenses', style: TextStyle(color: AppColors.text)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 18, color: AppColors.negative),
                        const SizedBox(width: 10),
                        Text('Delete Plan', style: TextStyle(color: AppColors.negative)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 3. Hero Card: Left to Spend + 3-Zone Progress + Tap for Details
          GestureDetector(
            onTap: () => _showCalculationBreakdownSheet(context, snapshot),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: zoneColor.withOpacity(0.3), width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('LEFT TO SPEND', style: TextStyle(color: AppColors.text3, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: zoneColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          zoneText,
                          style: TextStyle(color: zoneColor, fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isPrivate ? '••••••' : 'ETB ${NumberFormat('#,##0').format(snapshot.leftToSpend)}',
                    style: TextStyle(
                      color: snapshot.leftToSpend < 0 ? AppColors.negative : AppColors.text,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.0,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: AppColors.surface2,
                      valueColor: AlwaysStoppedAnimation<Color>(zoneColor),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Spent: ${NumberFormat('#,##0').format(snapshot.totalSpent)}',
                        style: const TextStyle(color: AppColors.text3, fontSize: 12),
                      ),
                      Text(
                        'Budget: ${NumberFormat('#,##0').format(snapshot.spendableBudget)}',
                        style: const TextStyle(color: AppColors.text3, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // 4. Today & Tomorrow Allowance Cards
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('TODAY\'S ALLOWANCE', style: TextStyle(color: AppColors.text3, fontSize: 10, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text(
                        isPrivate ? '••••' : 'ETB ${NumberFormat('#,##0').format(snapshot.todayRemaining)}',
                        style: const TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'of ${NumberFormat('#,##0').format(snapshot.todayAllowance)} allowance',
                        style: const TextStyle(color: AppColors.text3, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('TOMORROW', style: TextStyle(color: AppColors.text3, fontSize: 10, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text(
                        isPrivate ? '••••' : 'ETB ${NumberFormat('#,##0').format(snapshot.tomorrowAllowance)}',
                        style: const TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${snapshot.tomorrowPctOfNormal.toStringAsFixed(0)}% of normal day',
                        style: const TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 5. Pace & Runway Indicator
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                Icon(
                  snapshot.paceStatus == 'under'
                      ? Icons.trending_down
                      : snapshot.paceStatus == 'over'
                          ? Icons.trending_up
                          : Icons.trending_flat,
                  color: snapshot.paceStatus == 'under'
                      ? AppColors.positive
                      : snapshot.paceStatus == 'over'
                          ? AppColors.negative
                          : AppColors.accent,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    snapshot.paceStatus == 'over'
                        ? (snapshot.projectedRunwayDate != null
                            ? 'At this pace your budget runs out around ${DateFormat('d MMMM').format(snapshot.projectedRunwayDate!)}'
                            : 'Spending is faster than planned daily pace')
                        : snapshot.paceStatus == 'under'
                            ? 'You are spending under pace. Savings are smoothing into tomorrow.'
                            : 'You are on track with your planned pace.',
                    style: const TextStyle(color: AppColors.text, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // 6. Expected Expenses Card (Section 8.3)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('EXPECTED EXPENSES', style: TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w800)),
                    TextButton.icon(
                      icon: const Icon(Icons.add, size: 15, color: AppColors.accent),
                      label: const Text('Add', style: TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.w700)),
                      onPressed: () => _showAddExpectedExpenseSheet(context, plan['id'] as String),
                    ),
                  ],
                ),
                Text(
                  'Expected: ${NumberFormat('#,##0').format(snapshot.totalExpected)} · '
                  'Paid: ${NumberFormat('#,##0').format(snapshot.totalExpectedPaid)} · '
                  'To pay: ${NumberFormat('#,##0').format(snapshot.totalExpectedToPay)}',
                  style: const TextStyle(color: AppColors.text3, fontSize: 12),
                ),
                const SizedBox(height: 12),
                if (snapshot.expectedExpenses.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No expected expenses. Known costs (rent, school fee) sit outside your limit.', style: TextStyle(color: AppColors.text3, fontSize: 12)),
                  )
                else
                  ...snapshot.expectedExpenses.map((exp) {
                    final id = exp['id'] as String;
                    final name = exp['name'] as String? ?? 'Expense';
                    final amount = (exp['amount'] as num).toDouble();
                    final isPaid = (exp['status'] as String? ?? '').toLowerCase() == 'paid';
                    final due = exp['due_date'] as String?;

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => ref.read(planControllerProvider).toggleExpectedExpensePaid(id, isPaid),
                            child: Icon(
                              isPaid ? Icons.check_circle : Icons.radio_button_unchecked,
                              color: isPaid ? AppColors.positive : AppColors.text3,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: TextStyle(
                                    color: isPaid ? AppColors.text3 : AppColors.text,
                                    fontWeight: FontWeight.w600,
                                    decoration: isPaid ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                                if (due != null)
                                  Text('Due: $due', style: const TextStyle(color: AppColors.text3, fontSize: 11)),
                              ],
                            ),
                          ),
                          Text('ETB ${NumberFormat('#,##0').format(amount)}', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // 7. Weekly Chunks View (7-Day Target vs Spent)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('WEEKLY BREAKDOWN', style: TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                ...snapshot.weeklyChunks.map((w) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: w.status == 'Now'
                                ? AppColors.accent.withOpacity(0.15)
                                : AppColors.surface2,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'W${w.weekNumber}',
                            style: TextStyle(
                              color: w.status == 'Now' ? AppColors.accent : AppColors.text3,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(w.label, style: const TextStyle(color: AppColors.text, fontSize: 12, fontWeight: FontWeight.w600)),
                              Text('Target: ${NumberFormat('#,##0').format(w.plannedTarget)}', style: const TextStyle(color: AppColors.text3, fontSize: 11)),
                            ],
                          ),
                        ),
                        Text(
                          'Spent: ${NumberFormat('#,##0').format(w.spent)}',
                          style: TextStyle(
                            color: w.spent > w.plannedTarget ? AppColors.negative : AppColors.text,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // 8. Spending Chart (PaceChart)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('IDEAL VS ACTUAL SPENDING', style: TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                SizedBox(
                  height: 140,
                  child: PaceChart(
                    totalDays: snapshot.totalDays,
                    currentDay: snapshot.daysElapsed,
                    budget: snapshot.spendableBudget,
                    spentByDay: snapshot.weeklyChunks.map((w) => w.spent).toList(),
                    height: 140,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // 9. Not Counted Breakdown Banner & List (Section 5)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('NOT COUNTED IN PLAN', style: TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(
                          'Total: ETB ${NumberFormat('#,##0').format(snapshot.totalNotCountedAmount)} (${snapshot.excludedTransactions.length} txns)',
                          style: const TextStyle(color: AppColors.text3, fontSize: 12),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: Icon(_notCountedExpanded ? Icons.expand_less : Icons.expand_more, color: AppColors.accent),
                      onPressed: () => setState(() => _notCountedExpanded = !_notCountedExpanded),
                    ),
                  ],
                ),
                if (_notCountedExpanded) ...[
                  const Divider(color: AppColors.surface2, height: 20),
                  ...snapshot.excludedTransactions.map((t) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(10)),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.counterparty ?? t.type.toUpperCase(),
                                  style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                                const SizedBox(height: 2),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface3,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    t.exclusionReason ?? 'Excluded',
                                    style: const TextStyle(color: AppColors.accent, fontSize: 10, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text('ETB ${NumberFormat('#,##0').format(t.amount)}', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
                          IconButton(
                            icon: const Icon(Icons.undo, size: 16, color: AppColors.text3),
                            tooltip: 'Count in plan',
                            onPressed: () {
                              ref.read(planControllerProvider).toggleTransactionPlanExclusion(t.id, exclude: false);
                            },
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),

          // 10. Your Rules Summary Pill
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                const Icon(Icons.tune, color: AppColors.text3, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Rules: ${plan['reaction_mode'] == 'adaptive' ? 'Adaptive rebalancing' : 'Fixed daily allowance'} · '
                    '${plan['count_fees'] == 1 ? 'Fees counted' : 'Fees omitted'} · '
                    '${plan['count_withdrawals'] == 1 ? 'Cash counted' : 'Cash omitted'}',
                    style: const TextStyle(color: AppColors.text3, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 80), // Padding for FloatingActionButton
        ],
      ),
    );
  }

  // --- MODAL SHEETS & ACTIONS ---

  void _showCalculationBreakdownSheet(BuildContext context, PlanEvaluationSnapshot snapshot) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('How Your Plan is Calculated', style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            _buildCalcRow('Everyday Spending Limit', 'ETB ${NumberFormat('#,##0').format(snapshot.spendingLimit)}'),
            if (snapshot.emergencyReserve > 0)
              _buildCalcRow('− Emergency Reserve', 'ETB ${NumberFormat('#,##0').format(snapshot.emergencyReserve)}'),
            _buildCalcRow('= Spendable Budget', 'ETB ${NumberFormat('#,##0').format(snapshot.spendableBudget)}'),
            _buildCalcRow('− Counted Spending', 'ETB ${NumberFormat('#,##0').format(snapshot.totalSpent)}'),
            const Divider(color: AppColors.surface2, height: 24),
            _buildCalcRow('Left to Spend', 'ETB ${NumberFormat('#,##0').format(snapshot.leftToSpend)}', isBold: true),
            const SizedBox(height: 12),
            Text(
              'Expected expenses (${NumberFormat('#,##0').format(snapshot.totalExpected)}) sit outside this number and do not change it.',
              style: const TextStyle(color: AppColors.text3, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalcRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: isBold ? AppColors.text : AppColors.text3, fontWeight: isBold ? FontWeight.w700 : FontWeight.w500)),
          Text(value, style: TextStyle(color: isBold ? AppColors.accent : AppColors.text, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  void _showAddExpectedExpenseSheet(BuildContext context, String planId) {
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Add Expected Expense', style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            TextField(
              controller: nameCtrl,
              style: const TextStyle(color: AppColors.text),
              decoration: InputDecoration(
                hintText: 'Name (e.g. House rent, School fees)',
                filled: true,
                fillColor: AppColors.surface2,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppColors.text),
              decoration: InputDecoration(
                hintText: 'Amount (ETB)',
                filled: true,
                fillColor: AppColors.surface2,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.background,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                final name = nameCtrl.text.trim();
                final amt = double.tryParse(amountCtrl.text.trim()) ?? 0.0;
                if (name.isNotEmpty && amt > 0) {
                  ref.read(planControllerProvider).addExpectedExpense(
                    planId: planId,
                    name: name,
                    amount: amt,
                  );
                  Navigator.of(ctx).pop();
                }
              },
              child: const Text('Add to Plan', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  void _handleMenuAction(BuildContext context, Map<String, dynamic> plan, String action) {
    final planId = plan['id'] as String;
    switch (action) {
      case 'pause':
        ref.read(planControllerProvider).pausePlan(planId);
        break;
      case 'resume':
        ref.read(planControllerProvider).resumePlan(planId);
        break;
      case 'expected_expenses':
        _showAddExpectedExpenseSheet(context, planId);
        break;
      case 'delete':
        _confirmDeletePlan(context, planId);
        break;
    }
  }

  void _confirmDeletePlan(BuildContext context, String planId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Delete this plan?', style: TextStyle(color: AppColors.text)),
        content: const Text(
          'Your transactions are not affected. You will have 8 seconds to undo.',
          style: TextStyle(color: AppColors.text3),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: AppColors.text3)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.negative),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final backupPlan = ref.read(activeBudgetPlanStreamProvider).value;
              await ref.read(planControllerProvider).deletePlan(planId);

              // 8-second animated undo snackbar
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    duration: const Duration(seconds: 8),
                    backgroundColor: AppColors.surface,
                    content: const Text('Plan deleted', style: TextStyle(color: AppColors.text)),
                    action: SnackBarAction(
                      label: 'Undo',
                      textColor: AppColors.accent,
                      onPressed: () {
                        if (backupPlan != null) {
                          ref.read(planControllerProvider).createPlan(
                            name: backupPlan['name'] as String,
                            periodType: backupPlan['period_type'] as String,
                            startDate: DateTime.parse(backupPlan['start_date'] as String),
                            endDate: DateTime.parse(backupPlan['end_date'] as String),
                            spendingLimit: (backupPlan['spending_limit'] as num).toDouble(),
                          );
                        }
                      },
                    ),
                  ),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

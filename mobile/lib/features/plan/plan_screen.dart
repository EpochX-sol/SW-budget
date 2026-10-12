import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/security/privacy_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/charts/pace_chart.dart';
import '../../core/widgets/progress_ring.dart';
import '../../core/widgets/status_pill.dart';
import '../../core/widgets/tick_bar.dart';
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
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Plan',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.accentBg,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(Icons.track_changes_rounded, color: AppColors.accent, size: 34),
                ),
                const SizedBox(height: 20),
                const Text(
                  'No active plan',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Pick a period and a limit. We split it into days and weeks and keep re-balancing as you spend.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.text2, fontSize: 14, height: 1.45),
                ),
                const SizedBox(height: 26),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.onAccent,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    elevation: 0,
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PlanCreationWizard()),
                    );
                  },
                  child: const Text('Create a plan', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ],
            ),
          ),
        ],
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
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.accentBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.timer_outlined, color: AppColors.accent, size: 30),
              ),
              const SizedBox(height: 18),
              Text(
                planName,
                style: const TextStyle(color: AppColors.text, fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Starts in $daysUntil days on ${DateFormat('d MMMM yyyy').format(start)}',
                style: const TextStyle(color: AppColors.text3, fontSize: 14),
              ),
              const SizedBox(height: 16),
              Text(
                'Planned limit: ETB ${NumberFormat('#,##0').format(limit)}',
                style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.surface3),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  minimumSize: const Size(double.infinity, 46),
                ),
                onPressed: () => _confirmDeletePlan(context, plan['id'] as String),
                child: const Text('Cancel or Delete Plan', style: TextStyle(color: AppColors.expense, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // 3. FINISHED STATE
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
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: isUnder ? AppColors.income.withValues(alpha: 0.4) : AppColors.expense.withValues(alpha: 0.4), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('PLAN COMPLETED', style: TextStyle(color: AppColors.text3, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
                  Icon(isUnder ? Icons.check_circle_rounded : Icons.warning_rounded, color: isUnder ? AppColors.income : AppColors.expense, size: 24),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                plan['name'] as String? ?? 'Your Spending Plan',
                style: const TextStyle(color: AppColors.text, fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              Text(
                'You spent ETB ${NumberFormat('#,##0').format(snapshot.totalSpent)} of ${NumberFormat('#,##0').format(snapshot.spendingLimit)} '
                '(${isUnder ? 'ETB ${NumberFormat('#,##0').format(diff)} under budget' : 'ETB ${NumberFormat('#,##0').format(-diff)} over plan'}).',
                style: const TextStyle(color: AppColors.text2, fontSize: 14.5, height: 1.4),
              ),
              const Divider(color: AppColors.line, height: 32),
              _buildSummaryRow('Period Days', '${snapshot.totalDays} days'),
              _buildSummaryRow('Emergency Reserve', snapshot.emergencyReserve > 0 ? (snapshot.reserveUsed > 0 ? 'Used ETB ${NumberFormat('#,##0').format(snapshot.reserveUsed)}' : 'Untouched') : 'None set'),
              _buildSummaryRow('Expected Expenses', 'Paid ETB ${NumberFormat('#,##0').format(snapshot.totalExpectedPaid)} of ${NumberFormat('#,##0').format(snapshot.totalExpected)}'),
              _buildSummaryRow('Total Not Counted', 'ETB ${NumberFormat('#,##0').format(snapshot.totalNotCountedAmount)} (${snapshot.excludedTransactions.length} txns)'),
              const SizedBox(height: 24),
              const Text(
                'This plan will now be removed so you can start a clean new cycle.',
                style: TextStyle(color: AppColors.text3, fontSize: 12),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.onAccent,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () async {
                  await ref.read(planControllerProvider).deletePlan(planId);
                },
                child: const Text('Close & Create New Plan', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.text2, fontSize: 13.5)),
          Text(value, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 13.5)),
        ],
      ),
    );
  }

  // ==========================================
  // 4. ACTIVE DASHBOARD (Exact Prototype Layout)
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
    final periodTypeStr = (plan['period_type'] as String? ?? 'monthly').toUpperCase();

    // 1. Burn ratio & prototype-accurate status pill
    final expectedPrev = snapshot.dailyPlanBaseline * (snapshot.daysElapsed - 1);
    final spentPrev = snapshot.totalSpent - snapshot.todaySpent;
    final burn = expectedPrev > 0 ? (spentPrev / expectedPrev) : 1.0;

    String status = 'ON TRACK';
    if (snapshot.leftToSpend <= 0 || burn > 1.25 || snapshot.zone == PlanBudgetZone.overPlan) {
      status = 'DEFICIT';
    } else if (burn > 1.05 || snapshot.zone == PlanBudgetZone.usingReserve) {
      status = 'CAUTION';
    } else if (burn < 0.95) {
      status = 'AHEAD';
    }

    // 2. Used % & dynamic ring color
    final usedPct = snapshot.todayAllowance > 0
        ? (snapshot.todaySpent / snapshot.todayAllowance * 100.0)
        : 100.0;
    final Color ringColor = snapshot.todayRemaining < 0
        ? AppColors.expense
        : (usedPct > 80 ? AppColors.amber : AppColors.income);

    // 3. Cycle progress %
    final cyclePct = snapshot.totalDays > 0
        ? ((snapshot.daysElapsed - 1) / snapshot.totalDays * 100.0).clamp(0.0, 100.0)
        : 0.0;

    // 4. Tomorrow & Next week differences vs baseline
    final tomorrowDiffPct = snapshot.dailyPlanBaseline > 0
        ? ((snapshot.tomorrowAllowance / snapshot.dailyPlanBaseline - 1.0) * 100.0)
        : 0.0;

    PlanWeekChunk? nextWeek;
    for (int i = 0; i < snapshot.weeklyChunks.length; i++) {
      if (snapshot.weeklyChunks[i].status == 'Now') {
        if (i + 1 < snapshot.weeklyChunks.length) {
          nextWeek = snapshot.weeklyChunks[i + 1];
        }
        break;
      }
    }
    final nextWeekDiffPct = (nextWeek != null && nextWeek.plannedTarget > 0)
        ? ((nextWeek.plannedTarget / (snapshot.dailyPlanBaseline * 7) - 1.0) * 100.0)
        : 0.0;

    // 5. Pace calculations
    final dailySpents = _buildDailySpents(snapshot, plan);
    final avgDaily = snapshot.daysElapsed > 0 ? (snapshot.totalSpent / snapshot.daysElapsed) : 0.0;
    final daysAfter = snapshot.totalDays - snapshot.daysElapsed;
    final projectedFinish = snapshot.totalSpent + (avgDaily * daysAfter);
    final overBy = projectedFinish - snapshot.spendableBudget;

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
          // A. Paused Banner (if paused)
          if (isPaused) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.text3.withValues(alpha: 0.4)),
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

          // B. Top Bar: Header & Action Menu
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Plan',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$periodTypeStr · $dateRangeStr',
                      style: const TextStyle(color: AppColors.text3, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.line),
                ),
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: AppColors.text2, size: 20),
                  padding: EdgeInsets.zero,
                  color: AppColors.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.line)),
                  onSelected: (val) => _handleMenuAction(context, plan, val, snapshot),
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
                      value: 'breakdown',
                      child: Row(
                        children: [
                          Icon(Icons.calculate_outlined, size: 18, color: AppColors.text),
                          const SizedBox(width: 10),
                          Text('Calculation Info', style: TextStyle(color: AppColors.text)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 18, color: AppColors.expense),
                          const SizedBox(width: 10),
                          Text('Delete Plan', style: TextStyle(color: AppColors.expense)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // C. Hero Card (Prototype Gradient & Circular Ring Gauge)
          GestureDetector(
            onTap: () => _showCalculationBreakdownSheet(context, snapshot),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppColors.heroGradient,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: AppColors.line2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Row: Safe to spend today + Status pill
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Safe to spend today',
                        style: TextStyle(
                          color: AppColors.text3,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                      StatusPill(status: status),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Middle Row: Circular Gauge + Allowance Values
                  Row(
                    children: [
                      ProgressRing(
                        percentage: usedPct,
                        size: 96,
                        strokeWidth: 10,
                        color: ringColor,
                        centerChild: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isPrivate ? '••' : '${usedPct.round()}%',
                              style: const TextStyle(
                                color: AppColors.text,
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Text(
                              'used',
                              style: TextStyle(
                                color: AppColors.text3,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isPrivate ? '••••••' : 'ETB ${NumberFormat('#,##0').format(snapshot.todayAllowance)}',
                              style: const TextStyle(
                                color: AppColors.text,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: isPrivate
                                        ? '•••• '
                                        : 'ETB ${NumberFormat('#,##0').format(snapshot.todayRemaining.abs())} ',
                                    style: TextStyle(
                                      color: snapshot.todayRemaining < 0 ? AppColors.expense : AppColors.text,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  TextSpan(
                                    text: snapshot.todayRemaining >= 0 ? 'left today' : 'over today\'s allowance',
                                    style: TextStyle(
                                      color: snapshot.todayRemaining < 0 ? AppColors.expense : AppColors.text2,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isPrivate
                                  ? '•• spent · base ••/day'
                                  : 'ETB ${NumberFormat('#,##0').format(snapshot.todaySpent)} spent · base ETB ${NumberFormat('#,##0').format(snapshot.dailyPlanBaseline)}/day',
                              style: const TextStyle(
                                color: AppColors.text3,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Bottom Row: Days passed & Days left + Progress Bar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${snapshot.daysElapsed - 1} days passed',
                        style: const TextStyle(color: AppColors.text2, fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                      Text(
                        '${snapshot.daysRemaining} days left',
                        style: const TextStyle(color: AppColors.text2, fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TickBar(
                    percentage: cyclePct,
                    color: AppColors.accent,
                    height: 8,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // D. Two-Column Stat Cards (Tomorrow & Next Week / Runway)
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TOMORROW',
                        style: TextStyle(
                          color: AppColors.text3,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isPrivate ? '••••' : 'ETB ${NumberFormat('#,##0').format(snapshot.tomorrowAllowance)}',
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isPrivate
                            ? '••'
                            : (tomorrowDiffPct >= 0
                                ? '+${tomorrowDiffPct.toStringAsFixed(1)}% vs base'
                                : '${tomorrowDiffPct.toStringAsFixed(1)}% vs base'),
                        style: TextStyle(
                          color: tomorrowDiffPct < 0 ? AppColors.amber : AppColors.income,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nextWeek != null ? 'NEXT WEEK' : 'RUNWAY',
                        style: const TextStyle(
                          color: AppColors.text3,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isPrivate
                            ? '••••'
                            : (nextWeek != null
                                ? 'ETB ${NumberFormat('#,##0').format(nextWeek.plannedTarget)}'
                                : (snapshot.projectedRunwayDate != null
                                    ? DateFormat('d MMM').format(snapshot.projectedRunwayDate!)
                                    : 'On plan')),
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        nextWeek != null
                            ? (nextWeekDiffPct >= 0
                                ? '+${nextWeekDiffPct.toStringAsFixed(1)}% vs base'
                                : '${nextWeekDiffPct.toStringAsFixed(1)}% vs base')
                            : (snapshot.daysRemaining > 0 ? '${snapshot.daysRemaining} days left' : 'Plan ends'),
                        style: TextStyle(
                          color: nextWeekDiffPct < 0 ? AppColors.amber : AppColors.income,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // E. Capacity Section
          const Text('Capacity', style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              children: [
                _buildCapacityRow('Planned budget', isPrivate ? '••••' : 'ETB ${NumberFormat('#,##0').format(snapshot.spendingLimit)}'),
                const Divider(color: AppColors.line, height: 1),
                _buildCapacityRow('Spent so far', isPrivate ? '••••' : 'ETB ${NumberFormat('#,##0').format(snapshot.totalSpent)}'),
                const Divider(color: AppColors.line, height: 1),
                _buildCapacityRow('Upcoming bills reserved', isPrivate ? '••••' : 'ETB ${NumberFormat('#,##0').format(snapshot.totalExpectedToPay)}'),
                if (snapshot.emergencyReserve > 0) ...[
                  const Divider(color: AppColors.line, height: 1),
                  _buildCapacityRow('Emergency reserve', isPrivate ? '••••' : 'ETB ${NumberFormat('#,##0').format(snapshot.emergencyReserve)}'),
                ],
                const Divider(color: AppColors.line, height: 1),
                _buildCapacityRow(
                  'Available to spend',
                  isPrivate ? '••••' : 'ETB ${NumberFormat('#,##0').format(snapshot.leftToSpend)}',
                  valueColor: snapshot.leftToSpend < 0 ? AppColors.expense : AppColors.income,
                ),
                const Divider(color: AppColors.line, height: 1),
                _buildCapacityRow(
                  'Burn ratio',
                  '',
                  trailingWidget: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isPrivate ? '••' : '${burn.toStringAsFixed(2)}×',
                        style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        burn > 1.0 ? 'faster than plan' : 'slower than plan',
                        style: const TextStyle(color: AppColors.text3, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // F. Pace Section with PaceChart & Pacing Advice Banner
          const Text('Pace', style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PaceChart(
                  totalDays: snapshot.totalDays,
                  currentDay: snapshot.daysElapsed,
                  budget: snapshot.spendableBudget,
                  spentByDay: dailySpents,
                  height: 160,
                  isMasked: isPrivate,
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: overBy > 0 ? AppColors.amberBg : AppColors.inBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: overBy > 0
                          ? AppColors.amber.withValues(alpha: 0.3)
                          : AppColors.income.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        overBy > 0 ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
                        color: overBy > 0 ? AppColors.amber : AppColors.income,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          overBy > 0
                              ? (snapshot.projectedRunwayDate != null
                                  ? 'At this pace you\'d overspend by ETB ${NumberFormat('#,##0').format(overBy)} and run out around ${DateFormat('d MMM').format(snapshot.projectedRunwayDate!)}.'
                                  : 'At this pace you\'d overspend by ETB ${NumberFormat('#,##0').format(overBy)}.')
                              : 'At this pace you\'ll finish with ETB ${NumberFormat('#,##0').format(-overBy)} to spare.',
                          style: const TextStyle(color: AppColors.text2, fontSize: 13, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // G. Weeks Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('Weeks', style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w800)),
              Text('Adjusted to stay on plan', style: TextStyle(color: AppColors.text3, fontSize: 12.5, fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              children: snapshot.weeklyChunks.asMap().entries.map((entry) {
                final idx = entry.key;
                final w = entry.value;
                final pctUsed = w.plannedTarget > 0 ? (w.spent / w.plannedTarget * 100.0) : 0.0;
                final daysInWeek = w.endDate.difference(w.startDate).inDays + 1;
                final elapsedInWeek = (DateTime.now().difference(w.startDate).inDays + 1).clamp(0, daysInWeek);
                final pctElapsed = daysInWeek > 0 ? (elapsedInWeek / daysInWeek * 100.0) : 0.0;
                final isOver = w.spent > w.plannedTarget;
                final Color barColor = isOver
                    ? AppColors.expense
                    : (pctUsed > pctElapsed + 5 ? AppColors.amber : AppColors.income);

                return Column(
                  children: [
                    if (idx > 0) const Divider(color: AppColors.line, height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Week ${w.weekNumber}',
                                    style: const TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${DateFormat('d MMM').format(w.startDate)} – ${DateFormat('d MMM').format(w.endDate)}',
                                    style: const TextStyle(color: AppColors.text3, fontSize: 12.5),
                                  ),
                                ],
                              ),
                              if (w.status == 'Now')
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                  decoration: BoxDecoration(color: AppColors.accentBg, borderRadius: BorderRadius.circular(999)),
                                  child: const Text('Now', style: TextStyle(color: AppColors.accent, fontSize: 11.5, fontWeight: FontWeight.w700)),
                                )
                              else if (w.status == 'Done')
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                  decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(999)),
                                  child: const Text('Done', style: TextStyle(color: AppColors.text3, fontSize: 11.5, fontWeight: FontWeight.w700)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              RichText(
                                text: TextSpan(
                                  children: [
                                    const TextSpan(text: 'Spent ', style: TextStyle(color: AppColors.text2, fontSize: 13)),
                                    TextSpan(
                                      text: isPrivate ? '••••' : 'ETB ${NumberFormat('#,##0').format(w.spent)}',
                                      style: TextStyle(
                                        color: isOver ? AppColors.expense : AppColors.text,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              RichText(
                                text: TextSpan(
                                  children: [
                                    const TextSpan(text: 'Target ', style: TextStyle(color: AppColors.text2, fontSize: 13)),
                                    TextSpan(
                                      text: isPrivate ? '••••' : 'ETB ${NumberFormat('#,##0').format(w.plannedTarget)}',
                                      style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TickBar(
                            percentage: pctUsed,
                            color: barColor,
                            ticks: w.status == 'Now' ? [pctElapsed] : const [],
                            height: 8,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            w.status == 'Now'
                                ? (isPrivate ? '••' : '${pctUsed.round()}% of target used · ${pctElapsed.round()}% of week elapsed')
                                : 'Base ETB ${NumberFormat('#,##0').format(w.plannedTarget)}',
                            style: const TextStyle(color: AppColors.text3, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 24),

          // H. Upcoming Bills / Expected Expenses Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Upcoming bills', style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w800)),
                  SizedBox(height: 2),
                  Text('Tracked separately · Excluded from daily limit', style: TextStyle(color: AppColors.text3, fontSize: 12)),
                ],
              ),
              TextButton(
                onPressed: () => _showAddExpectedExpenseSheet(context, plan['id'] as String),
                child: const Text('+ Add', style: TextStyle(color: AppColors.accent, fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.line),
            ),
            child: snapshot.expectedExpenses.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.receipt_long_outlined, color: AppColors.text3.withValues(alpha: 0.5), size: 36),
                          const SizedBox(height: 8),
                          const Text(
                            'No expected expenses yet',
                            style: TextStyle(color: AppColors.text2, fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Add rent, school fee or debt payments to sit safely outside your daily limit.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.text3, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  )
                : Column(
                    children: snapshot.expectedExpenses.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final exp = entry.value;
                      final id = exp['id'] as String;
                      final name = exp['name'] as String? ?? 'Expense';
                      final amount = (exp['amount'] as num).toDouble();
                      final isPaid = (exp['status'] as String? ?? '').toLowerCase() == 'paid';
                      final due = exp['due_date'] as String?;

                      return Column(
                        children: [
                          if (idx > 0) const Divider(color: AppColors.line, height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: isPaid ? AppColors.inBg : AppColors.surface2,
                                    borderRadius: BorderRadius.circular(13),
                                  ),
                                  child: Icon(
                                    isPaid ? Icons.check_rounded : Icons.bolt_rounded,
                                    color: isPaid ? AppColors.income : AppColors.accent,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: TextStyle(
                                          color: isPaid ? AppColors.text3 : AppColors.text,
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w600,
                                          decoration: isPaid ? TextDecoration.lineThrough : null,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        isPaid ? 'Paid' : (due != null ? 'Due $due · reserved' : 'Reserved outside limit'),
                                        style: const TextStyle(color: AppColors.text3, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  isPrivate ? '••••' : 'ETB ${NumberFormat('#,##0').format(amount)}',
                                  style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 15),
                                ),
                                const SizedBox(width: 8),
                                if (!isPaid)
                                  OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                      minimumSize: const Size(48, 32),
                                      side: const BorderSide(color: AppColors.line2),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      backgroundColor: AppColors.surface2,
                                    ),
                                    onPressed: () => ref.read(planControllerProvider).toggleExpectedExpensePaid(id, false),
                                    child: const Text('Paid', style: TextStyle(color: AppColors.text, fontSize: 12, fontWeight: FontWeight.w600)),
                                  )
                                else
                                  GestureDetector(
                                    onTap: () => ref.read(planControllerProvider).toggleExpectedExpensePaid(id, true),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(color: AppColors.inBg, borderRadius: BorderRadius.circular(8)),
                                      child: const Text('Paid ✓', style: TextStyle(color: AppColors.income, fontSize: 11.5, fontWeight: FontWeight.w700)),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 24),

          // I. Not Counted in Plan Section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('NOT COUNTED IN PLAN', style: TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                        const SizedBox(height: 3),
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
                  const Divider(color: AppColors.line, height: 20),
                  ...snapshot.excludedTransactions.map((t) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.counterparty ?? t.type.toUpperCase(),
                                  style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 13.5),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface3,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    t.exclusionReason ?? 'Excluded',
                                    style: const TextStyle(color: AppColors.accent, fontSize: 10.5, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            isPrivate ? '••••' : 'ETB ${NumberFormat('#,##0').format(t.amount)}',
                            style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.undo, size: 18, color: AppColors.text3),
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
          const SizedBox(height: 14),

          // J. Your Rules Summary Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                const Icon(Icons.tune_rounded, color: AppColors.text3, size: 18),
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
          const SizedBox(height: 88), // Extra space for FAB
        ],
      ),
    );
  }

  Widget _buildCapacityRow(String label, String value, {Color? valueColor, Widget? trailingWidget}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.text2, fontSize: 14)),
          if (trailingWidget != null)
            trailingWidget
          else
            Text(
              value,
              style: TextStyle(
                color: valueColor ?? AppColors.text,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }

  List<double> _buildDailySpents(PlanEvaluationSnapshot snapshot, Map<String, dynamic> plan) {
    final startDateRaw = DateTime.parse(plan['start_date'] as String);
    final startDate = DateTime(startDateRaw.year, startDateRaw.month, startDateRaw.day);
    final days = snapshot.daysElapsed;
    final daily = List<double>.filled(days > 0 ? days : 1, 0.0);

    for (final t in snapshot.countedTransactions) {
      final d = DateTime(t.occurredAt.year, t.occurredAt.month, t.occurredAt.day);
      final idx = d.difference(startDate).inDays;
      if (idx >= 0 && idx < daily.length) {
        daily[idx] += t.netImpact;
      }
    }
    return daily;
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

  void _handleMenuAction(BuildContext context, Map<String, dynamic> plan, String action, PlanEvaluationSnapshot snapshot) {
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
      case 'breakdown':
        _showCalculationBreakdownSheet(context, snapshot);
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

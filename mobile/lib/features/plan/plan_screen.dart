import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/security/privacy_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/charts/pace_chart.dart';
import '../../core/widgets/progress_ring.dart';
import '../../core/widgets/sheets/envelope_edit_sheet.dart';
import '../../core/widgets/sheets/goal_edit_sheet.dart';
import '../../core/widgets/sheets/plan_edit_sheet.dart';
import '../../core/widgets/status_pill.dart';
import '../../core/widgets/tick_bar.dart';
import '../../domain/use_cases/budget_math_service.dart';
import 'plan_providers.dart';

class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final limitsAsync = ref.watch(limitsStreamProvider);
    final goalsAsync = ref.watch(savingPlansStreamProvider);
    final safeToSpend = ref.watch(safeToSpendProvider);
    final isPrivate = ref.watch(privacyModeProvider);

    final rawLimits = limitsAsync.value ?? [];
    final rawGoals = goalsAsync.value ?? [];

    final now = DateTime.now();
    final currentMonthName = DateFormat('MMMM \'yy').format(now);

    final double totalBudget = safeToSpend.totalBudget > 0 ? safeToSpend.totalBudget : 25000.00;
    final double spentSoFar = safeToSpend.spentSoFar > 0 ? safeToSpend.spentSoFar : 9450.00;
    const double upcomingBills = 1850.00;
    final double emergencyReserve = totalBudget * 0.10;
    final double availableToSpend =
        (totalBudget - spentSoFar - upcomingBills - emergencyReserve).clamp(0.0, double.infinity);

    final double safeToday = safeToSpend.safeToday > 0 ? safeToSpend.safeToday : 896.82;
    final int daysElapsed = safeToSpend.daysElapsed > 0 ? safeToSpend.daysElapsed : now.day;
    final int totalDays =
        safeToSpend.totalDaysInPeriod > 0 ? safeToSpend.totalDaysInPeriod : 30;
    final int daysLeft = totalDays - daysElapsed;

    final double tomorrowAllowance = safeToday * 1.05;
    final double nextWeekAllowance = safeToday * 0.98;

    final burnRatio = safeToSpend.burnRatio > 0 ? safeToSpend.burnRatio : 0.94;
    final statusString = safeToSpend.pace == SpendingPace.ahead
        ? 'AHEAD'
        : safeToSpend.pace == SpendingPace.caution
            ? 'CAUTION'
            : safeToSpend.pace == SpendingPace.deficit
                ? 'DEFICIT'
                : 'ON TRACK';

    final ringProgress = (spentSoFar / totalBudget).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.accent,
          backgroundColor: AppColors.surface,
          onRefresh: () async {
            ref.invalidate(limitsStreamProvider);
            ref.invalidate(savingPlansStreamProvider);
          },
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // 1. Header: Plan Name + Edit Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ACTIVE PLAN',
                        style: TextStyle(
                          color: AppColors.text3,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$currentMonthName Plan',
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => PlanEditSheet.show(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.tune_rounded, color: AppColors.accent, size: 16),
                          SizedBox(width: 6),
                          Text(
                            'Edit Plan',
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
              const SizedBox(height: 16),

              // 2. Safe to Spend Hero Card
              _buildSafeToSpendHero(
                safeToday: safeToday,
                daysElapsed: daysElapsed,
                daysLeft: daysLeft,
                totalDays: totalDays,
                ringProgress: ringProgress,
                statusString: statusString,
                isPrivate: isPrivate,
              ),
              const SizedBox(height: 14),

              // 3. Tomorrow & Next Week Projection Cards
              Row(
                children: [
                  Expanded(
                    child: _buildProjectionTile(
                      label: 'Tomorrow allowance',
                      amount: tomorrowAllowance,
                      tag: '+5% vs today',
                      tagColor: AppColors.income,
                      isPrivate: isPrivate,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildProjectionTile(
                      label: 'Next week daily',
                      amount: nextWeekAllowance,
                      tag: 'Projected',
                      tagColor: AppColors.accent,
                      isPrivate: isPrivate,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 4. Capacity Table
              _buildCapacityCard(
                totalBudget: totalBudget,
                spentSoFar: spentSoFar,
                upcomingBills: upcomingBills,
                emergencyReserve: emergencyReserve,
                availableToSpend: availableToSpend,
                burnRatio: burnRatio,
                isPrivate: isPrivate,
              ),
              const SizedBox(height: 18),

              // 5. Pace Chart
              _buildPaceChartSection(),
              const SizedBox(height: 18),

              // 6. 4-Week Cycle Cards
              _buildCycleWeeksSection(isPrivate: isPrivate),
              const SizedBox(height: 18),

              // 7. Category Envelopes
              _buildCategoryEnvelopesSection(context, rawLimits, isPrivate),
              const SizedBox(height: 18),

              // 8. Upcoming Bills
              _buildUpcomingBillsSection(context, isPrivate),
              const SizedBox(height: 18),

              // 9. Saving Goals Jars
              _buildSavingGoalsSection(context, rawGoals, isPrivate),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSafeToSpendHero({
    required double safeToday,
    required int daysElapsed,
    required int daysLeft,
    required int totalDays,
    required double ringProgress,
    required String statusString,
    required bool isPrivate,
  }) {
    final cyclePercent = totalDays > 0 ? (daysElapsed / totalDays).clamp(0.0, 1.0) : 0.4;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line2),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              ProgressRing(
                progress: ringProgress,
                size: 96,
                strokeWidth: 8,
                progressColor: AppColors.accent,
                centerChild: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${(ringProgress * 100).toInt()}%',
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Text(
                      'Used',
                      style: TextStyle(
                        color: AppColors.text3,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
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
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Recalculated every midnight from real activity',
                      style: const TextStyle(
                        color: AppColors.text3,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Cycle Progress Bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$daysElapsed days passed',
                    style: const TextStyle(color: AppColors.text3, fontSize: 11),
                  ),
                  Text(
                    '$daysLeft days left in cycle',
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: cyclePercent,
                  backgroundColor: AppColors.surface3,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
                  minHeight: 5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProjectionTile({
    required String label,
    required double amount,
    required String tag,
    required Color tagColor,
    required bool isPrivate,
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(color: AppColors.text3, fontSize: 11),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: tagColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  tag,
                  style: TextStyle(
                    color: tagColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            formatCurrency(amount, isPrivate: isPrivate),
            style: const TextStyle(
              color: AppColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapacityCard({
    required double totalBudget,
    required double spentSoFar,
    required double upcomingBills,
    required double emergencyReserve,
    required double availableToSpend,
    required double burnRatio,
    required bool isPrivate,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'CAPACITY BREAKDOWN',
                style: TextStyle(
                  color: AppColors.text3,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surface3,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Burn: ${burnRatio.toStringAsFixed(2)}x',
                  style: const TextStyle(
                    color: AppColors.text2,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildCapacityRow('Total Planned Budget', totalBudget, isPrivate: isPrivate),
          _buildCapacityRow('Spent So Far', spentSoFar, isExpense: true, isPrivate: isPrivate),
          _buildCapacityRow('Upcoming Bills (Reserved)', upcomingBills, isPrivate: isPrivate),
          _buildCapacityRow('Emergency Buffer (10%)', emergencyReserve, isPrivate: isPrivate),
          const Divider(color: AppColors.line, height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Available to Spend',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                formatCurrency(availableToSpend, isPrivate: isPrivate),
                style: const TextStyle(
                  color: AppColors.income,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCapacityRow(
    String label,
    double amount, {
    bool isExpense = false,
    required bool isPrivate,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.text2, fontSize: 12),
          ),
          Text(
            '${isExpense ? '-' : ''}${formatCurrency(amount, isPrivate: isPrivate)}',
            style: TextStyle(
              color: isExpense ? AppColors.expense : AppColors.text,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaceChartSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SPENDING PACE & PROJECTION',
          style: TextStyle(
            color: AppColors.text3,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 10),
        const PaceChart(),
      ],
    );
  }

  Widget _buildCycleWeeksSection({required bool isPrivate}) {
    final weeks = [
      {'title': 'Week 1', 'range': 'Mar 1 - 7', 'target': 6250.0, 'spent': 5800.0, 'status': 'Done'},
      {'title': 'Week 2', 'range': 'Mar 8 - 14', 'target': 6250.0, 'spent': 3650.0, 'status': 'Now'},
      {'title': 'Week 3', 'range': 'Mar 15 - 21', 'target': 6250.0, 'spent': 0.0, 'status': 'Upcoming'},
      {'title': 'Week 4', 'range': 'Mar 22 - 30', 'target': 6250.0, 'spent': 0.0, 'status': 'Upcoming'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'CYCLE WEEKS BREAKDOWN',
          style: TextStyle(
            color: AppColors.text3,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 10),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: weeks.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final w = weeks[index];
            final spent = w['spent'] as double;
            final target = w['target'] as double;
            final isNow = w['status'] == 'Now';
            final isDone = w['status'] == 'Done';
            final ratio = (spent / target).clamp(0.0, 1.0);

            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isNow ? AppColors.accent.withOpacity(0.5) : AppColors.line,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            w['title'] as String,
                            style: const TextStyle(
                              color: AppColors.text,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            w['range'] as String,
                            style: const TextStyle(color: AppColors.text3, fontSize: 11),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: isNow
                              ? AppColors.accentBg
                              : isDone
                                  ? AppColors.surface3
                                  : AppColors.surface2,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          w['status'] as String,
                          style: TextStyle(
                            color: isNow ? AppColors.accent : AppColors.text3,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${formatCurrency(spent, isPrivate: isPrivate)} / ${formatCurrency(target, isPrivate: isPrivate)}',
                        style: const TextStyle(color: AppColors.text2, fontSize: 11),
                      ),
                      Text(
                        '${(ratio * 100).toInt()}%',
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: ratio,
                      backgroundColor: AppColors.surface3,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        spent > target ? AppColors.expense : AppColors.accent,
                      ),
                      minHeight: 4,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCategoryEnvelopesSection(
    BuildContext context,
    List<Map<String, dynamic>> limits,
    bool isPrivate,
  ) {
    final displayLimits = limits.isNotEmpty
        ? limits
        : [
            {'name': 'Food & Groceries', 'spent': 4200.0, 'limit': 6000.0, 'mode': 'soft'},
            {'name': 'Dining & Cafes', 'spent': 1850.0, 'limit': 2500.0, 'mode': 'soft'},
            {'name': 'Transport & Fuel', 'spent': 1900.0, 'limit': 2000.0, 'mode': 'hard'},
            {'name': 'Entertainment', 'spent': 1500.0, 'limit': 1500.0, 'mode': 'soft'},
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'CATEGORY ENVELOPES',
              style: TextStyle(
                color: AppColors.text3,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            GestureDetector(
              onTap: () => EnvelopeEditSheet.show(context),
              child: const Text(
                '+ Add',
                style: TextStyle(
                  color: AppColors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: displayLimits.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final env = displayLimits[index];
            final name = (env['name'] ?? env['category_name'] ?? 'Category') as String;
            final spent = (env['spent'] as num?)?.toDouble() ?? 0.0;
            final limit = (env['limit'] ?? env['amount'] as num?)?.toDouble() ?? 1000.0;
            final isHard = (env['mode'] ?? env['limit_type'] ?? '') == 'hard';

            return GestureDetector(
              onTap: () => EnvelopeEditSheet.show(context, envelope: env),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.line),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                color: AppColors.text,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: isHard ? AppColors.expenseBg : AppColors.surface2,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isHard ? 'HARD' : 'SOFT',
                                style: TextStyle(
                                  color: isHard ? AppColors.expense : AppColors.text3,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${formatCurrency(spent, isPrivate: isPrivate)} / ${formatCurrency(limit, isPrivate: isPrivate)}',
                          style: const TextStyle(
                            color: AppColors.text2,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TickBar(
                      spent: spent,
                      limit: limit,
                      tickPercents: const [0.50, 0.80],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildUpcomingBillsSection(BuildContext context, bool isPrivate) {
    final bills = [
      {'name': 'Ethio Telecom Fibre', 'amount': 1400.0, 'due': 'In 4 days'},
      {'name': 'Gym Membership', 'amount': 450.0, 'due': 'In 9 days'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'UPCOMING BILLS',
          style: TextStyle(
            color: AppColors.text3,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 10),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: bills.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final b = bills[index];
            final amount = b['amount'] as double;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, color: AppColors.accent, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          b['name'] as String,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          b['due'] as String,
                          style: const TextStyle(color: AppColors.text3, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    formatCurrency(amount, isPrivate: isPrivate),
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: const Text(
                      'Paid',
                      style: TextStyle(
                        color: AppColors.income,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSavingGoalsSection(
    BuildContext context,
    List<Map<String, dynamic>> goals,
    bool isPrivate,
  ) {
    final displayGoals = goals.isNotEmpty
        ? goals
        : [
            {'title': 'Emergency Fund', 'current': 45000.0, 'target': 60000.0, 'monthly': 2500.0},
            {'title': 'New Laptop', 'current': 32000.0, 'target': 85000.0, 'monthly': 4000.0},
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'SAVING GOALS',
              style: TextStyle(
                color: AppColors.text3,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            GestureDetector(
              onTap: () => GoalEditSheet.show(context),
              child: const Text(
                '+ New Goal',
                style: TextStyle(
                  color: AppColors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: displayGoals.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final g = displayGoals[index];
            final title = (g['title'] ?? g['plan_name'] ?? 'Saving Goal') as String;
            final current = (g['current'] ?? g['current_amount'] as num?)?.toDouble() ?? 0.0;
            final target = (g['target'] ?? g['target_amount'] as num?)?.toDouble() ?? 10000.0;
            final monthly = (g['monthly'] as num?)?.toDouble() ?? 1000.0;
            final ratio = target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0;

            return GestureDetector(
              onTap: () => GoalEditSheet.show(context, goal: g),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.line),
                ),
                child: Row(
                  children: [
                    ProgressRing(
                      progress: ratio,
                      size: 48,
                      strokeWidth: 5,
                      progressColor: AppColors.income,
                      centerChild: Text(
                        '${(ratio * 100).toInt()}%',
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: AppColors.text,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${formatCurrency(current, isPrivate: isPrivate)} of ${formatCurrency(target, isPrivate: isPrivate)}',
                            style: const TextStyle(color: AppColors.text3, fontSize: 11),
                          ),
                          Text(
                            'Required: ${formatCurrency(monthly, isPrivate: isPrivate)}/mo',
                            style: const TextStyle(
                              color: AppColors.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.accentBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Add',
                        style: TextStyle(
                          color: AppColors.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

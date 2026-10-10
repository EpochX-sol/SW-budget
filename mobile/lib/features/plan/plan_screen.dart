import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../domain/use_cases/budget_math_service.dart';
import 'plan_providers.dart';

class PlanScreen extends ConsumerStatefulWidget {
  const PlanScreen({super.key});

  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showCreateLimitDialog() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => const _CreateLimitModal(),
    );
  }

  void _showCreateSavingPlanDialog() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => const _CreateSavingPlanModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Budgets & Goals', style: AppTypography.titleLarge),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primaryLight,
          labelColor: AppColors.primaryLight,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: 'Budget Envelopes'),
            Tab(text: 'Saving Goal Jars'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _EnvelopesTab(onAdd: _showCreateLimitDialog),
          _SavingJarsTab(onAdd: _showCreateSavingPlanDialog),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (_tabController.index == 0) {
            _showCreateLimitDialog();
          } else {
            _showCreateSavingPlanDialog();
          }
        },
        backgroundColor: AppColors.primaryLight,
        foregroundColor: AppColors.textInverse,
        elevation: 4,
        child: const Icon(Icons.add_rounded, size: 28),
      ),
    );
  }
}

// --- ENVELOPES TAB ---

class _EnvelopesTab extends ConsumerWidget {
  final VoidCallback onAdd;

  const _EnvelopesTab({required this.onAdd});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final limitsAsync = ref.watch(limitsStreamProvider);
    final spendAsync = ref.watch(currentMonthSpendSummaryProvider);

    return limitsAsync.when(
      data: (limits) {
        if (limits.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inventory_2_outlined, size: 64, color: AppColors.textMuted.withOpacity(0.5)),
                const SizedBox(height: 16),
                Text('No Budget Limits Created', style: AppTypography.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'Set up envelopes for Food, Transport, or overall monthly spending.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 20),
                FilledButton.tonal(
                  onPressed: onAdd,
                  child: const Text('Create First Envelope'),
                ),
              ],
            ),
          );
        }

        final spendMap = spendAsync.asData?.value ?? {};
        final safeToSpend = ref.watch(safeToSpendProvider);

        return ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // Executive Budget Health Summary
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'DAILY SAFE SPEND ALLOWANCE',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.textMuted,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (safeToSpend.pace == SpendingPace.onTrack || safeToSpend.pace == SpendingPace.ahead)
                              ? AppColors.incomeSurface
                              : (safeToSpend.pace == SpendingPace.caution
                                  ? AppColors.warningSurface
                                  : AppColors.expenseSurface),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          (safeToSpend.pace == SpendingPace.onTrack || safeToSpend.pace == SpendingPace.ahead)
                              ? 'ON TRACK'
                              : (safeToSpend.pace == SpendingPace.caution ? 'CAUTION' : 'DEFICIT'),
                          style: AppTypography.labelSmall.copyWith(
                            color: (safeToSpend.pace == SpendingPace.onTrack || safeToSpend.pace == SpendingPace.ahead)
                                ? AppColors.income
                                : (safeToSpend.pace == SpendingPace.caution
                                    ? AppColors.secondary
                                    : AppColors.expense),
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        'ETB ${safeToSpend.safeToday.toStringAsFixed(0)}',
                        style: AppTypography.displayMedium.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '/ day',
                        style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${safeToSpend.daysRemaining} days remaining • ETB ${safeToSpend.remainingBudget.toStringAsFixed(0)} unallocated budget left this month',
                    style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Text(
              'Envelopes & Spending Limits',
              style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            ...limits.map((limit) {
              final scopeType = limit['scope_type'] as String? ?? 'category';
              final scopeId = limit['scope_id'] as String?;
              final limitAmount = (limit['amount'] as num?)?.toDouble() ?? 0.0;
              final mode = limit['mode'] as String? ?? 'soft';

              // Find spending for this limit
              double spent = 0.0;
              if (scopeType == 'overall') {
                spent = spendMap['_total_expense'] ?? 0.0;
              } else if (scopeId != null) {
                spent = spendMap[scopeId] ?? 0.0;
              }

              final progress = BudgetMathService.calculateLimitProgress(
                spent: spent,
                limitAmount: limitAmount,
              );

              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: _LimitEnvelopeCard(
                  title: scopeType == 'overall' ? 'Overall Monthly Budget' : 'Category Envelope',
                  progress: progress,
                  mode: mode,
                ),
              );
            }),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primaryLight)),
      error: (e, _) => Center(child: Text('Error loading limits: $e')),
    );
  }
}

class _LimitEnvelopeCard extends StatelessWidget {
  final String title;
  final LimitProgress progress;
  final String mode;

  const _LimitEnvelopeCard({
    required this.title,
    required this.progress,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    Color barColor = AppColors.incomeLight;
    if (progress.percentage >= 100) {
      barColor = AppColors.expense;
    } else if (progress.percentage >= 80) {
      barColor = AppColors.warning;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: progress.isExceeded ? AppColors.expense.withOpacity(0.5) : AppColors.border,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: mode == 'hard' ? AppColors.expenseSurface : AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: mode == 'hard' ? AppColors.expense.withOpacity(0.4) : AppColors.border,
                  ),
                ),
                child: Text(
                  mode.toUpperCase(),
                  style: AppTypography.labelSmall.copyWith(
                    color: mode == 'hard' ? AppColors.expenseLight : AppColors.textSecondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: (progress.percentage / 100).clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: AppColors.surfaceElevated,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
          const SizedBox(height: 10),

          // Numbers Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${progress.spent.toStringAsFixed(0)} / ${progress.limitAmount.toStringAsFixed(0)} ETB',
                style: AppTypography.bodySmall.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                '${progress.percentage.toStringAsFixed(1)}%',
                style: AppTypography.bodySmall.copyWith(
                  fontWeight: FontWeight.bold,
                  color: barColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- SAVING GOAL JARS TAB ---

class _SavingJarsTab extends ConsumerWidget {
  final VoidCallback onAdd;

  const _SavingJarsTab({required this.onAdd});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(savingPlansStreamProvider);

    return plansAsync.when(
      data: (plans) {
        if (plans.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.savings_outlined, size: 64, color: AppColors.secondaryLight.withOpacity(0.5)),
                const SizedBox(height: 16),
                Text('No Saving Goals Set', style: AppTypography.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'Set target goals for an Emergency Fund, holiday, or equipment.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 20),
                FilledButton.tonal(
                  onPressed: onAdd,
                  child: const Text('Create Goal Jar'),
                ),
              ],
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 0.82,
          ),
          itemCount: plans.length,
          itemBuilder: (context, index) {
            final plan = plans[index];
            return _GoalJarCard(plan: plan);
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primaryLight)),
      error: (e, _) => Center(child: Text('Error loading goals: $e')),
    );
  }
}

class _GoalJarCard extends StatelessWidget {
  final Map<String, dynamic> plan;

  const _GoalJarCard({required this.plan});

  @override
  Widget build(BuildContext context) {
    final name = plan['name'] as String? ?? 'Goal';
    final target = (plan['target_amount'] as num?)?.toDouble() ?? 1000.0;
    final current = (plan['current_amount'] as num?)?.toDouble() ?? 0.0;
    final targetDate = DateTime.tryParse(plan['target_date'] as String? ?? '') ?? DateTime.now();

    final ratio = target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0;
    final percent = (ratio * 100).toStringAsFixed(0);
    final daysLeft = max(0, targetDate.difference(DateTime.now()).inDays);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.savings_rounded, color: AppColors.secondaryLight, size: 22),
              ),
              Text('$percent%', style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold, color: AppColors.secondaryLight)),
            ],
          ),
          const Spacer(),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '${current.toStringAsFixed(0)} / ${target.toStringAsFixed(0)} ETB',
            style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: AppColors.surfaceElevated,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.secondaryLight),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$daysLeft days left',
            style: AppTypography.labelSmall.copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

// --- CREATE MODALS ---

class _CreateLimitModal extends ConsumerStatefulWidget {
  const _CreateLimitModal();

  @override
  ConsumerState<_CreateLimitModal> createState() => _CreateLimitModalState();
}

class _CreateLimitModalState extends ConsumerState<_CreateLimitModal> {
  final _amountController = TextEditingController();
  String _scopeType = 'overall';
  String _mode = 'soft';

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Create Budget Envelope', style: AppTypography.headlineSmall),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _scopeType,
            dropdownColor: AppColors.surfaceElevated,
            decoration: const InputDecoration(labelText: 'Envelope Scope'),
            items: const [
              DropdownMenuItem(value: 'overall', child: Text('Overall Monthly Budget')),
              DropdownMenuItem(value: 'category', child: Text('Category Envelope')),
            ],
            onChanged: (val) => setState(() => _scopeType = val ?? 'overall'),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Limit Amount (ETB)',
              prefixText: 'ETB ',
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: _mode,
            dropdownColor: AppColors.surfaceElevated,
            decoration: const InputDecoration(labelText: 'Limit Strictness'),
            items: const [
              DropdownMenuItem(value: 'soft', child: Text('Soft Limit (Warning notification only)')),
              DropdownMenuItem(value: 'hard', child: Text('Hard Limit (Strict alert & lock indicator)')),
            ],
            onChanged: (val) => setState(() => _mode = val ?? 'soft'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () async {
              final amount = double.tryParse(_amountController.text.trim());
              if (amount != null && amount > 0) {
                await ref.read(planControllerProvider).createLimit(
                      scopeType: _scopeType,
                      periodType: 'monthly',
                      amount: amount,
                      mode: _mode,
                    );
                if (context.mounted) Navigator.pop(context);
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryLight,
              foregroundColor: AppColors.textInverse,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Save Envelope', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _CreateSavingPlanModal extends ConsumerStatefulWidget {
  const _CreateSavingPlanModal();

  @override
  ConsumerState<_CreateSavingPlanModal> createState() => _CreateSavingPlanModalState();
}

class _CreateSavingPlanModalState extends ConsumerState<_CreateSavingPlanModal> {
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  DateTime _targetDate = DateTime.now().add(const Duration(days: 90));

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dateFormatted = DateFormat('MMM d, yyyy').format(_targetDate);

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('New Saving Goal Jar', style: AppTypography.headlineSmall),
          const SizedBox(height: 16),
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Goal Name (e.g. Emergency Fund)'),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Target Amount (ETB)',
              prefixText: 'ETB ',
            ),
          ),
          const SizedBox(height: 14),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Target Completion Date'),
            subtitle: Text(dateFormatted, style: const TextStyle(color: AppColors.secondaryLight)),
            trailing: const Icon(Icons.calendar_today_rounded, color: AppColors.textSecondary),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _targetDate,
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
              );
              if (picked != null) {
                setState(() => _targetDate = picked);
              }
            },
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () async {
              final name = _nameController.text.trim();
              final amount = double.tryParse(_amountController.text.trim());
              if (name.isNotEmpty && amount != null && amount > 0) {
                await ref.read(planControllerProvider).createSavingPlan(
                      name: name,
                      targetAmount: amount,
                      targetDate: _targetDate,
                    );
                if (context.mounted) Navigator.pop(context);
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.secondaryLight,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: const Text('Create Goal Jar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

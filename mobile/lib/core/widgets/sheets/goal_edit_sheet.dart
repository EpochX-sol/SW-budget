import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

class GoalEditSheet extends StatefulWidget {
  final Map<String, dynamic>? existingGoal;
  final Function(double amountAdded)? onFund;
  final Function(String name, double target, String date)? onCreate;

  const GoalEditSheet({
    super.key,
    this.existingGoal,
    this.onFund,
    this.onCreate,
  });

  static void show(
    BuildContext context, {
    Map<String, dynamic>? goal,
    Function(double amountAdded)? onFund,
    Function(String name, double target, String date)? onCreate,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => GoalEditSheet(
        existingGoal: goal,
        onFund: onFund,
        onCreate: onCreate,
      ),
    );
  }

  static void showFund(
    BuildContext context, {
    required Map<String, dynamic> goal,
    required Function(double amountAdded) onFund,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => GoalEditSheet(existingGoal: goal, onFund: onFund),
    );
  }

  static void showNew(
    BuildContext context, {
    required Function(String name, double target, String date) onCreate,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => GoalEditSheet(onCreate: onCreate),
    );
  }

  @override
  State<GoalEditSheet> createState() => _GoalEditSheetState();
}

class _GoalEditSheetState extends State<GoalEditSheet> {
  final _fundController = TextEditingController();
  final _nameController = TextEditingController();
  final _targetController = TextEditingController();
  late DateTime _targetDate;

  @override
  void initState() {
    super.initState();
    _targetDate = DateTime.now().add(const Duration(days: 180));
  }

  @override
  void dispose() {
    _fundController.dispose();
    _nameController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.existingGoal;
    final isFunding = g != null;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.surface3,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isFunding ? 'Add to ${g['name']}' : 'New saving goal',
                  style: AppTypography.titleLarge,
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.text2),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (isFunding) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SAVED SO FAR', style: TextStyle(color: AppColors.text3, fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      'ETB ${(g['saved'] as num?)?.toDouble().toStringAsFixed(0) ?? '0'} of ETB ${(g['target'] as num?)?.toDouble().toStringAsFixed(0) ?? '0'}',
                      style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('Amount to add', style: AppTypography.labelSmall.copyWith(color: AppColors.text2)),
              const SizedBox(height: 6),
              TextField(
                controller: _fundController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(prefixText: 'ETB ', hintText: '0.00'),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  final amt = double.tryParse(_fundController.text.replaceAll(',', '').trim()) ?? 0.0;
                  if (amt <= 0) return;
                  Navigator.pop(context);
                  widget.onFund?.call(amt);
                },
                child: const Text('Add to goal'),
              ),
            ] else ...[
              Text('Goal name', style: AppTypography.labelSmall.copyWith(color: AppColors.text2)),
              const SizedBox(height: 6),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(hintText: 'e.g. New phone, Emergency fund'),
              ),
              const SizedBox(height: 14),
              Text('Target amount', style: AppTypography.labelSmall.copyWith(color: AppColors.text2)),
              const SizedBox(height: 6),
              TextField(
                controller: _targetController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(prefixText: 'ETB ', hintText: '50,000'),
              ),
              const SizedBox(height: 14),
              Text('Target date', style: AppTypography.labelSmall.copyWith(color: AppColors.text2)),
              const SizedBox(height: 6),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _targetDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime(2035),
                  );
                  if (picked != null) setState(() => _targetDate = picked);
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Text(
                    '${_targetDate.year}-${_targetDate.month.toString().padLeft(2, '0')}-${_targetDate.day.toString().padLeft(2, '0')}',
                    style: AppTypography.bodyMedium,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  final target = double.tryParse(_targetController.text.replaceAll(',', '').trim()) ?? 0.0;
                  final name = _nameController.text.trim();
                  if (target <= 0 || name.isEmpty) return;
                  Navigator.pop(context);
                  widget.onCreate?.call(
                    name,
                    target,
                    '${_targetDate.year}-${_targetDate.month.toString().padLeft(2, '0')}-${_targetDate.day.toString().padLeft(2, '0')}',
                  );
                },
                child: const Text('Create goal'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

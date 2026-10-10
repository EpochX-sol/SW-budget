import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

class QuickActionsBar extends StatelessWidget {
  final VoidCallback? onAddExpense;
  final VoidCallback? onAddIncome;

  const QuickActionsBar({
    super.key,
    this.onAddExpense,
    this.onAddIncome,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            icon: Icons.arrow_upward_rounded,
            iconColor: AppColors.expense,
            label: 'Expense',
            onTap: onAddExpense ?? () => _showAddEntrySheet(context, isExpense: true),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _ActionButton(
            icon: Icons.arrow_downward_rounded,
            iconColor: AppColors.income,
            label: 'Income',
            onTap: onAddIncome ?? () => _showAddEntrySheet(context, isExpense: false),
          ),
        ),
      ],
    );
  }

  void _showAddEntrySheet(BuildContext context, {required bool isExpense}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
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
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderHighlight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (isExpense ? AppColors.expense : AppColors.income)
                          .withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isExpense ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                      color: isExpense ? AppColors.expense : AppColors.income,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isExpense ? 'Record Expense' : 'Record Income',
                    style: AppTypography.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Manual cash transactions recorded here are immediately reflected in your Cash Wallet balance and cashflow metrics.',
                style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              TextField(
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                style: AppTypography.headlineMedium.copyWith(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  prefixText: 'ETB ',
                  prefixStyle: AppTypography.headlineMedium.copyWith(color: AppColors.textSecondary),
                  hintText: '0.00',
                  hintStyle: AppTypography.headlineMedium.copyWith(color: AppColors.textMuted),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Note or Merchant (e.g. Lunch, Taxi, Salary)',
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isExpense ? 'Expense logged successfully' : 'Income logged successfully',
                      ),
                      backgroundColor: AppColors.surfaceElevated,
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isExpense ? AppColors.expense : AppColors.income,
                ),
                child: Text(
                  isExpense ? 'Save Expense' : 'Save Income',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 16),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: AppTypography.labelLarge.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

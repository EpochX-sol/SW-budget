import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/database_provider.dart';
import '../../../domain/use_cases/plan_evaluation_engine.dart';

class AddPlanExpenseSheet extends ConsumerStatefulWidget {
  final PlanEvaluationSnapshot snapshot;

  const AddPlanExpenseSheet({
    super.key,
    required this.snapshot,
  });

  @override
  ConsumerState<AddPlanExpenseSheet> createState() => _AddPlanExpenseSheetState();
}

class _AddPlanExpenseSheetState extends ConsumerState<AddPlanExpenseSheet> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  String? _selectedAccountId;
  String? _selectedCategoryId;
  DateTime _occurredAt = DateTime.now();

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dbAsync = ref.watch(databaseProvider);
    final plan = widget.snapshot.plan;
    final startDate = DateTime.parse(plan['start_date'] as String);
    final endDate = DateTime.parse(plan['end_date'] as String);

    // Live validation feedback
    String feedbackText = 'Counts in your plan';
    Color feedbackColor = AppColors.positive;
    IconData feedbackIcon = Icons.check_circle_outline;

    if (_occurredAt.isBefore(startDate) || _occurredAt.isAfter(endDate)) {
      feedbackText = 'This date is outside your plan, so it won\'t count';
      feedbackColor = AppColors.warning;
      feedbackIcon = Icons.warning_amber_rounded;
    } else {
      // Check if selected category links to an expected expense
      for (final exp in widget.snapshot.expectedExpenses) {
        final linkedCat = exp['linked_category_id'] as String?;
        if (linkedCat != null && linkedCat == _selectedCategoryId) {
          final expName = exp['name'] as String? ?? 'Expected expense';
          feedbackText = 'Not counted: this pays your expected expense $expName';
          feedbackColor = AppColors.accent;
          feedbackIcon = Icons.info_outline;
          break;
        }
      }
    }

    return dbAsync.when(
      data: (db) {
        final accounts = db.getAccounts();
        final categories = db.getCategories();

        // Default to cash or first account if null
        if (_selectedAccountId == null && accounts.isNotEmpty) {
          final cashAcc = accounts.firstWhere(
            (a) => (a['name'] as String).toLowerCase().contains('cash'),
            orElse: () => accounts.first,
          );
          _selectedAccountId = cashAcc['id'] as String;
        }

        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Add Expense', style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w800)),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.text3),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Amount Input
              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                autofocus: true,
                style: const TextStyle(color: AppColors.text, fontSize: 24, fontWeight: FontWeight.w800),
                decoration: InputDecoration(
                  prefixText: 'ETB ',
                  prefixStyle: const TextStyle(color: AppColors.accent, fontSize: 24, fontWeight: FontWeight.w800),
                  hintText: '0.00',
                  filled: true,
                  fillColor: AppColors.surface2,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              // Account & Category dropdowns
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedAccountId,
                      dropdownColor: AppColors.surface,
                      decoration: InputDecoration(
                        labelText: 'Paid From',
                        labelStyle: const TextStyle(color: AppColors.text3, fontSize: 12),
                        filled: true,
                        fillColor: AppColors.surface2,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                      items: accounts.map((a) {
                        return DropdownMenuItem<String>(
                          value: a['id'] as String,
                          child: Text(a['name'] as String, style: const TextStyle(color: AppColors.text, fontSize: 13)),
                        );
                      }).toList(),
                      onChanged: (val) => setState(() => _selectedAccountId = val),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedCategoryId,
                      dropdownColor: AppColors.surface,
                      decoration: InputDecoration(
                        labelText: 'Category',
                        labelStyle: const TextStyle(color: AppColors.text3, fontSize: 12),
                        filled: true,
                        fillColor: AppColors.surface2,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('Uncategorized', style: TextStyle(color: AppColors.text3, fontSize: 13)),
                        ),
                        ...categories.map((c) {
                          return DropdownMenuItem<String>(
                            value: c['id'] as String,
                            child: Text(c['name'] as String, style: const TextStyle(color: AppColors.text, fontSize: 13)),
                          );
                        }),
                      ],
                      onChanged: (val) => setState(() => _selectedCategoryId = val),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Note input
              TextField(
                controller: _noteController,
                style: const TextStyle(color: AppColors.text, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Note (optional, e.g. Lunch with team)',
                  hintStyle: const TextStyle(color: AppColors.text3, fontSize: 13),
                  filled: true,
                  fillColor: AppColors.surface2,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 14),
              // Live Feedback Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: feedbackColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: feedbackColor.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    Icon(feedbackIcon, color: feedbackColor, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        feedbackText,
                        style: TextStyle(color: feedbackColor, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Save Button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.background,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => _saveExpense(db),
                child: const Text('Save Expense', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Text('Failed to load accounts'),
    );
  }

  void _saveExpense(AppDatabase db) {
    final amt = double.tryParse(_amountController.text.trim()) ?? 0.0;
    if (amt <= 0) return;

    final txnId = const Uuid().v4();
    db.upsertTransaction(
      id: txnId,
      accountId: _selectedAccountId ?? 'cash',
      categoryId: _selectedCategoryId,
      type: 'expense',
      amount: amt,
      occurredAt: _occurredAt,
      source: 'manual',
      note: _noteController.text.trim().isNotEmpty ? _noteController.text.trim() : null,
      isDirty: true,
    );

    Navigator.of(context).pop();
  }
}

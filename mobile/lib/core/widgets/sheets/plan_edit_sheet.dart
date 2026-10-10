import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

class PlanEditSheet extends StatefulWidget {
  final Map<String, dynamic>? currentPlan;
  final Function({
    required String name,
    required String startDate,
    required String endDate,
    required double budget,
    required double reservePct,
    required String rollover,
  })? onSave;
  final VoidCallback? onDelete;

  const PlanEditSheet({
    super.key,
    this.currentPlan,
    this.onSave,
    this.onDelete,
  });

  static void show(
    BuildContext context, {
    Map<String, dynamic>? currentPlan,
    Function({
      required String name,
      required String startDate,
      required String endDate,
      required double budget,
      required double reservePct,
      required String rollover,
    })? onSave,
    VoidCallback? onDelete,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => PlanEditSheet(
        currentPlan: currentPlan,
        onSave: onSave,
        onDelete: onDelete,
      ),
    );
  }

  @override
  State<PlanEditSheet> createState() => _PlanEditSheetState();
}

class _PlanEditSheetState extends State<PlanEditSheet> {
  late TextEditingController _nameController;
  late TextEditingController _budgetController;
  late TextEditingController _reserveController;
  late DateTime _startDate;
  late DateTime _endDate;
  String _rollover = 'SPREAD_EVENLY';

  final Map<String, List<String>> _rolloverLabels = {
    'SPREAD_EVENLY': ['Spread evenly', 'Over- or under-spend is shared across all remaining days'],
    'NEXT_DAY': ['Next day absorbs', 'Tomorrow takes the whole difference, other days stay at base'],
    'WEEK_ONLY': ['This week only', 'The rest of this week absorbs it; next week starts fresh'],
    'TO_SAVINGS': ['Surplus to savings', 'Underspend is saved; overspend is spread evenly'],
  };

  @override
  void initState() {
    super.initState();
    final p = widget.currentPlan;
    _nameController = TextEditingController(text: p?['name'] as String? ?? 'Paycheck cycle');
    final b = (p?['budget'] as num?)?.toDouble() ?? 25000.0;
    _budgetController = TextEditingController(text: b.toStringAsFixed(0));
    final r = (p?['reservePct'] as num?)?.toDouble() ?? 0.0;
    _reserveController = TextEditingController(text: r.toStringAsFixed(0));

    final now = DateTime.now();
    _startDate = DateTime.tryParse(p?['start'] as String? ?? '') ?? now;
    _endDate = DateTime.tryParse(p?['end'] as String? ?? '') ?? now.add(const Duration(days: 29));
    _rollover = p?['rollover'] as String? ?? 'SPREAD_EVENLY';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _budgetController.dispose();
    _reserveController.dispose();
    super.dispose();
  }

  void _applyQuickPeriod(int days) {
    setState(() {
      _endDate = _startDate.add(Duration(days: days - 1));
    });
  }

  @override
  Widget build(BuildContext context) {
    final creating = widget.currentPlan == null;
    final budget = double.tryParse(_budgetController.text.replaceAll(',', '')) ?? 0.0;
    final reservePct = double.tryParse(_reserveController.text.replaceAll(',', '')) ?? 0.0;
    final days = _endDate.difference(_startDate).inDays + 1;
    final effectiveBudget = budget * (1.0 - (reservePct / 100.0).clamp(0.0, 1.0));
    final perDay = days > 0 ? (effectiveBudget / days) : 0.0;
    final perWeek = perDay * 7;

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
                Text(creating ? 'Create a plan' : 'Edit plan', style: AppTypography.titleLarge),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.text2),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            if (!creating) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.amberBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.amber.withOpacity(0.3)),
                ),
                child: Text(
                  'Changing the budget or end date recalculates every daily and weekly limit from your real spending.',
                  style: AppTypography.bodySmall.copyWith(color: AppColors.text),
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Plan Name
            Text('Plan name', style: AppTypography.labelSmall.copyWith(color: AppColors.text2)),
            const SizedBox(height: 6),
            TextField(controller: _nameController),

            const SizedBox(height: 14),

            // Quick Period Chips
            Text('Quick period', style: AppTypography.labelSmall.copyWith(color: AppColors.text2)),
            const SizedBox(height: 8),
            Row(
              children: [
                _chipButton('2 weeks', () => _applyQuickPeriod(14)),
                const SizedBox(width: 8),
                _chipButton('1 month', () => _applyQuickPeriod(30)),
                const SizedBox(width: 8),
                _chipButton('Paycheck', () {
                  final now = DateTime.now();
                  setState(() {
                    _startDate = DateTime(now.year, now.month, 25);
                    _endDate = DateTime(now.year, now.month + 1, 24);
                  });
                }),
              ],
            ),

            const SizedBox(height: 14),

            // Dates Row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Start', style: AppTypography.labelSmall.copyWith(color: AppColors.text2)),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: creating ? () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _startDate,
                            firstDate: DateTime(2024),
                            lastDate: DateTime(2030),
                          );
                          if (picked != null) setState(() => _startDate = picked);
                        } : null,
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surface2,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.line),
                          ),
                          child: Text(
                            '${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')}',
                            style: AppTypography.bodyMedium.copyWith(
                              color: creating ? AppColors.text : AppColors.text3,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('End', style: AppTypography.labelSmall.copyWith(color: AppColors.text2)),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _endDate,
                            firstDate: _startDate,
                            lastDate: DateTime(2030),
                          );
                          if (picked != null) setState(() => _endDate = picked);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.surface2,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.line),
                          ),
                          child: Text(
                            '${_endDate.year}-${_endDate.month.toString().padLeft(2, '0')}-${_endDate.day.toString().padLeft(2, '0')}',
                            style: AppTypography.bodyMedium,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Spending limit
            Text('Spending limit', style: AppTypography.labelSmall.copyWith(color: AppColors.text2)),
            const SizedBox(height: 6),
            TextField(
              controller: _budgetController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(prefixText: 'ETB ', hintText: '25,000'),
            ),

            const SizedBox(height: 14),

            // Emergency reserve %
            Text('Emergency reserve', style: AppTypography.labelSmall.copyWith(color: AppColors.text2)),
            const SizedBox(height: 6),
            TextField(
              controller: _reserveController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixText: '% ',
                hintText: '0',
                helperText: 'Held back from daily allowance. 0–30%.',
              ),
            ),

            const SizedBox(height: 14),

            // Rollover strategy
            Text('When you over- or under-spend', style: AppTypography.labelSmall.copyWith(color: AppColors.text2)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.line, width: 1.5),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _rollover,
                  isExpanded: true,
                  dropdownColor: AppColors.surface,
                  items: _rolloverLabels.entries.map((e) {
                    return DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value[0], style: AppTypography.bodyMedium),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _rollover = val);
                  },
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _rolloverLabels[_rollover]?[1] ?? '',
              style: AppTypography.bodySmall.copyWith(color: AppColors.text3, fontSize: 12),
            ),

            const SizedBox(height: 16),

            // Live Preview Box
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
                  Text(
                    'PREVIEW',
                    style: TextStyle(
                      color: AppColors.text3,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _previewRow('Per day', 'ETB ${perDay.toStringAsFixed(0)}'),
                  const SizedBox(height: 6),
                  _previewRow('Per week', 'ETB ${perWeek.toStringAsFixed(0)}'),
                  const SizedBox(height: 6),
                  _previewRow('Length', '$days days · ${(days / 7).ceil()} weeks'),
                ],
              ),
            ),

            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                widget.onSave?.call(
                  name: _nameController.text.trim(),
                  startDate: '${_startDate.year}-${_startDate.month.toString().padLeft(2, '0')}-${_startDate.day.toString().padLeft(2, '0')}',
                  endDate: '${_endDate.year}-${_endDate.month.toString().padLeft(2, '0')}-${_endDate.day.toString().padLeft(2, '0')}',
                  budget: budget,
                  reservePct: reservePct,
                  rollover: _rollover,
                );
              },
              child: Text(creating ? 'Create plan' : 'Save plan'),
            ),

            if (!creating) ...[
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onDelete?.call();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.outBg,
                  foregroundColor: AppColors.expense,
                ),
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Delete plan'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chipButton(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.line),
        ),
        child: Text(
          label,
          style: TextStyle(color: AppColors.text2, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _previewRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: AppColors.text2, fontSize: 13)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }
}

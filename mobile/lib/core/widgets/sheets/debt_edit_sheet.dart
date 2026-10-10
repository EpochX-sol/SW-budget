import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

class DebtEditSheet extends StatefulWidget {
  final bool initialIsOwed;
  final Function({
    required bool isOwed,
    required String who,
    required double amount,
    required String? dueDate,
    required String note,
  })? onSave;

  const DebtEditSheet({
    super.key,
    this.initialIsOwed = true,
    this.onSave,
  });

  static void show(
    BuildContext context, {
    bool initialIsOwed = true,
    Function({
      required bool isOwed,
      required String who,
      required double amount,
      required String? dueDate,
      required String note,
    })? onSave,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => DebtEditSheet(initialIsOwed: initialIsOwed, onSave: onSave),
    );
  }

  @override
  State<DebtEditSheet> createState() => _DebtEditSheetState();
}

class _DebtEditSheetState extends State<DebtEditSheet> {
  late bool _isOwed;
  final _whoController = TextEditingController();
  final _amtController = TextEditingController();
  final _noteController = TextEditingController();
  DateTime? _dueDate;

  @override
  void initState() {
    super.initState();
    _isOwed = widget.initialIsOwed;
  }

  @override
  void dispose() {
    _whoController.dispose();
    _amtController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                Text('Add a debt', style: AppTypography.titleLarge),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.text2),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Segment Direction
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _segButton('Someone owes me', _isOwed, () {
                      setState(() => _isOwed = true);
                    }),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _segButton('I owe someone', !_isOwed, () {
                      setState(() => _isOwed = false);
                    }),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            Text('Name', style: AppTypography.labelSmall.copyWith(color: AppColors.text2)),
            const SizedBox(height: 6),
            TextField(controller: _whoController, decoration: const InputDecoration(hintText: 'e.g. Dawit Alemu')),

            const SizedBox(height: 14),

            Text('Amount', style: AppTypography.labelSmall.copyWith(color: AppColors.text2)),
            const SizedBox(height: 6),
            TextField(
              controller: _amtController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(prefixText: 'ETB ', hintText: '0.00'),
            ),

            const SizedBox(height: 14),

            Text('Due date (optional)', style: AppTypography.labelSmall.copyWith(color: AppColors.text2)),
            const SizedBox(height: 6),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now().add(const Duration(days: 14)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime(2035),
                );
                if (picked != null) setState(() => _dueDate = picked);
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.line),
                ),
                child: Text(
                  _dueDate != null
                      ? '${_dueDate!.year}-${_dueDate!.month.toString().padLeft(2, '0')}-${_dueDate!.day.toString().padLeft(2, '0')}'
                      : 'Pick due date',
                  style: AppTypography.bodyMedium.copyWith(
                    color: _dueDate != null ? AppColors.text : AppColors.text3,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 14),

            Text('Note (optional)', style: AppTypography.labelSmall.copyWith(color: AppColors.text2)),
            const SizedBox(height: 6),
            TextField(controller: _noteController, decoration: const InputDecoration(hintText: 'e.g. Dinner split, loan')),

            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: () {
                final amt = double.tryParse(_amtController.text.replaceAll(',', '').trim()) ?? 0.0;
                final who = _whoController.text.trim();
                if (amt <= 0 || who.isEmpty) return;

                Navigator.pop(context);
                widget.onSave?.call(
                  isOwed: _isOwed,
                  who: who,
                  amount: amt,
                  dueDate: _dueDate != null
                      ? '${_dueDate!.year}-${_dueDate!.month.toString().padLeft(2, '0')}-${_dueDate!.day.toString().padLeft(2, '0')}'
                      : null,
                  note: _noteController.text.trim(),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _segButton(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isSelected ? AppColors.text : AppColors.text2,
          ),
        ),
      ),
    );
  }
}

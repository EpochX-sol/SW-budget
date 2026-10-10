import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

class EnvelopeEditSheet extends StatefulWidget {
  final Map<String, dynamic>? envelope;
  final List<String> availableCategories;
  final Function(String category, double limit, String mode)? onSave;
  final VoidCallback? onDelete;

  const EnvelopeEditSheet({
    super.key,
    this.envelope,
    this.availableCategories = const [],
    this.onSave,
    this.onDelete,
  });

  static void show(
    BuildContext context, {
    Map<String, dynamic>? envelope,
    List<String> availableCategories = const [],
    Function(String category, double limit, String mode)? onSave,
    VoidCallback? onDelete,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => EnvelopeEditSheet(
        envelope: envelope,
        availableCategories: availableCategories,
        onSave: onSave,
        onDelete: onDelete,
      ),
    );
  }

  @override
  State<EnvelopeEditSheet> createState() => _EnvelopeEditSheetState();
}

class _EnvelopeEditSheetState extends State<EnvelopeEditSheet> {
  late String _category;
  late TextEditingController _limitController;
  String _mode = 'soft';

  @override
  void initState() {
    super.initState();
    final e = widget.envelope;
    _category = e?['cat'] as String? ??
        (widget.availableCategories.isNotEmpty ? widget.availableCategories.first : 'Food & Groceries');
    final lim = (e?['limit'] as num?)?.toDouble() ?? 3000.0;
    _limitController = TextEditingController(text: e != null ? lim.toStringAsFixed(0) : '');
    _mode = e?['mode'] as String? ?? 'soft';
  }

  @override
  void dispose() {
    _limitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.envelope != null;

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
                Text(editing ? 'Edit envelope' : 'New envelope', style: AppTypography.titleLarge),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.text2),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Category selector (or static title if editing)
            if (editing) ...[
              Text('Category: $_category', style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
            ] else ...[
              Text('Category', style: AppTypography.labelSmall.copyWith(color: AppColors.text2)),
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
                    value: _category,
                    isExpanded: true,
                    dropdownColor: AppColors.surface,
                    items: widget.availableCategories.map((cat) {
                      return DropdownMenuItem(value: cat, child: Text(cat, style: AppTypography.bodyMedium));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _category = val);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Limit input
            Text('Limit for this cycle', style: AppTypography.labelSmall.copyWith(color: AppColors.text2)),
            const SizedBox(height: 6),
            TextField(
              controller: _limitController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(prefixText: 'ETB ', hintText: 'e.g. 3,000'),
            ),

            const SizedBox(height: 16),

            // Mode Behaviour
            Text('Behaviour', style: AppTypography.labelSmall.copyWith(color: AppColors.text2)),
            const SizedBox(height: 8),
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
                    child: _segButton('Soft · gentle alert', _mode == 'soft', () {
                      setState(() => _mode = 'soft');
                    }),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _segButton('Hard · strict cap', _mode == 'hard', () {
                      setState(() => _mode = 'hard');
                    }),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: () {
                final lim = double.tryParse(_limitController.text.replaceAll(',', '').trim()) ?? 0.0;
                if (lim <= 0) return;
                Navigator.pop(context);
                widget.onSave?.call(_category, lim, _mode);
              },
              child: Text(editing ? 'Save envelope' : 'Add envelope'),
            ),

            if (editing) ...[
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
                label: const Text('Remove envelope'),
              ),
            ],
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

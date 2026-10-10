import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

class TransactionDetailSheet extends StatefulWidget {
  final Map<String, dynamic> transaction;
  final Function(String newCategory, String newNote)? onSave;
  final VoidCallback? onMarkTransfer;
  final VoidCallback? onDelete;

  const TransactionDetailSheet({
    super.key,
    required this.transaction,
    this.onSave,
    this.onMarkTransfer,
    this.onDelete,
  });

  static void show(
    BuildContext context, {
    required Map<String, dynamic> transaction,
    Function(String newCategory, String newNote)? onSave,
    VoidCallback? onMarkTransfer,
    VoidCallback? onDelete,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => TransactionDetailSheet(
        transaction: transaction,
        onSave: onSave,
        onMarkTransfer: onMarkTransfer,
        onDelete: onDelete,
      ),
    );
  }

  @override
  State<TransactionDetailSheet> createState() => _TransactionDetailSheetState();
}

class _TransactionDetailSheetState extends State<TransactionDetailSheet> {
  late String _selectedCat;
  late TextEditingController _noteController;
  bool _showRaw = false;

  final List<String> _expenseCats = [
    'Food & Groceries',
    'Transport & Fuel',
    'Utilities & Telecom',
    'Shopping',
    'Housing & Rent',
    'Health & Fitness',
    'Entertainment',
    'Family Support',
    'Miscellaneous',
    'Uncategorized',
  ];

  @override
  void initState() {
    super.initState();
    _selectedCat = widget.transaction['category_name'] as String? ??
        widget.transaction['category'] as String? ??
        'Uncategorized';
    _noteController = TextEditingController(
      text: widget.transaction['note'] as String? ?? '',
    );
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.transaction;
    final type = (t['type'] as String? ?? 'debit').toLowerCase();
    final isIn = type == 'credit' || type == 'income';
    final isT = type == 'transfer';
    final amount = (t['amount'] as num?)?.toDouble() ?? 0.0;
    final party = t['counterparty'] as String? ?? t['party'] as String? ?? 'Transaction';
    final verified = (t['balance_chain_ok'] == 1) || (t['verified'] == true);
    final gap = (t['gap_before_amount'] as num?)?.toDouble() ??
        (t['gap'] as num?)?.toDouble() ??
        0.0;
    final accountName = t['account_name'] as String? ?? t['acc_name'] as String? ?? 'Account';
    final dateStr = t['occurred_at'] as String? ?? t['date'] as String? ?? '';
    final refStr = t['ref'] as String? ?? t['dedupe_key'] as String? ?? 'TXN';
    final runBal = (t['running_balance'] as num?)?.toDouble() ??
        (t['balance_after'] as num?)?.toDouble() ??
        (t['run'] as num?)?.toDouble();
    final rawMsg = t['raw_body'] as String? ?? t['raw'] as String? ?? '';
    final isManual = refStr == 'MANUAL';

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
            // Grab handle
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

            // Sheet Title & Close
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Transaction', style: AppTypography.titleLarge),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.text2),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Centered Party & Big Amount
            Center(
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: isT
                          ? AppColors.surface2
                          : (isIn ? AppColors.inBg : AppColors.outBg),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      isT
                          ? Icons.swap_horiz_rounded
                          : (isIn ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded),
                      color: isT
                          ? AppColors.text2
                          : (isIn ? AppColors.income : AppColors.expense),
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    party,
                    style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${isT ? "" : (isIn ? "+" : "-")} ETB ${amount.toStringAsFixed(2)}',
                    style: AppTypography.displayMedium.copyWith(
                      fontWeight: FontWeight.w800,
                      color: isT
                          ? AppColors.text
                          : (isIn ? AppColors.income : AppColors.text),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Pill Badges: Verified / Origin
                  Wrap(
                    spacing: 8,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: verified ? AppColors.inBg : AppColors.amberBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              verified ? Icons.verified_user_rounded : Icons.warning_amber_rounded,
                              size: 12,
                              color: verified ? AppColors.income : AppColors.amber,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              verified ? 'Verified' : 'Unverified',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: verified ? AppColors.income : AppColors.amber,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'AI categorised',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Balance Gap Warning Banner
            if (gap > 0) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.amberBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.amber.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: AppColors.amber, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${gap.toStringAsFixed(2)} ETB unaccounted before this event — a cash spend or a missing message.',
                        style: AppTypography.bodySmall.copyWith(color: AppColors.text),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Metadata Card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                children: [
                  _kvRow('Account', accountName),
                  _kvRow('When', dateStr),
                  _kvRow('Reference', refStr),
                  if (runBal != null) _kvRow('Running balance', 'ETB ${runBal.toStringAsFixed(2)}'),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Category Selector (if not transfer)
            if (!isT) ...[
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
                    value: _expenseCats.contains(_selectedCat) ? _selectedCat : 'Uncategorized',
                    isExpanded: true,
                    dropdownColor: AppColors.surface,
                    items: _expenseCats.map((cat) {
                      return DropdownMenuItem(
                        value: cat,
                        child: Text(cat, style: AppTypography.bodyMedium),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedCat = val);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Note input
            Text('Note', style: AppTypography.labelSmall.copyWith(color: AppColors.text2)),
            const SizedBox(height: 6),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                hintText: 'Add a note',
              ),
            ),

            // Raw notification expandable
            if (rawMsg.isNotEmpty) ...[
              const SizedBox(height: 14),
              InkWell(
                onTap: () => setState(() => _showRaw = !_showRaw),
                child: Row(
                  children: [
                    const Icon(Icons.chat_bubble_outline_rounded, size: 16, color: AppColors.accent),
                    const SizedBox(width: 6),
                    Text(
                      'Original notification',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _showRaw ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: AppColors.accent,
                    ),
                  ],
                ),
              ),
              if (_showRaw) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Text(
                    rawMsg,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: AppColors.text2,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ],

            const SizedBox(height: 20),

            // Action Buttons
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                widget.onSave?.call(_selectedCat, _noteController.text.trim());
              },
              child: const Text('Save changes'),
            ),

            if (type == 'debit') ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onMarkTransfer?.call();
                },
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                label: const Text('Mark as internal transfer'),
              ),
            ],

            if (isManual) ...[
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
                label: const Text('Delete entry'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kvRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.bodySmall.copyWith(color: AppColors.text2)),
          Text(
            value,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

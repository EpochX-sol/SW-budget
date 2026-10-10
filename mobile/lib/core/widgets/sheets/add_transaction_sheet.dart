import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

class AddTransactionSheet extends StatefulWidget {
  final List<Map<String, dynamic>> accounts;
  final Function({
    required bool isExpense,
    required double amount,
    required String counterparty,
    required String accountId,
    required String category,
    required String note,
  })? onSubmit;

  const AddTransactionSheet({
    super.key,
    required this.accounts,
    this.onSubmit,
  });

  static void show(
    BuildContext context, {
    List<Map<String, dynamic>> accounts = const [
      {'id': 'acc_cbe', 'account_name': 'Commercial Bank of Ethiopia', 'name': 'Commercial Bank of Ethiopia'},
      {'id': 'acc_tb', 'account_name': 'Telebirr Wallet', 'name': 'Telebirr Wallet'},
      {'id': 'acc_cash', 'account_name': 'Physical Cash', 'name': 'Physical Cash'},
    ],
    Function({
      required bool isExpense,
      required double amount,
      required String counterparty,
      required String accountId,
      required String category,
      required String note,
    })? onSubmit,
  }) {
    final effectiveAccounts = accounts.isNotEmpty ? accounts : const [
      {'id': 'acc_cbe', 'account_name': 'Commercial Bank of Ethiopia', 'name': 'Commercial Bank of Ethiopia'},
      {'id': 'acc_tb', 'account_name': 'Telebirr Wallet', 'name': 'Telebirr Wallet'},
      {'id': 'acc_cash', 'account_name': 'Physical Cash', 'name': 'Physical Cash'},
    ];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => AddTransactionSheet(
        accounts: effectiveAccounts,
        onSubmit: onSubmit,
      ),
    );
  }

  @override
  State<AddTransactionSheet> createState() => _AddTransactionSheetState();
}

class _AddTransactionSheetState extends State<AddTransactionSheet> {
  bool _isExpense = true;
  final _amountController = TextEditingController();
  final _partyController = TextEditingController();
  final _noteController = TextEditingController();

  late String _selectedAccountId;
  late String _selectedCat;

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
  ];

  final List<String> _incomeCats = [
    'Salary & Wages',
    'Business / Freelance',
    'Family Support',
    'Miscellaneous',
  ];

  @override
  void initState() {
    super.initState();
    _selectedAccountId = widget.accounts.isNotEmpty
        ? (widget.accounts.first['id'] as String? ?? 'cash')
        : 'cash';
    _selectedCat = _expenseCats.first;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _partyController.dispose();
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

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Add transaction', style: AppTypography.titleLarge),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.text2),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Segment: Expense vs Income
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
                    child: _segButton('Expense', _isExpense, () {
                      setState(() {
                        _isExpense = true;
                        _selectedCat = _expenseCats.first;
                      });
                    }),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _segButton('Income', !_isExpense, () {
                      setState(() {
                        _isExpense = false;
                        _selectedCat = _incomeCats.first;
                      });
                    }),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Amount Field
            Text('Amount', style: AppTypography.labelSmall.copyWith(color: AppColors.text2)),
            const SizedBox(height: 6),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                prefixText: 'ETB ',
                prefixStyle: AppTypography.headlineSmall.copyWith(color: AppColors.text3),
                hintText: '0.00',
              ),
            ),

            const SizedBox(height: 14),

            // Merchant / Person
            Text('Merchant or person', style: AppTypography.labelSmall.copyWith(color: AppColors.text2)),
            const SizedBox(height: 6),
            TextField(
              controller: _partyController,
              decoration: const InputDecoration(
                hintText: 'e.g. Café Tomoca, Ride',
              ),
            ),

            const SizedBox(height: 14),

            // Account Selector
            if (widget.accounts.isNotEmpty) ...[
              Text('Account', style: AppTypography.labelSmall.copyWith(color: AppColors.text2)),
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
                    value: _selectedAccountId,
                    isExpanded: true,
                    dropdownColor: AppColors.surface,
                    items: widget.accounts.map((acc) {
                      final id = acc['id'] as String? ?? '';
                      final name = acc['name'] as String? ?? 'Account';
                      final bal = (acc['last_known_balance'] as num?)?.toDouble() ?? 0.0;
                      return DropdownMenuItem(
                        value: id,
                        child: Text(
                          '$name · ETB ${bal.toStringAsFixed(0)}',
                          style: AppTypography.bodyMedium,
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedAccountId = val);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Category Selector
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
                  value: _selectedCat,
                  isExpanded: true,
                  dropdownColor: AppColors.surface,
                  items: (_isExpense ? _expenseCats : _incomeCats).map((cat) {
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

            // Note (Optional)
            Text('Note (optional)', style: AppTypography.labelSmall.copyWith(color: AppColors.text2)),
            const SizedBox(height: 6),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                hintText: 'Add a note',
              ),
            ),

            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: () {
                final amt = double.tryParse(_amountController.text.replaceAll(',', '').trim()) ?? 0.0;
                final party = _partyController.text.trim();
                if (amt <= 0 || party.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid amount and merchant name.')),
                  );
                  return;
                }

                Navigator.pop(context);
                widget.onSubmit?.call(
                  isExpense: _isExpense,
                  amount: amt,
                  counterparty: party,
                  accountId: _selectedAccountId,
                  category: _selectedCat,
                  note: _noteController.text.trim(),
                );
              },
              child: const Text('Save transaction'),
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
          boxShadow: isSelected
              ? [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 2))]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isSelected ? AppColors.text : AppColors.text2,
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../brand_badge.dart';

class AccountEditSheet extends StatefulWidget {
  final Map<String, dynamic> account;
  final List<Map<String, dynamic>> recentTransactions;
  final Function(bool isLiquid)? onToggleLiquid;
  final Function(double newCashBalance)? onUpdateCashBalance;

  const AccountEditSheet({
    super.key,
    required this.account,
    this.recentTransactions = const [],
    this.onToggleLiquid,
    this.onUpdateCashBalance,
  });

  static void show(
    BuildContext context, {
    Map<String, dynamic>? account,
    List<Map<String, dynamic>> recentTransactions = const [],
    Function(bool isLiquid)? onToggleLiquid,
    Function(double newCashBalance)? onUpdateCashBalance,
  }) {
    final effectiveAccount = account ?? {
      'id': 'acc_new',
      'name': 'Cash Wallet',
      'account_name': 'Physical Cash',
      'institution': 'cash',
      'type': 'cash',
      'balance': 0.0,
      'last_known_balance': 0.0,
      'is_locked': false,
    };
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => AccountEditSheet(
        account: effectiveAccount,
        recentTransactions: recentTransactions,
        onToggleLiquid: onToggleLiquid,
        onUpdateCashBalance: onUpdateCashBalance,
      ),
    );
  }

  @override
  State<AccountEditSheet> createState() => _AccountEditSheetState();
}

class _AccountEditSheetState extends State<AccountEditSheet> {
  late bool _isLiquid;
  late TextEditingController _cashController;

  @override
  void initState() {
    super.initState();
    final a = widget.account;
    _isLiquid = (a['type'] as String? ?? 'liquid') == 'liquid' && (a['is_savings'] != 1);
    final bal = (a['balance'] as num?)?.toDouble() ??
        (a['last_known_balance'] as num?)?.toDouble() ??
        0.0;
    _cashController = TextEditingController(text: bal.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _cashController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.account;
    final provider = (a['provider'] as String? ?? 'ACCOUNT').toUpperCase();
    final name = a['name'] as String? ?? 'Account';
    final mask = a['mask'] as String? ?? a['account_mask'] as String? ?? '';
    final bal = (a['balance'] as num?)?.toDouble() ??
        (a['last_known_balance'] as num?)?.toDouble() ??
        0.0;
    final unproc = (a['unprocessed'] as num?)?.toInt() ?? 0;
    final isCash = provider == 'CASH';

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
                Text(name, style: AppTypography.titleLarge),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.text2),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Top Row: Brand Badge + Info
            Row(
              children: [
                BrandBadge(provider: provider, size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('$provider • $mask', style: AppTypography.bodySmall.copyWith(color: AppColors.text3)),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Big balance
            Text(
              'ETB ${bal.toStringAsFixed(2)}',
              style: AppTypography.displayMedium.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              'Reconciled balance${unproc > 0 ? " · $unproc messages waiting to be parsed" : ""}',
              style: AppTypography.bodySmall.copyWith(color: AppColors.text3),
            ),

            const SizedBox(height: 18),

            // Liquid account toggle row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined, color: AppColors.text2, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Count toward safe-to-spend', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(
                          _isLiquid ? 'Liquid account' : 'Savings · excluded',
                          style: TextStyle(color: AppColors.text3, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _isLiquid,
                    activeColor: AppColors.income,
                    onChanged: (val) {
                      setState(() => _isLiquid = val);
                      widget.onToggleLiquid?.call(val);
                    },
                  ),
                ],
              ),
            ),

            if (isCash) ...[
              const SizedBox(height: 16),
              Text('Update cash on hand', style: AppTypography.labelSmall.copyWith(color: AppColors.text2)),
              const SizedBox(height: 6),
              TextField(
                controller: _cashController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  prefixText: 'ETB ',
                  helperText: 'Cash is not tracked by SMS — adjust it when you count your wallet.',
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  final newAmt = double.tryParse(_cashController.text.replaceAll(',', '').trim()) ?? 0.0;
                  widget.onUpdateCashBalance?.call(newAmt);
                  Navigator.pop(context);
                },
                child: const Text('Save balance'),
              ),
            ],

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

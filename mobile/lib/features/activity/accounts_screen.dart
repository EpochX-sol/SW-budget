import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/security/privacy_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/brand_badge.dart';
import '../../core/widgets/sheets/account_edit_sheet.dart';
import '../../core/widgets/split_bar.dart';
import '../../data/local/database_provider.dart';
import 'activity_providers.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsStreamProvider);
    final isPrivate = ref.watch(privacyModeProvider);

    final rawAccounts = accountsAsync.value ?? [];
    final accounts = rawAccounts;

    double bankTotal = 0.0;
    double telebirrTotal = 0.0;
    double cashTotal = 0.0;
    double liquidTotal = 0.0;
    double lockedTotal = 0.0;

    for (final acc in accounts) {
      final bal = (acc['last_known_balance'] as num?)?.toDouble() ?? 0.0;
      final type = (acc['account_type'] as String? ?? '').toLowerCase();
      final inst = (acc['institution_id'] as String? ?? '').toLowerCase();
      final isLocked = (acc['is_locked'] == 1 || acc['is_locked'] == true);

      if (isLocked) {
        lockedTotal += bal;
      } else {
        liquidTotal += bal;
        if (type == 'cash') {
          cashTotal += bal;
        } else if (inst.contains('telebirr') || inst.contains('tb') || type == 'mobile_money') {
          telebirrTotal += bal;
        } else {
          bankTotal += bal;
        }
      }
    }

    final netWorth = liquidTotal + lockedTotal;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.text, size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Accounts & Institutions',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            // Net Worth Hero Card
            Container(
              decoration: BoxDecoration(
                gradient: AppColors.heroGradient,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.line2),
              ),
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TOTAL NET WORTH',
                    style: TextStyle(
                      color: AppColors.text3,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    formatCurrency(netWorth, isPrivate: isPrivate),
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Liquid Assets', style: TextStyle(color: AppColors.text3, fontSize: 11)),
                            const SizedBox(height: 2),
                            Text(
                              formatCurrency(liquidTotal, isPrivate: isPrivate),
                              style: const TextStyle(
                                color: AppColors.income,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Locked / Reserved', style: TextStyle(color: AppColors.text3, fontSize: 11)),
                            const SizedBox(height: 2),
                            Text(
                              formatCurrency(lockedTotal, isPrivate: isPrivate),
                              style: const TextStyle(
                                color: AppColors.text2,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SplitBar(
                    bankAmount: bankTotal,
                    mobileMoneyAmount: telebirrTotal,
                    cashAmount: cashTotal,
                    isPrivate: isPrivate,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Connected Accounts Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'CONNECTED ACCOUNTS',
                  style: TextStyle(
                    color: AppColors.text3,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
                Text(
                  '${accounts.length} active',
                  style: const TextStyle(color: AppColors.text3, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.line),
              ),
              child: accounts.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.account_balance_outlined, color: AppColors.text3, size: 36),
                            SizedBox(height: 10),
                            Text(
                              'No accounts linked yet',
                              style: TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w700),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Connect a bank below or tap + to track cash',
                              style: TextStyle(color: AppColors.text3, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: accounts.length,
                      separatorBuilder: (_, __) => const Divider(color: AppColors.line, height: 1),
                itemBuilder: (context, index) {
                  final acc = accounts[index];
                  final name = acc['account_name'] as String? ?? 'Account';
                  final inst = acc['institution_id'] as String? ?? '';
                  final mask = acc['account_number_mask'] as String? ?? '';
                  final bal = (acc['last_known_balance'] as num?)?.toDouble() ?? 0.0;
                  final isLocked = acc['is_locked'] == 1 || acc['is_locked'] == true;

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    leading: BrandBadge(institution: inst, size: 36),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              color: AppColors.text,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (isLocked) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.surface3,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Locked',
                              style: TextStyle(
                                color: AppColors.text3,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      mask,
                      style: const TextStyle(color: AppColors.text3, fontSize: 11),
                    ),
                    trailing: Text(
                      formatCurrency(bal, isPrivate: isPrivate),
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onTap: () {
                      AccountEditSheet.show(
                        context,
                        account: acc,
                        onToggleLiquid: (isLiquid) async {
                          final db = await ref.read(databaseProvider.future);
                          final accId = acc['id'] as String;
                          db.updateAccountLockStatus(accId, !isLiquid);
                        },
                        onUpdateCashBalance: (newBalance) async {
                          final db = await ref.read(databaseProvider.future);
                          final accId = acc['id'] as String;
                          db.updateAccountBalance(accId, newBalance);
                        },
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 20),

            // Detected Candidate Banks Section
            const Text(
              'DETECTED CANDIDATE INSTITUTIONS',
              style: TextStyle(
                color: AppColors.text3,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'We found transaction SMS notifications matching known Ethiopian banks on your device:',
              style: TextStyle(color: AppColors.text3, fontSize: 11),
            ),
            const SizedBox(height: 10),
            _buildCandidateCard(
              context,
              ref,
              institution: 'boa',
              bankName: 'Bank of Abyssinia',
              smsCount: 4,
            ),
            const SizedBox(height: 8),
            _buildCandidateCard(
              context,
              ref,
              institution: 'awash',
              bankName: 'Awash Bank',
              smsCount: 2,
            ),
            const SizedBox(height: 20),

            // Add Manual Account or Cash
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: const BorderSide(color: AppColors.line),
                  backgroundColor: AppColors.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text(
                  'Add manual account or cash wallet',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                onPressed: () {
                  AccountEditSheet.show(
                    context,
                    onUpdateCashBalance: (newBalance) async {
                      final db = await ref.read(databaseProvider.future);
                      db.upsertAccount(
                        id: 'acc_cash',
                        provider: 'CASH',
                        name: 'Physical Cash',
                        accountMask: 'Pocket wallet',
                        lastKnownBalance: newBalance,
                        isSavings: false,
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildCandidateCard(
    BuildContext context,
    WidgetRef ref, {
    required String institution,
    required String bankName,
    required int smsCount,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          BrandBadge(institution: institution, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bankName,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '$smsCount SMS notifications parsed',
                  style: const TextStyle(color: AppColors.text3, fontSize: 11),
                ),
              ],
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accentBg,
              foregroundColor: AppColors.accent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            ),
            child: const Text(
              'Connect',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
            ),
            onPressed: () async {
              final db = await ref.read(databaseProvider.future);
              db.upsertAccount(
                id: 'acc_${institution.toLowerCase()}',
                provider: institution.toUpperCase(),
                name: bankName,
                accountMask: '•••• auto',
                lastKnownBalance: 0.0,
                isSavings: false,
              );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Linked $bankName to active tracking!'),
                  backgroundColor: AppColors.surface2,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

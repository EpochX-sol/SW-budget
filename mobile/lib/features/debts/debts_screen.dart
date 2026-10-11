import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/security/privacy_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sheets/debt_edit_sheet.dart';
import 'debts_providers.dart';

class DebtsScreen extends ConsumerStatefulWidget {
  const DebtsScreen({super.key});

  @override
  ConsumerState<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends ConsumerState<DebtsScreen> {
  int _selectedTab = 0; // 0: Owed to me, 1: I owe, 2: Reimburse

  @override
  Widget build(BuildContext context) {
    final isPrivate = ref.watch(privacyModeProvider);
    final debtsAsync = ref.watch(debtsStreamProvider);
    final reimbAsync = ref.watch(reimbursementsStreamProvider);

    final allDebts = debtsAsync.value ?? [];
    final allReimbursements = reimbAsync.value ?? [];

    final liveOwedToMe = allDebts
        .where((d) => d['direction'] == 'owed_to_me' && d['status'] == 'active')
        .toList();
    final liveIOwe = allDebts
        .where((d) => d['direction'] == 'i_owe' && d['status'] == 'active')
        .toList();
    final liveReimb = allReimbursements
        .where((r) => r['status'] == 'pending')
        .toList();

    final effectiveOwedToMe = liveOwedToMe;
    final effectiveIOwe = liveIOwe;
    final effectiveReimb = liveReimb;

    // Compute totals
    double totalOwedToMe = 0.0;
    for (final d in effectiveOwedToMe) {
      final total = ((d['total_amount'] ?? d['amount']) as num?)?.toDouble() ?? 0.0;
      final paid = ((d['paid_amount'] ?? d['paid']) as num?)?.toDouble() ?? 0.0;
      totalOwedToMe += (total - paid);
    }
    double totalIOwe = 0.0;
    for (final d in effectiveIOwe) {
      final total = ((d['total_amount'] ?? d['amount']) as num?)?.toDouble() ?? 0.0;
      final paid = ((d['paid_amount'] ?? d['paid']) as num?)?.toDouble() ?? 0.0;
      totalIOwe += (total - paid);
    }

    final currentList = _selectedTab == 0
        ? effectiveOwedToMe
        : _selectedTab == 1
            ? effectiveIOwe
            : effectiveReimb;

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
          'Debts & Reimbursements',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.accent,
        foregroundColor: const Color(0xFF080C14),
        shape: const CircleBorder(),
        child: const Icon(Icons.add, size: 28),
        onPressed: () => DebtEditSheet.show(
          context,
          initialIsOwed: _selectedTab == 0,
          onSave: ({
            required bool isOwed,
            required String who,
            required double amount,
            required String? dueDate,
            required String note,
          }) {
            if (_selectedTab == 2) {
              ref.read(debtsControllerProvider).addReimbursement(
                    title: who,
                    amount: amount,
                    note: note,
                  );
            } else {
              ref.read(debtsControllerProvider).addDebt(
                    isOwed: isOwed,
                    who: who,
                    amount: amount,
                    dueDate: dueDate,
                    note: note,
                  );
            }
          },
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            // Summary Cards Row
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.arrow_downward_rounded, color: AppColors.income, size: 14),
                            SizedBox(width: 4),
                            Text('Owed to you', style: TextStyle(color: AppColors.text3, fontSize: 11)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          formatCurrency(totalOwedToMe, isPrivate: isPrivate),
                          style: const TextStyle(
                            color: AppColors.income,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.arrow_upward_rounded, color: AppColors.expense, size: 14),
                            SizedBox(width: 4),
                            Text('You owe', style: TextStyle(color: AppColors.text3, fontSize: 11)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          formatCurrency(totalIOwe, isPrivate: isPrivate),
                          style: const TextStyle(
                            color: AppColors.expense,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Segmented Switcher: Owed to me | I owe | Reimburse
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.line),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  _buildTabOption(0, 'Owed to me'),
                  _buildTabOption(1, 'I owe'),
                  _buildTabOption(2, 'Reimburse'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // List of items
            if (currentList.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.line),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.handshake_outlined, color: AppColors.text3, size: 36),
                    const SizedBox(height: 10),
                    Text(
                      _selectedTab == 0
                          ? 'No money owed to you'
                          : _selectedTab == 1
                              ? 'You have no outstanding debts'
                              : 'No pending reimbursement claims',
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Tap + Record below to add a loan, debt, or expense claim',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.text3, fontSize: 11),
                    ),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: currentList.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = currentList[index];
                  final name = (item['counterparty'] ?? item['title'] ?? item['name'] ?? 'Record') as String;
                  final total = ((item['total_amount'] ?? item['amount']) as num?)?.toDouble() ?? 0.0;
                  final paid = ((item['paid_amount'] ?? item['paid']) as num?)?.toDouble() ?? 0.0;
                  final remaining = total - paid;
                  final due = (item['due_date'] ?? item['due'] ?? '') as String;
                  final note = (item['note'] ?? '') as String;
                  final ratio = total > 0 ? (paid / total).clamp(0.0, 1.0) : 0.0;

                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                color: AppColors.text,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              formatCurrency(remaining, isPrivate: isPrivate),
                              style: TextStyle(
                                color: _selectedTab == 0
                                    ? AppColors.income
                                    : _selectedTab == 1
                                        ? AppColors.expense
                                        : AppColors.accent,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          note,
                          style: const TextStyle(color: AppColors.text3, fontSize: 11),
                        ),
                        const SizedBox(height: 10),
                        // Progress bar
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${formatCurrency(paid, isPrivate: isPrivate)} of ${formatCurrency(total, isPrivate: isPrivate)} paid',
                              style: const TextStyle(color: AppColors.text3, fontSize: 10),
                            ),
                            Text(
                              '${(ratio * 100).toInt()}%',
                              style: const TextStyle(
                                color: AppColors.text2,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: ratio,
                            backgroundColor: AppColors.surface3,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _selectedTab == 0 ? AppColors.income : AppColors.accent,
                            ),
                            minHeight: 4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              due,
                              style: const TextStyle(
                                color: AppColors.text3,
                                fontSize: 11,
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                final itemId = item['id'] as String? ?? '';
                                if (_selectedTab == 2) {
                                  ref.read(debtsControllerProvider).settleReimbursement(itemId);
                                } else {
                                  ref.read(debtsControllerProvider).settleDebt(itemId);
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Settled payment for $name'),
                                    backgroundColor: AppColors.surface2,
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: AppColors.surface2,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.line),
                                ),
                                child: const Text(
                                  'Settle',
                                  style: TextStyle(
                                    color: AppColors.accent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildTabOption(int index, String label) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedTab = index;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.accentBg : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppColors.accent.withOpacity(0.5) : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? AppColors.accent : AppColors.text3,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

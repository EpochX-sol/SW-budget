import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/security/privacy_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/sheets/add_transaction_sheet.dart';
import '../../core/widgets/sheets/transaction_detail_sheet.dart';
import 'activity_providers.dart';

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  String _activeFilter = 'All';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  static const _filters = [
    'All',
    'Expenses',
    'Income',
    'Transfers',
    'Needs review',
    'Gaps',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final transactionsAsync = ref.watch(transactionsProvider);
    final reviewCountAsync = ref.watch(reviewInboxCountProvider);
    final isPrivate = ref.watch(privacyModeProvider);

    final rawTransactions = transactionsAsync.value ?? [];
    final reviewCount = reviewCountAsync.value ?? 0;

    // Filter transactions
    final filtered = rawTransactions.where((tx) {
      final type = (tx['type'] as String? ?? '').toLowerCase();
      final party = ((tx['counterparty'] ?? tx['merchant'] ?? '') as String).toLowerCase();
      final note = (tx['note'] as String? ?? '').toLowerCase();
      final category = (tx['category_id'] as String? ?? '').toLowerCase();
      final isReview = (tx['needs_review'] == 1 || tx['needs_review'] == true);
      final isGap = (tx['is_gap'] == 1 || tx['is_gap'] == true || type.contains('gap'));

      // Text search
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchesQuery = party.contains(q) || note.contains(q) || category.contains(q);
        if (!matchesQuery) return false;
      }

      // Filter chips
      switch (_activeFilter) {
        case 'Expenses':
          return type == 'debit' || type == 'expense';
        case 'Income':
          return type == 'credit' || type == 'income';
        case 'Transfers':
          return type == 'transfer';
        case 'Needs review':
          return isReview;
        case 'Gaps':
          return isGap;
        case 'All':
        default:
          return true;
      }
    }).toList();

    // Calculate In / Out summary
    double totalInflow = 0.0;
    double totalOutflow = 0.0;
    for (final tx in rawTransactions) {
      final type = (tx['type'] as String? ?? '').toLowerCase();
      final amt = (tx['amount'] as num?)?.toDouble() ?? 0.0;
      if (type == 'credit' || type == 'income') {
        totalInflow += amt;
      } else if (type == 'debit' || type == 'expense') {
        totalOutflow += amt;
      }
    }

    // Prototype fallback if empty
    if (rawTransactions.isEmpty) {
      totalInflow = 45000.00;
      totalOutflow = 18095.39;
    }

    // Group by Date
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final tx in filtered) {
      final dtStr = tx['occurred_at'] as String? ?? '';
      String dayKey = 'Earlier';
      if (dtStr.isNotEmpty) {
        final dt = DateTime.tryParse(dtStr);
        if (dt != null) {
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final dateDay = DateTime(dt.year, dt.month, dt.day);
          final diff = today.difference(dateDay).inDays;
          if (diff == 0) {
            dayKey = 'Today';
          } else if (diff == 1) {
            dayKey = 'Yesterday';
          } else {
            dayKey = DateFormat('EEEE, MMM d').format(dt);
          }
        }
      }
      grouped.putIfAbsent(dayKey, () => []).add(tx);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.accent,
        foregroundColor: const Color(0xFF080C14),
        shape: const CircleBorder(),
        child: const Icon(Icons.add, size: 28),
        onPressed: () {
          final accounts = ref.read(accountsStreamProvider).value ?? [];
          AddTransactionSheet.show(
            context,
            accounts: accounts,
            onSubmit: ({
              required bool isExpense,
              required double amount,
              required String counterparty,
              required String accountId,
              required String category,
              required String note,
            }) {
              ref.read(transactionControllerProvider).addTransaction(
                    isExpense: isExpense,
                    amount: amount,
                    counterparty: counterparty,
                    accountId: accountId,
                    category: category,
                    note: note,
                  );
            },
          );
        },
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 1. Header with Title & Review Badge Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Activity',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => context.push('/review-inbox'),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.line),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.inbox_outlined,
                            color: AppColors.text2,
                            size: 20,
                          ),
                        ),
                        if (reviewCount > 0)
                          Positioned(
                            top: -4,
                            right: -4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.amber,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$reviewCount',
                                style: const TextStyle(
                                  color: Color(0xFF080C14),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 2. Search Input Field
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.line),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: AppColors.text3, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(color: AppColors.text, fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: 'Search merchant, note, or amount...',
                          hintStyle: TextStyle(color: AppColors.text3, fontSize: 13),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onChanged: (val) {
                          setState(() {
                            _searchQuery = val;
                          });
                        },
                      ),
                    ),
                    if (_searchQuery.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                        child: const Icon(Icons.close, color: AppColors.text3, size: 18),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // 3. Filter Chips
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _filters.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final f = _filters[index];
                  final isSelected = _activeFilter == f;

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _activeFilter = f;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.accentBg : AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? AppColors.accent : AppColors.line,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        f,
                        style: TextStyle(
                          color: isSelected ? AppColors.accent : AppColors.text2,
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),

            // 4. In / Out Summary Cards
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.arrow_downward_rounded, color: AppColors.income, size: 14),
                              SizedBox(width: 4),
                              Text(
                                'Inflow',
                                style: TextStyle(color: AppColors.text3, fontSize: 11),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            formatCurrency(totalInflow, isPrivate: isPrivate),
                            style: const TextStyle(
                              color: AppColors.income,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.arrow_upward_rounded, color: AppColors.expense, size: 14),
                              SizedBox(width: 4),
                              Text(
                                'Outflow',
                                style: TextStyle(color: AppColors.text3, fontSize: 11),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            formatCurrency(totalOutflow, isPrivate: isPrivate),
                            style: const TextStyle(
                              color: AppColors.expense,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // 5. Date-Grouped Transaction List
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.receipt_long_outlined, color: AppColors.text3, size: 40),
                          const SizedBox(height: 12),
                          Text(
                            _searchQuery.isNotEmpty || _activeFilter != 'All'
                                ? 'No transactions match "$_activeFilter"'
                                : 'No recorded transactions yet',
                            style: const TextStyle(color: AppColors.text3, fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 80),
                      itemCount: grouped.keys.length,
                      itemBuilder: (context, groupIndex) {
                        final dayKey = grouped.keys.elementAt(groupIndex);
                        final txns = grouped[dayKey]!;

                        // Calculate day total outflow
                        double dayOutflow = 0.0;
                        for (final t in txns) {
                          final type = (t['type'] as String? ?? '').toLowerCase();
                          if (type == 'debit' || type == 'expense') {
                            dayOutflow += (t['amount'] as num?)?.toDouble() ?? 0.0;
                          }
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Sticky Day Header
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    dayKey,
                                    style: const TextStyle(
                                      color: AppColors.text3,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  if (dayOutflow > 0)
                                    Text(
                                      'Out: ${formatCurrency(dayOutflow, isPrivate: isPrivate)}',
                                      style: const TextStyle(
                                        color: AppColors.text3,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            // Group Card Container
                            Container(
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppColors.line),
                              ),
                              child: ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: txns.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(color: AppColors.line, height: 1),
                                itemBuilder: (context, index) {
                                  final tx = txns[index];
                                  final party = ((tx['counterparty'] ?? tx['merchant'] ?? 'Transaction')
                                      as String);
                                  final type = (tx['type'] as String? ?? 'debit').toLowerCase();
                                  final isCredit = type == 'credit' || type == 'income';
                                  final isTransfer = type == 'transfer';
                                  final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
                                  final occurredAt = tx['occurred_at'] as String? ?? '';
                                  final isVerified =
                                      tx['is_verified'] == 1 || tx['is_verified'] == true;
                                  final isGap =
                                      tx['is_gap'] == 1 || tx['is_gap'] == true || type.contains('gap');
                                  final route = (tx['account_route'] ?? tx['channel'] ?? '') as String;

                                  String timeStr = '';
                                  if (occurredAt.isNotEmpty) {
                                    final dt = DateTime.tryParse(occurredAt);
                                    if (dt != null) {
                                      timeStr = DateFormat('h:mm a').format(dt);
                                    }
                                  }

                                  return ListTile(
                                    contentPadding:
                                        const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                                    leading: Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: isGap
                                            ? AppColors.amberBg
                                            : isCredit
                                                ? AppColors.incomeBg
                                                : isTransfer
                                                    ? AppColors.accentBg
                                                    : AppColors.surface2,
                                        shape: BoxShape.circle,
                                      ),
                                      alignment: Alignment.center,
                                      child: Icon(
                                        isGap
                                            ? Icons.warning_amber_rounded
                                            : isCredit
                                                ? Icons.arrow_downward_rounded
                                                : isTransfer
                                                    ? Icons.swap_horiz_rounded
                                                    : Icons.shopping_bag_outlined,
                                        color: isGap
                                            ? AppColors.amber
                                            : isCredit
                                                ? AppColors.income
                                                : isTransfer
                                                    ? AppColors.accent
                                                    : AppColors.text2,
                                        size: 18,
                                      ),
                                    ),
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            party.isEmpty ? 'Transaction' : party,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: AppColors.text,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        if (isVerified) ...[
                                          const SizedBox(width: 4),
                                          const Icon(
                                            Icons.verified_rounded,
                                            color: AppColors.income,
                                            size: 14,
                                          ),
                                        ],
                                        if (isGap) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppColors.amberBg,
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Text(
                                              'GAP',
                                              style: TextStyle(
                                                color: AppColors.amber,
                                                fontSize: 9,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    subtitle: Text(
                                      route.isNotEmpty
                                          ? '$timeStr · $route'
                                          : timeStr,
                                      style: const TextStyle(
                                        color: AppColors.text3,
                                        fontSize: 11,
                                      ),
                                    ),
                                    trailing: Text(
                                      '${isCredit ? '+' : isTransfer ? '' : '-'}${formatCurrency(amount, isPrivate: isPrivate)}',
                                      style: TextStyle(
                                        color: isCredit
                                            ? AppColors.income
                                            : isTransfer
                                                ? AppColors.accent
                                                : AppColors.expense,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    onTap: () {
                                      final txId = (tx['id'] as String?) ?? '';
                                       TransactionDetailSheet.show(
                                         context,
                                         transaction: tx,
                                         onSave: (newCat, newNote) {
                                           if (txId.isNotEmpty) {
                                             ref.read(transactionControllerProvider).updateDetails(
                                                   id: txId,
                                                   category: newCat,
                                                   note: newNote,
                                                 );
                                           }
                                         },
                                         onMarkTransfer: () {
                                           if (txId.isNotEmpty) {
                                             ref.read(transactionControllerProvider).markTransfer(txId);
                                           }
                                         },
                                         onDelete: () {
                                           if (txId.isNotEmpty) {
                                             ref.read(transactionControllerProvider).delete(txId);
                                           }
                                         },
                                       );
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

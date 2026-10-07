import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/sync/sync_provider.dart';
import 'activity_providers.dart';

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  String _selectedFilter = 'ALL';

  @override
  Widget build(BuildContext context) {
    final transactionsAsync = ref.watch(transactionsProvider);
    final reviewCountAsync = ref.watch(reviewInboxCountProvider);
    final syncState = ref.watch(syncStateProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Activity & Ledger', style: AppTypography.titleLarge),
        actions: [
          // Review Inbox badge
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.inbox_rounded, color: AppColors.textPrimary),
                reviewCountAsync.when(
                  data: (count) => count > 0
                      ? Positioned(
                          right: -4,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: AppColors.secondary,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                            child: Text(
                              '$count',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ],
            ),
            tooltip: 'Review Inbox',
            onPressed: () => context.push('/review-inbox'),
          ),

          // Manual sync button
          IconButton(
            icon: syncState.isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryLight),
                  )
                : const Icon(Icons.sync_rounded, color: AppColors.textSecondary),
            tooltip: 'Sync Changes',
            onPressed: () => ref.read(syncStateProvider.notifier).triggerSync(),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Filter Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                children: [
                  _FilterChip(
                    label: 'All Activity',
                    isSelected: _selectedFilter == 'ALL',
                    onTap: () => setState(() => _selectedFilter = 'ALL'),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Telebirr',
                    isSelected: _selectedFilter == 'TELEBIRR',
                    onTap: () => setState(() => _selectedFilter = 'TELEBIRR'),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'CBE',
                    isSelected: _selectedFilter == 'CBE',
                    onTap: () => setState(() => _selectedFilter = 'CBE'),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Abyssinia',
                    isSelected: _selectedFilter == 'BOA',
                    onTap: () => setState(() => _selectedFilter = 'BOA'),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Needs Review',
                    isSelected: _selectedFilter == 'REVIEW',
                    onTap: () => setState(() => _selectedFilter = 'REVIEW'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Transactions Feed
            Expanded(
              child: transactionsAsync.when(
                data: (transactions) {
                  final filtered = _filterTransactions(transactions);

                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 64,
                            color: AppColors.textMuted.withOpacity(0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No transactions recorded yet',
                            style: AppTypography.titleMedium.copyWith(color: AppColors.textSecondary),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Incoming banking SMS or notifications will appear here automatically.',
                            textAlign: TextAlign.center,
                            style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () => ref.read(syncStateProvider.notifier).triggerSync(),
                    color: AppColors.primaryLight,
                    backgroundColor: AppColors.surface,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final txn = filtered[index];
                        return _TransactionCard(txn: txn);
                      },
                    ),
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.primaryLight),
                ),
                error: (error, _) => Center(
                  child: Text(
                    'Error loading ledger: $error',
                    style: AppTypography.bodyMedium.copyWith(color: AppColors.expense),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _filterTransactions(List<Map<String, dynamic>> list) {
    if (_selectedFilter == 'ALL') return list;
    if (_selectedFilter == 'REVIEW') {
      return list.where((t) => t['needs_review'] == 1 || t['needs_review'] == true).toList();
    }
    return list.where((t) {
      final sender = (t['sender'] as String? ?? '').toUpperCase();
      final dedupe = (t['dedupe_key'] as String? ?? '').toUpperCase();
      return sender.contains(_selectedFilter) || dedupe.contains(_selectedFilter);
    }).toList();
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primaryLight : AppColors.border,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  final Map<String, dynamic> txn;

  const _TransactionCard({required this.txn});

  @override
  Widget build(BuildContext context) {
    final amount = (txn['amount'] as num?)?.toDouble() ?? 0.0;
    final balanceAfter = (txn['balance_after'] as num?)?.toDouble();
    final type = (txn['type'] as String? ?? 'expense').toLowerCase();
    final counterparty = txn['counterparty'] as String? ?? 'Direct Transaction';
    final occurredAt = DateTime.tryParse(txn['occurred_at'] as String? ?? '') ?? DateTime.now();
    final timeFormatted = DateFormat('MMM d, h:mm a').format(occurredAt);

    final balanceChainOk = txn['balance_chain_ok'];
    final gapAmount = (txn['gap_before_amount'] as num?)?.toDouble();
    final hasGap = balanceChainOk == 0 && gapAmount != null && gapAmount > 0;
    final isVerified = balanceChainOk == 1;

    final isIncome = type == 'income';
    final amountText = '${isIncome ? '+' : '-'} ${amount.toStringAsFixed(2)} ETB';
    final amountColor = isIncome ? AppColors.incomeLight : AppColors.textPrimary;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasGap ? AppColors.secondary.withOpacity(0.5) : AppColors.border,
          width: hasGap ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          // Gap Warning Banner if balance discrepancy was computed
          if (hasGap) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.warningSurface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.secondary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Missing Gap Detected: ${gapAmount.toStringAsFixed(2)} ETB unaccounted before this event.',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.secondaryLight,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                // Direction Icon
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isIncome ? AppColors.incomeSurface : AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isIncome ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                    color: isIncome ? AppColors.incomeLight : AppColors.expense,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),

                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        counterparty,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(timeFormatted, style: AppTypography.labelSmall.copyWith(color: AppColors.textMuted)),
                          const SizedBox(width: 8),
                          if (isVerified) ...[
                            const Icon(Icons.verified_rounded, size: 14, color: AppColors.incomeLight),
                            const SizedBox(width: 2),
                            Text(
                              'Verified',
                              style: AppTypography.labelSmall.copyWith(
                                color: AppColors.incomeLight,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // Amount & Running Balance
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      amountText,
                      style: AppTypography.titleMedium.copyWith(
                        fontWeight: FontWeight.w800,
                        color: amountColor,
                      ),
                    ),
                    if (balanceAfter != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Bal: ${balanceAfter.toStringAsFixed(2)}',
                        style: AppTypography.labelSmall.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

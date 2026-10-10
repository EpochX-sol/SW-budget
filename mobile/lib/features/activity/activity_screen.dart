import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/sync/sync_provider.dart';
import 'activity_providers.dart';
import 'widgets/bank_tile_card.dart';

enum _ActivityViewTab { activity, accounts }

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  _ActivityViewTab _currentTab = _ActivityViewTab.activity;
  String _selectedFilter = 'ALL';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final transactionsAsync = ref.watch(transactionsProvider);
    final accountsAsync = ref.watch(accountsStreamProvider);
    final reviewCountAsync = ref.watch(reviewInboxCountProvider);
    final syncState = ref.watch(syncStateProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _currentTab == _ActivityViewTab.activity ? 'Activity & Ledger' : 'Connected Banks',
          style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.bold),
        ),
        actions: [
          // Review Inbox shortcut
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
            // Segmented Top Tab Switcher: [ Activity | Accounts ]
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Expanded(
                      child: _SegmentTabButton(
                        label: 'Activity',
                        icon: Icons.receipt_long_rounded,
                        isSelected: _currentTab == _ActivityViewTab.activity,
                        onTap: () => setState(() => _currentTab = _ActivityViewTab.activity),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _SegmentTabButton(
                        label: 'Accounts',
                        icon: Icons.account_balance_rounded,
                        isSelected: _currentTab == _ActivityViewTab.accounts,
                        onTap: () => setState(() => _currentTab = _ActivityViewTab.accounts),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 6),

            // Main Tab Viewport
            Expanded(
              child: _currentTab == _ActivityViewTab.activity
                  ? _buildActivityView(transactionsAsync)
                  : _buildAccountsView(accountsAsync, transactionsAsync),
            ),
          ],
        ),
      ),
    );
  }

  // --- ACCOUNTS 2-COLUMN VIEW (Matching Totals) ---

  Widget _buildAccountsView(
    AsyncValue<List<Map<String, dynamic>>> accountsAsync,
    AsyncValue<List<Map<String, dynamic>>> transactionsAsync,
  ) {
    return accountsAsync.when(
      data: (accounts) {
        final transactions = transactionsAsync.value ?? [];
        double totalBalance = 0.0;
        double totalIncome = 0.0;
        double totalExpense = 0.0;

        for (final acc in accounts) {
          final bal = (acc['last_known_balance'] as num?)?.toDouble() ?? 0.0;
          totalBalance += bal;
        }

        for (final tx in transactions) {
          final type = (tx['type'] as String? ?? 'debit').toLowerCase();
          final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
          if (type == 'credit' || type == 'income') {
            totalIncome += amount;
          } else {
            totalExpense += amount;
          }
        }

        // Distinct Banks
        final Set<String> banks = {};
        for (final acc in accounts) {
          final provider = (acc['provider'] as String? ?? 'ACCOUNT').toUpperCase();
          banks.add(provider);
        }

        return RefreshIndicator(
          color: AppColors.primaryLight,
          backgroundColor: AppColors.surface,
          onRefresh: () async => ref.invalidate(accountsStreamProvider),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Totals-style Aggregate Stats Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TOTAL RECONCILED BALANCE',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.textMuted,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'ETB ${totalBalance.toStringAsFixed(2)}',
                        style: AppTypography.displayMedium.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${banks.length} Banks | ${accounts.length} Accounts | ${transactions.length} Transactions',
                        style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                      ),
                      const Divider(color: AppColors.border, height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                const Icon(Icons.arrow_downward_rounded, color: AppColors.income, size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  '+ETB ${_formatK(totalIncome)}',
                                  style: AppTypography.labelMedium.copyWith(
                                    color: AppColors.income,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Row(
                              children: [
                                const Icon(Icons.arrow_upward_rounded, color: AppColors.expense, size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  '-ETB ${_formatK(totalExpense)}',
                                  style: AppTypography.labelMedium.copyWith(
                                    color: AppColors.expense,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                Text(
                  'Connected Bank Accounts',
                  style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                // 2-Column Responsive Grid of Bank Tiles
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.15,
                  children: [
                    // Always show Cash Wallet
                    const BankTileCard(
                      title: 'Cash Wallet',
                      subtitle: 'On-hand cash',
                      balance: 'Not in total balance',
                      brandColor: AppColors.bankCash,
                      icon: Icons.account_balance_wallet_rounded,
                    ),

                    // Live linked accounts
                    ...accounts.map((acc) {
                      final provider = (acc['provider'] as String? ?? 'ACCOUNT').toUpperCase();
                      final name = acc['name'] as String? ?? 'Bank Account';
                      final mask = acc['account_mask'] as String? ?? '';
                      final subtitle = mask.isNotEmpty ? '•••• $mask' : '1 Account';
                      final balVal = (acc['last_known_balance'] as num?)?.toDouble() ?? 0.0;
                      final balStr = 'ETB ${balVal.toStringAsFixed(2)}';

                      Color brandColor = AppColors.primary;
                      IconData brandIcon = Icons.account_balance_rounded;

                      if (provider.contains('TELEBIRR') || provider == '127') {
                        brandColor = AppColors.bankTelebirr;
                        brandIcon = Icons.phone_android_rounded;
                      } else if (provider.contains('CBE')) {
                        brandColor = AppColors.bankCbe;
                        brandIcon = Icons.account_balance_rounded;
                      } else if (provider.contains('BOA') || provider.contains('ABYSSINIA')) {
                        brandColor = AppColors.bankAbyssinia;
                        brandIcon = Icons.account_balance_wallet_rounded;
                      } else if (provider.contains('AWASH')) {
                        brandColor = AppColors.bankAwash;
                        brandIcon = Icons.business_rounded;
                      }

                      return BankTileCard(
                        title: name,
                        subtitle: subtitle,
                        balance: balStr,
                        brandColor: brandColor,
                        icon: brandIcon,
                        onTap: () => _showAccountDetailsSheet(acc),
                      );
                    }),

                    // Candidate detected bank cards (from Totals pattern)
                    BankTileCard(
                      title: 'CBE Birr',
                      subtitle: 'Mobile Banking',
                      isCandidate: true,
                      messageCount: 312,
                      brandColor: AppColors.bankCbe,
                      icon: Icons.mobile_friendly_rounded,
                      onTap: () => _showCandidatePrompt('CBE Birr'),
                    ),
                    BankTileCard(
                      title: 'Apollo',
                      subtitle: 'Digital Banking',
                      isCandidate: true,
                      messageCount: 73,
                      brandColor: AppColors.primaryLight,
                      icon: Icons.credit_card_rounded,
                      onTap: () => _showCandidatePrompt('Apollo'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: AppColors.primaryLight),
      ),
      error: (e, _) => Center(
        child: Text('Error loading accounts: $e', style: const TextStyle(color: AppColors.expense)),
      ),
    );
  }

  // --- ACTIVITY FEED VIEW ---

  Widget _buildActivityView(AsyncValue<List<Map<String, dynamic>>> transactionsAsync) {
    return Column(
      children: [
        // Search & Filter Box
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, size: 20, color: AppColors.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                    style: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      hintText: 'Search merchant, ref number, or amount...',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                    },
                    child: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
                  ),
              ],
            ),
          ),
        ),

        // Filter Chips Horizontal Bar
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
                        size: 60,
                        color: AppColors.textMuted.withOpacity(0.4),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'No matching transactions found',
                        style: AppTypography.titleMedium.copyWith(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Try clearing your filters or search keywords.',
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
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final txn = filtered[index];
                    return _TransactionCard(
                      txn: txn,
                      onTap: () => _showTransactionDetails(txn),
                    );
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
    );
  }

  List<Map<String, dynamic>> _filterTransactions(List<Map<String, dynamic>> list) {
    var result = list;

    if (_selectedFilter == 'REVIEW') {
      result = result.where((t) => t['needs_review'] == 1 || t['needs_review'] == true).toList();
    } else if (_selectedFilter != 'ALL') {
      result = result.where((t) {
        final sender = (t['sender'] as String? ?? '').toUpperCase();
        final dedupe = (t['dedupe_key'] as String? ?? '').toUpperCase();
        return sender.contains(_selectedFilter) || dedupe.contains(_selectedFilter);
      }).toList();
    }

    if (_searchQuery.isNotEmpty) {
      result = result.where((t) {
        final counterparty = (t['counterparty'] as String? ?? '').toLowerCase();
        final rawBody = (t['raw_body'] as String? ?? '').toLowerCase();
        final amount = (t['amount']?.toString() ?? '');
        return counterparty.contains(_searchQuery) ||
            rawBody.contains(_searchQuery) ||
            amount.contains(_searchQuery);
      }).toList();
    }

    return result;
  }

  String _formatK(double amount) {
    if (amount.abs() >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(2)}M';
    } else if (amount.abs() >= 1000) {
      return '${(amount / 1000).toStringAsFixed(1)}K';
    }
    return amount.toStringAsFixed(2);
  }

  void _showCandidatePrompt(String bankName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Link $bankName Account', style: AppTypography.titleLarge),
            const SizedBox(height: 10),
            Text(
              'Historical transactions from $bankName SMS messages will be parsed and incorporated into your ledger balances.',
              style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Activated parsing for $bankName messages')),
                );
              },
              child: Text('Confirm & Link $bankName'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAccountDetailsSheet(Map<String, dynamic> acc) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final name = acc['name'] as String? ?? 'Account';
        final mask = acc['account_mask'] as String? ?? '••••';
        final provider = acc['provider'] as String? ?? '';
        final bal = (acc['last_known_balance'] as num?)?.toDouble() ?? 0.0;

        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderHighlight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(name, style: AppTypography.titleLarge),
                  Text('ETB ${bal.toStringAsFixed(2)}',
                      style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 4),
              Text('$provider • Account $mask',
                  style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted)),
              const Divider(color: AppColors.border, height: 28),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.sync_rounded, color: AppColors.primaryLight),
                title: const Text('Re-parse Bank Statements'),
                subtitle: const Text('Re-scan SMS messages and reconstruct balance chain'),
                onTap: () {
                  Navigator.pop(ctx);
                  ref.read(syncStateProvider.notifier).triggerSync();
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.picture_as_pdf_rounded, color: AppColors.secondaryLight),
                title: const Text('Export Statement'),
                subtitle: const Text('Generate CSV / PDF statement for this account'),
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showTransactionDetails(Map<String, dynamic> txn) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final amount = (txn['amount'] as num?)?.toDouble() ?? 0.0;
        final type = (txn['type'] as String? ?? 'expense').toLowerCase();
        final isIncome = type == 'income' || type == 'credit';
        final counterparty = txn['counterparty'] as String? ?? 'Transaction';
        final occurredAt = DateTime.tryParse(txn['occurred_at'] as String? ?? '') ?? DateTime.now();
        final rawBody = txn['raw_body'] as String? ?? '';
        final dedupeKey = txn['dedupe_key'] as String? ?? '';
        final balAfter = (txn['balance_after'] as num?)?.toDouble();

        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderHighlight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(counterparty, style: AppTypography.titleLarge),
                  Text(
                    '${isIncome ? '+' : '-'} ETB ${amount.toStringAsFixed(2)}',
                    style: AppTypography.titleLarge.copyWith(
                      color: isIncome ? AppColors.income : AppColors.expense,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat('EEEE, MMM d, yyyy • h:mm a').format(occurredAt),
                style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
              ),
              if (balAfter != null) ...[
                const SizedBox(height: 4),
                Text('Recorded Balance: ETB ${balAfter.toStringAsFixed(2)}',
                    style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
              ],
              const Divider(color: AppColors.border, height: 28),
              if (rawBody.isNotEmpty) ...[
                Text('ORIGINAL NOTIFICATION',
                    style: AppTypography.labelSmall.copyWith(color: AppColors.textMuted)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLow,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    rawBody,
                    style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Text('Deduplication ID: $dedupeKey',
                  style: AppTypography.labelSmall.copyWith(color: AppColors.textMuted, fontSize: 10)),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}

class _SegmentTabButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _SegmentTabButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTypography.labelMedium.copyWith(
                color: isSelected ? Colors.white : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
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
  final VoidCallback? onTap;

  const _TransactionCard({required this.txn, this.onTap});

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

    final isIncome = type == 'income' || type == 'credit';
    final amountText = '${isIncome ? '+' : '-'} ${amount.toStringAsFixed(2)} ETB';
    final amountColor = isIncome ? AppColors.incomeLight : AppColors.textPrimary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
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
                padding: const EdgeInsets.all(14.0),
                child: Row(
                  children: [
                    // Direction Icon
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: isIncome ? AppColors.incomeSurface : AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isIncome ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                        color: isIncome ? AppColors.incomeLight : AppColors.expense,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            counterparty,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Text(timeFormatted,
                                  style: AppTypography.labelSmall.copyWith(color: AppColors.textMuted)),
                              const SizedBox(width: 8),
                              if (isVerified) ...[
                                const Icon(Icons.verified_rounded, size: 13, color: AppColors.incomeLight),
                                const SizedBox(width: 2),
                                Text(
                                  'Verified',
                                  style: AppTypography.labelSmall.copyWith(
                                    color: AppColors.incomeLight,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 10,
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
                          style: AppTypography.bodyMedium.copyWith(
                            fontWeight: FontWeight.w800,
                            color: amountColor,
                          ),
                        ),
                        if (balanceAfter != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Bal: ${balanceAfter.toStringAsFixed(2)}',
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

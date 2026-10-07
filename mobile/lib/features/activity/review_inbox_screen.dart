import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/local/database_provider.dart';

class ReviewInboxScreen extends ConsumerStatefulWidget {
  const ReviewInboxScreen({super.key});

  @override
  ConsumerState<ReviewInboxScreen> createState() => _ReviewInboxScreenState();
}

class _ReviewInboxScreenState extends ConsumerState<ReviewInboxScreen> {
  List<Map<String, dynamic>> _reviewTransactions = [];
  List<Map<String, dynamic>> _unparsedMessages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() => _isLoading = true);
    final db = await ref.read(databaseProvider.future);
    final txns = db.getTransactionsNeedingReview();
    final unparsed = db.getPendingUnparsedMessages();
    if (mounted) {
      setState(() {
        _reviewTransactions = txns;
        _unparsedMessages = unparsed;
        _isLoading = false;
      });
    }
  }

  Future<void> _markTransactionResolved(String id) async {
    final db = await ref.read(databaseProvider.future);
    // Fetch transaction, set needs_review = 0
    final txn = _reviewTransactions.firstWhere((t) => t['id'] == id);
    db.upsertTransaction(
      id: id,
      accountId: txn['account_id'] as String,
      categoryId: txn['category_id'] as String?,
      type: txn['type'] as String,
      amount: (txn['amount'] as num).toDouble(),
      balanceAfter: (txn['balance_after'] as num?)?.toDouble(),
      counterparty: txn['counterparty'] as String?,
      reference: txn['reference'] as String?,
      note: txn['note'] as String?,
      occurredAt: DateTime.parse(txn['occurred_at'] as String),
      source: txn['source'] as String,
      parseConfidence: (txn['parse_confidence'] as num?)?.toDouble(),
      dedupeKey: txn['dedupe_key'] as String?,
      rawBody: txn['raw_body'] as String?,
      sender: txn['sender'] as String?,
      balanceChainOk: txn['balance_chain_ok'] == 1,
      gapBeforeAmount: (txn['gap_before_amount'] as num?)?.toDouble(),
      needsReview: false, // Resolved!
      isDirty: true,
    );
    await _loadItems();
  }

  @override
  Widget build(BuildContext context) {
    final totalItems = _reviewTransactions.length + _unparsedMessages.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Review Inbox ($totalItems)', style: AppTypography.titleLarge),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primaryLight))
            : totalItems == 0
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle_outline_rounded,
                            size: 64, color: AppColors.incomeLight),
                        const SizedBox(height: 16),
                        Text('All Caught Up!', style: AppTypography.headlineSmall),
                        const SizedBox(height: 8),
                        Text(
                          'No missing transaction gaps or ambiguous SMS messages.',
                          style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16.0),
                    children: [
                      if (_reviewTransactions.isNotEmpty) ...[
                        Text('Discrepancies & Flagged Transactions', style: AppTypography.titleMedium),
                        const SizedBox(height: 12),
                        ..._reviewTransactions.map((txn) => _ReviewTransactionCard(
                              txn: txn,
                              onResolve: () => _markTransactionResolved(txn['id'] as String),
                            )),
                        const SizedBox(height: 24),
                      ],
                      if (_unparsedMessages.isNotEmpty) ...[
                        Text('Unrecognized Banking Messages', style: AppTypography.titleMedium),
                        const SizedBox(height: 12),
                        ..._unparsedMessages.map((msg) => _UnparsedMessageCard(
                              msg: msg,
                              onDismiss: () async {
                                // Mark ignored
                                await _loadItems();
                              },
                            )),
                      ],
                    ],
                  ),
      ),
    );
  }
}

class _ReviewTransactionCard extends StatelessWidget {
  final Map<String, dynamic> txn;
  final VoidCallback onResolve;

  const _ReviewTransactionCard({required this.txn, required this.onResolve});

  @override
  Widget build(BuildContext context) {
    final amount = (txn['amount'] as num?)?.toDouble() ?? 0.0;
    final counterparty = txn['counterparty'] as String? ?? 'Transaction';
    final gapAmount = (txn['gap_before_amount'] as num?)?.toDouble();
    final rawBody = txn['raw_body'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.secondary.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(counterparty, style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold)),
              Text(
                '${amount.toStringAsFixed(2)} ETB',
                style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          if (gapAmount != null && gapAmount > 0) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.warningSurface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Gap: Missing $gapAmount ETB before this transaction was recorded.',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.secondaryLight,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          if (rawBody.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              rawBody,
              style: AppTypography.bodySmall.copyWith(color: AppColors.textMuted),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FilledButton.tonal(
                onPressed: onResolve,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary.withOpacity(0.2),
                  foregroundColor: AppColors.primaryLight,
                ),
                child: const Text('Mark Verified'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UnparsedMessageCard extends StatelessWidget {
  final Map<String, dynamic> msg;
  final VoidCallback onDismiss;

  const _UnparsedMessageCard({required this.msg, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'From: ${msg['sender']}',
            style: AppTypography.labelLarge.copyWith(color: AppColors.primaryLight),
          ),
          const SizedBox(height: 6),
          Text(
            msg['body'] as String? ?? '',
            style: AppTypography.bodyMedium,
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onDismiss,
                child: const Text('Ignore'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

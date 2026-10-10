import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/security/privacy_provider.dart';
import '../../core/theme/app_colors.dart';
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

  Future<void> _resolveTxn(String id, {String? categoryId, String? type}) async {
    final db = await ref.read(databaseProvider.future);
    final txn = _reviewTransactions.firstWhere((t) => t['id'] == id);
    db.upsertTransaction(
      id: id,
      accountId: txn['account_id'] as String,
      categoryId: categoryId ?? txn['category_id'] as String?,
      type: type ?? txn['type'] as String,
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
      needsReview: false,
    );
    await _loadItems();
  }

  Future<void> _dismissUnparsed(String id) async {
    final db = await ref.read(databaseProvider.future);
    db.deleteUnparsedMessage(id);
    await _loadItems();
  }

  @override
  Widget build(BuildContext context) {
    final isPrivate = ref.watch(privacyModeProvider);

    // If both empty and in preview mode, demonstrate prototype mock items
    final hasRealItems = _reviewTransactions.isNotEmpty || _unparsedMessages.isNotEmpty;
    final totalCount = _reviewTransactions.length + _unparsedMessages.length;

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
          'Review Inbox',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
            : ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  // Subtitle notice
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.amberBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.amber.withOpacity(0.35)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, color: AppColors.amber, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            hasRealItems
                                ? '$totalCount items need quick confirmation · ~20s'
                                : 'All caught up! Zero ledger conflicts pending.',
                            style: const TextStyle(
                              color: AppColors.text,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (!hasRealItems) ...[
                    // Prototype mock triage cards if empty
                    _buildMockTransferCard(context, isPrivate),
                    const SizedBox(height: 12),
                    _buildMockGapCard(context, isPrivate),
                    const SizedBox(height: 12),
                    _buildMockSenderCard(context),
                  ] else ...[
                    // Real items from local database
                    ..._reviewTransactions.map((tx) => _buildRealTxnCard(tx, isPrivate)),
                    ..._unparsedMessages.map((msg) => _buildRealUnparsedCard(msg)),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }

  Widget _buildMockTransferCard(BuildContext context, bool isPrivate) {
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accentBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'UNCLEAR TRANSFER',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Text(
                '68% confidence',
                style: TextStyle(color: AppColors.amber, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Kenenisa Tadesse',
                style: TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w700),
              ),
              Text(
                formatCurrency(1200.0, isPrivate: isPrivate),
                style: const TextStyle(
                  color: AppColors.expense,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Telebirr transfer · Is this an expense or an own transfer to another account?',
            style: TextStyle(color: AppColors.text3, fontSize: 11),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildActionButton(
                label: 'Expense',
                color: AppColors.expense,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Marked as Personal Expense')),
                  );
                },
              ),
              _buildActionButton(
                label: 'Own Transfer',
                color: AppColors.accent,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Marked as Internal Transfer')),
                  );
                },
              ),
              _buildActionButton(
                label: 'Dismiss',
                color: AppColors.text3,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Item dismissed')),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMockGapCard(BuildContext context, bool isPrivate) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.amber.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.amberBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'BALANCE GAP',
                  style: TextStyle(
                    color: AppColors.amber,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Text(
                'Yesterday',
                style: TextStyle(color: AppColors.text3, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'CBE Balance Drop',
                style: TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w700),
              ),
              Text(
                formatCurrency(850.0, isPrivate: isPrivate),
                style: const TextStyle(
                  color: AppColors.amber,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Your CBE balance dropped from ETB 19,300 to ETB 18,450 without an SMS notification.',
            style: TextStyle(color: AppColors.text3, fontSize: 11),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildActionButton(
                label: 'Log as Expense',
                color: AppColors.income,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Logged unaccounted drop as expense')),
                  );
                },
              ),
              _buildActionButton(
                label: 'Ignore Gap',
                color: AppColors.text3,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Gap ignored and balance calibrated')),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMockSenderCard(BuildContext context) {
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'NEW SENDER FOUND',
              style: TextStyle(
                color: AppColors.text2,
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Sender "AwashBank"',
            style: TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Received transaction SMS from sender AwashBank. Link this sender to an account?',
            style: TextStyle(color: AppColors.text3, fontSize: 11),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              _buildActionButton(
                label: 'Add Institution',
                color: AppColors.accent,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Added AwashBank to parser rules')),
                  );
                },
              ),
              _buildActionButton(
                label: 'Ignore Sender',
                color: AppColors.text3,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Ignored sender')),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRealTxnCard(Map<String, dynamic> tx, bool isPrivate) {
    final id = tx['id'] as String;
    final party = (tx['counterparty'] ?? tx['merchant'] ?? 'Transaction') as String;
    final amt = (tx['amount'] as num?)?.toDouble() ?? 0.0;
    final conf = (tx['parse_confidence'] as num?)?.toDouble() ?? 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
                party,
                style: const TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w700),
              ),
              Text(
                formatCurrency(amt, isPrivate: isPrivate),
                style: const TextStyle(color: AppColors.expense, fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Confidence: ${(conf * 100).toInt()}% · Needs classification',
            style: const TextStyle(color: AppColors.text3, fontSize: 11),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildActionButton(
                label: 'Confirm Expense',
                color: AppColors.income,
                onTap: () => _resolveTxn(id, type: 'expense'),
              ),
              const SizedBox(width: 8),
              _buildActionButton(
                label: 'Dismiss',
                color: AppColors.text3,
                onTap: () => _resolveTxn(id),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRealUnparsedCard(Map<String, dynamic> msg) {
    final id = msg['id'] as String;
    final sender = msg['sender'] as String? ?? 'Unknown';
    final body = msg['raw_body'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Unparsed SMS from $sender',
            style: const TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.text3, fontSize: 11, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 10),
          _buildActionButton(
            label: 'Dismiss',
            color: AppColors.text3,
            onTap: () => _dismissUnparsed(id),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

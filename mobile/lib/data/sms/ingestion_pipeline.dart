import 'dart:async';
import 'package:uuid/uuid.dart';
import '../local/app_database.dart';
import '../parser/financial_parser.dart';
import '../parser/models/parse_result.dart';
import '../../domain/use_cases/balance_chain_verifier.dart';
import '../../domain/use_cases/dedupe_engine.dart';
import 'models/raw_financial_message.dart';
import 'sources/transaction_source.dart';

/// Pipeline coordinating raw SMS/Notification capture, parser evaluation,
/// deduplication, account matching, balance-chain verification, and database persistence.
class IngestionPipeline {
  final AppDatabase _database;
  final FinancialParser _parser;
  final List<TransactionSource> _sources;

  final List<StreamSubscription> _subscriptions = [];
  final StreamController<ParseResult> _parsedStreamController =
      StreamController<ParseResult>.broadcast();

  IngestionPipeline({
    required AppDatabase database,
    required FinancialParser parser,
    required List<TransactionSource> sources,
  })  : _database = database,
        _parser = parser,
        _sources = sources {
    _startListening();
  }

  Stream<ParseResult> get onTransactionParsed => _parsedStreamController.stream;

  void _startListening() {
    for (final source in _sources) {
      final sub = source.messageStream.listen(
        (RawFinancialMessage msg) async {
          await processMessage(msg);
        },
        onError: (dynamic error) {
          // Log or handle stream error
        },
      );
      _subscriptions.add(sub);
    }
  }

  /// Ingests and processes a single incoming financial message
  Future<Map<String, dynamic>?> processMessage(RawFinancialMessage msg) async {
    // 1. Run Parser
    final parseResult = _parser.parse(
      sender: msg.sender,
      body: msg.body,
      receivedAt: msg.receivedAt,
    );

    // 2. Handle failed or non-financial messages
    if (!parseResult.isSuccess || parseResult.transaction == null) {
      _database.saveUnparsedMessage(
        id: msg.id,
        sender: msg.sender,
        body: msg.body,
        receivedAt: msg.receivedAt,
        reason: parseResult.failureReason ?? 'Unrecognized bank SMS pattern',
      );
      return null;
    }

    final txn = parseResult.transaction!;

    // 3. Deduplication check
    final dedupeKey = DedupeEngine.generateKey(
      provider: txn.provider,
      reference: txn.reference,
      sender: msg.sender,
      amount: txn.amount,
      type: txn.type,
      occurredAt: msg.receivedAt,
      counterparty: txn.counterparty,
    );

    final existing = _database.findTransactionByDedupeKey(dedupeKey);
    if (existing != null) {
      // Transaction already recorded via parallel channel (e.g. notification after SMS)
      return existing;
    }

    // 4. Resolve or Auto-Provision Account
    final accountId = _resolveOrCreateAccount(txn.provider, txn.balanceAfter);

    // 5. Balance-Chain Mathematical Evaluation
    final prevTxn = _database.getLatestTransactionForAccount(accountId);
    final prevBalance = prevTxn != null
        ? (prevTxn['balance_after'] as num?)?.toDouble()
        : null;

    final chainResult = BalanceChainVerifier.verify(
      amount: txn.amount,
      type: txn.type,
      currentBalanceAfter: txn.balanceAfter,
      previousBalanceAfter: prevBalance,
    );

    // 6. Persist Transaction to Encrypted Database
    final transactionId = const Uuid().v4();
    final needsReview = chainResult.needsReview || txn.parseConfidence < 0.85;

    _database.upsertTransaction(
      id: transactionId,
      accountId: accountId,
      categoryId: null, // Left null for auto-categorization or user review
      type: txn.type,
      amount: txn.amount,
      balanceAfter: txn.balanceAfter,
      counterparty: txn.counterparty,
      reference: txn.reference,
      note: null,
      occurredAt: msg.receivedAt,
      source: msg.source,
      parseConfidence: txn.parseConfidence,
      dedupeKey: dedupeKey,
      rawBody: msg.body,
      sender: msg.sender,
      balanceChainOk: chainResult.isChainOk,
      gapBeforeAmount: chainResult.gapAmount,
      needsReview: needsReview,
      changeSeq: 0,
      isDirty: true,
    );

    // 7. Update Account's Last Known Balance
    if (txn.balanceAfter != null) {
      final account = _database.getAccountById(accountId);
      if (account != null) {
        _database.upsertAccount(
          id: accountId,
          provider: account['provider'] as String,
          name: account['name'] as String,
          accountMask: account['account_mask'] as String?,
          lastKnownBalance: txn.balanceAfter,
          isSavings: account['is_savings'] == 1,
        );
      }
    }

    _parsedStreamController.add(parseResult);

    return _database.findTransactionByDedupeKey(dedupeKey);
  }

  /// Matches existing provider account or auto-creates one
  String _resolveOrCreateAccount(String bank, double? initialBalance) {
    final accounts = _database.getAccounts();
    final normalizedBank = bank.trim().toUpperCase();

    for (final acc in accounts) {
      if ((acc['provider'] as String).toUpperCase() == normalizedBank) {
        return acc['id'] as String;
      }
    }

    // Auto-create initial account for bank
    final newId = const Uuid().v4();
    String accountName;
    if (normalizedBank == 'TELEBIRR') {
      accountName = 'Telebirr Wallet';
    } else if (normalizedBank == 'CBE') {
      accountName = 'CBE Account';
    } else if (normalizedBank == 'BOA' || normalizedBank.contains('ABYSSINIA')) {
      accountName = 'Bank of Abyssinia';
    } else {
      accountName = '$bank Account';
    }

    _database.upsertAccount(
      id: newId,
      provider: normalizedBank,
      name: accountName,
      lastKnownBalance: initialBalance,
      isSavings: false,
    );

    return newId;
  }

  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _parsedStreamController.close();
  }
}

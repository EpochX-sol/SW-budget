import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local/app_database.dart';
import '../../data/local/database_provider.dart';

final transactionsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final db = await ref.watch(databaseProvider.future);

  // Emit initial state
  yield db.getTransactions(limit: 200);

  // Listen to table mutations
  await for (final event in db.onTableChanged) {
    if (event == DatabaseTable.transactions) {
      yield db.getTransactions(limit: 200);
    }
  }
});

final reviewInboxCountProvider = StreamProvider<int>((ref) async* {
  final db = await ref.watch(databaseProvider.future);

  yield db.getTransactionsNeedingReview().length + db.getPendingUnparsedMessages().length;

  await for (final event in db.onTableChanged) {
    if (event == DatabaseTable.transactions || event == DatabaseTable.unparsedMessages) {
      yield db.getTransactionsNeedingReview().length + db.getPendingUnparsedMessages().length;
    }
  }
});

final accountsStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final db = await ref.watch(databaseProvider.future);

  yield db.getAccounts();

  await for (final event in db.onTableChanged) {
    if (event == DatabaseTable.accounts) {
      yield db.getAccounts();
    }
  }
});

class TransactionController {
  final Ref _ref;

  TransactionController(this._ref);

  Future<void> addTransaction({
    required bool isExpense,
    required double amount,
    required String counterparty,
    required String accountId,
    required String category,
    required String note,
  }) async {
    final db = await _ref.read(databaseProvider.future);
    final now = DateTime.now();
    final id = 'manual_${now.millisecondsSinceEpoch}';

    // Update account balance if known
    final acc = db.getAccountById(accountId);
    double? balanceAfter;
    if (acc != null && acc['last_known_balance'] != null) {
      final currentBal = (acc['last_known_balance'] as num).toDouble();
      balanceAfter = isExpense ? currentBal - amount : currentBal + amount;
      db.updateAccountBalance(accountId, balanceAfter);
    }

    db.upsertTransaction(
      id: id,
      accountId: accountId,
      categoryId: category,
      type: isExpense ? 'expense' : 'income',
      amount: amount,
      balanceAfter: balanceAfter,
      counterparty: counterparty,
      note: note.isNotEmpty ? note : null,
      occurredAt: now,
      source: 'manual',
      parseConfidence: 1.0,
      balanceChainOk: true,
      needsReview: false,
    );
  }

  Future<void> updateDetails({
    required String id,
    required String category,
    required String note,
  }) async {
    final db = await _ref.read(databaseProvider.future);
    db.updateTransactionCategoryAndNote(id: id, categoryId: category, note: note);
  }

  Future<void> markTransfer(String id) async {
    final db = await _ref.read(databaseProvider.future);
    db.markTransactionAsTransfer(id);
  }

  Future<void> delete(String id) async {
    final db = await _ref.read(databaseProvider.future);
    db.deleteTransaction(id);
  }
}

final transactionControllerProvider = Provider<TransactionController>((ref) {
  return TransactionController(ref);
});

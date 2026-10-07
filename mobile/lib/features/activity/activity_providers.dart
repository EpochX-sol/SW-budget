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

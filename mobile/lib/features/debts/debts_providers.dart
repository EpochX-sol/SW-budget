import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../data/local/app_database.dart';
import '../../data/local/database_provider.dart';

final debtsStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final db = await ref.watch(databaseProvider.future);
  yield db.getDebts(includeSettled: true);

  await for (final event in db.onTableChanged) {
    if (event == DatabaseTable.debts) {
      yield db.getDebts(includeSettled: true);
    }
  }
});

final reimbursementsStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final db = await ref.watch(databaseProvider.future);
  yield db.getReimbursements(includeSettled: true);

  await for (final event in db.onTableChanged) {
    if (event == DatabaseTable.reimbursements) {
      yield db.getReimbursements(includeSettled: true);
    }
  }
});

class DebtsController {
  final Ref _ref;

  DebtsController(this._ref);

  Future<void> addDebt({
    required bool isOwed,
    required String who,
    required double amount,
    String? dueDate,
    required String note,
  }) async {
    final db = await _ref.read(databaseProvider.future);
    final id = const Uuid().v4();
    db.upsertDebt(
      id: id,
      direction: isOwed ? 'owed_to_me' : 'i_owe',
      counterparty: who,
      totalAmount: amount,
      paidAmount: 0.0,
      dueDate: dueDate,
      note: note.isEmpty ? null : note,
      status: 'active',
    );
  }

  Future<void> settleDebt(String id) async {
    final db = await _ref.read(databaseProvider.future);
    db.settleDebt(id);
  }

  Future<void> deleteDebt(String id) async {
    final db = await _ref.read(databaseProvider.future);
    db.deleteDebt(id);
  }

  Future<void> addReimbursement({
    required String title,
    required double amount,
    String? note,
  }) async {
    final db = await _ref.read(databaseProvider.future);
    final id = const Uuid().v4();
    db.upsertReimbursement(
      id: id,
      title: title,
      amount: amount,
      paidAmount: 0.0,
      status: 'pending',
      note: note,
    );
  }

  Future<void> settleReimbursement(String id) async {
    final db = await _ref.read(databaseProvider.future);
    db.settleReimbursement(id);
  }
}

final debtsControllerProvider = Provider<DebtsController>((ref) {
  return DebtsController(ref);
});

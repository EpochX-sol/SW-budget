import 'package:drift/drift.dart';

class LocalSyncState extends Table {
  TextColumn get key => text()(); // e.g. "global_sync"
  IntColumn get lastSyncSeq => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();
  TextColumn get status => text().withDefault(const Constant('idle'))(); // idle, syncing, error

  @override
  Set<Column> get primaryKey => {key};
}

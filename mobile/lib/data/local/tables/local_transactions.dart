import 'package:drift/drift.dart';

class LocalTransactions extends Table {
  TextColumn get id => text()();
  TextColumn get accountId => text()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get type => text()(); // expense, income, transfer
  RealColumn get amount => real()();
  RealColumn get balanceAfter => real().nullable()();
  TextColumn get counterparty => text().nullable()();
  TextColumn get reference => text().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get source => text()(); // sms, notification, manual
  RealColumn get parseConfidence => real().nullable()();
  TextColumn get dedupeKey => text().nullable()();
  TextColumn get rawBody => text().nullable()();
  TextColumn get sender => text().nullable()();
  
  // Balance-Chain Integrity
  BoolColumn get balanceChainOk => boolean().nullable()();
  RealColumn get gapBeforeAmount => real().nullable()();
  BoolColumn get needsReview => boolean().withDefault(const Constant(false))();

  // Sync state
  IntColumn get changeSeq => integer().withDefault(const Constant(0))();
  BoolColumn get isDirty => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

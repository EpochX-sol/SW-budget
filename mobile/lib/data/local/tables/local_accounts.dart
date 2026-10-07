import 'package:drift/drift.dart';

class LocalAccounts extends Table {
  TextColumn get id => text()();
  TextColumn get provider => text()(); // TELEBIRR, CBE, BOA, CASH
  TextColumn get name => text()();
  TextColumn get accountMask => text().nullable()();
  RealColumn get lastKnownBalance => real().nullable()();
  BoolColumn get isSavings => boolean().withDefault(const Constant(false))();
  IntColumn get changeSeq => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

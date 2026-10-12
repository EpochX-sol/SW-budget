import 'package:drift/drift.dart';

class LocalExpectedExpenses extends Table {
  TextColumn get id => text()();
  TextColumn get planId => text()();
  TextColumn get name => text()();
  RealColumn get amount => real()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  TextColumn get linkedCategoryId => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('expected'))(); // expected, paid
  RealColumn get paidAmount => real().withDefault(const Constant(0.0))();
  TextColumn get paidTxnId => text().nullable()();
  BoolColumn get reminderEnabled => boolean().withDefault(const Constant(true))();
  IntColumn get changeSeq => integer().withDefault(const Constant(0))();
  BoolColumn get isDirty => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

import 'package:drift/drift.dart';

class LocalLimits extends Table {
  TextColumn get id => text()();
  TextColumn get scopeType => text()(); // category, overall
  TextColumn get scopeId => text().nullable()();
  TextColumn get periodType => text()(); // monthly, weekly, daily
  RealColumn get amount => real()();
  TextColumn get mode => text().withDefault(const Constant('soft'))(); // soft, hard
  BoolColumn get rollover => boolean().withDefault(const Constant(false))();
  TextColumn get alertThresholds => text().withDefault(const Constant('[50,80,100]'))(); // JSON array string
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  IntColumn get changeSeq => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

import 'package:drift/drift.dart';

class LocalUnparsedMessages extends Table {
  TextColumn get id => text()();
  TextColumn get sender => text()();
  TextColumn get body => text()();
  DateTimeColumn get receivedAt => dateTime()();
  TextColumn get reason => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('pending'))(); // pending, ignored, manually_resolved

  @override
  Set<Column> get primaryKey => {id};
}

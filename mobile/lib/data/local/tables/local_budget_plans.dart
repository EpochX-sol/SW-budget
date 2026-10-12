import 'package:drift/drift.dart';

class LocalBudgetPlans extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get periodType => text()(); // daily, weekly, monthly, yearly, custom
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime()();
  IntColumn get monthlyStartDay => integer().withDefault(const Constant(1))();
  RealColumn get spendingLimit => real()();
  TextColumn get reserveType => text().withDefault(const Constant('none'))(); // none, fixed, percentage
  RealColumn get reserveValue => real().withDefault(const Constant(0.0))();
  TextColumn get watchedBankIds => text().nullable()(); // JSON array of account IDs, or null
  BoolColumn get countFees => boolean().withDefault(const Constant(true))();
  BoolColumn get countWithdrawals => boolean().withDefault(const Constant(true))();
  TextColumn get reactionMode => text().withDefault(const Constant('adaptive'))(); // adaptive, fixed
  TextColumn get status => text().withDefault(const Constant('active'))(); // active, paused, finished, archived
  DateTimeColumn get pausedAt => dateTime().nullable()();
  IntColumn get pausedDaysCount => integer().withDefault(const Constant(0))();
  BoolColumn get morningBriefEnabled => boolean().withDefault(const Constant(true))();
  TextColumn get morningBriefTime => text().withDefault(const Constant('07:30'))();
  BoolColumn get dailyReportEnabled => boolean().withDefault(const Constant(true))();
  TextColumn get dailyReportTime => text().withDefault(const Constant('21:00'))();
  BoolColumn get skipEmptyDays => boolean().withDefault(const Constant(false))();
  TextColumn get alertThresholds => text().withDefault(const Constant('[50,80,100]'))();
  BoolColumn get reserveAlertEnabled => boolean().withDefault(const Constant(true))();
  TextColumn get finalSummaryPayload => text().nullable()(); // JSON string on completion
  IntColumn get changeSeq => integer().withDefault(const Constant(0))();
  BoolColumn get isDirty => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

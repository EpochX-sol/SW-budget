import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../local/database_provider.dart';
import '../parser/financial_parser.dart';
import 'ingestion_pipeline.dart';
import 'sources/sms_transaction_source.dart';
import 'sources/notification_listener_source.dart';

final smsSourceProvider = Provider<SmsTransactionSource>((ref) {
  final source = SmsTransactionSource();
  ref.onDispose(() => source.dispose());
  return source;
});

final notificationSourceProvider = Provider<NotificationListenerSource>((ref) {
  final source = NotificationListenerSource();
  ref.onDispose(() => source.dispose());
  return source;
});

final financialParserProvider = FutureProvider<FinancialParser>((ref) async {
  final parser = FinancialParser();
  try {
    final bundleJson = await rootBundle.loadString('assets/templates/default_bundle.json');
    parser.loadTemplatesFromJson(bundleJson);
  } catch (_) {
    // Graceful fallback for headless test runner
  }
  try {
    final patternsJson = await rootBundle.loadString('assets/templates/sms_patterns.json');
    final banksJson = await rootBundle.loadString('assets/templates/banks.json');
    parser.loadNamedPatterns(patternsJson: patternsJson, banksJson: banksJson);
  } catch (_) {
    // Graceful fallback if full named patterns cannot be loaded
  }
  return parser;
});

final ingestionPipelineProvider = FutureProvider<IngestionPipeline>((ref) async {
  final database = await ref.watch(databaseProvider.future);
  final parser = await ref.watch(financialParserProvider.future);
  final smsSource = ref.watch(smsSourceProvider);
  final notifSource = ref.watch(notificationSourceProvider);

  final pipeline = IngestionPipeline(
    database: database,
    parser: parser,
    sources: [smsSource, notifSource],
  );

  ref.onDispose(() => pipeline.dispose());
  return pipeline;
});

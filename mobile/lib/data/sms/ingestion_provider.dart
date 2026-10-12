import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../local/database_provider.dart';
import '../parser/financial_parser.dart';
import '../parser/models/template_bundle.dart';
import '../remote/api_client_provider.dart';
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

  // Attempt Over-The-Air signed template update from backend
  try {
    final apiClient = ref.watch(apiClientProvider);
    final remoteBundleData = await apiClient.getSmsTemplates();
    final bundle = TemplateBundle.fromJson(remoteBundleData);
    if (bundle.templates.isNotEmpty) {
      parser.updateTemplateBundle(bundle);
    }
  } catch (_) {
    // Offline or unreachable: built-in asset regex patterns maintain 100% operation
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

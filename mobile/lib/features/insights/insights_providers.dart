import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local/app_database.dart';
import '../../data/local/database_provider.dart';
import '../../data/remote/api_client_provider.dart';
import '../activity/activity_providers.dart';
import 'insights_math_service.dart';

/// Currently selected time filter on the Insights screen: '7D' | '30D' | 'MOM' | 'YTD'
final insightsPeriodProvider = StateProvider<String>((ref) => '30D');

/// Stream of local categories from SQLite
final insightsCategoriesStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) async* {
  final db = await ref.watch(databaseProvider.future);
  yield db.getCategories();

  await for (final event in db.onTableChanged) {
    if (event == DatabaseTable.categories) {
      yield db.getCategories();
    }
  }
});

/// Background fetch for backend analytics trends (cached / graceful fallback)
final remoteAnalyticsTrendsProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  try {
    final client = ref.watch(apiClientProvider);
    return await client.getAnalyticsTrends();
  } catch (_) {
    return null;
  }
});

/// Background fetch for backend fees
final remoteAnalyticsFeesProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  try {
    final client = ref.watch(apiClientProvider);
    return await client.getAnalyticsFees();
  } catch (_) {
    return null;
  }
});

/// Background fetch for backend 30-day forecast
final remoteAnalyticsForecastProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  try {
    final client = ref.watch(apiClientProvider);
    return await client.getAnalyticsForecast();
  } catch (_) {
    return null;
  }
});

/// Complete, reactive Insights evaluation snapshot
final insightsSummaryProvider = Provider<InsightsDataState>((ref) {
  final period = ref.watch(insightsPeriodProvider);
  final txAsync = ref.watch(transactionsProvider);
  final catAsync = ref.watch(insightsCategoriesStreamProvider);

  final trendsAsync = ref.watch(remoteAnalyticsTrendsProvider);
  final feesAsync = ref.watch(remoteAnalyticsFeesProvider);
  final forecastAsync = ref.watch(remoteAnalyticsForecastProvider);

  final transactions = txAsync.value ?? [];
  final categories = catAsync.value ?? [];

  final trendsData = trendsAsync.value;
  final feesData = feesAsync.value;
  final forecastData = forecastAsync.value;

  final double? momChangePct = (trendsData?['month_over_month_change_pct'] as num?)?.toDouble();
  final double? totalFees = (feesData?['total_fees'] as num?)?.toDouble();
  final double? dailyBurnRate = (forecastData?['daily_burn_rate'] as num?)?.toDouble();

  return InsightsMathService.calculateInsights(
    period: period,
    allTransactions: transactions,
    categories: categories,
    remoteMomChangePct: momChangePct,
    remoteTotalFees: totalFees,
    remoteDailyBurnRate: dailyBurnRate,
  );
});

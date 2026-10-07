import 'dart:io';
import 'package:flutter/foundation.dart';

/// Centralized API endpoint constants and base URL resolution
class ApiEndpoints {
  /// Default base URL with dart-define override and Render production fallback
  static String get defaultBaseUrl {
    const envUrl = String.fromEnvironment('API_BASE_URL');
    if (envUrl.isNotEmpty) {
      return envUrl;
    }

    return 'https://sw-budget.onrender.com';
  }

  // System
  static const String health = '/health';
  static const String metrics = '/metrics';

  // Auth & Profile
  static const String register = '/v1/auth/register';
  static const String login = '/v1/auth/login';
  static const String refresh = '/v1/auth/refresh';
  static const String logout = '/v1/auth/logout';
  static const String me = '/v1/me';

  // Financial Entities
  static const String accounts = '/v1/accounts';
  static String accountById(String id) => '/v1/accounts/$id';

  static const String categories = '/v1/categories';
  static String categoryById(String id) => '/v1/categories/$id';

  static const String limits = '/v1/limits';
  static String limitById(String id) => '/v1/limits/$id';

  static const String savingPlans = '/v1/saving-plans';
  static String savingPlanById(String id) => '/v1/saving-plans/$id';

  // Sync
  static const String syncPush = '/v1/sync/push';
  static const String syncPull = '/v1/sync/pull';
  static const String syncStatus = '/v1/sync/status';

  // Signed SMS Parser Templates
  static const String smsTemplates = '/v1/sms-templates';

  // AI Financial Coach
  static const String aiThreads = '/v1/ai/threads';
  static String aiThreadMessages(String threadId) => '/v1/ai/threads/$threadId/messages';
  static const String aiProposals = '/v1/ai/proposals';
  static String aiProposalDecision(String id) => '/v1/ai/proposals/$id/decision';
  static const String aiMemories = '/v1/ai/memories';
  static const String aiUsage = '/v1/ai/usage';

  // Analytics & Forecasts
  static const String analyticsForecast = '/v1/analytics/forecast';
  static const String analyticsTrends = '/v1/analytics/trends';
  static const String analyticsFees = '/v1/analytics/fees';
}

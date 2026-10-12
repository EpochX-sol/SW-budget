import 'dart:io';
import 'package:dio/dio.dart';
import '../../core/security/secure_storage_service.dart';
import 'api_endpoints.dart';
import 'api_exception.dart';
import 'auth_interceptor.dart';

/// Type-safe HTTP Client wrapping Dio to interface with the Fastify backend
class ApiClient {
  final Dio _dio;
  final SecureStorageService _secureStorage;
  final String baseUrl;

  ApiClient({
    required SecureStorageService secureStorage,
    String? customBaseUrl,
    void Function()? onSessionExpired,
  })  : _secureStorage = secureStorage,
        baseUrl = customBaseUrl ?? ApiEndpoints.defaultBaseUrl,
        _dio = Dio(BaseOptions(
          baseUrl: customBaseUrl ?? ApiEndpoints.defaultBaseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        )) {
    _dio.interceptors.add(
      AuthInterceptor(
        dio: _dio,
        secureStorage: _secureStorage,
        baseUrl: baseUrl,
        onSessionExpired: onSessionExpired,
      ),
    );
  }

  // --- AUTHENTICATION ---

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String displayName,
    String currency = 'ETB',
    String timezone = 'Africa/Addis_Ababa',
    int monthStartDay = 1,
  }) async {
    final deviceId = await _secureStorage.getOrGenerateDeviceId();
    try {
      final response = await _dio.post(
        ApiEndpoints.register,
        data: {
          'email': email,
          'password': password,
          'display_name': displayName,
          'currency': currency,
          'timezone': timezone,
          'month_start_day': monthStartDay,
          'device': {
            'id': deviceId,
            'device_name': 'Android Device',
            'platform': 'android',
            'app_version': '1.0.0',
            'fcm_token': 'fcm_local_token',
          },
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final deviceId = await _secureStorage.getOrGenerateDeviceId();
    try {
      final response = await _dio.post(
        ApiEndpoints.login,
        data: {
          'email': email,
          'password': password,
          'device': {
            'id': deviceId,
            'device_name': 'Android Device',
            'platform': 'android',
            'app_version': '1.0.0',
            'fcm_token': 'fcm_local_token',
          },
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> logout() async {
    final deviceId = await _secureStorage.getOrGenerateDeviceId();
    try {
      await _dio.post(
        ApiEndpoints.logout,
        data: {'device_id': deviceId},
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> getMe() async {
    try {
      final response = await _dio.get(ApiEndpoints.me);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  // --- FINANCIAL ENTITIES ---

  Future<List<dynamic>> getAccounts() async {
    try {
      final response = await _dio.get(ApiEndpoints.accounts);
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> createAccount({
    required String provider,
    required String name,
    String? accountMask,
    double? lastKnownBalance,
    bool isSavings = false,
  }) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.accounts,
        data: {
          'provider': provider,
          'name': name,
          'account_mask': accountMask,
          'last_known_balance': lastKnownBalance,
          'is_savings': isSavings,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> deleteAccount(String id) async {
    try {
      await _dio.delete(ApiEndpoints.accountById(id));
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<List<dynamic>> getCategories() async {
    try {
      final response = await _dio.get(ApiEndpoints.categories);
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> createCategory({
    required String name,
    required String icon,
    required String colorHex,
  }) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.categories,
        data: {
          'name': name,
          'icon': icon,
          'color_hex': colorHex,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<List<dynamic>> getLimits() async {
    try {
      final response = await _dio.get(ApiEndpoints.limits);
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> createLimit({
    required String scopeType,
    String? scopeId,
    required String periodType,
    required double amount,
    String mode = 'soft',
    bool rollover = false,
    List<int> alertThresholds = const [50, 80, 100],
  }) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.limits,
        data: {
          'scope_type': scopeType,
          'scope_id': scopeId,
          'period_type': periodType,
          'amount': amount,
          'mode': mode,
          'rollover': rollover,
          'alert_thresholds': alertThresholds,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<List<dynamic>> getSavingPlans() async {
    try {
      final response = await _dio.get(ApiEndpoints.savingPlans);
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> createSavingPlan({
    required String name,
    required double targetAmount,
    required DateTime targetDate,
  }) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.savingPlans,
        data: {
          'name': name,
          'target_amount': targetAmount,
          'target_date': targetDate.toIso8601String(),
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  // --- SYNC PROTOCOL ---

  Future<Map<String, dynamic>> pushSync({
    required int batchIndex,
    required int totalBatches,
    required List<Map<String, dynamic>> changes,
    String? idempotencyKey,
  }) async {
    final deviceId = await _secureStorage.getOrGenerateDeviceId();
    try {
      final options = Options();
      if (idempotencyKey != null) {
        options.headers = {'Idempotency-Key': idempotencyKey};
      }
      final response = await _dio.post(
        ApiEndpoints.syncPush,
        data: {
          'device_id': deviceId,
          'batch_index': batchIndex,
          'total_batches': totalBatches,
          'changes': changes,
        },
        options: options,
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> pullSync({
    int cursor = 0,
    int limit = 100,
  }) async {
    try {
      final response = await _dio.get(
        ApiEndpoints.syncPull,
        queryParameters: {
          'cursor': cursor,
          'limit': limit,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> getSyncStatus() async {
    try {
      final response = await _dio.get(ApiEndpoints.syncStatus);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  // --- SIGNED SMS TEMPLATES ---

  Future<Map<String, dynamic>> getSmsTemplates() async {
    try {
      final response = await _dio.get(ApiEndpoints.smsTemplates);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  // --- ANALYTICS ---

  Future<Map<String, dynamic>> getForecast() async {
    try {
      final response = await _dio.get(ApiEndpoints.analyticsForecast);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<List<dynamic>> getTrends() async {
    try {
      final response = await _dio.get(ApiEndpoints.analyticsTrends);
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> getFees() async {
    try {
      final response = await _dio.get(ApiEndpoints.analyticsFees);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  // --- AI GATEWAY ---

  Future<Map<String, dynamic>> createAiThread({String title = 'Financial Advice'}) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.aiThreads,
        data: {'title': title},
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<List<dynamic>> getAiThreads() async {
    try {
      final response = await _dio.get(ApiEndpoints.aiThreads);
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<List<dynamic>> getAiProposals() async {
    try {
      final response = await _dio.get(ApiEndpoints.aiProposals);
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> decideAiProposal({
    required String proposalId,
    required String decision, // "accepted" or "rejected"
  }) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.aiProposalDecision(proposalId),
        data: {'decision': decision},
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  // --- OVER-THE-AIR (OTA) TEMPLATES ---

  Future<Map<String, dynamic>?> fetchOtaPatterns({String? ifNoneMatch}) async {
    try {
      final options = Options(
        headers: ifNoneMatch != null ? {'If-None-Match': ifNoneMatch} : null,
        validateStatus: (status) => status != null && (status == 200 || status == 304),
      );
      final response = await _dio.get(ApiEndpoints.templatesPatterns, options: options);
      if (response.statusCode == 304) {
        return null;
      }
      final etag = response.headers.value('etag');
      return {
        'etag': etag,
        'payload': response.data,
      };
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  // --- SERVER EXPORT & BACKUP ---

  Future<List<int>> downloadExcelExport() async {
    try {
      final jobRes = await _dio.post(ApiEndpoints.exportJobs);
      final data = jobRes.data as Map<String, dynamic>;
      final jobId = data['job_id'] as String;

      final downloadRes = await _dio.get<List<int>>(
        ApiEndpoints.exportJobDownload(jobId),
        options: Options(responseType: ResponseType.bytes),
      );
      return downloadRes.data ?? [];
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  // --- NOTIFICATION PREFERENCES & CLOUD ALERTS ---

  Future<Map<String, dynamic>> getNotificationPreferences() async {
    try {
      final response = await _dio.get(ApiEndpoints.notificationPreferences);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> updateNotificationPreferences({
    bool? enabled,
    String? quietStart,
    String? quietEnd,
    bool? showAmounts,
    int? dailyCap,
  }) async {
    try {
      final response = await _dio.put(
        ApiEndpoints.notificationPreferences,
        data: {
          if (enabled != null) 'enabled': enabled,
          if (quietStart != null) 'quiet_start': quietStart,
          if (quietEnd != null) 'quiet_end': quietEnd,
          if (showAmounts != null) 'show_amounts': showAmounts,
          if (dailyCap != null) 'daily_cap': dailyCap,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<List<dynamic>> getNotifications() async {
    try {
      final response = await _dio.get(ApiEndpoints.notifications);
      return response.data as List<dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  // --- AI VECTOR MEMORIES & QUOTA USAGE ---

  Future<List<dynamic>> getAiMemories() async {
    try {
      final response = await _dio.get(ApiEndpoints.aiMemories);
      final data = response.data as Map<String, dynamic>;
      return (data['memories'] as List<dynamic>?) ?? [];
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> addAiMemory({
    required String kind,
    required String content,
    int importance = 3,
    bool pinned = false,
  }) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.aiMemories,
        data: {
          'kind': kind,
          'content': content,
          'importance': importance,
          'pinned': pinned,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<void> deleteAiMemory(String id) async {
    try {
      await _dio.delete(ApiEndpoints.aiMemoryById(id));
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> getAiUsage() async {
    try {
      final response = await _dio.get(ApiEndpoints.aiUsage);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  // --- SPENDING PLAN SIMULATION ---

  Future<Map<String, dynamic>> simulatePlanSpend({
    required String planId,
    required double simulatedDailySpend,
  }) async {
    try {
      final response = await _dio.post(
        ApiEndpoints.planSimulate(planId),
        data: {'simulated_daily_spend': simulatedDailySpend},
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>?> getActivePlan() async {
    try {
      final response = await _dio.get(
        ApiEndpoints.activePlan,
        options: Options(validateStatus: (status) => status != null && (status == 200 || status == 404)),
      );
      if (response.statusCode == 404) return null;
      return response.data as Map<String, dynamic>?;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  // --- ANALYTICS ---

  Future<Map<String, dynamic>> getAnalyticsForecast() async {
    try {
      final response = await _dio.get(ApiEndpoints.analyticsForecast);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> getAnalyticsTrends() async {
    try {
      final response = await _dio.get(ApiEndpoints.analyticsTrends);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> getAnalyticsFees() async {
    try {
      final response = await _dio.get(ApiEndpoints.analyticsFees);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}

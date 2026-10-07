import 'dart:async';
import 'package:dio/dio.dart';
import '../../core/security/secure_storage_service.dart';
import 'api_endpoints.dart';

/// Interceptor that:
/// 1. Injects Bearer JWT into headers for protected requests
/// 2. Handles concurrent 401 Unauthorized responses with an atomic Single-Flight Mutex
///    to execute exactly one POST /v1/auth/refresh and replay all waiting requests
class AuthInterceptor extends QueuedInterceptor {
  final Dio _dio;
  final SecureStorageService _secureStorage;
  final String _baseUrl;
  final void Function()? _onSessionExpired;

  bool _isRefreshing = false;
  final List<_QueuedRequest> _refreshQueue = [];

  AuthInterceptor({
    required Dio dio,
    required SecureStorageService secureStorage,
    required String baseUrl,
    void Function()? onSessionExpired,
  })  : _dio = dio,
        _secureStorage = secureStorage,
        _baseUrl = baseUrl,
        _onSessionExpired = onSessionExpired;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // If authorization header is already manually set, leave it
    if (!options.headers.containsKey('Authorization')) {
      final token = await _secureStorage.getAccessToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }

  @override
  void onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    final statusCode = response?.statusCode;
    final path = err.requestOptions.path;

    // Do not attempt refresh on auth endpoints (login, register, refresh itself)
    final isAuthEndpoint = path.contains(ApiEndpoints.login) ||
        path.contains(ApiEndpoints.register) ||
        path.contains(ApiEndpoints.refresh);

    if (statusCode == 401 && !isAuthEndpoint) {
      if (_isRefreshing) {
        // Enqueue this request and wait for active refresh to complete
        final completer = Completer<Response<dynamic>>();
        _refreshQueue.add(_QueuedRequest(
          options: err.requestOptions,
          completer: completer,
        ));

        try {
          final res = await completer.future;
          handler.resolve(res);
          return;
        } catch (e) {
          handler.reject(err);
          return;
        }
      }

      // Initiate single-flight refresh
      _isRefreshing = true;

      try {
        final refreshToken = await _secureStorage.getRefreshToken();
        final deviceId = await _secureStorage.getOrGenerateDeviceId();

        if (refreshToken == null || refreshToken.isEmpty) {
          _failQueueAndLogout(handler, err);
          return;
        }

        // Call refresh using an isolated raw Dio client to bypass interceptors
        final refreshDio = Dio(BaseOptions(
          baseUrl: _baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ));

        final refreshRes = await refreshDio.post(
          ApiEndpoints.refresh,
          data: {
            'refresh_token': refreshToken,
            'device_id': deviceId,
          },
        );

        bool refreshSucceeded = false;
        String? newAccessToken;
        String? newRefreshToken;

        try {
          final refreshRes = await refreshDio.post(
            ApiEndpoints.refresh,
            data: {
              'refresh_token': refreshToken,
              'device_id': deviceId,
            },
          );

          if (refreshRes.statusCode == 200 && refreshRes.data is Map<String, dynamic>) {
            final data = refreshRes.data as Map<String, dynamic>;
            newAccessToken = data['access_token'] as String;
            newRefreshToken = data['refresh_token'] as String;
            refreshSucceeded = true;
          }
        } on DioException catch (refreshErr) {
          final statusCode = refreshErr.response?.statusCode;
          if (statusCode == 401 || statusCode == 403) {
            // Refresh token is revoked or expired - genuine session termination
            _failQueueAndLogout(handler, refreshErr);
            return;
          } else {
            // Transient network error or 5xx server glitch - do not logout
            _failQueueWithoutLogout(handler, refreshErr);
            return;
          }
        } catch (e) {
          _failQueueWithoutLogout(handler, err);
          return;
        }

        if (refreshSucceeded && newAccessToken != null && newRefreshToken != null) {
          // Save new tokens
          await _secureStorage.saveTokens(
            accessToken: newAccessToken,
            refreshToken: newRefreshToken,
          );

          // Retry queued requests
          final queueCopy = List<_QueuedRequest>.from(_refreshQueue);
          _refreshQueue.clear();

          for (final queued in queueCopy) {
            queued.options.headers['Authorization'] = 'Bearer $newAccessToken';
            _dio.fetch(queued.options).then(
                  (res) => queued.completer.complete(res),
                  onError: (e) => queued.completer.completeError(e),
                );
          }

          // Retry the original request that triggered 401
          err.requestOptions.headers['Authorization'] = 'Bearer $newAccessToken';
          try {
            final retryResponse = await _dio.fetch(err.requestOptions);
            handler.resolve(retryResponse);
          } on DioException catch (retryErr) {
            handler.reject(retryErr);
          } catch (retryErr) {
            handler.reject(err);
          }
          return;
        } else {
          _failQueueAndLogout(handler, err);
          return;
        }
      } finally {
        _isRefreshing = false;
      }
    }

    handler.next(err);
  }

  void _failQueueAndLogout(ErrorInterceptorHandler handler, DioException err) {
    _isRefreshing = false;
    for (final queued in _refreshQueue) {
      queued.completer.completeError(err);
    }
    _refreshQueue.clear();
    _secureStorage.clearAuthTokens();
    _onSessionExpired?.call();
    handler.reject(err);
  }

  void _failQueueWithoutLogout(ErrorInterceptorHandler handler, DioException err) {
    _isRefreshing = false;
    for (final queued in _refreshQueue) {
      queued.completer.completeError(err);
    }
    _refreshQueue.clear();
    handler.reject(err);
  }
}

class _QueuedRequest {
  final RequestOptions options;
  final Completer<Response<dynamic>> completer;

  _QueuedRequest({
    required this.options,
    required this.completer,
  });
}

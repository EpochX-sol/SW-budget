import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:sw_budget/core/security/secure_storage_service.dart';
import 'package:sw_budget/data/remote/auth_interceptor.dart';

// In-memory mock for SecureStorageService to run without platform channel
class MockSecureStorageService implements SecureStorageService {
  String? accessToken = 'initial_access_token';
  String? refreshToken = 'initial_refresh_token';
  String? deviceId = 'test_device_123';
  final Map<String, dynamic> userProfile = {};
  bool biometricsEnabled = false;
  int lockTimeout = 60;
  int? backgroundTs;

  @override
  Future<String> getOrGenerateDbPassphrase() async => 'test_passphrase_32_bytes_entropy';

  @override
  Future<String> getOrGenerateDeviceId() async => deviceId!;

  @override
  Future<String?> getAccessToken() async => accessToken;

  @override
  Future<void> saveAccessToken(String token) async => accessToken = token;

  @override
  Future<String?> getRefreshToken() async => refreshToken;

  @override
  Future<void> saveRefreshToken(String token) async => refreshToken = token;

  @override
  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
  }

  @override
  Future<void> clearAuthTokens() async {
    accessToken = null;
    refreshToken = null;
  }

  @override
  Future<void> saveUserProfile(Map<String, dynamic> user) async => userProfile.addAll(user);

  @override
  Future<Map<String, dynamic>?> getUserProfile() async => userProfile;

  @override
  Future<bool> isBiometricsEnabled() async => biometricsEnabled;

  @override
  Future<void> setBiometricsEnabled(bool enabled) async => biometricsEnabled = enabled;

  @override
  Future<int> getLockTimeoutSeconds() async => lockTimeout;

  @override
  Future<void> setLockTimeoutSeconds(int seconds) async => lockTimeout = seconds;

  @override
  Future<void> recordBackgroundTimestamp() async =>
      backgroundTs = DateTime.now().millisecondsSinceEpoch;

  @override
  Future<int?> getLastBackgroundTimestamp() async => backgroundTs;

  @override
  Future<void> clearBackgroundTimestamp() async => backgroundTs = null;

  @override
  Future<void> wipeAll() async => clearAuthTokens();
}

void main() {
  group('AuthInterceptor Tests', () {
    late Dio dio;
    late MockSecureStorageService mockStorage;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
      mockStorage = MockSecureStorageService();
    });

    test('injects Bearer token into outgoing request headers', () async {
      final interceptor = AuthInterceptor(
        dio: dio,
        secureStorage: mockStorage,
        baseUrl: 'http://localhost:3000',
      );

      final options = RequestOptions(path: '/v1/accounts');
      interceptor.onRequest(options, RequestInterceptorHandler());
      await Future<void>.delayed(Duration.zero);

      // After handler next, authorization should be present
      expect(options.headers['Authorization'], 'Bearer initial_access_token');
    });

    test('bypasses authorization header if already explicitly specified', () async {
      final interceptor = AuthInterceptor(
        dio: dio,
        secureStorage: mockStorage,
        baseUrl: 'http://localhost:3000',
      );

      final options = RequestOptions(
        path: '/v1/accounts',
        headers: {'Authorization': 'Bearer custom_override'},
      );
      interceptor.onRequest(options, RequestInterceptorHandler());
      await Future<void>.delayed(Duration.zero);

      expect(options.headers['Authorization'], 'Bearer custom_override');
    });
  });
}

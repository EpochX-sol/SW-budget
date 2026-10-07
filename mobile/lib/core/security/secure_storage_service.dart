import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Secure storage service backed by Android Keystore (via FlutterSecureStorage)
/// Responsible for hardware-backed encryption key derivation, SQLCipher passphrase,
/// session tokens, and device identification.
class SecureStorageService {
  final FlutterSecureStorage _storage;

  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
                resetOnError: false,
              ),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  // Storage Keys
  static const String _keyDbPassphrase = 'sw_budget_sqlcipher_passphrase';
  static const String _keyAccessToken = 'sw_budget_access_token';
  static const String _keyRefreshToken = 'sw_budget_refresh_token';
  static const String _keyDeviceId = 'sw_budget_device_id';
  static const String _keyUserProfile = 'sw_budget_user_profile';
  static const String _keyBiometricsEnabled = 'sw_budget_biometrics_enabled';
  static const String _keyLockTimeoutSeconds = 'sw_budget_lock_timeout_sec';
  static const String _keyLastBackgroundTs = 'sw_budget_last_background_ts';

  /// Retrieves or generates a 256-bit cryptographically secure passphrase
  /// for the local SQLCipher database.
  Future<String> getOrGenerateDbPassphrase() async {
    String? passphrase = await _storage.read(key: _keyDbPassphrase);
    if (passphrase == null || passphrase.isEmpty) {
      final random = Random.secure();
      final values = List<int>.generate(32, (i) => random.nextInt(256));
      passphrase = base64UrlEncode(values);
      await _storage.write(key: _keyDbPassphrase, value: passphrase);
    }
    return passphrase;
  }

  /// Retrieves or generates a persistent device UUID v4
  Future<String> getOrGenerateDeviceId() async {
    String? deviceId = await _storage.read(key: _keyDeviceId);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await _storage.write(key: _keyDeviceId, value: deviceId);
    }
    return deviceId;
  }

  // Token Management
  Future<String?> getAccessToken() async {
    return _storage.read(key: _keyAccessToken);
  }

  Future<void> saveAccessToken(String token) async {
    await _storage.write(key: _keyAccessToken, value: token);
  }

  Future<String?> getRefreshToken() async {
    return _storage.read(key: _keyRefreshToken);
  }

  Future<void> saveRefreshToken(String token) async {
    await _storage.write(key: _keyRefreshToken, value: token);
  }

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      saveAccessToken(accessToken),
      saveRefreshToken(refreshToken),
    ]);
  }

  Future<void> clearAuthTokens() async {
    await Future.wait([
      _storage.delete(key: _keyAccessToken),
      _storage.delete(key: _keyRefreshToken),
      _storage.delete(key: _keyUserProfile),
    ]);
  }

  // User Profile Cache
  Future<void> saveUserProfile(Map<String, dynamic> user) async {
    await _storage.write(key: _keyUserProfile, value: jsonEncode(user));
  }

  Future<Map<String, dynamic>?> getUserProfile() async {
    final raw = await _storage.read(key: _keyUserProfile);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // Biometrics & Lock Config
  Future<bool> isBiometricsEnabled() async {
    final val = await _storage.read(key: _keyBiometricsEnabled);
    return val == 'true';
  }

  Future<void> setBiometricsEnabled(bool enabled) async {
    await _storage.write(key: _keyBiometricsEnabled, value: enabled.toString());
  }

  Future<int> getLockTimeoutSeconds() async {
    final val = await _storage.read(key: _keyLockTimeoutSeconds);
    return int.tryParse(val ?? '') ?? 60; // Default: 60 seconds
  }

  Future<void> setLockTimeoutSeconds(int seconds) async {
    await _storage.write(key: _keyLockTimeoutSeconds, value: seconds.toString());
  }

  Future<void> recordBackgroundTimestamp() async {
    final nowMs = DateTime.now().millisecondsSinceEpoch.toString();
    await _storage.write(key: _keyLastBackgroundTs, value: nowMs);
  }

  Future<int?> getLastBackgroundTimestamp() async {
    final val = await _storage.read(key: _keyLastBackgroundTs);
    return int.tryParse(val ?? '');
  }

  Future<void> clearBackgroundTimestamp() async {
    await _storage.delete(key: _keyLastBackgroundTs);
  }

  /// Full purge for account deletion or reset
  Future<void> wipeAll() async {
    await _storage.deleteAll();
  }
}

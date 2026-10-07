import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'secure_storage_service.dart';

/// Service handling device hardware biometric authentication (Fingerprint, Face unlock)
/// and evaluating inactivity timeouts for app lock screens.
class BiometricAuthService {
  final LocalAuthentication _localAuth;
  final SecureStorageService _secureStorage;

  BiometricAuthService({
    LocalAuthentication? localAuth,
    required SecureStorageService secureStorage,
  })  : _localAuth = localAuth ?? LocalAuthentication(),
        _secureStorage = secureStorage;

  /// Check if hardware supports biometrics
  Future<bool> isHardwareSupported() async {
    try {
      final isSupported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      return isSupported && canCheck;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Get available biometric types (fingerprint, face, iris)
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } on PlatformException catch (_) {
      return [];
    }
  }

  /// Prompt user for biometric authentication
  Future<bool> authenticate({
    String reason = 'Authenticate to access your SW-budget ledger',
  }) async {
    try {
      final isSupported = await isHardwareSupported();
      if (!isSupported) {
        return false;
      }

      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // Allows device PIN/pattern fallback if configured
          useErrorDialogs: true,
        ),
      );
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Checks whether app should be locked upon resuming from background
  Future<bool> shouldLockOnResume() async {
    final enabled = await _secureStorage.isBiometricsEnabled();
    if (!enabled) return false;

    final lastBgMs = await _secureStorage.getLastBackgroundTimestamp();
    if (lastBgMs == null) return false;

    final timeoutSeconds = await _secureStorage.getLockTimeoutSeconds();
    if (timeoutSeconds <= 0) return true; // Immediate lock

    final elapsedMs = DateTime.now().millisecondsSinceEpoch - lastBgMs;
    final elapsedSec = elapsedMs / 1000;

    return elapsedSec >= timeoutSeconds;
  }
}

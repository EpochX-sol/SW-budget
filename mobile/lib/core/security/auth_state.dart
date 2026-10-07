import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'secure_storage_service.dart';
import 'biometric_auth_service.dart';

enum AuthStatus {
  initial,
  unauthenticated,
  authenticated,
  biometricLocked,
}

class AuthState {
  final AuthStatus status;
  final Map<String, dynamic>? userProfile;
  final String? errorMessage;

  const AuthState({
    required this.status,
    this.userProfile,
    this.errorMessage,
  });

  bool get isAuthenticated => status == AuthStatus.authenticated;
  bool get isLocked => status == AuthStatus.biometricLocked;
  bool get isUnauthenticated => status == AuthStatus.unauthenticated;

  AuthState copyWith({
    AuthStatus? status,
    Map<String, dynamic>? userProfile,
    String? errorMessage,
  }) {
    return AuthState(
      status: status ?? this.status,
      userProfile: userProfile ?? this.userProfile,
      errorMessage: errorMessage,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final SecureStorageService _secureStorage;
  final BiometricAuthService _biometricAuth;

  AuthNotifier({
    required SecureStorageService secureStorage,
    required BiometricAuthService biometricAuth,
  })  : _secureStorage = secureStorage,
        _biometricAuth = biometricAuth,
        super(const AuthState(status: AuthStatus.initial)) {
    checkInitialAuth();
  }

  /// Bootstrap auth state on app launch
  Future<void> checkInitialAuth() async {
    final token = await _secureStorage.getAccessToken();
    if (token == null || token.isEmpty) {
      state = const AuthState(status: AuthStatus.unauthenticated);
      return;
    }

    final userProfile = await _secureStorage.getUserProfile();
    final biometricsEnabled = await _secureStorage.isBiometricsEnabled();

    if (biometricsEnabled) {
      state = AuthState(
        status: AuthStatus.biometricLocked,
        userProfile: userProfile,
      );
    } else {
      state = AuthState(
        status: AuthStatus.authenticated,
        userProfile: userProfile,
      );
    }
  }

  /// Called after successful login or registration
  Future<void> setAuthenticated({
    required String accessToken,
    required String refreshToken,
    required Map<String, dynamic> userProfile,
  }) async {
    await _secureStorage.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
    await _secureStorage.saveUserProfile(userProfile);

    state = AuthState(
      status: AuthStatus.authenticated,
      userProfile: userProfile,
    );
  }

  /// Trigger biometric unlock
  Future<bool> unlockWithBiometrics() async {
    final success = await _biometricAuth.authenticate();
    if (success) {
      final userProfile = await _secureStorage.getUserProfile();
      state = AuthState(
        status: AuthStatus.authenticated,
        userProfile: userProfile,
      );
      await _secureStorage.clearBackgroundTimestamp();
      return true;
    }
    return false;
  }

  /// Manually lock app
  void lockApp() {
    if (state.status == AuthStatus.authenticated) {
      state = state.copyWith(status: AuthStatus.biometricLocked);
    }
  }

  /// Check lock condition when returning from background
  Future<void> handleAppResume() async {
    if (state.status == AuthStatus.authenticated) {
      final shouldLock = await _biometricAuth.shouldLockOnResume();
      if (shouldLock) {
        state = state.copyWith(status: AuthStatus.biometricLocked);
      }
    }
  }

  /// Record timestamp when entering background
  Future<void> handleAppPause() async {
    if (state.status == AuthStatus.authenticated) {
      await _secureStorage.recordBackgroundTimestamp();
    }
  }

  /// Logout and wipe session tokens
  Future<void> logout() async {
    await _secureStorage.clearAuthTokens();
    await _secureStorage.clearBackgroundTimestamp();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

// Providers
final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

final biometricAuthProvider = Provider<BiometricAuthService>((ref) {
  final storage = ref.watch(secureStorageProvider);
  return BiometricAuthService(secureStorage: storage);
});

final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final storage = ref.watch(secureStorageProvider);
  final biometrics = ref.watch(biometricAuthProvider);
  return AuthNotifier(
    secureStorage: storage,
    biometricAuth: biometrics,
  );
});

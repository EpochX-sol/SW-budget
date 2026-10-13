import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/security/auth_state.dart';
import '../../core/security/secure_storage_service.dart';
import 'api_client.dart';
import 'api_endpoints.dart';

class ServerConfigNotifier extends StateNotifier<String> {
  final SecureStorageService _secureStorage;

  ServerConfigNotifier(this._secureStorage) : super(ApiEndpoints.defaultBaseUrl) {
    _loadCustomUrl();
  }

  Future<void> _loadCustomUrl() async {
    final customUrl = await _secureStorage.getCustomBaseUrl();
    if (customUrl != null && customUrl.trim().isNotEmpty) {
      state = customUrl.trim();
    }
  }

  Future<void> updateBaseUrl(String newUrl) async {
    final cleaned = newUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (cleaned.isNotEmpty) {
      await _secureStorage.setCustomBaseUrl(cleaned);
      state = cleaned;
    }
  }

  Future<void> resetToDefault() async {
    await _secureStorage.setCustomBaseUrl(null);
    state = ApiEndpoints.defaultBaseUrl;
  }
}

final serverConfigProvider = StateNotifierProvider<ServerConfigNotifier, String>((ref) {
  final secureStorage = ref.watch(secureStorageProvider);
  return ServerConfigNotifier(secureStorage);
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final secureStorage = ref.watch(secureStorageProvider);
  final activeBaseUrl = ref.watch(serverConfigProvider);

  return ApiClient(
    secureStorage: secureStorage,
    customBaseUrl: activeBaseUrl,
    onSessionExpired: () {
      // Notify authNotifier to trigger logout and route to login
      ref.read(authStateProvider.notifier).logout();
    },
  );
});

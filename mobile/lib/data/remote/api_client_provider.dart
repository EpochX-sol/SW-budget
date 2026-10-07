import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/security/auth_state.dart';
import '../../core/security/secure_storage_service.dart';
import 'api_client.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  final secureStorage = ref.watch(secureStorageProvider);
  return ApiClient(
    secureStorage: secureStorage,
    onSessionExpired: () {
      // Notify authNotifier to trigger logout and route to login
      ref.read(authStateProvider.notifier).logout();
    },
  );
});

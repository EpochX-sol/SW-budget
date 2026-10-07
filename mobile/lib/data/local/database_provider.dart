import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/security/secure_storage_service.dart';
import '../../core/security/auth_state.dart';
import 'app_database.dart';

final databaseProvider = FutureProvider<AppDatabase>((ref) async {
  final secureStorage = ref.watch(secureStorageProvider);
  final passphrase = await secureStorage.getOrGenerateDbPassphrase();
  return AppDatabase.openEncrypted(passphrase: passphrase);
});

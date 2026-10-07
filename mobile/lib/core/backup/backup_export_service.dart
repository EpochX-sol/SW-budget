import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local/app_database.dart';
import '../../data/local/database_provider.dart';
import '../../data/remote/api_client.dart';
import '../../data/remote/api_client_provider.dart';

/// Service managing data sovereignty, Excel/CSV exports, and encrypted .swbackup creation
class BackupExportService {
  final AppDatabase _database;
  final ApiClient _apiClient;

  BackupExportService({
    required AppDatabase database,
    required ApiClient apiClient,
  })  : _database = database,
        _apiClient = apiClient;

  /// Generates a local CSV/Excel export of transactions and triggers system share sheet
  Future<String> exportTransactionsCsv() async {
    final txns = _database.getTransactions(limit: 5000);
    final buffer = StringBuffer();

    // CSV Header
    buffer.writeln('ID,Date,Type,Amount,BalanceAfter,Counterparty,Reference,Source,Verified');

    for (final t in txns) {
      final id = t['id'];
      final date = t['occurred_at'];
      final type = t['type'];
      final amount = t['amount'];
      final balance = t['balance_after'] ?? '';
      final party = '"${(t['counterparty'] ?? '').toString().replaceAll('"', '""')}"';
      final ref = t['reference'] ?? '';
      final source = t['source'];
      final verified = t['balance_chain_ok'] == 1 ? 'Yes' : 'No';

      buffer.writeln('$id,$date,$type,$amount,$balance,$party,$ref,$source,$verified');
    }

    final tempDir = await getTemporaryDirectory();
    final now = DateTime.now();
    final fileName = 'sw_budget_transactions_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.csv';
    final file = File(p.join(tempDir.path, fileName));

    await file.writeAsString(buffer.toString());

    // Share via system sheet
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'SW-budget Financial Ledger Export',
    );

    return file.path;
  }

  /// Creates a genuine AES-256-GCM encrypted .swbackup archive derived with PBKDF2/SHA-256
  Future<String> createEncryptedBackupFile({required String password}) async {
    final accounts = _database.getAccounts();
    final categories = _database.getCategories();
    final transactions = _database.getTransactions(limit: 10000);
    final limits = _database.getLimits();
    final savingPlans = _database.getSavingPlans();

    final payload = {
      'version': 2,
      'createdAt': DateTime.now().toIso8601String(),
      'accounts': accounts,
      'categories': categories,
      'transactions': transactions,
      'limits': limits,
      'saving_plans': savingPlans,
    };

    final rawJsonBytes = utf8.encode(jsonEncode(payload));

    // 1. Generate 16-byte random salt and 12-byte random nonce
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final nonce = List<int>.generate(12, (_) => random.nextInt(256));

    // 2. Derive 256-bit key from password using PBKDF2 with HMAC-SHA256
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 10000,
      bits: 256,
    );

    final secretKey = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );

    // 3. Encrypt payload with AES-256-GCM
    final algorithm = AesGcm.with256bits();
    final secretBox = await algorithm.encrypt(
      rawJsonBytes,
      secretKey: secretKey,
      nonce: nonce,
    );

    // 4. Pack: [16 bytes salt] + [12 bytes nonce] + [16 bytes MAC] + [ciphertext]
    final packed = BytesBuilder()
      ..add(salt)
      ..add(nonce)
      ..add(secretBox.mac.bytes)
      ..add(secretBox.cipherText);

    final encodedPayload = 'SWBACKUP_V2:' + base64UrlEncode(packed.toBytes());

    final tempDir = await getTemporaryDirectory();
    final now = DateTime.now();
    final fileName = 'sw_vault_backup_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.swbackup';
    final file = File(p.join(tempDir.path, fileName));

    await file.writeAsString(encodedPayload);

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'SW-budget Encrypted Backup Vault',
    );

    return file.path;
  }

  /// Decrypts a .swbackup file using the provided password
  Future<Map<String, dynamic>> decryptBackupContent({
    required String backupContent,
    required String password,
  }) async {
    if (!backupContent.startsWith('SWBACKUP_V2:')) {
      throw const FormatException('Invalid or unsupported SW-budget backup file version');
    }

    final encoded = backupContent.substring('SWBACKUP_V2:'.length);
    final packedBytes = base64Url.decode(encoded);

    if (packedBytes.length < 44) {
      throw const FormatException('Corrupted backup payload: insufficient length');
    }

    final salt = packedBytes.sublist(0, 16);
    final nonce = packedBytes.sublist(16, 28);
    final macBytes = packedBytes.sublist(28, 44);
    final cipherText = packedBytes.sublist(44);

    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 10000,
      bits: 256,
    );

    final secretKey = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );

    final algorithm = AesGcm.with256bits();
    final decryptedBytes = await algorithm.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes)),
      secretKey: secretKey,
    );

    final jsonStr = utf8.decode(decryptedBytes);
    return jsonDecode(jsonStr) as Map<String, dynamic>;
  }
}

final backupExportServiceProvider = FutureProvider<BackupExportService>((ref) async {
  final database = await ref.watch(databaseProvider.future);
  final apiClient = ref.watch(apiClientProvider);
  return BackupExportService(database: database, apiClient: apiClient);
});


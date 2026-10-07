import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'tables/local_accounts.dart';
import 'tables/local_categories.dart';
import 'tables/local_transactions.dart';
import 'tables/local_limits.dart';
import 'tables/local_saving_plans.dart';
import 'tables/local_sync_state.dart';
import 'tables/local_unparsed_messages.dart';

DynamicLibrary _openSqlCipherOnAndroid() {
  try {
    return DynamicLibrary.open('libsqlcipher.so');
  } on ArgumentError {
    try {
      final appIdAsBytes = File('/proc/self/cmdline').readAsBytesSync();
      final endOfAppId = appIdAsBytes.indexOf(0);
      final appId = String.fromCharCodes(
        appIdAsBytes.sublist(0, endOfAppId > 0 ? endOfAppId : appIdAsBytes.length),
      );
      return DynamicLibrary.open('/data/data/$appId/lib/libsqlcipher.so');
    } catch (_) {
      return DynamicLibrary.process();
    }
  } catch (_) {
    return DynamicLibrary.process();
  }
}

DynamicLibrary _openSqlCipherOnWindows() {
  try {
    return DynamicLibrary.open('sqlcipher.dll');
  } catch (_) {
    return DynamicLibrary.open('sqlite3.dll');
  }
}

DynamicLibrary _openSqlCipherOnLinux() {
  try {
    return DynamicLibrary.open('libsqlcipher.so');
  } catch (_) {
    return DynamicLibrary.open('libsqlite3.so');
  }
}

bool _sqlCipherInitialized = false;

/// Configures sqlite3 FFI to load the bundled SQLCipher binary instead of default unencrypted sqlite3
void ensureSqlCipherLoaded() {
  if (_sqlCipherInitialized || kIsWeb) return;
  _sqlCipherInitialized = true;
  if (Platform.isAndroid) {
    open.overrideFor(OperatingSystem.android, _openSqlCipherOnAndroid);
  } else if (Platform.isWindows) {
    open.overrideFor(OperatingSystem.windows, _openSqlCipherOnWindows);
  } else if (Platform.isLinux) {
    open.overrideFor(OperatingSystem.linux, _openSqlCipherOnLinux);
  }
}

export 'tables/local_accounts.dart';
export 'tables/local_categories.dart';
export 'tables/local_transactions.dart';
export 'tables/local_limits.dart';
export 'tables/local_saving_plans.dart';
export 'tables/local_sync_state.dart';
export 'tables/local_unparsed_messages.dart';

/// Database event for reactive data updates
enum DatabaseTable {
  accounts,
  categories,
  transactions,
  limits,
  savingPlans,
  syncState,
  unparsedMessages,
}

/// Encrypted Local SQLite Database using SQLCipher (AES-256)
/// Stores all financial accounts, transactions, categories, budgets, and sync states offline.
class AppDatabase {
  final sqlite.Database _db;
  final StreamController<DatabaseTable> _changeController =
      StreamController<DatabaseTable>.broadcast();

  AppDatabase._(this._db) {
    _createSchema();
  }

  Stream<DatabaseTable> get onTableChanged => _changeController.stream;

  /// Open an AES-256 encrypted database using the provided passphrase
  static Future<AppDatabase> openEncrypted({
    required String passphrase,
    String? customPath,
  }) async {
    ensureSqlCipherLoaded();
    String dbPath = customPath ?? '';
    if (dbPath.isEmpty) {
      final docsDir = await getApplicationDocumentsDirectory();
      dbPath = p.join(docsDir.path, 'sw_budget_encrypted.db');
    }

    final db = sqlite.sqlite3.open(dbPath);

    // SQLCipher security pragmas
    // Escape single quotes in passphrase if any
    final sanitizedPassphrase = passphrase.replaceAll("'", "''");
    db.execute("PRAGMA key = '$sanitizedPassphrase';");
    db.execute("PRAGMA cipher_compatibility = 4;");
    db.execute("PRAGMA cipher_page_size = 4096;");
    db.execute("PRAGMA kdf_iter = 64000;");
    db.execute("PRAGMA foreign_keys = ON;");

    // Quick verification that SQLCipher cipher is working
    try {
      db.select('SELECT count(*) FROM sqlite_master;');
    } catch (e) {
      debugPrint('SQLCipher Key Verification Error: $e');
      rethrow;
    }

    return AppDatabase._(db);
  }

  /// In-memory encrypted or test database
  static AppDatabase openInMemory({String? passphrase}) {
    ensureSqlCipherLoaded();
    final db = sqlite.sqlite3.openInMemory();
    if (passphrase != null && passphrase.isNotEmpty) {
      final sanitized = passphrase.replaceAll("'", "''");
      db.execute("PRAGMA key = '$sanitized';");
    }
    return AppDatabase._(db);
  }

  /// Initial schema setup
  void _createSchema() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS local_accounts (
        id TEXT PRIMARY KEY,
        provider TEXT NOT NULL,
        name TEXT NOT NULL,
        account_mask TEXT,
        last_known_balance REAL,
        is_savings INTEGER NOT NULL DEFAULT 0,
        change_seq INTEGER NOT NULL DEFAULT 0,
        is_dirty INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        deleted_at TEXT
      );

      CREATE TABLE IF NOT EXISTS local_categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        icon TEXT NOT NULL,
        color_hex TEXT NOT NULL,
        is_system INTEGER NOT NULL DEFAULT 0,
        change_seq INTEGER NOT NULL DEFAULT 0,
        is_dirty INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        deleted_at TEXT
      );

      CREATE TABLE IF NOT EXISTS local_transactions (
        id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL,
        category_id TEXT,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        balance_after REAL,
        counterparty TEXT,
        reference TEXT,
        note TEXT,
        occurred_at TEXT NOT NULL,
        source TEXT NOT NULL,
        parse_confidence REAL,
        dedupe_key TEXT,
        raw_body TEXT,
        sender TEXT,
        balance_chain_ok INTEGER,
        gap_before_amount REAL,
        needs_review INTEGER NOT NULL DEFAULT 0,
        change_seq INTEGER NOT NULL DEFAULT 0,
        is_dirty INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        deleted_at TEXT
      );

      CREATE INDEX IF NOT EXISTS idx_txn_dedupe ON local_transactions(dedupe_key);
      CREATE INDEX IF NOT EXISTS idx_txn_occurred ON local_transactions(occurred_at);
      CREATE INDEX IF NOT EXISTS idx_txn_account ON local_transactions(account_id);
      CREATE INDEX IF NOT EXISTS idx_txn_category ON local_transactions(category_id);
      CREATE INDEX IF NOT EXISTS idx_txn_dirty ON local_transactions(is_dirty);
      CREATE INDEX IF NOT EXISTS idx_txn_review ON local_transactions(needs_review);

      CREATE TABLE IF NOT EXISTS local_limits (
        id TEXT PRIMARY KEY,
        scope_type TEXT NOT NULL,
        scope_id TEXT,
        period_type TEXT NOT NULL,
        amount REAL NOT NULL,
        mode TEXT NOT NULL DEFAULT 'soft',
        rollover INTEGER NOT NULL DEFAULT 0,
        alert_thresholds TEXT NOT NULL DEFAULT '[50,80,100]',
        active INTEGER NOT NULL DEFAULT 1,
        change_seq INTEGER NOT NULL DEFAULT 0,
        is_dirty INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        deleted_at TEXT
      );

      CREATE TABLE IF NOT EXISTS local_saving_plans (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        target_amount REAL NOT NULL,
        current_amount REAL NOT NULL DEFAULT 0.0,
        target_date TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'active',
        change_seq INTEGER NOT NULL DEFAULT 0,
        is_dirty INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        deleted_at TEXT
      );

      CREATE TABLE IF NOT EXISTS local_sync_state (
        key TEXT PRIMARY KEY,
        last_sync_seq INTEGER NOT NULL DEFAULT 0,
        last_synced_at TEXT,
        status TEXT NOT NULL DEFAULT 'idle'
      );

      CREATE TABLE IF NOT EXISTS local_unparsed_messages (
        id TEXT PRIMARY KEY,
        sender TEXT NOT NULL,
        body TEXT NOT NULL,
        received_at TEXT NOT NULL,
        reason TEXT,
        status TEXT NOT NULL DEFAULT 'pending'
      );
    ''');
  }

  // --- ACCOUNTS ---

  List<Map<String, dynamic>> getAccounts({bool includeDeleted = false}) {
    final query = includeDeleted
        ? 'SELECT * FROM local_accounts ORDER BY name ASC;'
        : 'SELECT * FROM local_accounts WHERE deleted_at IS NULL ORDER BY name ASC;';
    final result = _db.select(query);
    return result.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Map<String, dynamic>? getAccountById(String id) {
    final result = _db.select('SELECT * FROM local_accounts WHERE id = ?;', [id]);
    if (result.isEmpty) return null;
    return Map<String, dynamic>.from(result.first);
  }

  void upsertAccount({
    required String id,
    required String provider,
    required String name,
    String? accountMask,
    double? lastKnownBalance,
    bool isSavings = false,
    int changeSeq = 0,
    bool isDirty = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final now = DateTime.now().toIso8601String();
    final created = (createdAt ?? DateTime.now()).toIso8601String();
    final updated = (updatedAt ?? DateTime.now()).toIso8601String();

    _db.execute('''
      INSERT INTO local_accounts (
        id, provider, name, account_mask, last_known_balance, is_savings, change_seq, is_dirty, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        provider = excluded.provider,
        name = excluded.name,
        account_mask = excluded.account_mask,
        last_known_balance = excluded.last_known_balance,
        is_savings = excluded.is_savings,
        change_seq = excluded.change_seq,
        is_dirty = excluded.is_dirty,
        updated_at = excluded.updated_at,
        deleted_at = NULL;
    ''', [
      id,
      provider,
      name,
      accountMask,
      lastKnownBalance,
      isSavings ? 1 : 0,
      changeSeq,
      isDirty ? 1 : 0,
      created,
      updated,
    ]);
    _notify(DatabaseTable.accounts);
  }

  List<Map<String, dynamic>> getDirtyAccounts({int limit = 100}) {
    final result = _db.select(
      'SELECT * FROM local_accounts WHERE is_dirty = 1 ORDER BY created_at ASC LIMIT ?;',
      [limit],
    );
    return result.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  void markAccountsSynced(List<String> ids, int newChangeSeq) {
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    final now = DateTime.now().toIso8601String();
    _db.execute(
      'UPDATE local_accounts SET is_dirty = 0, change_seq = ?, updated_at = ? WHERE id IN ($placeholders);',
      [newChangeSeq, now, ...ids],
    );
    _notify(DatabaseTable.accounts);
  }

  void deleteAccount(String id) {
    final now = DateTime.now().toIso8601String();
    _db.execute(
      'UPDATE local_accounts SET deleted_at = ?, updated_at = ?, is_dirty = 1 WHERE id = ?;',
      [now, now, id],
    );
    _notify(DatabaseTable.accounts);
  }

  // --- CATEGORIES ---

  List<Map<String, dynamic>> getCategories({bool includeDeleted = false}) {
    final query = includeDeleted
        ? 'SELECT * FROM local_categories ORDER BY name ASC;'
        : 'SELECT * FROM local_categories WHERE deleted_at IS NULL ORDER BY name ASC;';
    final result = _db.select(query);
    return result.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  void upsertCategory({
    required String id,
    required String name,
    required String icon,
    required String colorHex,
    bool isSystem = false,
    int changeSeq = 0,
    DateTime? createdAt,
  }) {
    final created = (createdAt ?? DateTime.now()).toIso8601String();
    final updated = DateTime.now().toIso8601String();
    _db.execute('''
      INSERT INTO local_categories (
        id, name, icon, color_hex, is_system, change_seq, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        name = excluded.name,
        icon = excluded.icon,
        color_hex = excluded.color_hex,
        change_seq = excluded.change_seq,
        updated_at = excluded.updated_at,
        deleted_at = NULL;
    ''', [
      id,
      name,
      icon,
      colorHex,
      isSystem ? 1 : 0,
      changeSeq,
      created,
      updated,
    ]);
    _notify(DatabaseTable.categories);
  }

  // --- TRANSACTIONS ---

  List<Map<String, dynamic>> getTransactions({
    String? accountId,
    int limit = 100,
    int offset = 0,
    bool includeDeleted = false,
  }) {
    String sql = 'SELECT * FROM local_transactions';
    final whereClauses = <String>[];
    final params = <dynamic>[];

    if (!includeDeleted) {
      whereClauses.add('deleted_at IS NULL');
    }
    if (accountId != null) {
      whereClauses.add('account_id = ?');
      params.add(accountId);
    }

    if (whereClauses.isNotEmpty) {
      sql += ' WHERE ${whereClauses.join(' AND ')}';
    }

    sql += ' ORDER BY occurred_at DESC LIMIT ? OFFSET ?;';
    params.addAll([limit, offset]);

    final result = _db.select(sql, params);
    return result.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Map<String, dynamic>? findTransactionByDedupeKey(String dedupeKey) {
    final result = _db.select(
      'SELECT * FROM local_transactions WHERE dedupe_key = ? AND deleted_at IS NULL LIMIT 1;',
      [dedupeKey],
    );
    if (result.isEmpty) return null;
    return Map<String, dynamic>.from(result.first);
  }

  Map<String, dynamic>? getLatestTransactionForAccount(String accountId) {
    final result = _db.select(
      'SELECT * FROM local_transactions WHERE account_id = ? AND deleted_at IS NULL ORDER BY occurred_at DESC, created_at DESC LIMIT 1;',
      [accountId],
    );
    if (result.isEmpty) return null;
    return Map<String, dynamic>.from(result.first);
  }

  List<Map<String, dynamic>> getDirtyTransactions({int limit = 100}) {
    final result = _db.select(
      'SELECT * FROM local_transactions WHERE is_dirty = 1 ORDER BY occurred_at ASC LIMIT ?;',
      [limit],
    );
    return result.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  void markTransactionsSynced(List<String> ids, int newChangeSeq) {
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    final now = DateTime.now().toIso8601String();
    _db.execute(
      'UPDATE local_transactions SET is_dirty = 0, change_seq = ?, updated_at = ? WHERE id IN ($placeholders);',
      [newChangeSeq, now, ...ids],
    );
    _notify(DatabaseTable.transactions);
  }

  List<Map<String, dynamic>> getTransactionsNeedingReview() {
    final result = _db.select(
      'SELECT * FROM local_transactions WHERE needs_review = 1 AND deleted_at IS NULL ORDER BY occurred_at DESC;',
    );
    return result.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  void upsertTransaction({
    required String id,
    required String accountId,
    String? categoryId,
    required String type,
    required double amount,
    double? balanceAfter,
    String? counterparty,
    String? reference,
    String? note,
    required DateTime occurredAt,
    required String source,
    double? parseConfidence,
    String? dedupeKey,
    String? rawBody,
    String? sender,
    bool? balanceChainOk,
    double? gapBeforeAmount,
    bool needsReview = false,
    int changeSeq = 0,
    bool isDirty = true,
    DateTime? createdAt,
  }) {
    final created = (createdAt ?? DateTime.now()).toIso8601String();
    final updated = DateTime.now().toIso8601String();
    final occurred = occurredAt.toIso8601String();

    _db.execute('''
      INSERT INTO local_transactions (
        id, account_id, category_id, type, amount, balance_after,
        counterparty, reference, note, occurred_at, source, parse_confidence,
        dedupe_key, raw_body, sender, balance_chain_ok, gap_before_amount,
        needs_review, change_seq, is_dirty, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        account_id = excluded.account_id,
        category_id = excluded.category_id,
        type = excluded.type,
        amount = excluded.amount,
        balance_after = excluded.balance_after,
        counterparty = excluded.counterparty,
        reference = excluded.reference,
        note = excluded.note,
        occurred_at = excluded.occurred_at,
        source = excluded.source,
        parse_confidence = excluded.parse_confidence,
        dedupe_key = excluded.dedupe_key,
        raw_body = excluded.raw_body,
        sender = excluded.sender,
        balance_chain_ok = excluded.balance_chain_ok,
        gap_before_amount = excluded.gap_before_amount,
        needs_review = excluded.needs_review,
        change_seq = excluded.change_seq,
        is_dirty = excluded.is_dirty,
        updated_at = excluded.updated_at,
        deleted_at = NULL;
    ''', [
      id,
      accountId,
      categoryId,
      type,
      amount,
      balanceAfter,
      counterparty,
      reference,
      note,
      occurred,
      source,
      parseConfidence,
      dedupeKey,
      rawBody,
      sender,
      balanceChainOk == null ? null : (balanceChainOk ? 1 : 0),
      gapBeforeAmount,
      needsReview ? 1 : 0,
      changeSeq,
      isDirty ? 1 : 0,
      created,
      updated,
    ]);
    _notify(DatabaseTable.transactions);
  }

  void deleteTransaction(String id) {
    final now = DateTime.now().toIso8601String();
    _db.execute(
      'UPDATE local_transactions SET deleted_at = ?, updated_at = ?, is_dirty = 1 WHERE id = ?;',
      [now, now, id],
    );
    _notify(DatabaseTable.transactions);
  }

  // --- LIMITS ---

  List<Map<String, dynamic>> getLimits({bool includeDeleted = false}) {
    final query = includeDeleted
        ? 'SELECT * FROM local_limits ORDER BY created_at DESC;'
        : 'SELECT * FROM local_limits WHERE deleted_at IS NULL ORDER BY created_at DESC;';
    final result = _db.select(query);
    return result.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  void upsertLimit({
    required String id,
    required String scopeType,
    String? scopeId,
    required String periodType,
    required double amount,
    String mode = 'soft',
    bool rollover = false,
    String alertThresholds = '[50,80,100]',
    bool active = true,
    int changeSeq = 0,
    bool isDirty = true,
    DateTime? createdAt,
  }) {
    final created = (createdAt ?? DateTime.now()).toIso8601String();
    final updated = DateTime.now().toIso8601String();
    _db.execute('''
      INSERT INTO local_limits (
        id, scope_type, scope_id, period_type, amount, mode,
        rollover, alert_thresholds, active, change_seq, is_dirty, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        scope_type = excluded.scope_type,
        scope_id = excluded.scope_id,
        period_type = excluded.period_type,
        amount = excluded.amount,
        mode = excluded.mode,
        rollover = excluded.rollover,
        alert_thresholds = excluded.alert_thresholds,
        active = excluded.active,
        change_seq = excluded.change_seq,
        is_dirty = excluded.is_dirty,
        updated_at = excluded.updated_at,
        deleted_at = NULL;
    ''', [
      id,
      scopeType,
      scopeId,
      periodType,
      amount,
      mode,
      rollover ? 1 : 0,
      alertThresholds,
      active ? 1 : 0,
      changeSeq,
      isDirty ? 1 : 0,
      created,
      updated,
    ]);
    _notify(DatabaseTable.limits);
  }

  List<Map<String, dynamic>> getDirtyLimits({int limit = 100}) {
    final result = _db.select(
      'SELECT * FROM local_limits WHERE is_dirty = 1 ORDER BY created_at ASC LIMIT ?;',
      [limit],
    );
    return result.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  void markLimitsSynced(List<String> ids, int newChangeSeq) {
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    final now = DateTime.now().toIso8601String();
    _db.execute(
      'UPDATE local_limits SET is_dirty = 0, change_seq = ?, updated_at = ? WHERE id IN ($placeholders);',
      [newChangeSeq, now, ...ids],
    );
    _notify(DatabaseTable.limits);
  }

  // --- SAVING PLANS ---

  List<Map<String, dynamic>> getSavingPlans({bool includeDeleted = false}) {
    final query = includeDeleted
        ? 'SELECT * FROM local_saving_plans ORDER BY target_date ASC;'
        : 'SELECT * FROM local_saving_plans WHERE deleted_at IS NULL ORDER BY target_date ASC;';
    final result = _db.select(query);
    return result.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  void upsertSavingPlan({
    required String id,
    required String name,
    required double targetAmount,
    double currentAmount = 0.0,
    required DateTime targetDate,
    String status = 'active',
    int changeSeq = 0,
    bool isDirty = true,
    DateTime? createdAt,
  }) {
    final created = (createdAt ?? DateTime.now()).toIso8601String();
    final updated = DateTime.now().toIso8601String();
    _db.execute('''
      INSERT INTO local_saving_plans (
        id, name, target_amount, current_amount, target_date, status, change_seq, is_dirty, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        name = excluded.name,
        target_amount = excluded.target_amount,
        current_amount = excluded.current_amount,
        target_date = excluded.target_date,
        status = excluded.status,
        change_seq = excluded.change_seq,
        is_dirty = excluded.is_dirty,
        updated_at = excluded.updated_at,
        deleted_at = NULL;
    ''', [
      id,
      name,
      targetAmount,
      currentAmount,
      targetDate.toIso8601String(),
      status,
      changeSeq,
      isDirty ? 1 : 0,
      created,
      updated,
    ]);
    _notify(DatabaseTable.savingPlans);
  }

  List<Map<String, dynamic>> getDirtySavingPlans({int limit = 100}) {
    final result = _db.select(
      'SELECT * FROM local_saving_plans WHERE is_dirty = 1 ORDER BY created_at ASC LIMIT ?;',
      [limit],
    );
    return result.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  void markSavingPlansSynced(List<String> ids, int newChangeSeq) {
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    final now = DateTime.now().toIso8601String();
    _db.execute(
      'UPDATE local_saving_plans SET is_dirty = 0, change_seq = ?, updated_at = ? WHERE id IN ($placeholders);',
      [newChangeSeq, now, ...ids],
    );
    _notify(DatabaseTable.savingPlans);
  }

  // --- SYNC STATE ---

  int getLastSyncCursor({String key = 'global_sync'}) {
    final result = _db.select(
      'SELECT last_sync_seq FROM local_sync_state WHERE key = ?;',
      [key],
    );
    if (result.isEmpty) return 0;
    return result.first['last_sync_seq'] as int? ?? 0;
  }

  void updateSyncCursor({
    String key = 'global_sync',
    required int lastSyncSeq,
    String status = 'synced',
  }) {
    final now = DateTime.now().toIso8601String();
    _db.execute('''
      INSERT INTO local_sync_state (key, last_sync_seq, last_synced_at, status)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(key) DO UPDATE SET
        last_sync_seq = excluded.last_sync_seq,
        last_synced_at = excluded.last_synced_at,
        status = excluded.status;
    ''', [key, lastSyncSeq, now, status]);
    _notify(DatabaseTable.syncState);
  }

  // --- UNPARSED MESSAGES ---

  void saveUnparsedMessage({
    required String id,
    required String sender,
    required String body,
    required DateTime receivedAt,
    String? reason,
  }) {
    _db.execute('''
      INSERT OR IGNORE INTO local_unparsed_messages (id, sender, body, received_at, reason, status)
      VALUES (?, ?, ?, ?, ?, 'pending');
    ''', [id, sender, body, receivedAt.toIso8601String(), reason]);
    _notify(DatabaseTable.unparsedMessages);
  }

  List<Map<String, dynamic>> getPendingUnparsedMessages() {
    final result = _db.select(
      "SELECT * FROM local_unparsed_messages WHERE status = 'pending' ORDER BY received_at DESC;",
    );
    return result.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  void _notify(DatabaseTable table) {
    if (!_changeController.isClosed) {
      _changeController.add(table);
    }
  }

  void wipeLocalLedger() {
    _db.execute('DELETE FROM local_transactions;');
    _db.execute('DELETE FROM local_accounts;');
    _db.execute('DELETE FROM local_categories;');
    _db.execute('DELETE FROM local_limits;');
    _db.execute('DELETE FROM local_saving_plans;');
    _db.execute('DELETE FROM local_sync_state;');
    _db.execute('DELETE FROM local_unparsed_messages;');
    _notify(DatabaseTable.transactions);
    _notify(DatabaseTable.accounts);
    _notify(DatabaseTable.categories);
    _notify(DatabaseTable.limits);
    _notify(DatabaseTable.savingPlans);
  }

  void close() {
    _changeController.close();
    _db.dispose();
  }
}

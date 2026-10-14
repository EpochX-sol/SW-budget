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
import 'tables/local_budget_plans.dart';
import 'tables/local_expected_expenses.dart';

export 'tables/local_accounts.dart';
export 'tables/local_categories.dart';
export 'tables/local_transactions.dart';
export 'tables/local_limits.dart';
export 'tables/local_saving_plans.dart';
export 'tables/local_sync_state.dart';
export 'tables/local_unparsed_messages.dart';
export 'tables/local_budget_plans.dart';
export 'tables/local_expected_expenses.dart';

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
    try {
      return DynamicLibrary.open('sqlite3.dll');
    } catch (_) {
      try {
        return DynamicLibrary.open('winsqlite3.dll');
      } catch (_) {
        return DynamicLibrary.process();
      }
    }
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

/// Database event for reactive data updates
enum DatabaseTable {
  accounts,
  categories,
  transactions,
  limits,
  savingPlans,
  syncState,
  unparsedMessages,
  debts,
  reimbursements,
  budgetPlans,
  expectedExpenses,
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

      CREATE TABLE IF NOT EXISTS local_debts (
        id TEXT PRIMARY KEY,
        direction TEXT NOT NULL,
        counterparty TEXT NOT NULL,
        total_amount REAL NOT NULL,
        paid_amount REAL NOT NULL DEFAULT 0.0,
        due_date TEXT,
        note TEXT,
        status TEXT NOT NULL DEFAULT 'active',
        change_seq INTEGER NOT NULL DEFAULT 0,
        is_dirty INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        deleted_at TEXT
      );

      CREATE TABLE IF NOT EXISTS local_reimbursements (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        amount REAL NOT NULL,
        paid_amount REAL NOT NULL DEFAULT 0.0,
        status TEXT NOT NULL DEFAULT 'pending',
        note TEXT,
        change_seq INTEGER NOT NULL DEFAULT 0,
        is_dirty INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        deleted_at TEXT
      );

      CREATE TABLE IF NOT EXISTS local_budget_plans (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        period_type TEXT NOT NULL,
        start_date TEXT NOT NULL,
        end_date TEXT NOT NULL,
        monthly_start_day INTEGER NOT NULL DEFAULT 1,
        spending_limit REAL NOT NULL,
        reserve_type TEXT NOT NULL DEFAULT 'none',
        reserve_value REAL NOT NULL DEFAULT 0.0,
        watched_bank_ids TEXT,
        count_fees INTEGER NOT NULL DEFAULT 1,
        count_withdrawals INTEGER NOT NULL DEFAULT 1,
        reaction_mode TEXT NOT NULL DEFAULT 'adaptive',
        status TEXT NOT NULL DEFAULT 'active',
        paused_at TEXT,
        paused_days_count INTEGER NOT NULL DEFAULT 0,
        morning_brief_enabled INTEGER NOT NULL DEFAULT 1,
        morning_brief_time TEXT NOT NULL DEFAULT '07:30',
        daily_report_enabled INTEGER NOT NULL DEFAULT 1,
        daily_report_time TEXT NOT NULL DEFAULT '21:00',
        skip_empty_days INTEGER NOT NULL DEFAULT 0,
        alert_thresholds TEXT NOT NULL DEFAULT '[50,80,100]',
        reserve_alert_enabled INTEGER NOT NULL DEFAULT 1,
        final_summary_payload TEXT,
        change_seq INTEGER NOT NULL DEFAULT 0,
        is_dirty INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        deleted_at TEXT
      );

      CREATE TABLE IF NOT EXISTS local_expected_expenses (
        id TEXT PRIMARY KEY,
        plan_id TEXT NOT NULL,
        name TEXT NOT NULL,
        amount REAL NOT NULL,
        due_date TEXT,
        linked_category_id TEXT,
        status TEXT NOT NULL DEFAULT 'expected',
        paid_amount REAL NOT NULL DEFAULT 0.0,
        paid_txn_id TEXT,
        reminder_enabled INTEGER NOT NULL DEFAULT 1,
        change_seq INTEGER NOT NULL DEFAULT 0,
        is_dirty INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        deleted_at TEXT
      );

      CREATE INDEX IF NOT EXISTS idx_plan_active ON local_budget_plans(status);
      CREATE INDEX IF NOT EXISTS idx_expected_plan ON local_expected_expenses(plan_id);
      CREATE INDEX IF NOT EXISTS idx_debts_dirty ON local_debts(is_dirty);
      CREATE INDEX IF NOT EXISTS idx_reimbursements_dirty ON local_reimbursements(is_dirty);
      CREATE INDEX IF NOT EXISTS idx_reimbursements_status ON local_reimbursements(status);
    ''');

    // Migration safe guards for existing local db instances
    try {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS local_reimbursements (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          amount REAL NOT NULL,
          paid_amount REAL NOT NULL DEFAULT 0.0,
          status TEXT NOT NULL DEFAULT 'pending',
          note TEXT,
          change_seq INTEGER NOT NULL DEFAULT 0,
          is_dirty INTEGER NOT NULL DEFAULT 1,
          created_at TEXT NOT NULL,
          updated_at TEXT,
          deleted_at TEXT
        );
      ''');
    } catch (_) {}
    try { _db.execute('CREATE INDEX IF NOT EXISTS idx_reimbursements_dirty ON local_reimbursements(is_dirty);'); } catch (_) {}
    try { _db.execute('CREATE INDEX IF NOT EXISTS idx_reimbursements_status ON local_reimbursements(status);'); } catch (_) {}
    try { _db.execute('CREATE INDEX IF NOT EXISTS idx_debts_dirty ON local_debts(is_dirty);'); } catch (_) {}
    try { _db.execute('ALTER TABLE local_debts ADD COLUMN change_seq INTEGER NOT NULL DEFAULT 0;'); } catch (_) {}
    try { _db.execute('ALTER TABLE local_debts ADD COLUMN is_dirty INTEGER NOT NULL DEFAULT 1;'); } catch (_) {}
    try { _db.execute('ALTER TABLE local_reimbursements ADD COLUMN change_seq INTEGER NOT NULL DEFAULT 0;'); } catch (_) {}
    try { _db.execute('ALTER TABLE local_reimbursements ADD COLUMN is_dirty INTEGER NOT NULL DEFAULT 1;'); } catch (_) {}
    try { _db.execute('ALTER TABLE local_transactions ADD COLUMN exclude_from_plan INTEGER NOT NULL DEFAULT 0;'); } catch (_) {}
    try { _db.execute('ALTER TABLE local_transactions ADD COLUMN plan_exclusion_reason TEXT;'); } catch (_) {}
    try { _db.execute('UPDATE local_accounts SET is_dirty = 1 WHERE change_seq = 0;'); } catch (_) {}
    try { _db.execute('UPDATE local_transactions SET is_dirty = 1 WHERE change_seq = 0;'); } catch (_) {}
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

  void updateAccountBalance(String id, double newBalance) {
    final now = DateTime.now().toIso8601String();
    _db.execute(
      'UPDATE local_accounts SET last_known_balance = ?, updated_at = ?, is_dirty = 1 WHERE id = ?;',
      [newBalance, now, id],
    );
    _notify(DatabaseTable.accounts);
  }

  void updateAccountLockStatus(String id, bool isLocked) {
    final now = DateTime.now().toIso8601String();
    _db.execute(
      'UPDATE local_accounts SET is_savings = ?, updated_at = ?, is_dirty = 1 WHERE id = ?;',
      [isLocked ? 1 : 0, now, id],
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

  Map<String, dynamic>? getLatestTransactionBefore({
    required String accountId,
    required DateTime beforeTime,
  }) {
    final beforeIso = beforeTime.toIso8601String();
    final result = _db.select(
      'SELECT * FROM local_transactions WHERE account_id = ? AND occurred_at <= ? AND deleted_at IS NULL ORDER BY occurred_at DESC, created_at DESC LIMIT 1;',
      [accountId, beforeIso],
    );
    if (result.isEmpty) return null;
    return Map<String, dynamic>.from(result.first);
  }

  double? getLatestBalanceForAccount(String accountId) {
    final result = _db.select(
      'SELECT balance_after FROM local_transactions WHERE account_id = ? AND balance_after IS NOT NULL AND deleted_at IS NULL ORDER BY occurred_at DESC, created_at DESC LIMIT 1;',
      [accountId],
    );
    if (result.isEmpty) return null;
    return (result.first['balance_after'] as num?)?.toDouble();
  }

  void syncAccountBalanceFromLatestTransaction(String accountId) {
    final latestBal = getLatestBalanceForAccount(accountId);
    if (latestBal != null) {
      final acc = getAccountById(accountId);
      if (acc != null) {
        upsertAccount(
          id: accountId,
          provider: acc['provider'] as String,
          name: acc['name'] as String,
          accountMask: acc['account_mask'] as String?,
          lastKnownBalance: latestBal,
          isSavings: acc['is_savings'] == 1,
        );
      }
    }
  }

  /// Automatically fixes existing corrupted transactions (like non-ledger airtime acknowledgements
  /// mistakenly captured as 100,000 ETB expenses) and syncs all accounts to their latest chronological balances.
  void repairCorruptedTransactionsAndBalances() {
    try {
      // 1. Remove non-ledger airtime delivery receipts or corrupted 100k records
      _db.execute('''
        DELETE FROM local_transactions 
        WHERE (raw_body LIKE '%ተሞልቶሎታል%' OR raw_body LIKE '%ATM withdraw%')
           OR (amount >= 50000 AND (counterparty LIKE '%ብር%' OR raw_body LIKE '%ተሞልቶሎታል%'));
      ''');

      // 2. Clear false balance chain gaps created by previous inverted historical processing
      _db.execute('''
        UPDATE local_transactions 
        SET balance_chain_ok = 1, gap_before_amount = NULL 
        WHERE gap_before_amount IS NOT NULL;
      ''');

      // 3. Recalculate each account's balance from its newest transaction
      final accounts = getAccounts();
      for (final acc in accounts) {
        final accId = acc['id'] as String;
        syncAccountBalanceFromLatestTransaction(accId);
      }

      _notify(DatabaseTable.transactions);
      _notify(DatabaseTable.accounts);
    } catch (_) {}
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

  void updateTransactionCategoryAndNote({
    required String id,
    required String categoryId,
    required String note,
  }) {
    final now = DateTime.now().toIso8601String();
    _db.execute(
      'UPDATE local_transactions SET category_id = ?, note = ?, updated_at = ?, is_dirty = 1 WHERE id = ?;',
      [categoryId, note, now, id],
    );
    _notify(DatabaseTable.transactions);
  }

  void markTransactionAsTransfer(String id) {
    final now = DateTime.now().toIso8601String();
    _db.execute(
      "UPDATE local_transactions SET type = 'transfer', updated_at = ?, is_dirty = 1 WHERE id = ?;",
      [now, id],
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

  void deleteLimit(String id) {
    final now = DateTime.now().toIso8601String();
    _db.execute(
      'UPDATE local_limits SET deleted_at = ?, updated_at = ?, is_dirty = 1 WHERE id = ?;',
      [now, now, id],
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

  void deleteSavingPlan(String id) {
    final now = DateTime.now().toIso8601String();
    _db.execute(
      'UPDATE local_saving_plans SET deleted_at = ?, updated_at = ?, is_dirty = 1 WHERE id = ?;',
      [now, now, id],
    );
    _notify(DatabaseTable.savingPlans);
  }

  void addSavingPlanFunding(String id, double additionalAmount) {
    final now = DateTime.now().toIso8601String();
    _db.execute(
      'UPDATE local_saving_plans SET current_amount = current_amount + ?, updated_at = ?, is_dirty = 1 WHERE id = ?;',
      [additionalAmount, now, id],
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

  void deleteUnparsedMessage(String id) {
    _db.execute('DELETE FROM local_unparsed_messages WHERE id = ?;', [id]);
    _notify(DatabaseTable.unparsedMessages);
  }

  // --- DEBTS & REIMBURSEMENTS ---

  List<Map<String, dynamic>> getDebts({bool includeSettled = false}) {
    final query = includeSettled
        ? 'SELECT * FROM local_debts WHERE deleted_at IS NULL ORDER BY created_at DESC;'
        : "SELECT * FROM local_debts WHERE deleted_at IS NULL AND status = 'active' ORDER BY created_at DESC;";
    final result = _db.select(query);
    return result.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  void upsertDebt({
    required String id,
    required String direction,
    required String counterparty,
    required double totalAmount,
    double paidAmount = 0.0,
    String? dueDate,
    String? note,
    String status = 'active',
    int changeSeq = 0,
    bool isDirty = true,
  }) {
    final now = DateTime.now().toIso8601String();
    _db.execute('''
      INSERT INTO local_debts (
        id, direction, counterparty, total_amount, paid_amount, due_date, note, status, change_seq, is_dirty, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        direction = excluded.direction,
        counterparty = excluded.counterparty,
        total_amount = excluded.total_amount,
        paid_amount = excluded.paid_amount,
        due_date = excluded.due_date,
        note = excluded.note,
        status = excluded.status,
        change_seq = excluded.change_seq,
        is_dirty = excluded.is_dirty,
        updated_at = excluded.updated_at,
        deleted_at = NULL;
    ''', [
      id,
      direction,
      counterparty,
      totalAmount,
      paidAmount,
      dueDate,
      note,
      status,
      changeSeq,
      isDirty ? 1 : 0,
      now,
      now,
    ]);
    _notify(DatabaseTable.debts);
  }

  void settleDebt(String id) {
    final now = DateTime.now().toIso8601String();
    _db.execute(
      "UPDATE local_debts SET paid_amount = total_amount, status = 'settled', is_dirty = 1, updated_at = ? WHERE id = ?;",
      [now, id],
    );
    _notify(DatabaseTable.debts);
  }

  void deleteDebt(String id) {
    final now = DateTime.now().toIso8601String();
    _db.execute(
      'UPDATE local_debts SET deleted_at = ?, updated_at = ?, is_dirty = 1 WHERE id = ?;',
      [now, now, id],
    );
    _notify(DatabaseTable.debts);
  }

  List<Map<String, dynamic>> getDirtyDebts({int limit = 100}) {
    final result = _db.select(
      'SELECT * FROM local_debts WHERE is_dirty = 1 ORDER BY created_at ASC LIMIT ?;',
      [limit],
    );
    return result.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  void markDebtsSynced(List<String> ids, int newChangeSeq) {
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    final now = DateTime.now().toIso8601String();
    _db.execute(
      'UPDATE local_debts SET is_dirty = 0, change_seq = ?, updated_at = ? WHERE id IN ($placeholders);',
      [newChangeSeq, now, ...ids],
    );
    _notify(DatabaseTable.debts);
  }

  List<Map<String, dynamic>> getReimbursements({bool includeSettled = false}) {
    final query = includeSettled
        ? 'SELECT * FROM local_reimbursements WHERE deleted_at IS NULL ORDER BY created_at DESC;'
        : "SELECT * FROM local_reimbursements WHERE deleted_at IS NULL AND status = 'pending' ORDER BY created_at DESC;";
    final result = _db.select(query);
    return result.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  void upsertReimbursement({
    required String id,
    required String title,
    required double amount,
    double paidAmount = 0.0,
    String status = 'pending',
    String? note,
    int changeSeq = 0,
    bool isDirty = true,
  }) {
    final now = DateTime.now().toIso8601String();
    _db.execute('''
      INSERT INTO local_reimbursements (
        id, title, amount, paid_amount, status, note, change_seq, is_dirty, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        title = excluded.title,
        amount = excluded.amount,
        paid_amount = excluded.paid_amount,
        status = excluded.status,
        note = excluded.note,
        change_seq = excluded.change_seq,
        is_dirty = excluded.is_dirty,
        updated_at = excluded.updated_at,
        deleted_at = NULL;
    ''', [
      id,
      title,
      amount,
      paidAmount,
      status,
      note,
      changeSeq,
      isDirty ? 1 : 0,
      now,
      now,
    ]);
    _notify(DatabaseTable.reimbursements);
  }

  void settleReimbursement(String id) {
    final now = DateTime.now().toIso8601String();
    _db.execute(
      "UPDATE local_reimbursements SET paid_amount = amount, status = 'settled', is_dirty = 1, updated_at = ? WHERE id = ?;",
      [now, id],
    );
    _notify(DatabaseTable.reimbursements);
  }

  void deleteReimbursement(String id) {
    final now = DateTime.now().toIso8601String();
    _db.execute(
      'UPDATE local_reimbursements SET deleted_at = ?, updated_at = ?, is_dirty = 1 WHERE id = ?;',
      [now, now, id],
    );
    _notify(DatabaseTable.reimbursements);
  }

  List<Map<String, dynamic>> getDirtyReimbursements({int limit = 100}) {
    final result = _db.select(
      'SELECT * FROM local_reimbursements WHERE is_dirty = 1 ORDER BY created_at ASC LIMIT ?;',
      [limit],
    );
    return result.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  void markReimbursementsSynced(List<String> ids, int newChangeSeq) {
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    final now = DateTime.now().toIso8601String();
    _db.execute(
      'UPDATE local_reimbursements SET is_dirty = 0, change_seq = ?, updated_at = ? WHERE id IN ($placeholders);',
      [newChangeSeq, now, ...ids],
    );
    _notify(DatabaseTable.reimbursements);
  }

  // --- BUDGET PLANS (v2 Adaptive Single Plan) ---

  Map<String, dynamic>? getActiveBudgetPlan() {
    final result = _db.select('''
      SELECT * FROM local_budget_plans 
      WHERE (status = 'active' OR status = 'paused' OR status = 'finished') AND deleted_at IS NULL 
      ORDER BY created_at DESC LIMIT 1;
    ''');
    if (result.isEmpty) return null;
    return Map<String, dynamic>.from(result.first);
  }

  Map<String, dynamic>? getBudgetPlanById(String id) {
    final result = _db.select('SELECT * FROM local_budget_plans WHERE id = ?;', [id]);
    if (result.isEmpty) return null;
    return Map<String, dynamic>.from(result.first);
  }

  void upsertBudgetPlan({
    required String id,
    required String name,
    required String periodType,
    required DateTime startDate,
    required DateTime endDate,
    int monthlyStartDay = 1,
    required double spendingLimit,
    String reserveType = 'none',
    double reserveValue = 0.0,
    String? watchedBankIds,
    bool countFees = true,
    bool countWithdrawals = true,
    String reactionMode = 'adaptive',
    String status = 'active',
    DateTime? pausedAt,
    int pausedDaysCount = 0,
    bool morningBriefEnabled = true,
    String morningBriefTime = '07:30',
    bool dailyReportEnabled = true,
    String dailyReportTime = '21:00',
    bool skipEmptyDays = false,
    String alertThresholds = '[50,80,100]',
    bool reserveAlertEnabled = true,
    String? finalSummaryPayload,
    int changeSeq = 0,
    bool isDirty = true,
    DateTime? createdAt,
  }) {
    final now = DateTime.now().toIso8601String();
    final created = (createdAt ?? DateTime.now()).toIso8601String();
    final start = startDate.toIso8601String();
    final end = endDate.toIso8601String();
    final paused = pausedAt?.toIso8601String();

    // Enforce single active plan: archive any other active plan
    _db.execute('''
      UPDATE local_budget_plans 
      SET status = 'archived', updated_at = ?, is_dirty = 1 
      WHERE id != ? AND (status = 'active' OR status = 'paused');
    ''', [now, id]);

    _db.execute('''
      INSERT INTO local_budget_plans (
        id, name, period_type, start_date, end_date, monthly_start_day,
        spending_limit, reserve_type, reserve_value, watched_bank_ids,
        count_fees, count_withdrawals, reaction_mode, status,
        paused_at, paused_days_count, morning_brief_enabled, morning_brief_time,
        daily_report_enabled, daily_report_time, skip_empty_days,
        alert_thresholds, reserve_alert_enabled, final_summary_payload,
        change_seq, is_dirty, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        name = excluded.name,
        period_type = excluded.period_type,
        start_date = excluded.start_date,
        end_date = excluded.end_date,
        monthly_start_day = excluded.monthly_start_day,
        spending_limit = excluded.spending_limit,
        reserve_type = excluded.reserve_type,
        reserve_value = excluded.reserve_value,
        watched_bank_ids = excluded.watched_bank_ids,
        count_fees = excluded.count_fees,
        count_withdrawals = excluded.count_withdrawals,
        reaction_mode = excluded.reaction_mode,
        status = excluded.status,
        paused_at = excluded.paused_at,
        paused_days_count = excluded.paused_days_count,
        morning_brief_enabled = excluded.morning_brief_enabled,
        morning_brief_time = excluded.morning_brief_time,
        daily_report_enabled = excluded.daily_report_enabled,
        daily_report_time = excluded.daily_report_time,
        skip_empty_days = excluded.skip_empty_days,
        alert_thresholds = excluded.alert_thresholds,
        reserve_alert_enabled = excluded.reserve_alert_enabled,
        final_summary_payload = excluded.final_summary_payload,
        change_seq = excluded.change_seq,
        is_dirty = excluded.is_dirty,
        updated_at = excluded.updated_at,
        deleted_at = NULL;
    ''', [
      id, name, periodType, start, end, monthlyStartDay,
      spendingLimit, reserveType, reserveValue, watchedBankIds,
      countFees ? 1 : 0, countWithdrawals ? 1 : 0, reactionMode, status,
      paused, pausedDaysCount, morningBriefEnabled ? 1 : 0, morningBriefTime,
      dailyReportEnabled ? 1 : 0, dailyReportTime, skipEmptyDays ? 1 : 0,
      alertThresholds, reserveAlertEnabled ? 1 : 0, finalSummaryPayload,
      changeSeq, isDirty ? 1 : 0, created, now,
    ]);

    _notify(DatabaseTable.budgetPlans);
  }

  void pauseBudgetPlan(String id) {
    final now = DateTime.now().toIso8601String();
    _db.execute('''
      UPDATE local_budget_plans 
      SET status = 'paused', paused_at = ?, is_dirty = 1, updated_at = ? 
      WHERE id = ?;
    ''', [now, now, id]);
    _notify(DatabaseTable.budgetPlans);
  }

  void resumeBudgetPlan(String id) {
    final plan = getBudgetPlanById(id);
    if (plan == null) return;
    int extraPausedDays = 0;
    final pausedAtStr = plan['paused_at'] as String?;
    if (pausedAtStr != null) {
      final pausedDate = DateTime.tryParse(pausedAtStr);
      if (pausedDate != null) {
        extraPausedDays = DateTime.now().difference(pausedDate).inDays;
        if (extraPausedDays < 0) extraPausedDays = 0;
      }
    }
    final existingPausedDays = (plan['paused_days_count'] as num?)?.toInt() ?? 0;
    final totalPaused = existingPausedDays + extraPausedDays;

    final now = DateTime.now().toIso8601String();
    _db.execute('''
      UPDATE local_budget_plans 
      SET status = 'active', paused_at = NULL, paused_days_count = ?, is_dirty = 1, updated_at = ? 
      WHERE id = ?;
    ''', [totalPaused, now, id]);
    _notify(DatabaseTable.budgetPlans);
  }

  void deleteBudgetPlan(String id) {
    final now = DateTime.now().toIso8601String();
    _db.execute('''
      UPDATE local_budget_plans 
      SET deleted_at = ?, updated_at = ?, is_dirty = 1 
      WHERE id = ?;
    ''', [now, now, id]);
    _notify(DatabaseTable.budgetPlans);
  }

  void finishBudgetPlan(String id, String finalSummaryJson) {
    final now = DateTime.now().toIso8601String();
    _db.execute('''
      UPDATE local_budget_plans 
      SET status = 'finished', final_summary_payload = ?, updated_at = ?, is_dirty = 1 
      WHERE id = ?;
    ''', [finalSummaryJson, now, id]);
    _notify(DatabaseTable.budgetPlans);
  }

  // --- EXPECTED EXPENSES ---

  List<Map<String, dynamic>> getExpectedExpensesForPlan(String planId, {bool includeDeleted = false}) {
    final query = includeDeleted
        ? 'SELECT * FROM local_expected_expenses WHERE plan_id = ? ORDER BY due_date ASC;'
        : 'SELECT * FROM local_expected_expenses WHERE plan_id = ? AND deleted_at IS NULL ORDER BY due_date ASC;';
    final result = _db.select(query, [planId]);
    return result.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  void upsertExpectedExpense({
    required String id,
    required String planId,
    required String name,
    required double amount,
    DateTime? dueDate,
    String? linkedCategoryId,
    String status = 'expected',
    double paidAmount = 0.0,
    String? paidTxnId,
    bool reminderEnabled = true,
    int changeSeq = 0,
    bool isDirty = true,
    DateTime? createdAt,
  }) {
    final now = DateTime.now().toIso8601String();
    final created = (createdAt ?? DateTime.now()).toIso8601String();
    final due = dueDate?.toIso8601String();

    _db.execute('''
      INSERT INTO local_expected_expenses (
        id, plan_id, name, amount, due_date, linked_category_id,
        status, paid_amount, paid_txn_id, reminder_enabled,
        change_seq, is_dirty, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        name = excluded.name,
        amount = excluded.amount,
        due_date = excluded.due_date,
        linked_category_id = excluded.linked_category_id,
        status = excluded.status,
        paid_amount = excluded.paid_amount,
        paid_txn_id = excluded.paid_txn_id,
        reminder_enabled = excluded.reminder_enabled,
        change_seq = excluded.change_seq,
        is_dirty = excluded.is_dirty,
        updated_at = excluded.updated_at,
        deleted_at = NULL;
    ''', [
      id, planId, name, amount, due, linkedCategoryId,
      status, paidAmount, paidTxnId, reminderEnabled ? 1 : 0,
      changeSeq, isDirty ? 1 : 0, created, now,
    ]);
    _notify(DatabaseTable.expectedExpenses);
  }

  void markExpectedExpensePaid(String id, {double? paidAmount, String? paidTxnId}) {
    final now = DateTime.now().toIso8601String();
    _db.execute('''
      UPDATE local_expected_expenses 
      SET status = 'paid', 
          paid_amount = COALESCE(?, amount), 
          paid_txn_id = ?, 
          updated_at = ?, 
          is_dirty = 1 
      WHERE id = ?;
    ''', [paidAmount, paidTxnId, now, id]);
    _notify(DatabaseTable.expectedExpenses);
  }

  void markExpectedExpenseUnpaid(String id) {
    final now = DateTime.now().toIso8601String();
    _db.execute('''
      UPDATE local_expected_expenses 
      SET status = 'expected', paid_amount = 0.0, paid_txn_id = NULL, updated_at = ?, is_dirty = 1 
      WHERE id = ?;
    ''', [now, id]);
    _notify(DatabaseTable.expectedExpenses);
  }

  void deleteExpectedExpense(String id) {
    final now = DateTime.now().toIso8601String();
    _db.execute('''
      UPDATE local_expected_expenses 
      SET deleted_at = ?, updated_at = ?, is_dirty = 1 
      WHERE id = ?;
    ''', [now, now, id]);
    _notify(DatabaseTable.expectedExpenses);
  }

  // --- BUDGET PLANS & EXPECTED EXPENSES SYNC HELPERS ---

  List<Map<String, dynamic>> getDirtyBudgetPlans({int limit = 100}) {
    final result = _db.select('''
      SELECT * FROM local_budget_plans 
      WHERE is_dirty = 1 
      ORDER BY change_seq ASC 
      LIMIT ?;
    ''', [limit]);
    return result.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  void markBudgetPlansSynced(List<String> ids, int newChangeSeq) {
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    final now = DateTime.now().toIso8601String();
    _db.execute(
      'UPDATE local_budget_plans SET is_dirty = 0, change_seq = ?, updated_at = ? WHERE id IN ($placeholders);',
      [newChangeSeq, now, ...ids],
    );
    _notify(DatabaseTable.budgetPlans);
  }

  List<Map<String, dynamic>> getDirtyExpectedExpenses({int limit = 100}) {
    final result = _db.select('''
      SELECT * FROM local_expected_expenses 
      WHERE is_dirty = 1 
      ORDER BY change_seq ASC 
      LIMIT ?;
    ''', [limit]);
    return result.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  void markExpectedExpensesSynced(List<String> ids, int newChangeSeq) {
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(',');
    final now = DateTime.now().toIso8601String();
    _db.execute(
      'UPDATE local_expected_expenses SET is_dirty = 0, change_seq = ?, updated_at = ? WHERE id IN ($placeholders);',
      [newChangeSeq, now, ...ids],
    );
    _notify(DatabaseTable.expectedExpenses);
  }

  void applyRemoteBudgetPlan(Map<String, dynamic> data) {
    final id = data['id'] as String;
    final now = DateTime.now().toIso8601String();
    if (data['deleted_at'] != null) {
      _db.execute('''
        UPDATE local_budget_plans 
        SET deleted_at = ?, is_dirty = 0, updated_at = ? 
        WHERE id = ?;
      ''', [data['deleted_at'], now, id]);
    } else {
      final name = data['name'] as String? ?? 'My Spending Plan';
      final periodType = data['period_type'] as String? ?? 'monthly';
      final startDate = DateTime.tryParse(data['start_date']?.toString() ?? '') ?? DateTime.now();
      final endDate = DateTime.tryParse(data['end_date']?.toString() ?? '') ?? DateTime.now().add(const Duration(days: 30));
      final spendingLimit = (data['total_amount'] as num?)?.toDouble() ?? (data['spending_limit'] as num?)?.toDouble() ?? 0.0;
      final changeSeq = (data['change_seq'] as num?)?.toInt() ?? 0;
      final status = (data['active'] == false) ? 'archived' : (data['status'] as String? ?? 'active');

      upsertBudgetPlan(
        id: id,
        name: name,
        periodType: periodType,
        startDate: startDate,
        endDate: endDate,
        spendingLimit: spendingLimit,
        status: status,
        changeSeq: changeSeq,
        isDirty: false,
      );
    }
    _notify(DatabaseTable.budgetPlans);
  }

  void applyRemoteExpectedExpense(Map<String, dynamic> data) {
    final id = data['id'] as String;
    final now = DateTime.now().toIso8601String();
    if (data['deleted_at'] != null) {
      _db.execute('''
        UPDATE local_expected_expenses 
        SET deleted_at = ?, is_dirty = 0, updated_at = ? 
        WHERE id = ?;
      ''', [data['deleted_at'], now, id]);
    } else {
      final planId = data['plan_id'] as String;
      final name = data['name'] as String? ?? data['title'] as String? ?? 'Expense';
      final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
      final dueDate = data['due_date'] != null ? DateTime.tryParse(data['due_date'].toString()) : null;
      final changeSeq = (data['change_seq'] as num?)?.toInt() ?? 0;
      final paid = data['paid'] == true || data['status'] == 'paid';

      upsertExpectedExpense(
        id: id,
        planId: planId,
        name: name,
        amount: amount,
        dueDate: dueDate,
        status: paid ? 'paid' : 'expected',
        changeSeq: changeSeq,
        isDirty: false,
      );
    }
    _notify(DatabaseTable.expectedExpenses);
  }

  // --- TRANSACTION PLAN EXCLUSION ---

  void setTransactionPlanExclusion(String id, {required bool exclude, String? reason}) {
    final now = DateTime.now().toIso8601String();
    _db.execute('''
      UPDATE local_transactions 
      SET exclude_from_plan = ?, plan_exclusion_reason = ?, updated_at = ?, is_dirty = 1 
      WHERE id = ?;
    ''', [exclude ? 1 : 0, reason, now, id]);
    _notify(DatabaseTable.transactions);
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
    _db.execute('DELETE FROM local_debts;');
    _db.execute('DELETE FROM local_reimbursements;');
    _db.execute('DELETE FROM local_budget_plans;');
    _db.execute('DELETE FROM local_expected_expenses;');
    _notify(DatabaseTable.transactions);
    _notify(DatabaseTable.accounts);
    _notify(DatabaseTable.categories);
    _notify(DatabaseTable.limits);
    _notify(DatabaseTable.savingPlans);
    _notify(DatabaseTable.debts);
    _notify(DatabaseTable.reimbursements);
    _notify(DatabaseTable.budgetPlans);
    _notify(DatabaseTable.expectedExpenses);
  }

  void close() {
    _changeController.close();
    _db.dispose();
  }
}

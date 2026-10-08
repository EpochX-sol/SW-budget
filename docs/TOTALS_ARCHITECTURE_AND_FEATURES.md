# Comprehensive Architectural & Feature Documentation: Totals

This document provides an exhaustive, feature-by-feature architectural analysis of the **[Totals](https://github.com/detached-space/totals.git)** personal finance Android application (version 1.7), detailing both **what each feature does** and **the exact technical implementation** behind it.

---

## 1. Executive Summary & Design Philosophy

`Totals` is an offline-first, privacy-centric personal finance manager tailored for the Ethiopian banking ecosystem (Commercial Bank of Ethiopia, Telebirr, Bank of Abyssinia, Dashen Bank, Zemen Bank, etc.).

### Key Architectural Pillars:
1. **On-Device Execution**: Transaction parsing, ledger calculations, database storage, and PDF rendering occur 100% locally on the Android device.
2. **Zero Mandatory Cloud**: No user accounts, passwords, or authentication servers.
3. **Hardware & OS Integration**: Direct integration with Android Telephony content providers, SMS broadcast receivers, app-icon shortcuts, and home screen widgets.
4. **Relay-Only Networking**: Network features (shared expenses, backups) use end-to-end encryption (E2EE) where intermediate servers only see encrypted blobs.

---

## 2. Technology Stack & Key Dependencies

| Layer | Technology / Package | Purpose |
| :--- | :--- | :--- |
| **Framework** | Flutter (Dart 3.x) | Cross-platform UI runtime |
| **Local Database** | `sqflite: ^2.3.3+1` | Embedded SQLite relational database on device |
| **State Management** | `provider: ^6.1.2` | Dependency injection & reactive UI state |
| **SMS Ingestion** | `another_telephony` | Forked plugin for `content://sms/inbox` queries & incoming broadcast interception |
| **Cryptography** | `cryptography: ^2.7.0` | AES-256-GCM, Ed25519, X25519 key exchange |
| **Secure Storage** | `flutter_secure_storage: ^9.2.2` | Storing recovery keys & Telegram bot tokens in Android Keystore |
| **Background Work** | `workmanager: ^0.9.0+3` | Scheduled periodic backups and sync tasks |
| **Local Server** | `shelf: ^1.4.1`, `shelf_router` | Embedded HTTP server for local Wi-Fi web dashboard |
| **Widgets** | `home_widget: ^0.9.0` | Native Android AppWidget provider communication |
| **PDF Generation** | `pdf: ^3.12.0` | Client-side vector PDF generation for bank statements |
| **Mapping** | `google_maps_flutter`, `geolocator` | Transaction location capture and spending heatmap |
| **Notifications** | `flutter_local_notifications` | Budget alerts, transaction toast notifications |

---

## 3. Exhaustive Feature-by-Feature Breakdown

```
┌────────────────────────────────────────────────────────────────────────┐
│                        TOTALS FEATURE TOPOLOGY                         │
├────────────────────────────────┬───────────────────────────────────────┤
│ Core Financial Processing      │ Advanced Money Tools                  │
│  ├── 1. SMS Parsing Engine     │  ├── 8. Bank Statement PDF Generator  │
│  ├── 2. Multi-Account Matching │  ├── 9. Spending Map & Gazetteer      │
│  ├── 3. Account Reparse Engine │  ├── 10. E2EE Shared Expenses         │
│  ├── 4. Balance Reconciliation │  ├── 11. Telegram Encrypted Backup    │
│  ├── 5. Budget & Alerts Engine │  ├── 12. Outbound Data Sync Webhooks  │
│  ├── 6. Reimbursements Linking │  ├── 13. Local Wi-Fi Web Dashboard    │
│  ├── 7. Loans & Debts Manager  │  ├── 14. Payment Receipt Verification │
└────────────────────────────────┴───────────────────────────────────────┘
```

---

### Feature 1: Automated SMS Parsing & Bank Ingestion Engine

#### What it does:
Automatically discovers, reads, normalizes, and extracts financial transactions from bank SMS messages without manual data entry.

#### How it is implemented:
- **Files**: `lib/services/sms_service.dart`, `lib/sms_handler/telephony.dart`, `lib/services/fallback_sms_parser.dart`, `lib/services/sms_config_service.dart`
- **Runtime Flow**:
  1. **Permission Guard**: `SmsPermissionPrompt.ensureGranted(context)` checks `Permission.sms.status`. If denied, it presents a native disclosure dialog explaining bank tracking and calls `Permission.sms.request()`.
  2. **Historical Ingestion**: Calls `_telephony.getInboxSms()` querying Android's `Telephony.Sms.Inbox.CONTENT_URI` with projection `[ID, ADDRESS, BODY, DATE]`.
  3. **Live Listening**:
     ```dart
     _telephony.listenIncomingSms(
       onNewMessage: _handleForegroundMessage,
       onBackgroundMessage: onBackgroundMessage, // Top-level entry-point isolate
     );
     ```
  4. **Bank Matching**: `BankSenderMatcher` matches sender addresses (`CBE`, `127`, `Telebirr`, `BoA`, `Dashen`) against registered bank definitions.
  5. **Regex Evaluation**: `PatternParser` runs regex patterns loaded from local database (which syncs from remote `sms_patterns.json` on app start).
  6. **Heuristic Fallback**: If regex fails, `FallbackSmsParser` executes rule-based token extraction looking for keywords (`debited`, `credited`, `ETB`, `transferred`, dates, balances).
  7. **Deduplication**: `TransactionDuplicateDetector` calculates deterministic fingerprints (`address + timestamp + amount + reference`) to prevent duplicate records.

---

### Feature 2: Multi-Bank & Multi-Account Ownership System

#### What it does:
Allows users to have multiple bank accounts at the same bank (e.g. two CBE savings accounts and one CBE current account), automatically routing SMS transactions to the correct account based on partial account numbers.

#### How it is implemented:
- **Files**: `lib/services/account_ownership_service.dart`, `lib/services/account_registration_service.dart`, `lib/utils/account_identity.dart`
- **Implementation Mechanism**:
  - Banks often mask account numbers in SMS (e.g. `1****4177` or `1*22`).
  - `AccountOwnershipService` compares masked digits (`suffix`, `prefix`, `star count`) against the user's stored full account numbers.
  - **Unmatched Isolation**: If an SMS cannot be unambiguously mapped to a single account, it is placed under an **"Other transactions"** bucket instead of guessing.
  - Users can manually reassign transactions from "Other transactions" to a specific account in bulk.
  - Each account can be set as:
    - *Active* (included in total balance)
    - *Dormant* (frozen, excluded from main balance cards)
    - *Default* account for quick entry.

---

### Feature 3: Historical Account Reparsing Engine

#### What it does:
Allows the user to re-evaluate their entire past SMS history when bank regex patterns are updated, fixing old parsing bugs, correcting debit/credit directions, and importing previously missed transactions.

#### How it is implemented:
- **Files**: `lib/services/account_transaction_reparse_service.dart`, `lib/_redesign/screens/account_reparse_result_page.dart`
- **Implementation Mechanism**:
  - Accepts targets: a single account, all accounts, or the "Other transactions" bucket.
  - Options selectable by user:
    - `refreshFields`: re-extract reference, counterparty, balance from original SMS text.
    - `importMissed`: scan inbox for messages that failed earlier.
    - `applyAutoCategorization`: re-run category rules across history.
    - `repairDirections`: repair credit/debit inversions from older app versions.
  - Runs in chunks with a progress bar and outputs a detailed scorecard (`imported`, `updated`, `duplicatesRemoved`, `repaired`).

---

### Feature 4: Money Flow & Balance Mismatch Ledger

#### What it does:
Reconciles transaction arithmetic against the bank's reported "Available Balance" to detect untracked transactions, ATM fees, or SMS delivery gaps.

#### How it is implemented:
- **Files**: `lib/services/owned_account_transfer_service.dart`, `lib/models/account.dart`
- **Implementation Mechanism**:
  - **Money Flow Categorization**: Separates transactions into 6 buckets:
    1. External Income (money from other people)
    2. Internal Transfer In (moved from another owned account)
    3. External Expense (money spent externally)
    4. Internal Transfer Out (moved to another owned account)
    5. Bank Fees & VAT
    6. Unreconciled Balance Adjustments
  - **Balance Mismatch Ledger**: Whenever `previousBalance - amount != reportedBalance`, an entry is recorded in the mismatch ledger. This highlights hidden bank service charges or missed transactions.

---

### Feature 5: Category Budgets & Real-time Overspending Alerts

#### What it does:
Allows setting monthly budget envelopes per category (e.g. Food: ETB 6,000, Fuel: ETB 3,000) and triggers instant push notifications the moment an SMS transaction approaches or exceeds the budget.

#### How it is implemented:
- **Files**: `lib/services/budget_service.dart`, `lib/services/budget_alert_service.dart`, `lib/widgets/budget/budget_alert_banner.dart`
- **Implementation Mechanism**:
  - Stored in SQLite table `budgets` with `alertThreshold` (default: 80%).
  - In `sms_service.dart`, after saving any new expense transaction:
    ```dart
    await BudgetAlertService().checkAndNotifyBudgetAlerts();
    ```
  - `checkBudgetAlerts()` evaluates current month category spend:
    - If `spent >= limit * 0.80` and not exceeded: Triggers **"Budget Warning"** (`Food budget is 85% used`).
    - If `spent >= limit`: Triggers **"Budget Exceeded"** (`Food budget exceeded by ETB 450.00`).
  - Uses `SharedPreferences` flags (`budget_alert_sent:$budgetId:$type:$periodStart`) to deduplicate alerts and prevent spamming.

---

### Feature 6: Reimbursements Tracking (Net Cost Accounting)

#### What it does:
Allows incoming money received as a refund or repayment (e.g. a friend pays back their share of dinner) to be linked to the original expense. This reduces the recorded expense rather than artificially inflating total income.

#### How it is implemented:
- **Files**: `lib/models/transaction.dart`, `lib/services/transaction_service.dart`
- **Implementation Mechanism**:
  - Stored in a join table `reimbursement_links` mapping `income_transaction_id` -> `expense_transaction_id` with `allocated_amount`.
  - Supports 1-to-many (one reimbursement split across 3 expenses) and many-to-1 (multiple partial repayments for one large expense).
  - Net spending calculations:
    $$\text{Net Spend} = \text{Original Expense} - \sum \text{Allocated Reimbursements}$$
  - The main balance reflects real cashflow, while budget envelopes and spending charts reflect the true net cost.

---

### Feature 7: Loans & Debts Management

#### What it does:
Tracks personal loans (money you lent to someone) and debts (money you borrowed), linking repayments directly to bank transactions or cash entries.

#### How it is implemented:
- **Files**: `lib/_redesign/screens/loans_page.dart`, `lib/repositories/debt_repository.dart`
- **Implementation Mechanism**:
  - Maintains a Directory of People with net balance calculations:
    $$\text{Net Balance} = \text{Total Lent} - \text{Total Borrowed}$$
  - Links bank SMS transactions to loan repayments.
  - Supports status lifecycles: `Active`, `Partially Settled`, `Fully Settled`, and `Forgiven`.
  - Infinite scroll timeline for loan history with search and filter capabilities.

---

### Feature 8: On-Device Bank Statement PDF Generator

#### What it does:
Generates a formal bank statement PDF directly on the phone without sending any data to a remote server.

#### How it is implemented:
- **Files**: `lib/services/bank_statement_pdf_service.dart`, `lib/services/bank_statement_description_service.dart`
- **Implementation Mechanism**:
  - Built using `package:pdf/widgets.dart`.
  - User selects date range (`All Time`, `This Month`, `Custom Range`) and enters Account Holder Name.
  - Queries local database for transactions, ordered chronologically.
  - Computes opening balance, closing balance, total debits, total credits, and computes running balances line by line.
  - Formats into a printable PDF document with bank header branding, summary box, and itemized table.
  - Uses `share_plus` and `open_filex` to save or export the generated PDF file.

---

### Feature 9: Spending Map & Offline Place Gazetteer

#### What it does:
Captures geographical location when transactions occur and displays a map heatmap of where money was spent.

#### How it is implemented:
- **Files**: `lib/services/transaction_location_capture_service.dart`, `lib/services/offline_place_gazetteer.dart`, `lib/_redesign/screens/spending_map_page.dart`
- **Implementation Mechanism**:
  - Uses `geolocator` to capture GPS coordinates at the time of transaction.
  - `OfflinePlaceGazetteer`: An embedded, offline spatial lookup table containing sub-cities, neighborhoods, and commercial centers in Addis Ababa and major Ethiopian cities.
  - Visualized on a custom map using `google_maps_flutter` with marker clustering and spending summaries per district.

---

### Feature 10: End-to-End Encrypted (E2EE) Shared Expenses

#### What it does:
Enables splitting group expenses (e.g., trips, shared rent, dinner) with friends in end-to-end encrypted groups.

#### How it is implemented:
- **Files**: `lib/services/shared_expense_crypto_service.dart`, `lib/services/totals_engine_client.dart`, `lib/services/shared_expense_vault.dart`
- **Cryptographic Architecture**:
  - Every device generates an **X25519** keypair on first run.
  - Group creation establishes a 256-bit AES group symmetric key.
  - All shared payloads (expense description, amount, split fractions, settlement status) are encrypted on-device before leaving the phone.
  - **Totals Engine Relay**: A lightweight cloud relay server (`totals_engine_client.dart`) accepts and stores encrypted ciphertext blobs until recipient devices fetch and acknowledge them.
  - Intermediate servers cannot inspect members, amounts, or descriptions.

---

### Feature 11: Telegram Encrypted Cloud Backup

#### What it does:
Provides automated, scheduled backups stored in a private Telegram bot chat owned and controlled by the user.

#### How it is implemented:
- **Files**: `lib/services/telegram_backup/telegram_backup_service.dart`, `lib/services/telegram_backup/telegram_backup_crypto.dart`, `lib/services/telegram_backup/telegram_bot_api.dart`
- **Implementation Mechanism**:
  1. User creates their own private bot via `@BotFather` and pastes the bot HTTP token.
  2. Totals dumps database records (accounts, transactions, categories, budgets, SMS sources) into an encrypted JSON payload.
  3. Encryption uses **AES-256-GCM** with a locally generated 256-bit key.
  4. The recovery key is stored in `FlutterSecureStorage` (Android Keystore) and never transmitted.
  5. The encrypted archive is posted directly to Telegram Bot API (`https://api.telegram.org/bot<TOKEN>/sendDocument`).
  6. `Workmanager` handles automated daily/weekly background execution.

---

### Feature 12: Outbound Data Sync Webhook Engine

#### What it does:
Allows power users and developers to stream financial records to their own private self-hosted servers or webhooks.

#### How it is implemented:
- **Files**: `lib/services/data_sync/sync_service.dart`, `lib/services/data_sync/data_sync_repository.dart`
- **Implementation Mechanism**:
  - User configures custom URL endpoint (e.g. `https://my-nas.lan/api/transactions`) and authentication (Bearer token, Basic Auth, or Custom Header).
  - `SyncEnqueuer` intercepts local database changes and enqueues outbound JSON payloads into a local queue table.
  - `OutboundHttpClient` delivers payloads with exponential backoff retry.
  - Strictly **one-way export**: Totals never reads commands from remote webhooks.

---

### Feature 13: Local Wi-Fi Web Dashboard Server

#### What it does:
Runs an embedded HTTP server directly on the Android phone so users can view and manage their budget from a computer browser on the same Wi-Fi network.

#### How it is implemented:
- **Files**: `lib/local_server/server_service.dart`, `lib/local_server/handlers/`
- **Implementation Mechanism**:
  - Uses `shelf` and `shelf_router` to bind a server on `0.0.0.0:8080`.
  - Discovers local network IP (e.g., `192.168.1.15`).
  - Serves:
    - Embedded single-page application (SPA) static web assets.
    - REST API endpoints: `/api/v1/accounts`, `/api/v1/transactions`, `/api/v1/budgets`, `/api/v1/analytics`.
  - When the user toggles the server off in settings, the socket closes immediately.

---

### Feature 14: Payment & Receipt OCR Verification

#### What it does:
Verifies transaction slips and mobile banking receipt screenshots (CBE Birr, Telebirr, BoA slips) to confirm payment validity.

#### How it is implemented:
- **Files**: `lib/screens/verify_payments_page.dart`
- **Implementation Mechanism**:
  - Captures receipt image via camera or file picker (`image_picker`).
  - Posts image to `sms-parsing-visualizer.vercel.app/api/verify-image`.
  - Returns extracted transaction ID, payer, payee, timestamp, and amount to cross-reference against bank databases.

---

### Feature 15: Android Home Screen Widgets

#### What it does:
Displays real-time financial summaries on the Android home screen without opening the app.

#### How it is implemented:
- **Files**: `lib/services/widget_service.dart`, `android/app/src/main/res/layout/widget_expense_layout.xml`
- **Implementation Mechanism**:
  - Uses `home_widget` plugin to interface with Android's `AppWidgetProvider`.
  - When transactions are parsed or balances change, `WidgetDataProvider` writes JSON summaries into Android `SharedPreferences`.
  - Calls `HomeWidget.updateWidget(name: 'ExpenseWidgetProvider')` to trigger native layout re-render.

---

### Feature 16: Android App-Icon Shortcuts

#### What it does:
Long-pressing the app icon on Android reveals 4 instant actions:
1. **Add Expense**
2. **Add Income**
3. **Quick Accounts**
4. **Verify Payments**

#### How it is implemented:
- **Files**: `android/app/src/main/res/xml/shortcuts.xml`, `lib/main.dart`
- **Implementation Mechanism**:
  - Declared statically in Android manifest metadata: `<meta-data android:name="android.app.shortcuts" android:resource="@xml/shortcuts" />`.
  - Uses intent extras (`shortcut_action: add_expense`).
  - Flutter app handles incoming intent route in `main.dart` and pushes the respective bottom sheet or screen immediately.

---

### Feature 17: Account Hub & Quick Access Sharing

#### What it does:
Provides a fast-access card catalog of bank account numbers (both user's own accounts and frequent contacts) with 1-tap copy and QR code sharing.

#### How it is implemented:
- **Files**: `lib/widgets/account_detail.dart`, `lib/widgets/banks_summary_list.dart`
- **Implementation Mechanism**:
  - Stored in `quick_accounts` table.
  - Generates QR codes via `pretty_qr_code` encoding bank account details.
  - Integrated with Android clipboard for instant copy to paste into banking apps.

---

### Feature 18: Security, App Lock & Biometrics

#### What it does:
Protects financial records with fingerprint/face biometric unlock and session timeouts.

#### How it is implemented:
- **Files**: `lib/screens/lock_screen.dart`, `lib/auth-service.dart`
- **Implementation Mechanism**:
  - Uses `local_auth` plugin for biometric prompt (`authenticate(localizedReason: ...)`).
  - Listens to `WidgetsBindingObserver.didChangeAppLifecycleState`.
  - If app moves to background for longer than the configured timeout (e.g. 1 minute), it displays the blocking `LockScreen` upon resume.

---

### Feature 19: Privacy & Runtime Permission Management

#### What it does:
Educates users on why SMS permission is needed, handles runtime grants, and guides users through OEM battery optimization exemptions.

#### How it is implemented:
- **Files**: `lib/widgets/sms_permission_privacy_dialog.dart`, `lib/_redesign/screens/onboarding_page.dart`
- **Implementation Mechanism**:
  - Clear multi-step onboarding explaining that data never leaves the phone.
  - Checks `Permission.sms.status` and `Permission.ignoreBatteryOptimizations.status`.
  - Guides users on aggressive OEM battery killers (Tecno, Infinix, Xiaomi/MIUI) to ensure background SMS broadcast receivers are not terminated by Android.

---

## 4. Key Takeaways & Opportunities for SW-budget

| Dimension | `Totals` Implementation | `SW-budget` Status & Next Step |
| :--- | :--- | :--- |
| **SMS Ingestion** | `another_telephony` ContentProvider + BroadcastReceiver | SW-budget has native Kotlin `MainActivity.kt` + `SmsBroadcastReceiver`, but was **missing the runtime permission request** (`Permission.sms.request()`) and UI sync trigger. |
| **Parsing Logic** | Regex bundle loaded from local SQLite table + fallback heuristics | SW-budget has clean, high-performance Dart `FinancialParser` with signed JSON bundles (CBE, BoA, Telebirr 100% verified). |
| **Budgets & Alerts** | Monthly category caps with 80% and 100% threshold notifications | SW-budget can surpass `Totals` by implementing the **Dynamic Daily Allowance Window & Positive/Negative Day Scorecard**. |
| **Multi-Device Sync** | E2EE Relays & Telegram Bot Backups | SW-budget already has a dedicated modern **FastAPI + PostgreSQL + Render** backend with cryptographic offline syncing. |

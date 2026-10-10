# SW-budget vs Totals: Feature Gap Analysis, Architecture & Modernization Roadmap

> **Specification & Implementation Plan for upgrading SW-budget with battle-tested architectures and features from Totals.**

---

## 1. Metadata
- **Status:** Proposed / Ready for Review
- **Author:** Samuel W. & Antigravity AI
- **Date:** 2026-10-10
- **Type:** Architectural Gap Analysis, Technical Roadmap & Feature Specification
- **Related Documents:**
  - [.agent/docs/design/2026-10-07-sw-budget-app-design.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/.agent/docs/design/2026-10-07-sw-budget-app-design.md)
  - [docs/TOTALS_ARCHITECTURE_AND_FEATURES.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/docs/TOTALS_ARCHITECTURE_AND_FEATURES.md)
  - [reference_repos/totals/README.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/reference_repos/totals/README.md)
- **Confidence:** High (99%) — Derived directly from comparative source-code audits of `reference_repos/totals` and `SW-budget/mobile`.

---

## 2. Summary
SW-budget was conceived with an ambitious vision (cloud sync, AI financial coach, double-checking balance chain). However, its core Android device integration and financial feature set remain sparse and brittle in comparison to **Totals** (v1.7), a mature, production-grade Flutter expense tracker built specifically for Ethiopia. 

Most critically, **SW-budget's SMS ingestion currently fails silently** on modern Android devices due to content resolver query bugs and the absence of a background Dart isolate. Furthermore, SW-budget lacks essential financial utilities that Totals provides: multi-account ownership routing, 7-bank coverage, over-the-air pattern updates, reimbursements, informal loans & debts tracking, on-device bank statement PDF generation, home screen widgets, and offline local web dashboards.

This document details:
1. The exact bugs causing SW-budget's current failure in SMS ingestion.
2. The architectural patterns to adopt from Totals.
3. The exhaustive feature inventory to copy.
4. An actionable, ordered implementation roadmap.

---

## 3. Problem & Diagnostic: Why SW-budget is Currently Failing

A rigorous code audit of `SW-budget/mobile` revealed why SMS reading and ingestion fails:

### 3.1 ContentResolver Query Syntax Crash on Android 11+ (API 30+)
- **Location:** [mobile/android/app/src/main/kotlin/com/swbudget/app/MainActivity.kt:141-172](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/mobile/android/app/src/main/kotlin/com/swbudget/app/MainActivity.kt#L141-L172)
- **The Code:**
  ```kotlin
  val sortOrder = "${Telephony.Sms.DATE} DESC LIMIT 500"
  contentResolver.query(uri, projection, selection, selectionArgs, sortOrder)
  ```
- **The Flaw:** On Android 11+ (API 30+), appending `LIMIT` into the `sortOrder` string of a `ContentResolver` query violates the Android content provider contract and throws an `IllegalArgumentException`.
- **The Consequence:** The exception is caught by a generic `catch (_: Exception) {}` and silently returns an empty list `[]`. Historical SMS scanning **never yields a single transaction**.

### 3.2 Missing Headless Background Dart Isolate
- **Location:** [mobile/android/app/src/main/kotlin/com/swbudget/app/SmsBroadcastReceiver.kt:61-75](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/mobile/android/app/src/main/kotlin/com/swbudget/app/SmsBroadcastReceiver.kt#L61-L75)
- **The Flaw:** When an SMS arrives while SW-budget is closed or killed by the OS, `SmsBroadcastReceiver` merely buffers the JSON payload into `SharedPreferences`. It **never initializes a Flutter/Dart engine**.
- **The Consequence:** Unless the user manually opens the app, transactions are never parsed, Drift database records are never created, balance-chains are never updated, and budget alerts never fire. If the OS reclaims memory or clears the app before it opens, the buffered messages are permanently lost.

### 3.3 Artificial 7-Day Ingestion Boundary & Narrow Whitelist
- **Location:** [mobile/lib/core/device/background_sync_coordinator.dart:51-53](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/mobile/lib/core/device/background_sync_coordinator.dart#L51-L53)
- **The Flaw:** The coordinator hardcodes:
  ```dart
  final since = now.subtract(const Duration(days: 7));
  final whitelistSenders = ['CBE', '127', 'Telebirr', 'BoA', 'Abyssinia'];
  ```
- **The Consequence:** During onboarding or daily usage, all transaction history older than 7 days is permanently ignored. Furthermore, common banking shortcodes (e.g., `889`, `CBEBirr`) and all other Ethiopian banks (Awash, Dashen, Nib, Amhara) are discarded.

### 3.4 Multi-Account Ambiguity & Ledger Corruption
- **The Flaw:** Ethiopian bank SMS messages only display masked account numbers (e.g., `1000****4122`). When a user has multiple accounts at the same bank (e.g., Personal and Business CBE accounts), SW-budget matches the first account it finds in SQLite.
- **The Consequence:** Debits and credits are attributed to the wrong account, breaking the balance-chain calculation and falsely triggering gap cards.

---

## 4. Goals & Non-Goals

### 4.1 Goals
- Fix SMS ingestion completely using Totals' proven `another_telephony` integration and headless background isolate (`@pragma('vm:entry-point') onBackgroundMessage`).
- Expand bank coverage from 3 to **7 Ethiopian institutions** (CBE, Telebirr, BoA, Awash Bank, Dashen Bank, Amhara Bank, Nib Bank).
- Adopt dynamic Over-The-Air (OTA) regex pattern updates with fallback heuristics.
- Implement Totals' high-value financial features:
  - Account Reparsing & Repair Wizard
  - Reimbursements Linking (preventing inflated income)
  - Loans & Debts Ledger (tracking money owed to/by people)
  - Bank Statement PDF Generator (on-device vector PDF)
  - Batch Multi-Select Transaction Categorization
  - Android Home Screen Widgets & App-Icon Shortcuts
  - Offline Wi-Fi Web Dashboard (`shelf`)
  - Optional Encrypted Telegram Backup

### 4.2 Non-Goals
- We are **not** discarding SW-budget's unique strengths: the **Fastify cloud sync**, the **pgvector AI Financial Coach**, and the **mathematical balance-chain verifier** will remain the core differentiators of SW-budget. Totals lacks AI coaching and multi-device cloud synchronization. We are fusing the best of both worlds.

---

## 5. Architectural Comparison: SW-budget vs. Totals

```
┌───────────────────────────────────┬───────────────────────────────────┐
│         TOTALS (v1.7)             │        SW-BUDGET (Current)        │
├───────────────────────────────────┼───────────────────────────────────┤
│ • Offline-only, zero mandatory    │ • Local-first with optional       │
│   cloud account.                  │   Fastify + Postgres sync.        │
│ • another_telephony + headless    │ • Custom Kotlin MethodChannel     │
│   isolate for background parsing. │   (failing silently on API 30+).  │
│ • 7 Ethiopian banks supported     │ • 3 banks supported (brittle).    │
│ • OTA Regex Pattern updates       │ • Static hardcoded JSON in assets │
│   + heuristic fallback parser.    │   (no OTA updates).               │
│ • Advanced Ledger:                │ • Basic Ledger:                   │
│   - Reimbursements                │   - Expense / Income only         │
│   - Loans & Debts (People)        │   - No reimbursement linking      │
│   - Internal transfers resolver   │   - No loan/debt tracking         │
│ • Rich Android Extensions:        │ • Basic App:                      │
│   - Home screen widgets           │   - No widgets                    │
│   - App-icon shortcuts            │   - No shortcuts                  │
│   - Statement PDF generator       │   - Incomplete export             │
│   - Local Wi-Fi web server        │   - No local web server           │
│ • No AI coaching / No LLM.        │ • AI Coach + pgvector tools.      │
└───────────────────────────────────┴───────────────────────────────────┘
```

---

## 6. What to Copy from Totals: Detailed Feature Inventory

### 6.1 Ingestion & Parsing Infrastructure
1. **Headless Background SMS Listener (`SmsService`)**
   - **Source:** [reference_repos/totals/app/lib/services/sms_service.dart](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/reference_repos/totals/app/lib/services/sms_service.dart)
   - **Mechanism:** Integrates `another_telephony` with a top-level `@pragma('vm:entry-point') onBackgroundMessage(SmsMessage message)` function. Boots a Dart isolate in the background to parse the SMS, insert it into the SQLite database, update home widgets, and post a local notification immediately when received.
2. **Multi-Bank Definition Registry (`BankConfigService`)**
   - **Source:** [reference_repos/totals/app/lib/services/bank_config_service.dart](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/reference_repos/totals/app/lib/services/bank_config_service.dart)
   - **Coverage:** Adds complete sender matching and regex templates for:
     - Commercial Bank of Ethiopia (CBE / CBE Birr / 889)
     - Telebirr (telebirr / 127)
     - Bank of Abyssinia (BOA / Abyssinia)
     - Awash Bank (`Awash`, `AwashBank`)
     - Dashen Bank (`Dashen`, `DashenBank`)
     - Amhara Bank (`AmharaBank`)
     - Nib Bank (`NibBank`)
3. **Over-The-Air Pattern Engine (`TotalsEngineClient`) & Heuristic Fallback (`FallbackSmsParser`)**
   - **Source:** `totals_engine_client.dart` & `fallback_sms_parser.dart`
   - **Mechanism:** Checks for new regex definitions from the server on startup. If a bank alters its SMS format before an update, `FallbackSmsParser` uses token heuristics (`debited`, `credited`, `ETB`, `balance`) to extract transaction data rather than failing completely.
4. **Account Ownership & Identity Matching (`AccountOwnershipService`)**
   - **Source:** `account_ownership_service.dart` & `account_identity.dart`
   - **Mechanism:** Resolves masked account numbers (`1000****4122`) against registered user accounts. If ambiguous, routes the transaction to an **"Other Transactions" quarantine bucket** so the user can assign it manually, preserving balance integrity.

---

### 6.2 Financial Ledger & Domain Capabilities
1. **Reimbursements Flow (`ReimbursementService`)**
   - **Source:** `totals-1.7-features.md` § Reimbursements
   - **Problem Solved:** When a user pays 1,200 ETB for group dining and friends transfer 800 ETB back, recording the 800 ETB as "Income" artificially inflates income and distorts budgeting math.
   - **Solution:** Links the 800 ETB credit directly to the 1,200 ETB debit. The net expense is adjusted to **400 ETB**, and total income remains clean.
2. **Loans & Debts Ledger (`LoanDebtService`)**
   - **Source:** `totals-1.7-features.md` § Loans & Debts
   - **Capability:** A full person-by-person debt management subsystem:
     - Tracks money lent to others vs. money borrowed from others.
     - Direct links between bank SMS transfers and loan repayments.
     - Tracks partial repayments, settled status, and forgiven debts.
3. **Self-Transfer Recognition (`OwnedAccountTransferService`)**
   - **Source:** `owned_account_transfer_service.dart` & `self_transfer_notification_resolver.dart`
   - **Capability:** Detects when money moves between a user's own accounts (e.g. ATM cash withdrawal or CBE-to-Telebirr transfer) and tags them as internal transfers so they are excluded from spending metrics and duplicate notifications are suppressed.
4. **Historical Account Reparsing Wizard (`AccountTransactionReparseService`)**
   - **Source:** `account_transaction_reparse_service.dart`
   - **Capability:** A guided wizard allowing users to reparse their inbox from any custom date, detect missing transactions, deduplicate records, repair inverted credit/debit directions, and apply auto-categorization rules.

---

### 6.3 Convenience, Security & Android Platform Integration
1. **On-Device Bank Statement PDF Generator (`BankStatementPdfService`)**
   - **Source:** `bank_statement_pdf_service.dart`
   - **Capability:** Generates formatted vector PDFs of account statements locally on the phone using `pdf: ^3.12.0`. Includes bank branding, account holder name, statement period, opening/closing balance, running balance, debit/credit totals, and reference numbers.
2. **Android Home Screen Widgets (`WidgetService`)**
   - **Source:** `widget_service.dart` & `widget_expense_layout.xml`
   - **Capability:** Native Android AppWidgets powered by `home_widget` showing live account balances and daily discretionary spend.
3. **Android App-Icon Shortcuts**
   - **Source:** Long-press shortcuts for:
     - `Add Expense`
     - `Add Income`
     - `Quick Accounts`
     - `Verify Payments`
4. **Account Hub & QR Code Sharing**
   - **Source:** `totals-1.7-features.md` § Account Hub
   - **Capability:** Store and copy bank accounts belonging to friends or vendors, and generate QR codes for one-tap payment sharing.
5. **Private Telegram Encrypted Backup (`telegram_backup`)**
   - **Source:** `telegram_backup/`
   - **Capability:** Client-side AES-256-GCM encrypted backup uploaded directly to a personal user-owned Telegram Bot, with on-device recovery keys.
6. **Local Wi-Fi Web Dashboard (`shelf`)**
   - **Source:** `lib/local_server/`
   - **Capability:** Runs an embedded HTTP server on Android port 8080 (`http://192.168.x.x:8080`), allowing users to inspect their ledger and export data from any desktop browser on the same Wi-Fi network.

---

## 7. Implementation Plan

```mermaid
graph TD
    subgraph Phase 1: Core Ingestion Repair
        A1["Adopt another_telephony plugin"] --> A2["Implement @pragma('vm:entry-point') onBackgroundMessage"]
        A2 --> A3["Fix ContentResolver projection in Android"]
        A3 --> A4["Remove 7-day restriction & expand whitelists"]
    end

    subgraph Phase 2: Bank Expansion & Reparsing
        B1["Add Awash, Dashen, Amhara, Nib regexes"] --> B2["Implement AccountOwnershipService & 'Other Txns'"]
        B2 --> B3["Port AccountTransactionReparseService (Reparse Wizard)"]
    end

    subgraph Phase 3: Core Ledger Enhancements
        C1["Implement Reimbursements linking in Drift DB"] --> C2["Build Loans & Debts (People Ledger)"]
        C2 --> C3["Internal Self-Transfer Resolver"]
    end

    subgraph Phase 4: Android System & Export Tools
        D1["Bank Statement PDF Generator"] --> D2["Android Home Screen Widgets"]
        D2 --> D3["App-Icon Shortcuts & Local WiFi Server"]
    end

    Phase 1 --> Phase 2 --> Phase 3 --> Phase 4
```

### Step 1: Fix Core SMS Ingestion (P0)
- **Files to touch:**
  - [mobile/pubspec.yaml](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/mobile/pubspec.yaml): Add `another_telephony: ^0.4.1` (or stable fork).
  - [mobile/lib/data/sms/sources/sms_transaction_source.dart](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/mobile/lib/data/sms/sources/sms_transaction_source.dart): Migrate from raw `MethodChannel` to `Telephony.instance`.
  - [mobile/lib/main.dart](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/mobile/lib/main.dart): Register top-level headless background entrypoint with `DartPluginRegistrant.ensureInitialized()`.
  - [mobile/lib/core/device/background_sync_coordinator.dart](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/mobile/lib/core/device/background_sync_coordinator.dart): Remove the 7-day cutoff and query full history during initial setup.

### Step 2: Bank Expansion & Reparse Wizard (P1)
- **Files to touch:**
  - `mobile/lib/data/parser/banks/`: Port bank pattern definitions from Totals (`Awash`, `Dashen`, `Amhara`, `Nib`).
  - `mobile/lib/data/parser/normalizer/fallback_sms_parser.dart`: Port heuristic token extractor from Totals.
  - `mobile/lib/domain/use_cases/account_transaction_reparse_service.dart`: Create reparse wizard to repair historical records.
  - `mobile/lib/domain/use_cases/account_ownership_service.dart`: Create multi-account matching with "Other transactions" isolation.

### Step 3: Financial Feature Upgrades (P1)
- **Files to touch:**
  - `mobile/lib/data/local/tables/reimbursements_table.dart`: Add `reimbursements` table linking credit transactions to parent debit transactions.
  - `mobile/lib/domain/use_cases/budget_math_service.dart`: Update `SafeToday` and spending calculations to subtract reimbursed amounts.
  - `mobile/lib/features/plan/loans_debts/`: Create the Loans & Debts UI and person-by-person ledger.

### Step 4: System Integration & Exports (P2)
- **Files to touch:**
  - `mobile/lib/core/services/bank_statement_pdf_service.dart`: Implement vector PDF export with `pdf: ^3.12.0`.
  - `mobile/android/app/src/main/res/layout/`: Add Android widget layout and configure `home_widget`.
  - `mobile/android/app/src/main/res/xml/shortcuts.xml`: Add app-icon quick action shortcuts.

---

## 8. Testing & Validation Strategy

1. **Native SMS Channel Validation:**
   - Execute historical query across an emulator populated with 1,000+ realistic Ethiopian SMS messages across all 7 banks.
   - Verify that queries complete without `IllegalArgumentException` on Android 12, 13, and 14.
2. **Background Headless Ingestion Validation:**
   - Send test SMS via `adb emu sms send` while the Flutter app process is terminated.
   - Assert that the transaction is parsed, written to SQLCipher SQLite, and triggers an OS notification within 2 seconds.
3. **Reimbursement Calculation Tests:**
   - Unit test `BudgetMathService`: ensure an expense of 1,000 ETB with a 600 ETB reimbursement computes net spend as 400 ETB and zero inflation to gross income.
4. **Reparsing Engine Tests:**
   - Run the reparse wizard against corrupt or duplicate mock transactions; verify duplicate removal and direction repair.

---

## 9. Decision Log
- **2026-10-10:** Document created following comparative analysis of `reference_repos/totals` and `SW-budget`. Decision made to adopt Totals' telephony ingestion architecture, multi-bank definitions, and financial ledger features (reimbursements, debts, reparsing, PDF statements) while maintaining SW-budget's Fastify cloud sync and AI coaching capabilities.

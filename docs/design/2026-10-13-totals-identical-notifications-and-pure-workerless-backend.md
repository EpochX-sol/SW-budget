# Design Document: Totals-Identical Notification Architecture & Pure Workerless/Redis-Free Backend

## 1. Metadata
- **Status:** Proposed (Awaiting User Approval)
- **Author:** Antigravity AI Agent
- **Date:** 2026-10-13
- **Type:** Architecture & Feature Upgrade / System Simplification
- **Related Links:**
  - Reference Codebase: `c:\Users\samue\OneDrive\Desktop\code\personal\SW-budget\reference_repos\totals`
  - Mobile Notification Service: `mobile/lib/core/notifications/local_notification_service.dart`
  - Backend Server & Jobs: `backend/src/server.ts`, `backend/src/jobs/`
- **Confidence Level:** High (Comprehensive inspection of `reference_repos/totals` completed across all notification services, channels, models, and workers)

---

## 2. Summary
This design specifies two tightly coupled architectural changes:
1. **Totals-Identical Client Notification System:** Completely replace SW-budget's experimental notification stub with an exact port and adaptation of Totals' complete on-device notification architecture (`reference_repos/totals/app/lib/services/notification_service.dart`, `budget_alert_service.dart`, `notification_scheduler.dart`, `notification_settings_service.dart`, and `notification_intent_bus.dart`). This includes identical notification channels (`transactions`, `budgets`, `spending_summaries`, `failed_parse_review`, `account_sync`, `loan_debt_reminders`), identical notification titles and bodies, actionable inline counterparty reply (`txname:`) and quick-category buttons (`tx:|cat:`), background action handlers (`notificationTapBackground`), periodic spending workers (`Workmanager`), persistent notification history (`notification_history_v1`), and local notification settings.
2. **Pure Workerless & Redis-Free Backend:** Eliminate all Redis infrastructure (`ioredis`), all queue workers (`BullMQ`), all background worker processes (`backend/src/jobs/*`), and all server-to-app push mechanisms (`firebase-admin` FCM). The backend becomes a lean, fast REST API operating directly against Neon PostgreSQL with zero cloud daemon dependencies.

---

## 3. Problem / Motivation
1. **Disparity with Totals Notification Experience:** Currently, SW-budget only possesses a basic `LocalNotificationService` with a single channel (`budget_alerts`) and placeholder logic. It lacks Totals' instant SMS transaction notifications with inline counterparty replies, quick category buttons, failed parse review cards, deduplicated budget threshold alerts, and periodic spending summaries.
2. **Unnecessary Backend Complexity:** The backend relies on Redis (`ioredis`) for idempotency caching and BullMQ for background workers (`aggregates.worker.ts`, `outbox.worker.ts`, `plan-notifications.worker.ts`, `plan-snapshots.worker.ts`, `scheduler.worker.ts`) and Firebase Cloud Messaging (`firebase-admin`). Because the client operates local-first on SQLite/Drift with on-device parsing and on-device notifications, background server workers and Redis create cloud failure points, cold-start delays, and configuration friction without delivering user value.

---

## 4. Goals
- Deliver the **exact same notification logic, events, channels, formatting, and actions** found in the reference Totals application.
- Implement actionable notifications:
  - Inline input reply on the transaction notification banner to type and save counterparty name.
  - Up to 2-3 quick categorization buttons on the transaction notification banner to categorize with a single tap without opening the app.
  - Failed parse review notification with "Yes" / "No" action buttons.
  - Budget limit warnings ("Budget Warning: X% used") and exceed alerts ("Budget Exceeded: exceeded by ETB Y") with period-based deduplication cooldowns.
  - Daily, weekly, and monthly spending summary notifications triggered by `Workmanager`.
  - Notification history storage and history screen (`RedesignNotificationsPage`).
  - Full local settings screen (`NotificationSettingsPage`) with toggles, time pickers, and test notification triggers.
- Remove 100% of Redis dependencies, 100% of BullMQ queues/workers, and 100% of Firebase Admin push notification delivery from the backend.
- Ensure the backend boots instantly with Neon PostgreSQL as its single source of truth.

---

## 5. Non-Goals
- Cloud push notifications: We will NOT send remote FCM push messages from the server to mobile. All alerts are generated locally on-device.
- External worker daemons: We will NOT run separate Celery/BullMQ/Redis processes.
- Third-party message brokers: No RabbitMQ, Kafka, or AWS SQS.

---

## 6. Proposed Design

### 6.1 Client Architecture: Totals-Identical Notification Engine

```
       +-------------------------------------------------------------+
       |                     Mobile Client (Flutter)                 |
       +-------------------------------------------------------------+
                                      |
         +----------------------------+----------------------------+
         |                                                         |
 [Incoming Bank SMS]                                       [Workmanager 15m]
         |                                                         |
 [IngestionPipeline]                                     [DailySpendingWorker]
         |                                                         |
         v                                                         v
 [Persist Transaction]                                    - Today Spending
         |                                                - Weekly Spending
         +------------------+                             - Monthly Spending
         |                  |                                      |
         v                  v                                      v
[NotificationService] [BudgetAlertService]                         |
  .showTransaction()   .checkAndNotify()                           |
         |                  |                                      |
         +------------------+--------------------------------------+
                            |
                            v
          +------------------------------------+
          |    FlutterLocalNotificationsPlugin |
          +------------------------------------+
                            |
   +------------------------+------------------------+
   |                        |                        |
[transactions]          [budgets]          [spending_summaries]
 - High Importance       - Default Imp.     - Daily/Weekly/Monthly
 - Inline Reply Input    - Approaching/     - Time-of-day gated
 - Quick Category Btns     Exceeded
   |                        |
   +------------------------+------------------------+
                            |
                            v
          +------------------------------------+
          |   Actions & User Interaction       |
          +------------------------------------+
           /                                  \
   [Foreground Action]                [Background Action]
  _onNotificationResponse            notificationTapBackground
           |                                  |
   - Counterparty saved               - Counterparty saved
   - Category assigned                - Category assigned
   - Dismiss notification             - Dismiss notification
```

#### 6.1.1 Notification Channels Specification (Identical to Totals)
| Channel ID | Name | Importance | Priority | Description / Behavior |
|---|---|---|---|---|
| `transactions` | Transactions | High | High | Alerts when SMS transaction is ingested. Contains title `Bank • Money In/Out`, formatted amount, counterparty or prompt, category badge, inline reply input, and up to 3 quick-category buttons. |
| `budgets` | Budget Alerts | Default | Default | Alerts when spending approaches (80%+) or exceeds (100%+) a budget envelope. Deduplicated per budget per period. |
| `spending_summaries` | Spending summaries | Default | Default | Periodic daily summary (default 20:00), weekly summary (Sunday), monthly summary (last day of month). |
| `failed_parse_review` | Failed parse review | High | High | When a bank SMS cannot be parsed: "Was this a transaction?" with `Yes` and `No` action buttons. |
| `account_sync` | Account sync | Low | Low | Ongoing progress notification during bulk historical account message sync. |
| `account_sync_complete` | Account sync results | Default | Default | Completion notification when historical sync finishes. |
| `loan_debt_reminders` | Loan and debt reminders | High | High | Scheduled morning notification on return date for loans/debts. |
| `data_sync` | Data Sync | Default / High | Default / High | Result / progress notification for syncing data to backend. |

#### 6.1.2 Transaction Notification Banner & Actions Structure
1. **Title:**
   - Format: `${bank.shortName} • ${type == 'CREDIT' ? 'Money In' : 'Money Out'}`
   - Fallback: `Totals • Money In` / `SW Budget • Money Out`
2. **Body:**
   - With counterparty & categorized: `+ETB 1,500.00 • Abebe Kebede • Categorized as Salary`
   - With counterparty, uncategorized: `-ETB 250.00 • Cafe Tomoca • Tap to categorize`
   - Missing counterparty: `-ETB 120.00 • Expand notification to add receiver`
3. **Interactive Actions:**
   - When missing counterparty:
     - Action 1: Inline text reply `add receiver` / `add sender` (actionId: `txname:${Uri.encodeComponent(reference)}`). User types name directly in notification shade; on submit, saved to DB and notification updates without opening app!
     - Actions 2 & 3: Top 2 user-configured quick categories (`tx:${ref}|cat:${catId}`).
   - When counterparty already present:
     - Actions 1, 2, 3: Top 3 user-configured quick categories (`tx:${ref}|cat:${catId}`). Tapping one assigns category, cancels notification, and notifies app.
4. **Stable ID & Self-Transfer Suppression:**
   - ID: `reference.hashCode & 0x7fffffff` (prevents duplicate spam if SMS is re-read).
   - If self-transfer between user accounts is detected, existing notification is dismissed and new notification is suppressed.

#### 6.1.3 Background Action Dispatcher
```dart
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  if (response.notificationResponseType != NotificationResponseType.selectedNotificationAction) return;
  final actionId = response.actionId;
  if (actionId == null) return;
  if (actionId.startsWith('txname:')) {
    unawaited(_handleCounterpartyInputFromBackground(actionId, response.input, response.id));
  } else if (actionId.contains('|cat:')) {
    unawaited(_handleQuickCategorizeFromBackground(actionId, response.id));
  } else if (actionId.startsWith('fp|')) {
    unawaited(_handleFailedParseReviewFromBackground(actionId, response.id));
  }
}
```

#### 6.1.4 Periodic Worker via Workmanager (`dailySpendingWorker`)
- Triggered periodically every 15 minutes by Android `Workmanager`.
- Checks user preference: `isDailySummaryEnabled()`, `getDailySummaryTime()`.
- If current time >= daily summary time and not already sent today:
  - Computes today's total spending from local SQLite.
  - Shows notification: `Today's spending: You've spent ETB X today.`
  - Sets `daily_summary_last_sent_epoch_ms` in `SharedPreferences`.
- Checks Sunday for weekly summary and last day of month for monthly summary.

#### 6.1.5 Notification Settings & History UI
- Port `NotificationSettingsPage` from Totals:
  - Toggles for Transaction Notifications, Budget Alerts, Failed Parse Reviews, Daily Summaries, Weekly Summaries, Monthly Summaries.
  - TimeOfDay picker for Daily Summary Time.
  - Multi-selector for Quick Categorize Income categories (up to 3) and Expense categories (up to 3).
  - Test notification buttons for each channel.
- Port `RedesignNotificationsPage` from Totals:
  - History list of sent notifications with channel chips, timestamp, body, and clear button.

---

### 6.2 Backend Architecture: Pure Workerless & Redis-Free REST API

```
   [Mobile / Client HTTP Request]
                 |
                 v
       +--------------------+
       | Fastify REST API   |
       +--------------------+
                 |
        (Direct Query / Tx)
                 |
                 v
       +--------------------+
       |  Neon PostgreSQL   |
       +--------------------+
```

1. **Delete `backend/src/jobs/` completely:**
   - Remove `redis.ts`
   - Remove `queues.ts`
   - Remove `workers/aggregates.worker.ts`
   - Remove `workers/outbox.worker.ts`
   - Remove `workers/plan-notifications.worker.ts`
   - Remove `workers/plan-snapshots.worker.ts`
   - Remove `workers/scheduler.worker.ts`
2. **Uninstall Packages:**
   - Remove `ioredis`, `bullmq`, `firebase-admin` from `backend/package.json`.
3. **Refactor `backend/src/server.ts`:**
   - Remove imports of `redisConnection`.
   - Remove Redis connection shutdown hooks.
4. **Refactor `backend/src/modules/sync/sync.service.ts`:**
   - Remove `safeRedisGet` and `safeRedisSetex`.
   - Idempotency is handled directly via PostgreSQL transactions and database unique constraints (`reference`, `id`).
   - Remove dispatching to BullMQ queue; calculations/aggregates update directly within PostgreSQL.
5. **Refactor `backend/src/modules/health/health.routes.ts`:**
   - Remove Redis ping; health endpoint checks PostgreSQL connection only.
6. **Purge Push Notifications from Backend:**
   - Delete Firebase initialization and multicast FCM push calls in `notification.service.ts`. Backend notification endpoint (if called) only records notifications in PostgreSQL table for in-app inbox reading.

---

## 7. Interface Changes

### 7.1 Mobile Notification Engine Interfaces
- `NotificationService.instance`:
  - `ensureInitialized(): Future<void>`
  - `showTransactionNotification({required Transaction transaction, required int? bankId, bool ignoreEnabledCheck = false, bool recordHistory = true}): Future<void>`
  - `dismissTransactionNotification(Transaction transaction, {bool removeFromHistory = false}): Future<void>`
  - `showFailedParseReviewNotification({required String reviewId, required String bankName, required String messageBody}): Future<bool>`
  - `showDailySpendingNotification({required double amount, int id = 9001}): Future<bool>`
  - `showWeeklySpendingNotification({required double amount, int id = 9003}): Future<bool>`
  - `showMonthlySpendingNotification({required double amount, int id = 9005}): Future<bool>`
  - `showBudgetAlertNotification({required int id, required String title, required String body}): Future<void>`
  - `getNotificationHistory(): Future<List<NotificationHistoryEntry>>`
  - `clearNotificationHistory(): Future<void>`
- `BudgetAlertService`:
  - `checkBudgetAlerts(): Future<List<BudgetAlert>>`
  - `sendBudgetAlertNotification(BudgetAlert alert): Future<void>`
  - `checkAndNotifyBudgetAlerts(): Future<void>`
  - `checkAndNotifyBudgetAlert(Budget budget): Future<void>`
- `NotificationScheduler`:
  - `syncSpendingSummarySchedule(): Future<void>`
- `NotificationSettingsService.instance`:
  - SharedPreferences accessors for all toggles, times, and quick-category IDs.

### 7.2 Backend REST Interface Changes
- **Health Check (`GET /api/v1/health`)**:
  - Response shape simplified:
    ```json
    {
      "status": "ok",
      "timestamp": "2026-10-13T04:00:00.000Z",
      "services": {
        "database": "up"
      }
    }
    ```
- **Sync Batch (`POST /api/v1/sync/batch`)**:
  - Unchanged request/response schema; operates purely in PostgreSQL transaction without Redis intermediary.

---

## 8. Data Model Changes
- **Mobile Local Storage (`SharedPreferences`)**:
  - Added keys:
    - `notifications_transaction_enabled` (bool)
    - `notifications_failed_parse_review_enabled` (bool)
    - `notifications_budget_enabled` (bool)
    - `notifications_daily_enabled` (bool)
    - `notifications_daily_hour` (int)
    - `notifications_daily_minute` (int)
    - `notifications_daily_last_sent_epoch_ms` (int)
    - `notifications_weekly_enabled` (bool)
    - `notifications_weekly_last_sent_epoch_ms` (int)
    - `notifications_monthly_enabled` (bool)
    - `notifications_monthly_last_sent_epoch_ms` (int)
    - `quick_categorize_income_ids` (List<String>)
    - `quick_categorize_expense_ids` (List<String>)
    - `notification_history_v1` (List<String> JSON)
    - `budget_alert_sent:$budgetId:$type:$periodStart` (bool)
- **Backend Database**:
  - Zero schema migrations needed. Outbox events table can remain dormant or be pruned; no new tables or columns required.

---

## 9. Alternatives Considered
1. **Retain Redis for Idempotency Caching:**
   - *Pros:* High throughput cache for millions of duplicate requests.
   - *Cons:* Overkill for personal budget app; introduces Redis connection failure and latency when Redis is unreachable or requires cloud hosting fees. PostgreSQL unique constraints already guarantee idempotency natively.
   - *Verdict:* Rejected in favor of pure workerless Neon PostgreSQL.
2. **Keep Server-side FCM Push Notifications:**
   - *Pros:* Allows backend to wake up phone when account changes remotely.
   - *Cons:* Totals does not use FCM for transactions or budgets; all financial data comes via SMS directly to the user's handset. FCM requires Firebase setup, Google Play services tokens, and cloud credentials.
   - *Verdict:* Rejected in accordance with user's instruction.

---

## 10. Impact & Risks
- **Background Execution Reliability on Android:** Android OEM battery optimizations (MIUI, Samsung OneUI) can delay `Workmanager` periodic execution by a few minutes. This is standard across all Android apps (including Totals) and mitigated by `Workmanager`'s `ExistingPeriodicWorkPolicy.replace`.
- **Notification Permission:** Android 13+ requires `POST_NOTIFICATIONS` runtime permission. `NotificationService.requestPermissionsIfNeeded()` handles runtime requesting seamlessly.
- **Backend Reliability:** Removing Redis eliminates the #1 cause of connection timeouts and server crashes during startup.

---

## 11. Implementation Plan
Each step is designed as an atomic, verifiable commit:

### Step 1: Clean Backend — Purge Redis, BullMQ, Workers & Firebase
1. Delete `backend/src/jobs/` completely.
2. Uninstall `ioredis`, `bullmq`, `firebase-admin` via `npm uninstall`.
3. Refactor `backend/src/server.ts` to remove Redis imports and teardowns.
4. Refactor `backend/src/modules/sync/sync.service.ts` to execute database transactions directly without Redis.
5. Refactor `backend/src/modules/health/health.routes.ts` to remove Redis checks.
6. Verify backend build with `npm run build` and test server boot.

### Step 2: Implement Totals Notification Core Services in Mobile
1. Create `mobile/lib/core/notifications/notification_service.dart` (faithful port of Totals' `NotificationService`).
2. Create `mobile/lib/core/notifications/notification_settings_service.dart`.
3. Create `mobile/lib/core/notifications/notification_intent_bus.dart`.
4. Create `mobile/lib/core/notifications/budget_alert_service.dart`.
5. Create `mobile/lib/core/notifications/notification_scheduler.dart`.
6. Create `mobile/lib/core/notifications/daily_spending_worker.dart`.

### Step 3: Wire Pipeline and Ingestion Events
1. In `mobile/lib/data/sms/ingestion_pipeline.dart`:
   - Upon successful transaction ingestion & database save, invoke `NotificationService.instance.showTransactionNotification`.
   - Invoke `BudgetAlertService.instance.checkAndNotifyBudgetAlerts()`.
   - Upon unparsed bank SMS, invoke `NotificationService.instance.showFailedParseReviewNotification`.
2. In `mobile/lib/main.dart`:
   - Initialize `NotificationService.instance.ensureInitialized()`.
   - Initialize `Workmanager().initialize(callbackDispatcher)`.
   - Sync spending summary schedule via `NotificationScheduler.syncSpendingSummarySchedule()`.

### Step 4: Add Notification Settings & History UI
1. Add `NotificationSettingsPage` accessible from More/Settings page.
2. Add `NotificationsHistoryPage` accessible from More page / App bar icon.
3. Wire intent handling (when notification is tapped, navigate to transaction detail/categorize).

### Step 5: Verification & Build
1. Run `flutter analyze` to ensure zero compilation or type errors.
2. Run automated tests.
3. Build final release APK (`flutter build apk --release`).

---

## 12. Testing Strategy
- **Unit Tests:**
  - Verify `BudgetAlertService` correctly identifies approaching and exceeded limits.
  - Verify deduplication keys prevent repeated notifications within the same budget period.
  - Verify `NotificationSettingsService` persistence and default values.
- **Integration Tests:**
  - Test test-notification triggers (`showTestTransactionNotification`, `showDailySpendingTestNotification`).
  - Test inline reply action parsing (`txname:<ref>`) and category action parsing (`tx:<ref>|cat:<id>`).
  - Test backend health and sync endpoints with zero Redis running.

---

## 13. Rollout / Migration Plan
- **Migration:**
  - `SharedPreferences` keys are created on first run with default values matching Totals.
  - Backend requires no data migration; existing tables in PostgreSQL remain intact.
- **Rollback Plan:**
  - Code changes are tracked in Git commits and can be reverted cleanly if needed.

---

## 14. Open Questions
- None. The Totals codebase provided exact reference implementations for all notification channels, actions, settings, and workers.

---

## 15. References
- `reference_repos/totals/app/lib/services/notification_service.dart`
- `reference_repos/totals/app/lib/services/budget_alert_service.dart`
- `reference_repos/totals/app/lib/services/notification_scheduler.dart`
- `reference_repos/totals/app/lib/services/notification_settings_service.dart`
- `reference_repos/totals/app/lib/background/daily_spending_worker.dart`
- `reference_repos/totals/app/lib/screens/notification_settings_page.dart`
- `reference_repos/totals/app/lib/_redesign/screens/notifications_page.dart`

---

## 16. Decision Log
- **2026-10-13 (Draft & Approval):** Initial draft created following detailed inspection of `reference_repos/totals`. Approved by user for immediate implementation.
- **2026-10-13 (Implementation Completed):**
  - Backend: Completely purged `backend/src/jobs/` (Redis connection, BullMQ queues, 5 workers). Removed `ioredis`, `bullmq`, `firebase-admin` packages. Refactored `server.ts`, `sync.service.ts`, `health.routes.ts`, `env.ts`, and `notification.service.ts` to operate purely against Neon PostgreSQL. Verified `npm run build` exits 0.
  - Mobile: Implemented Totals-identical notification engine:
    - Created `NotificationService` with dedicated channels: `transactions`, `budgets`, `spending_summaries`, `failed_parse_review`, `account_sync`, `loan_debt_reminders`, `data_sync`.
    - Added interactive inline reply input (`txname:<ref>`) to enter counterparty directly on the notification shade.
    - Added quick-categorize action buttons (`tx:<ref>|cat:<id>`) on notification banners.
    - Added `notificationTapBackground` background handler for inline replies and quick categorization.
    - Created `BudgetAlertService` with 80% and 100% threshold detection and deduplication.
    - Created `NotificationSettingsService` with local on-device preferences.
    - Created `NotificationScheduler` and `daily_spending_worker.dart` for 15-minute background spending summaries via `Workmanager`.
    - Wired `IngestionPipeline` to trigger notifications on unparsed SMS and parsed transactions.
    - Added `NotificationSettingsScreen` and `NotificationHistoryScreen` UI.
    - Verified `flutter analyze` with 0 errors. Verified `flutter build apk --release`.


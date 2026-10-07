# Milestone F3 Design: Ingestion Pipeline, Balance-Chain & Sync Engine

> **Part of SW-budget Mobile Architecture Series**  
> **Focus:** Dual transaction capture (SMS BroadcastReceiver + NotificationListenerService), mathematical Balance-Chain verification, Gap Detector, Review Inbox swipe interface, and Monotonic Sequence Sync (`change_seq`).

---

## 1. Metadata
- **Status:** Approved
- **Author:** Samuel W. & Antigravity AI
- **Date:** 2026-10-07
- **Type:** Core Domain & Ingestion Specification
- **Related Links:**
  - Master Design: [2026-10-07-sw-budget-app-design.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/.agent/docs/design/2026-10-07-sw-budget-app-design.md)
  - Backend Sync API: [api-documentation.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/.agent/docs/api-documentation.md#5-offline-sync-engine-monotonic-sequence)
- **Confidence Level:** High (99%)

---

## 2. Summary
Milestone F3 delivers the core transaction ingestion and accounting engine of SW-budget. It captures financial messages via native Android channels (SMS receiver and notification listener), runs the F1 parser, calculates mathematical balance-chain integrity (`prev_balance ± amount == current_balance`), surfaces missing transaction gaps, presents the Review Inbox for edge-case triage, and implements the bidirectional monotonic sequence sync engine (`POST /v1/sync/push` & `GET /v1/sync/pull`) in resumable 100-item chunks.

---

## 3. Problem / Motivation
1. **Uncertain Ingestion Feasibility:** Relying purely on SMS permissions risks Google Play rejection, while relying purely on notifications misses transactions if notifications were cleared. A dual-source pipeline is essential.
2. **Silent Ledger Drift:** If an unrecorded transaction occurs (e.g. physical ATM cash withdrawal or unreceived SMS), traditional apps show corrupted balance numbers without explanation.
3. **High-Volume Sync Congestion:** During first-time setup, scanning 1,000+ historical SMS messages over low-bandwidth Ethiopian cellular networks causes timeouts if pushed in a single monolithic payload.

---

## 4. Goals
- **Dual Ingestion Pipeline:** Abstracted behind `TransactionSource` contract with native Kotlin platform channel bridges.
- **Balance-Chain Verification:** Evaluate whether reported balances match expected arithmetic; mark `balance_chain_ok = true` or `gap_before_amount`.
- **Review Inbox UI:** Swipeable cards allowing users to classify unknown merchants, assign categories, and confirm gaps.
- **Monotonic Sync Protocol:** Chunked sync batches (100 items) pushing to `/v1/sync/push` and pulling from `/v1/sync/pull` with cursor persistence.

---

## 5. Non-Goals
- Budgeting envelope graphs and safe-to-spend widgets (Milestone F4).
- Conversational AI streaming chat (Milestone F5).

---

## 6. Proposed Design

### 6.1 Balance-Chain Mathematical Evaluation

```
                    Incoming Transaction (T_curr)
                                 │
                                 ▼
           Retrieve preceding transaction for account (T_prev)
                                 │
                 ┌───────────────┴───────────────┐
                 ▼                               ▼
       T_prev has balanceAfter        No preceding balance record
                 │                               │
                 ▼                               ▼
 Expected = Balance(T_prev) ± Amount(T_curr)  Set balanceChainOk = null
                 │
      ┌──────────┴──────────┐
      ▼                     ▼
|Expected - Balance| < 0.01  |Expected - Balance| >= 0.01 (Discrepancy)
      │                     │
      ▼                     ▼
balanceChainOk = true       balanceChainOk = false
                            gapBeforeAmount = |Expected - Balance|
                            needsReview = true
                            Render "Missing Transaction Gap" Card
```

---

## 7. Interface Changes & API Handshake

### 7.1 Backend Sync Contract Handshake
- **Push (`POST /v1/sync/push`)**:
  - Headers: `Authorization: Bearer <token>`, `Idempotency-Key: <uuid>`.
  - Body: `{ device_id, batch_index, total_batches, changes: [...] }`.
  - Max batch size: 100 items.
- **Pull (`GET /v1/sync/pull`)**:
  - Query: `cursor=<local_seq>&limit=100`.
  - Response: `{ cursor, has_more, changes: [...] }`.
- **Status (`GET /v1/sync/status`)**:
  - Query server sequence number to compute sync drift.

---

## 8. Data Model: Local Drift Tables

```dart
class LocalTransactions extends Table {
  TextColumn get id => text()();
  TextColumn get accountId => text()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get type => text()(); // income, expense, transfer
  RealColumn get amount => real()();
  RealColumn get balanceAfter => real().nullable()();
  TextColumn get counterparty => text().nullable()();
  TextColumn get reference => text().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get source => text()(); // sms, notification, manual
  RealColumn get parseConfidence => real().nullable()();
  TextColumn get dedupeKey => text()();
  BoolColumn get balanceChainOk => boolean().nullable()();
  RealColumn get gapBeforeAmount => real().nullable()();
  BoolColumn get needsReview => boolean().withDefault(const Constant(false))();
  IntColumn get changeSeq => integer().withDefault(const Constant(0))();
  BoolColumn get isDirty => boolean().withDefault(const Constant(false))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

---

## 9. Alternatives Considered

| Alternative | Pros | Cons | Decision |
|---|---|---|---|
| **1. Timestamp-Based Sync (`updated_at`)** | Simple query (`WHERE updated_at > last_time`). | Susceptible to device clock skew and network race conditions. | **Rejected:** Monotonic sequence cursor (`change_seq`) guarantees deterministic order. |
| **2. Monolithic Initial Push (All in one request)** | One HTTP call. | Fails on slow networks; exceeds 15MB request limits on large inboxes. | **Adopted:** Chunked batching (100 items per request). |

---

## 10. Impact & Risks
- **SMS Spam Flooding:** Telemarketing SMS from unknown senders.
  - *Mitigation:* Whitelist bank senders (`CBE`, `127`, `Telebirr`, `BoA`).
- **Network Drops Mid-Batch:** Interrupted upload during multi-batch push.
  - *Mitigation:* Idempotency keys per batch; atomic sequence progression.

---

## 11. Implementation Plan
- **F3.1:** Implement Kotlin platform channels for SMS and Notification capture.
- **F3.2:** Build `BalanceChainVerifier` and `GapDetector` domain services.
- **F3.3:** Build Activity List screen with date grouping and trust badges.
- **F3.4:** Build Review Inbox swipe cards and gap confirmation dialogs.
- **F3.5:** Build `SyncEngine` supporting 100-item chunked push and pull.

---

## 12. Testing Strategy
- **Synthetic Gap Tests:** Inject transactions with deliberate gaps (e.g. 500 ETB discrepancy); verify gap cards appear with exact missing sums.
- **Offline Sync Tests:** Create 250 local transactions in airplane mode; restore network; verify 3 consecutive chunked batches sync successfully.

---

## 13. Rollout & Rollback Plan
- Feature-flagged ingestion source: sideloaded builds use SMS source, Play Store builds fall back to Notification listener.
- Rollback: Sync is non-destructive (soft-deletes only); reverting client code preserves local SQLite database.

---

## 14. Open Questions
- None. Balance-chain tolerance is mathematically validated at 0.01 ETB, and the chunked sync protocol aligns 100% with backend `/v1/sync/push` and `/v1/sync/pull`.

---

## 15. References
- Master Architecture: `.agent/docs/design/2026-10-07-sw-budget-app-design.md`
- Backend Sync API: `.agent/docs/api-documentation.md#5-offline-sync-engine-monotonic-sequence`
- Milestone F1 Parser: `.agent/docs/design/mobile/2026-10-07-f1-sms-notification-parser.md`

---

## 16. Decision Log
- **2026-10-07 (Tolerance for Balance-Chain):** Established 0.01 ETB rounding threshold in `BalanceChainVerifier` to eliminate false-positive gap warnings caused by IEEE 754 floating-point operations.
- **2026-10-07 (Deduplication Granularity):** Dedupe keys prioritize bank transaction reference tokens (`cbe_<ref>`, `telebirr_<ref>`), falling back to a minute-truncated SHA-256 composite content hash to eliminate duplicates across simultaneous SMS and push notifications.
- **2026-10-07 (Resumable Chunking):** Hardcoded max sync payload batch size to 100 items with UUID `Idempotency-Key` headers to ensure survivability on intermittent 2G/3G connections in Ethiopia.

---

## 17. Change Log
- **2026-10-07:** Completed implementation of Milestone F3:
  - Domain layer: `TransactionEntity`, `BalanceChainVerifier` (continuous arithmetic + gap detection), `DedupeEngine` (reference normalization + composite hash).
  - Native Ingestion: `RawFinancialMessage`, `TransactionSource`, `SmsTransactionSource`, `NotificationListenerSource`, Android Kotlin bridges (`SmsBroadcastReceiver.kt`, `FinancialNotificationListener.kt`, `MainActivity.kt`), and `AndroidManifest.xml` permissions.
  - Ingestion Pipeline: `IngestionPipeline` coordinating stream ingestion, parser execution, deduplication checks, auto-account provisioning, and balance-chain math.
  - Local Database: Added `balance_chain_ok`, `gap_before_amount`, `needs_review`, `is_dirty`, and `note` to `local_transactions` table and queries.
  - Monotonic Sync Engine: `SyncEngine` and `SyncNotifier` with 100-item chunked push (`POST /v1/sync/push`), cursor pagination (`GET /v1/sync/pull`), and local cursor persistence.
  - UI & Review: `ActivityScreen` with real-time reactive streams, filter chips, trust badges, gap warning cards, and `ReviewInboxScreen` for edge-case triage.
  - Unit Tests: `balance_chain_test.dart` and `sync_engine_test.dart`.


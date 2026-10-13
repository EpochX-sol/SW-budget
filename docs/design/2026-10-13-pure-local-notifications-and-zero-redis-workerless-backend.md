# Design Doc: Pure Local Notifications (Totals Parity) & Zero-Redis Workerless Backend

## 1. Metadata
- **Status**: Proposed (Awaiting User Approval)
- **Author**: Antigravity Assistant & Samuel
- **Date**: 2026-10-13
- **Type**: Architectural Simplification & Notification Engine Alignment
- **Related Links**:
  - `docs/TOTALS_ARCHITECTURE_AND_FEATURES.md`
  - `mobile/lib/core/notifications/local_notification_service.dart`
  - `mobile/lib/data/sms/ingestion_pipeline.dart`
  - `backend/src/server.ts`
  - `backend/src/jobs/`
  - `backend/src/modules/notifications/`
- **Confidence**: High (Aligns 100% with Totals app reference architecture and completely eliminates cloud infrastructure bottlenecks).

---

## 2. Summary
The user requested removing all Redis and background workers from the backend, removing server-to-app push notifications (FCM), and aligning the notification system to match the exact on-device architecture of the **Totals app**.

This design transitions SW-Budget into a clean, modern **offline-first local architecture**:
1. **Frontend (Totals Parity)**: All notifications (transaction receipts, 80%/100% budget threshold alerts, 07:30 morning allowances, 21:00 evening summaries, and reserve alerts) are evaluated and dispatched **100% locally on-device** using `flutter_local_notifications` immediately upon SMS arrival, with zero server dependency.
2. **Backend (Zero-Redis, Workerless)**: Completely eliminate `ioredis`, `bullmq`, `firebase-admin`, background queues, and worker daemons from the backend. The backend becomes a lean, ultra-fast stateless API focused exclusively on Authentication, PostgreSQL Sync/Ledger, AI Financial Coach, and OTA Template distribution.

---

## 3. Problem / Motivation
1. **Server-Side Push Fragility**: Sending financial alerts via cloud push notifications (Server -> FCM -> Phone) introduces network latency, requires Firebase service account credentials, fails when the phone is offline, and relies on background workers running on cloud servers.
2. **Totals App Precedent**: The reference app **Totals** operates entirely on-device. When an SMS arrives from Telebirr, CBE, or BoA, the phone parses it, updates SQLite, and fires an instant local notification in **< 50ms**. There is zero need for server notification relays.
3. **Operational Overhead of Redis & Workers**: Running BullMQ workers requires a separate Redis instance (`ioredis`), consumes memory and CPU, causes reconnection errors when Redis is absent, and complicates hosting on serverless/container platforms like Render.
4. **Redundant Duplicate Layers**: The codebase currently had both an on-device notification service (`local_notification_service.dart`) AND a backend notification worker (`plan-notifications.worker.ts`), creating split logic and confusion.

---

## 4. Goals
1. **Complete Removal of Redis & BullMQ**: Remove `ioredis`, `bullmq`, all worker scripts, and task queues from the backend codebase and dependencies.
2. **Complete Removal of Server Push Notifications**: Remove `firebase-admin`, FCM token registrations, and server-side notification push dispatchers.
3. **Full Totals App Notification Parity**: Wire `IngestionPipeline` directly to `LocalNotificationService` to deliver:
   - **Instant Transaction Receipt Notification**: On SMS receipt (amount, provider, type, updated balance).
   - **80% & 100% Budget Alerts**: Evaluated immediately in local SQLite against category envelopes with daily deduplication.
   - **Morning Brief (07:30 AM)**: Daily allowance and spending target.
   - **Evening Recap (21:00 PM)**: Summary of day's spending vs. target.
   - **Emergency Reserve Warning**: When reserve cushion is touched.
4. **Single-Database Backend**: The backend relies solely on **Neon PostgreSQL** via Prisma with zero other required infrastructure.

---

## 5. Non-Goals
- Removing local SMS parsing or background telephony listeners.
- Removing backend cloud backup/sync (Neon PostgreSQL synchronization remains active and reliable).
- Removing the AI Financial Coach.

---

## 6. Proposed Design

### 6.1 System Architecture: Totals-Style Local Flow vs Clean API

```
+=============================================================================+
|                           MOBILE DEVICE (LOCAL-FIRST)                       |
+=============================================================================+
|                                                                             |
|  [Incoming Bank SMS] (Telebirr, CBE, BoA, Awash)                            |
|          |                                                                  |
|          v                                                                  |
|  [Headless Telephony Receiver]                                              |
|          |                                                                  |
|          v                                                                  |
|  [IngestionPipeline] ---> Parses Transaction -> Saves to SQLCipher SQLite  |
|          |                                                                  |
|          +-------------------------------------------------------------+    |
|          |                                                             |    |
|          v                                                             v    |
|  [Transaction Receipt Toast]                           [Budget Threshold]   |
|  "Telebirr: -250.00 ETB"                               (Check Category Cap) |
|  "Balance: 14,250.00 ETB"                                              |    |
|          |                                                             v    |
|          |                                            [80% / 100% Alert]    |
|          |                                            "⚠️ 80% Food Budget"  |
|          \                                                             /    |
|           +----------------------------+------------------------------+     |
|                                        |                                    |
|                                        v                                    |
|                       [flutter_local_notifications]                         |
|                       - Instant on-device notification (<50ms)              |
|                       - Respects Quiet Hours (22:00-07:00)                  |
|                       - Respects Privacy Mask                               |
|                                                                             |
|  [Local Android Alarms / Schedulers]                                        |
|  - 07:30 AM: Morning Allowance Brief                                        |
|  - 21:00 PM: Evening Daily Spending Recap                                   |
+=============================================================================+
                                        |
                               (One-Tap / Background)
                                        |
                                        v
+=============================================================================+
|                      CLEAN FASTIFY BACKEND (NO REDIS / NO WORKERS)          |
+=============================================================================+
|                                                                             |
|   HTTP Endpoints (Stateless & Ultra-Fast):                                  |
|   - POST /v1/auth/*       (Register, Login, Refresh JWT)                    |
|   - POST /v1/sync/*       (Durable Zero-Duplication Upsert to Postgres)     |
|   - POST /v1/ai/*         (AI Financial Coach Tools & OpenRouter LLM)       |
|   - GET  /v1/templates    (Signed OTA Bank Parser Templates)                |
|   - GET  /health          (Instant DB Ping: <20ms)                          |
|                                                                             |
|                           [Neon PostgreSQL DB]                              |
|                           (Only 1 Cloud Dependency!)                        |
+=============================================================================+
```

### 6.2 Mobile Notification Events (Exact Totals Parity)

1. **Transaction Ingestion Event**:
   - Triggered inside `IngestionPipeline.processMessage(...)`.
   - Notification Content:
     - Title: `[Provider] [Type]` (e.g. `Telebirr Payment`, `CBE Transfer Sent`, `BoA Salary Credited`)
     - Body: `-250.00 ETB to Solomon. Balance: 14,250.50 ETB`
     - When Privacy Mask is ON: `Transaction recorded from Telebirr.`
2. **Category Budget Threshold Event**:
   - Immediately checks local SQLite `limits` table for matching `categoryId`.
   - If `spent >= 0.8 * limit` and not previously alerted today -> Post 80% Alert.
   - If `spent >= 1.0 * limit` and not previously alerted today -> Post 100% Exceeded Alert.
3. **Morning Allowance Event (07:30)**:
   - Evaluates remaining active budget divided by days remaining in billing cycle.
   - Posts: `☀️ Morning Target: You have ~450 ETB available to spend today.`
4. **Evening Recap Event (21:00)**:
   - Summarizes total spent today vs morning allowance.
   - Posts: `🌙 Day Recap: 320 ETB spent today. You stayed 130 ETB under allowance!`
5. **Emergency Reserve Cushion Event**:
   - Posts when total available liquid balance dips into user's designated emergency reserve cushion.

### 6.3 Backend Cleanup & Removal

1. **Delete Files**:
   - `backend/src/jobs/redis.ts`
   - `backend/src/jobs/queues.ts`
   - `backend/src/jobs/workers/aggregates.worker.ts`
   - `backend/src/jobs/workers/outbox.worker.ts`
   - `backend/src/jobs/workers/plan-notifications.worker.ts`
   - `backend/src/jobs/workers/plan-snapshots.worker.ts`
   - `backend/src/jobs/workers/scheduler.worker.ts`
   - `backend/src/modules/notifications/notification.service.ts` (FCM push logic)
2. **Refactor `backend/src/server.ts`**:
   - Remove BullMQ worker instantiations.
   - Remove background `setInterval` intervals.
   - Remove `redisConnection.quit()`.
   - Server boots pure Fastify app in **< 100ms**.
3. **Refactor `backend/src/modules/sync/sync.service.ts`**:
   - Remove Redis idempotency checks and caching.
   - Remove `aggregatesQueue.add(...)`.
   - If daily aggregate updates are needed for analytics, execute a lightweight inline SQL query directly inside Neon PostgreSQL.
4. **Refactor `backend/src/modules/health/health.routes.ts`**:
   - Only checks PostgreSQL (`SELECT 1`).
   - Returns 200 OK immediately with database status.
5. **Clean `backend/package.json`**:
   - Uninstall `bullmq`, `ioredis`, and `firebase-admin`.
   - Remove `REDIS_URL` and `FIREBASE_SERVICE_ACCOUNT_KEY` requirements from `env.ts`.

---

## 7. API / Interface Changes
- **Backend**:
  - Deprecate `/v1/notifications/preferences` and `/v1/notifications` server endpoints (all preferences stored on-device in `SharedPreferences` / `SecureStorage`).
  - Keep `/health` reporting `{ status: 'ok', services: { database: 'up' } }`.
- **Mobile**:
  - No breaking API changes; mobile stops sending FCM tokens to backend.

---

## 8. Data Model Changes
- No breaking Postgres migrations needed. Tables like `outbox_events` and `notifications` can remain dormant or be dropped in future cleanup without affecting the app.

---

## 9. Alternatives Considered

1. **Keep Redis with In-Memory Mode / Mock**:
   - *Pros*: Minimizes code deletion.
   - *Cons*: Still retains BullMQ complexity and potential memory leaks; doesn't solve the user's desire for clean architecture.
2. **Server-Side FCM Push Only**:
   - *Pros*: Centralized server logs.
   - *Cons*: High latency, fails offline, requires FCM configuration, doesn't match Totals.
3. **Pure On-Device Local Notifications + Workerless Backend (Selected)**:
   - *Pros*: Exact match to Totals app, zero latency (<50ms), works 100% offline, zero Redis dependency, zero worker crashes, super-fast backend boots.

---

## 10. Impact & Risks
- **Performance**: Massive positive impact. API responses are instantaneous. App notifications trigger in real-time on-device without cloud round-trip.
- **Reliability**: 100% offline notification support. Budget alerts fire even with no internet connection.
- **Security**: No Firebase service account keys stored in server env. Financial alert details never leave the user's phone.

---

## 11. Implementation Plan
1. **Phase 1: Backend Zero-Redis Workerless Strip-Down**:
   - Remove `backend/src/jobs/` directory completely.
   - Refactor `backend/src/server.ts` to remove worker lifecycles and Redis cleanups.
   - Refactor `backend/src/modules/sync/sync.service.ts` to execute purely against PostgreSQL.
   - Refactor `backend/src/modules/health/health.routes.ts` to test only PostgreSQL.
   - Remove `ioredis`, `bullmq`, and `firebase-admin` from `package.json` and `env.ts`.
   - Verify `npm run build` exits with code 0.
2. **Phase 2: Mobile Totals-Parity Notification Engine**:
   - Connect `IngestionPipeline` to `LocalNotificationService` for immediate transaction receipt alerts and budget cap warnings (80% and 100%).
   - Implement periodic local scheduling for 07:30 Morning Brief and 21:00 Evening Recap.
   - Remove any remaining FCM token submission calls in mobile.
3. **Phase 3: Verification & Release Build**:
   - Run unit and integration tests.
   - Run `flutter analyze`.
   - Build release APK (`flutter build apk --release`).

---

## 12. Testing Strategy
- **Local SMS Ingestion**: Verify simulated SMS receipt fires local notification within 50ms.
- **Budget Threshold**: Test adding expense that crosses 80% and 100% cap; verify notification fires with correct masked/unmasked text.
- **Quiet Hours**: Verify notification suppression between 22:00 and 07:00.
- **Backend Cleanliness**: Test backend boot without Redis; verify `/health` returns 200 in < 20ms.

---

## 13. Rollout / Migration Plan
- Git commit on `main`.
- Deploy to Render / Neon.
- Distribute updated release APK.
- Rollback: `git revert` if necessary.

---

## 14. Open Questions
- None. Requirements are clear and aligned with Totals app specifications.

---

## 15. References
- `docs/TOTALS_ARCHITECTURE_AND_FEATURES.md`
- `mobile/lib/core/notifications/local_notification_service.dart`
- Android `NotificationManager` & `flutter_local_notifications`

---

## 16. Decision Log
- **2026-10-13**: Proposed full removal of Redis, BullMQ, and server-side FCM push, replacing with pure on-device Totals-parity notifications and workerless single-database (Neon Postgres) backend.

# Milestone B4 Design: Schedulers, Analytics, Push & Hardening

> **Part of SW-budget Backend Architecture Series**
> **Focus:** Minute scheduler tick, per-user timezone execution, FCM push service with lock-screen privacy, financial analytics & burn-down forecasting, encrypted backup (.swbackup), data export jobs, and production security hardening.

---

## 1. Metadata
- **Status:** Implemented & Verified
- **Author:** Samuel W. & Antigravity AI
- **Date:** 2026-10-07
- **Type:** System Design & Implementation Specification
- **Related Links:**
  - Master Design: [2026-10-07-sw-budget-app-design.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/.agent/docs/design/2026-10-07-sw-budget-app-design.md)
  - Milestone B1: [2026-10-07-b1-foundation-db-auth.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/.agent/docs/design/backend/2026-10-07-b1-foundation-db-auth.md)
  - Milestone B2: [2026-10-07-b2-finance-api-sync-outbox.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/.agent/docs/design/backend/2026-10-07-b2-finance-api-sync-outbox.md)
  - Milestone B3: [2026-10-07-b3-ai-gateway-memory-tools.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/.agent/docs/design/backend/2026-10-07-b3-ai-gateway-memory-tools.md)
- **Confidence Level:** High (99%)

---

## 2. Summary
Milestone B4 completes the backend implementation by adding scheduled intelligence, automated notifications, deep financial analytics, and data portability. It implements a centralized minute-tick scheduler worker that queries `user_schedules` to trigger morning safe-to-spend allowances, bill warnings, and weekly summaries in user local timezones. It delivers a unified `NotificationService` dispatching FCM HTTP v1 pushes with quiet-hour filtering and lock-screen privacy masking. Finally, it implements encrypted backups (`.swbackup`), Excel/PDF exports with Amharic UTF-8 BOM support, and production security hardening (RLS, audit logs, and Prometheus metrics).

---

## 3. Problem / Motivation
Scheduled notifications often fail due to timezone drifts, redundant notifications, and lock-screen privacy violations where sensitive financial balances are exposed. Furthermore, generating complex month-end reports, forecasts, and full-database encrypted exports inside standard request cycles causes HTTP request timeouts and memory spikes. Milestone B4 offloads exports and schedules to dedicated background workers and establishes a robust privacy-preserving notification engine.

---

## 4. Goals
- **Per-User Timezone Scheduler:** A single minute-tick BullMQ worker executing scheduled tasks (`user_schedules`) according to each user's local timezone (e.g., `Africa/Addis_Ababa`).
- **Privacy-Preserving FCM Push Notifications:** Centralize push dispatch with deduplication, quiet hours (22:00–07:00), daily caps, and lock-screen amount masking.
- **Financial Analytics & 30-Day Forecasting:** Compute daily pace burn-downs, category trends, fee analyses, and predictive balance projections.
- **Secure Export & Backup Pipeline:** Generate AES-256-GCM encrypted `.swbackup` archives and stream CSV/XLSX/PDF exports asynchronously.
- **Operational Hardening:** Prometheus `/metrics`, structured audit logging, and PostgreSQL Row-Level Security (RLS) enforcement.

---

## 5. Non-Goals
- **No In-App Payment Execution:** Notifications and bill warnings are purely advisory; the system cannot directly settle bills.
- **No SMS Ingestion on the Server:** Push notifications are egress-only; raw SMS processing remains strictly on-device.

---

## 6. Proposed Design

### 6.1 Scheduler & Notification Pipeline

```
BullMQ Scheduler (Every 60s)
       │
       ▼
Query: SELECT user_id, kind FROM user_schedules WHERE next_run_at <= NOW()
       │
       ▼ Emits jobs to 'notifications' queue
NotificationService Worker
       │
       ├─ 1. Load User NotificationPreferences
       ├─ 2. Evaluate Quiet Hours (22:00 - 07:00; security alerts bypass)
       ├─ 3. Check Daily Cap (max 5 non-critical alerts/day)
       ├─ 4. Check Deduplication Key (e.g., limit:food:2026-10:80)
       ├─ 5. Mask Sensitive Payload (hide balance if show_amounts = false)
       ├─ 6. Record to in-app 'notifications' table
       │
       ▼ Dispatch
Firebase Cloud Messaging (FCM HTTP v1)
       │
       ▼
Android Mobile Device (Wake up / Display Banner)
```

---

## 7. Interface Changes (Concrete APIs)

### 7.1 Analytics & Forecast Endpoints

#### `GET /v1/analytics/forecast`
- **Response (200 OK):**
  ```json
  {
    "current_balance": 24300.50,
    "projected_end_balance": 8450.00,
    "daily_burn_rate": 520.00,
    "upcoming_bills_total": 6500.00,
    "points": [
      {
        "date": "2026-10-07",
        "projected_balance": 24300.50,
        "is_payday": false
      },
      {
        "date": "2026-10-15",
        "projected_balance": 20140.50,
        "bill_due": "Ethio Telecom Broadband (1,200 ETB)"
      }
    ]
  }
  ```

### 7.2 Data Portability & Export

#### `POST /v1/export/jobs`
- **Request Body:**
  ```json
  {
    "format": "xlsx",
    "range": {
      "from": "2026-01-01T00:00:00.000Z",
      "to": "2026-10-07T00:00:00.000Z"
    },
    "include_sheets": ["transactions", "accounts", "categories", "limits"]
  }
  ```
- **Response (202 Accepted):**
  ```json
  {
    "job_id": "018f3a70-1111-7a22-3333-000011112222",
    "status": "processing",
    "poll_url": "/v1/export/jobs/018f3a70-1111-7a22-3333-000011112222"
  }
  ```

#### `GET /v1/export/jobs/:id`
- **Response (200 OK):**
  ```json
  {
    "job_id": "018f3a70-1111-7a22-3333-000011112222",
    "status": "completed",
    "download_url": "https://api.swbudget.et/downloads/export_018f3a70.xlsx?token=expiring_token...",
    "expires_at": "2026-10-07T00:45:00.000Z"
  }
  ```

#### `POST /v1/backup`
- **Request Body:**
  ```json
  {
    "backup_password_hash": "$argon2id$v=19$m=65536,t=3,p=4$..."
  }
  ```
- **Response (200 OK):** Binary download stream of `.swbackup` encrypted with AES-256-GCM.

---

## 8. Data Model Changes

```sql
-- Notifications
CREATE TABLE notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  channel TEXT NOT NULL,
  priority TEXT NOT NULL DEFAULT 'normal',
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  data JSONB NOT NULL DEFAULT '{}',
  route TEXT,
  dedupe_key TEXT,
  delivery_status TEXT NOT NULL DEFAULT 'pending',
  sent_at TIMESTAMPTZ,
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX idx_notifications_dedupe ON notifications (user_id, dedupe_key) WHERE dedupe_key IS NOT NULL;

-- Notification Preferences
CREATE TABLE notification_preferences (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  enabled BOOLEAN NOT NULL DEFAULT true,
  categories JSONB NOT NULL DEFAULT '{"limits":true,"daily":true,"savings":true,"bills":true,"insights":true,"sync":true,"security":true}',
  quiet_start TIME NOT NULL DEFAULT '22:00',
  quiet_end TIME NOT NULL DEFAULT '07:00',
  morning_time TIME NOT NULL DEFAULT '07:30',
  evening_time TIME,
  digest_dow SMALLINT NOT NULL DEFAULT 0,
  digest_time TIME NOT NULL DEFAULT '18:00',
  show_amounts BOOLEAN NOT NULL DEFAULT false,
  daily_cap SMALLINT NOT NULL DEFAULT 5,
  snoozed_until TIMESTAMPTZ
);

-- User Schedules (Minute-Tick Scheduler)
CREATE TABLE user_schedules (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind TEXT NOT NULL, -- morning_allowance | evening_summary | bill_warning | weekly_digest
  next_run_at TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (user_id, kind)
);
CREATE INDEX idx_user_schedules_next_run ON user_schedules (next_run_at);

-- Audit Log
CREATE TABLE audit_log (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  ip_address INET,
  user_agent TEXT,
  metadata JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

---

## 9. Alternatives Considered

| Approach | Pros | Cons | Decision |
|---|---|---|---|
| **1. Dynamic Cron Jobs per User in Redis** | • Built into BullMQ Repeatable Jobs. | • Doesn't scale past hundreds of users.<br>• Clutters Redis with thousands of distinct cron definitions. | **Rejected:** Single minute-tick scheduler querying indexed `user_schedules.next_run_at` handles millions of users efficiently. |
| **2. Synchronous File Downloads for Export** | • Instant client download. | • Times out when generating multi-sheet workbooks with thousands of transactions over mobile data.<br>• Blocks Node.js event loop during PDF rendering. | **Rejected:** Asynchronous background job queue returning 202 Accepted with polling and secure 10-minute expiring download links. |

---

## 10. Impact & Risks
- **FCM Invalid Token Bloat:** Uninstalled apps leave stale device tokens.
  - *Mitigation:* `NotificationService` intercepts `UNREGISTERED` and `INVALID_ARGUMENT` errors from FCM HTTP v1 and automatically deletes the associated device row.
- **Lock-Screen Financial Leakage:** Sensitive balance amounts appearing on lock screens when unauthorized persons see the phone.
  - *Mitigation:* `show_amounts: false` by default; notification body displays masked text ("Your food budget needs attention") unless explicitly toggled on by the user.

---

## 11. Implementation Plan
- **B4.1:** Implement `NotificationService` supporting FCM HTTP v1, quiet hours, daily caps, and deduplication keys.
- **B4.2:** Implement BullMQ `scheduler` worker polling `user_schedules` every 60 seconds.
- **B4.3:** Build analytics and forecasting routes (`/analytics/forecast`, `/analytics/fees`, `/analytics/trends`).
- **B4.4:** Implement asynchronous export jobs for Excel (ExcelJS with UTF-8 BOM), CSV, and PDF reports.
- **B4.5:** Implement AES-256-GCM encrypted `.swbackup` generation and restoration.
- **B4.6:** Configure Prometheus `/metrics` endpoint and audit logging middleware.

---

## 12. Testing Strategy
- **Unit Tests:** Quiet hours evaluation spanning midnight (e.g., 22:00 to 07:00); deduplication key collisions; AES-256-GCM encryption roundtrip.
- **Integration Tests:**
  - Scheduler tick updates `next_run_at` and enqueues notification.
  - Stale FCM token error triggers automatic device deletion.
  - Export job completes and generates valid Excel workbook with readable Amharic characters.

---

## 13. Rollout & Rollback Plan
- **Rollout:** Deploy migrations; launch scheduler and notification worker processes; configure FCM service account.
- **Rollback:** Disable scheduler queue; gracefully fall back to local device notifications.

---

## 14. Open Questions
- None. Timezone handling and notification pipelines are completely specified.

---

## 15. References
- [Firebase Cloud Messaging HTTP v1 API](https://firebase.google.com/docs/cloud-messaging/migrate-v1)
- [ExcelJS: Spreadsheet generation](https://github.com/exceljs/exceljs)

---

## 16. Decision Log
- **2026-10-07:** Formalized Milestone B4 design. Mandated single minute-tick scheduler architecture and lock-screen privacy masking for all outgoing push payloads.
- **2026-10-07:** Implemented & fully verified Milestone B4.
  - Implemented schema additions in Prisma (`AuditLog`, `Notification`, `NotificationPreference`, `UserSchedule`) and synced to PostgreSQL.
  - Built `NotificationService` with quiet hours evaluation, daily quota caps, and lock-screen privacy masking (`"Activity detected on your account"`).
  - Built minute-tick BullMQ scheduler worker polling `user_schedules` per user timezone and calculating `nextRunAt`.
  - Built `AnalyticsService` delivering 30-day daily burn-down pace forecasting, spending projections, and category breakdowns.
  - Implemented ExcelJS multi-sheet workbook generation with UTF-8 BOM encoding for Amharic script support and AES-256-GCM encrypted `.swbackup` backup/restore pipeline.
  - Added Prometheus metrics exporter on `/metrics` with `sw_budget_` prefix.
  - Passed 47/47 automated Vitest unit/integration tests and 32/32 live HTTP E2E checks with 100% pass rate.
- **2026-10-07:** Production Readiness Audit & Remediation Completed.
  - Fixed IDOR on `/v1/auth/logout`: added `fastify.authenticate` hook and verified authenticated `userId` owns `device_id`.
  - Fixed cross-tenant data tampering in `restoreEncryptedBackup` and extended restore to transactionally restore categories, accounts, limits, and transactions.
  - Fixed sync page-boundary data loss: assigned individual strictly monotonic sequence numbers per operation in `applyPushBatch`.
  - Integrated `firebase-admin` push delivery in `NotificationService` with multicast dispatch and stale token cleanup.
  - Wired worker lifecycles, Outbox relay worker, minute-tick scheduler runner, and `SIGTERM`/`SIGINT` graceful shutdown in `server.ts`.
  - Added foreign key secondary indexes on `userId` across all models and created version-controlled baseline migration `prisma/migrations/20261007000000_init_baseline/migration.sql` with pgvector HNSW index.
  - Added Redis health check probe to `GET /health`, sanitized 500 error messages in production, and configured multi-stage production `Dockerfile` and `docker-compose.yml`.
  - 100% verified with clean `npm run lint`, `npm run build`, 47/47 Vitest suite, and 32/32 live HTTP E2E runner.
- **2026-10-07:** TypeScript Strong Typing, Exported Types, and Workspace IDE Resolution.
  - Root Cause: (1) In `finance.schemas.ts`, Zod schemas were exported but zero TypeScript inferred types were exported. (2) In `finance.repository.ts` and `finance.service.ts`, inputs were weakly typed as `data: any`. (3) In `finance.routes.ts`, `createTransactionSchema` and direct transaction creation route were missing. (4) In route files, `fastify.authenticate` and `request.user` lacked ambient global Fastify/JWT declarations. (5) Opening the monorepo root in IDE caused TypeScript Language Server to miss `NodeNext` ESM extension mapping without a root `tsconfig.json`.
  - Added ambient Fastify type definitions in `src/types/fastify.d.ts`.
  - Added explicit `: PrismaClient` type annotation on `prisma` in `src/db/prisma.ts`.
  - Exported all input types (`CreateAccountInput`, `CreateCategoryInput`, `CreateLimitInput`, `CreateSavingPlanInput`, `TransactionQueryInput`, `UpdateTransactionInput`, `CreateTransactionInput`) from `finance.schemas.ts`.
  - Strongly typed all parameters in `finance.repository.ts` and `finance.service.ts` and added `createTransaction`.
  - Added `POST /v1/transactions` in `finance.routes.ts`.
  - Created `finance/index.ts` barrel export.
  - Created root `tsconfig.json` with `moduleResolution: NodeNext`.
  - Verified: `npm run lint` (0 errors), `npm run build` (0 errors), and all 47/47 tests passing.


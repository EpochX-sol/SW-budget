# Milestone B2 Design: Core Finance API, Sequence Sync & Outbox

> **Part of SW-budget Backend Architecture Series**
> **Focus:** Relational finance schema (Accounts, Categories, Transactions, Limits, Savings), Monotonic `change_seq` sync engine, BullMQ outbox relay, incremental aggregation worker, and Ed25519-signed SMS template distribution.

---

## 1. Metadata
- **Status:** Implemented & Verified
- **Author:** Samuel W. & Antigravity AI
- **Date:** 2026-10-07
- **Type:** System Design & Implementation Specification
- **Related Links:**
  - Master Design: [2026-10-07-sw-budget-app-design.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/.agent/docs/design/2026-10-07-sw-budget-app-design.md)
  - Milestone B1: [2026-10-07-b1-foundation-db-auth.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/.agent/docs/design/backend/2026-10-07-b1-foundation-db-auth.md)
- **Confidence Level:** High (99%)

---

## 2. Summary
Milestone B2 builds the core financial domain and multi-device synchronization engine. It implements the data models and CRUD endpoints for Accounts, Categories, Transactions, Limits, and Savings Plans. It formalizes a reliable, clock-skew-immune two-way synchronization engine driven by a per-user monotonic sequence cursor (`change_seq`) and client-generated UUIDv7 identifiers. Writes emit transactional outbox events processed asynchronously by BullMQ workers to maintain `daily_category_totals` aggregations. Finally, it serves Ed25519-signed SMS template bundles to update mobile parsers over the air.

---

## 3. Problem / Motivation
In mobile environments with intermittent connectivity (e.g., Ethiopian 3G/4G networks), simple timestamp-based synchronization (`updated_at`) leads to lost updates, duplicate transactions, and race conditions. Furthermore, recomputing month-to-date category totals directly from thousands of transactions degrades dashboard and AI response times. Milestone B2 solves both problems with an explicit sequence counter and asynchronous transactional materialized aggregates.

---

## 4. Goals
- **Monotonic Sync Engine:** Support offline-first clients pushing and pulling batches using per-user monotonic `change_seq` cursors and `Idempotency-Key` headers.
- **Transactional Outbox & Aggregates:** Atomically commit domain changes and outbox events in a single PostgreSQL transaction; BullMQ workers incrementally maintain `daily_category_totals`.
- **Signed Template Distribution:** Expose an endpoint serving Ed25519-signed JSON template bundles to update mobile regex parsers without binary store releases.
- **Relational Domain Models:** Support accounts (CBE, Telebirr, BoA, Cash), hierarchical categories, fee linking (`parent_txn_id`), and transfer pairing.

---

## 5. Non-Goals
- **No Direct LLM Coaching or Vector Memory:** That is delivered in Milestone B3.
- **No Background Push Notifications:** Notifications and scheduler ticks are introduced in Milestone B4.

---

## 6. Proposed Design

### 6.1 Sync & Outbox Architecture

```
Mobile App (Flutter)                               Fastify Backend (Node.js)
       │                                                      │
       │─── 1. POST /v1/sync/push (Batch of 100 changes) ────►│
       │    Headers: Idempotency-Key: <UUIDv7>                │
       │                                                      │ ─── Single DB Transaction ───
       │                                                      │ 1. Lock user_sync_state FOR UPDATE
       │                                                      │ 2. Increment user_sync_state.seq
       │                                                      │ 3. Apply upserts/deletes with change_seq
       │                                                      │ 4. Insert into outbox_events
       │                                                      │ ─────────────────────────────
       │◄── 2. 200 OK (accepted_ids, conflicts, new_cursor) ──│
       │                                                      │
       │                                                      ▼
       │                                              Outbox Relay Worker (BullMQ)
       │                                              - Polls outbox_events
       │                                              - Emits to 'aggregates' queue
       │                                                      │
       │                                                      ▼
       │                                              Aggregates Worker
       │                                              - Incrementally updates
       │                                                daily_category_totals
       │                                                      │
       │─── 3. GET /v1/sync/pull?cursor=N&limit=100 ─────────►│
       │◄── 4. 200 OK (changes, has_more, cursor) ────────────│
```

---

## 7. Interface Changes (Concrete APIs)

### 7.1 Sync Engine Endpoints

#### `POST /v1/sync/push`
- **Headers:** `Idempotency-Key: 018f3a60-9999-7f44-8833-abcdef012345`, `Authorization: Bearer <token>`
- **Request Body:**
  ```json
  {
    "device_id": "018f3a5b-9b42-7c30-9b32-e02165849201",
    "batch_index": 1,
    "total_batches": 1,
    "changes": [
      {
        "entity": "transaction",
        "op": "upsert",
        "id": "018f3a60-2233-7a11-b998-112233445566",
        "client_updated_at": "2026-10-07T00:15:00.000Z",
        "data": {
          "account_id": "018f3a5d-1111-7b22-8888-000000000001",
          "category_id": "018f3a5e-2222-7c33-9999-000000000002",
          "type": "expense",
          "amount": "450.00",
          "balance_after": "12840.50",
          "counterparty": "Feres Transport",
          "reference": "TXN98765432",
          "occurred_at": "2026-10-07T00:12:30.000Z",
          "source": "sms",
          "parse_confidence": 0.98,
          "balance_chain_ok": true,
          "dedupe_key": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
          "user_edited_fields": []
        }
      }
    ]
  }
  ```
- **Response (200 OK):**
  ```json
  {
    "accepted_ids": ["018f3a60-2233-7a11-b998-112233445566"],
    "conflicts": [],
    "new_cursor": 1054
  }
  ```

#### `GET /v1/sync/pull?cursor=1000&limit=100`
- **Response (200 OK):**
  ```json
  {
    "cursor": 1054,
    "has_more": false,
    "changes": [
      {
        "entity": "transaction",
        "op": "upsert",
        "id": "018f3a60-2233-7a11-b998-112233445566",
        "change_seq": 1054,
        "data": {
          "account_id": "018f3a5d-1111-7b22-8888-000000000001",
          "category_id": "018f3a5e-2222-7c33-9999-000000000002",
          "type": "expense",
          "amount": "450.00",
          "balance_after": "12840.50",
          "counterparty": "Feres Transport",
          "reference": "TXN98765432",
          "occurred_at": "2026-10-07T00:12:30.000Z",
          "source": "sms",
          "parse_confidence": 0.98,
          "balance_chain_ok": true,
          "dedupe_key": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
          "user_edited_fields": []
        }
      }
    ]
  }
  ```

### 7.2 Signed Template Distribution

#### `GET /v1/sms-templates?since=2`
- **Response (200 OK):**
  ```json
  {
    "bundle_version": 3,
    "published_at": "2026-10-07T00:00:00.000Z",
    "signature": "30450221008f...Ed25519HexSignature...",
    "templates": [
      {
        "id": "cbe_debit_v3",
        "bank": "CBE",
        "version": 3,
        "match": "(?i)debited|transferred",
        "type": "expense",
        "fields": {
          "amount": "ETB\\s?([\\d,]+\\.?\\d*)",
          "balance": "(?i)balance(?: is)?\\s*:?\\s*ETB\\s?([\\d,]+\\.?\\d*)",
          "reference": "(?i)ref(?:erence)?(?: no)?[:.]?\\s*([A-Z0-9]+)",
          "counterparty": "(?i)to\\s+([A-Za-z ]+?)(?:\\s+on|\\.|,)"
        }
      }
    ]
  }
  ```

---

## 8. Data Model Changes

```sql
-- Accounts
CREATE TABLE accounts (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider TEXT NOT NULL,
  name TEXT NOT NULL,
  account_mask TEXT,
  last_known_balance NUMERIC(14,2),
  balance_updated_at TIMESTAMPTZ,
  is_savings BOOLEAN NOT NULL DEFAULT false,
  change_seq BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

-- Categories
CREATE TABLE categories (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  icon TEXT NOT NULL,
  color_hex CHAR(7) NOT NULL,
  is_system BOOLEAN NOT NULL DEFAULT false,
  change_seq BIGINT NOT NULL,
  deleted_at TIMESTAMPTZ
);

-- Transactions
CREATE TABLE transactions (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  account_id UUID NOT NULL REFERENCES accounts(id),
  category_id UUID REFERENCES categories(id),
  type TEXT NOT NULL,
  amount NUMERIC(14,2) NOT NULL CHECK (amount >= 0),
  balance_after NUMERIC(14,2),
  counterparty TEXT,
  reference TEXT,
  note TEXT,
  occurred_at TIMESTAMPTZ NOT NULL,
  source TEXT NOT NULL DEFAULT 'sms',
  parse_confidence REAL,
  template_id TEXT,
  balance_chain_ok BOOLEAN,
  gap_before_amount NUMERIC(14,2),
  is_internal_transfer BOOLEAN NOT NULL DEFAULT false,
  parent_txn_id UUID REFERENCES transactions(id),
  dedupe_key TEXT NOT NULL,
  needs_review BOOLEAN NOT NULL DEFAULT false,
  user_edited_fields TEXT[] NOT NULL DEFAULT '{}',
  change_seq BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ,
  UNIQUE (user_id, dedupe_key)
);
CREATE INDEX idx_transactions_user_occurred ON transactions (user_id, occurred_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_transactions_user_sync ON transactions (user_id, change_seq);

-- Daily Category Totals
CREATE TABLE daily_category_totals (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  day DATE NOT NULL,
  category_id UUID NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  expense NUMERIC(14,2) NOT NULL DEFAULT 0,
  income NUMERIC(14,2) NOT NULL DEFAULT 0,
  fees NUMERIC(14,2) NOT NULL DEFAULT 0,
  txn_count INT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, day, category_id, account_id)
);

-- Outbox Events
CREATE TABLE outbox_events (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL,
  payload JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  processed_at TIMESTAMPTZ
);
CREATE INDEX idx_outbox_unprocessed ON outbox_events (id) WHERE processed_at IS NULL;
```

---

## 9. Alternatives Considered

| Approach | Pros | Cons | Decision |
|---|---|---|---|
| **1. Synchronous Materialized View Refresh** | • No background worker queues required. | • Blocks user sync requests while running expensive view refreshes.<br>• Degrades mobile response times. | **Rejected:** Asynchronous BullMQ worker maintaining `daily_category_totals` updates incrementally in the background without blocking the sync HTTP response. |
| **2. Unsigned Remote Regex Configurations** | • Simpler endpoint; plain JSON files. | • Severe security vulnerability: an attacker or compromised CDN could inject arbitrary regex or exploit parsing logic. | **Rejected:** Ed25519 cryptographic signatures ensure that the mobile app refuses any modified or unverified template bundles. |

---

## 10. Impact & Risks
- **Deadlocks on Concurrent Sync:** Multiple devices syncing simultaneously for the same user could contend for `user_sync_state`.
  - *Mitigation:* A strict row-level lock (`SELECT seq FROM user_sync_state WHERE user_id = $1 FOR UPDATE`) guarantees serial, safe sequence incrementation.
- **Idempotency Cache Expiration:** Redis keys for `Idempotency-Key` are retained for 24 hours.

---

## 11. Implementation Plan
- **B2.1:** Implement Prisma models and migrations for Accounts, Categories, Transactions, Limits, and Outbox.
- **B2.2:** Build seed script for standard default categories (Food, Transport, Utilities, etc.).
- **B2.3:** Build `POST /sync/push` and `GET /sync/pull` transaction handlers with monotonic `change_seq` allocation.
- **B2.4:** Implement BullMQ worker to consume `outbox_events` and maintain `daily_category_totals`.
- **B2.5:** Implement Ed25519 signing script and `GET /v1/sms-templates` endpoint.

---

## 12. Testing Strategy
- **Unit Tests:** Ed25519 key signing and verification; sequence monotonicity generator.
- **Integration Tests:**
  - Push 100 transactions; verify `user_sync_state.seq` increments accurately.
  - Re-send push with identical `Idempotency-Key`; verify HTTP 200 returned with no duplicate database insertions.
  - Pull with older cursor; verify changes are correctly returned with tombstones.
  - Outbox worker verification: inserting a transaction creates/updates the matching `daily_category_totals` row.

---

## 13. Rollout & Rollback Plan
- **Rollout:** Deploy migration, seed default categories, launch BullMQ outbox worker process.
- **Rollback:** Disable outbox consumer; rollback routes to read-only mode if synchronization conflicts occur.

---

## 14. Open Questions
- None. Synchronization semantics and outbox schemas are completely defined.

---

## 15. References
- [The Transactional Outbox Pattern](https://microservices.io/patterns/data/transactional-outbox.html)
- [Ed25519 Digital Signature Standard](https://ed25519.cr.yp.to/)

---

## 16. Decision Log
- **2026-10-07:** Formalized Milestone B2 design. Adopted monotonic per-user sequence numbering and asynchronous BullMQ aggregate maintenance.
- **2026-10-07 (Implementation & Verification):**
  - **BigInt Serialization:** Registered JSON serialization polyfill for `BigInt` to format Prisma `change_seq` as Numbers without `TypeError`.
  - **BullMQ Custom IDs:** Replaced colon delimiter with underscores (`agg_${userId}_${day}_...`) to comply with BullMQ v5 custom job ID restrictions.
  - **Testing Coverage:** Automated test suite `test/b2-sync-finance.test.ts` (9 tests) and full test suite `npm test` (25 tests) passed at 100%.
  - **Live Verification:** Executed live HTTP end-to-end integration test `test/e2e-runner.ts` covering 20 comprehensive checks spanning B1 authentication and B2 core finance, sync engine, idempotency, and Ed25519 signatures. All 20 passed.

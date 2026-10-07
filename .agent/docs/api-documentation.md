# SW-Budget Backend API Reference Documentation

**Base URL**: `http://localhost:3000`  
**API Version**: `v1`  
**Content-Type**: `application/json`  
**Standard Error Format**: RFC 7807 Problem Details  

---

## 1. Global Conventions & Architecture

### Authentication
Endpoints marked with `🔒 Bearer Auth` require a JSON Web Token (JWT) in the HTTP `Authorization` header:
```http
Authorization: Bearer <access_token>
```
Access tokens expire after **15 minutes** (900s). Renew them using the `/v1/auth/refresh` endpoint with your rotating refresh token.

### Standard Error Response (RFC 7807)
All client (4xx) and server (5xx) errors conform to RFC 7807 Problem Details:
```json
{
  "type": "about:blank",
  "title": "Validation Error",
  "status": 400,
  "detail": "Password must be at least 8 characters, email is invalid",
  "instance": "/v1/auth/register",
  "timestamp": "2026-10-07T02:40:00.000Z"
}
```

### Idempotency
Critical mutation endpoints (such as `POST /v1/sync/push`) support an optional `Idempotency-Key` header:
```http
Idempotency-Key: 018f3a60-2233-7a11-b998-112233445566
```
Duplicate requests return the cached response with zero duplicate database mutations.

---

## 2. Health & System Monitoring

### `GET /health`
- **Auth**: None
- **Description**: Returns database, Redis, and vector extension health status.
- **Request Example**:
  ```http
  GET /health HTTP/1.1
  Host: localhost:3000
  ```
- **Response `200 OK`**:
  ```json
  {
    "status": "healthy",
    "timestamp": "2026-10-07T02:40:00.000Z",
    "checks": {
      "database": "up",
      "pgvector": "up",
      "redis": "up"
    }
  }
  ```

### `GET /metrics`
- **Auth**: None
- **Description**: Prometheus scraper endpoint exposing runtime, memory, and application counters prefixed with `sw_budget_`.
- **Response `200 OK`**: Text/plain Prometheus metric exposition.

---

## 3. Authentication & User Profile

### `POST /v1/auth/register`
- **Auth**: None
- **Description**: Registers a new user account, stores password using Argon2id, creates initial sync state (sequence 0), registers the initial device, and returns JWT access and refresh tokens.
- **Request Example**:
  ```json
  {
    "email": "samuel@example.com",
    "password": "SecurePassword123!",
    "display_name": "Samuel Finance",
    "currency": "ETB",
    "timezone": "Africa/Addis_Ababa",
    "month_start_day": 1,
    "device": {
      "id": "018f3a5b-9b42-7c30-9b32-e02165849b20",
      "device_name": "Samsung Galaxy S24",
      "platform": "android",
      "app_version": "1.0.0",
      "fcm_token": "fcm_token_sample_abc123"
    }
  }
  ```
- **Response `201 Created`**:
  ```json
  {
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "refresh_token": "4f9d8a3e7b1c...",
    "expires_in": 900,
    "user": {
      "id": "e81d86d6-056d-4950-8efc-1481d6f46a36",
      "email": "samuel@example.com",
      "display_name": "Samuel Finance",
      "currency": "ETB",
      "timezone": "Africa/Addis_Ababa",
      "month_start_day": 1
    }
  }
  ```
- **Errors**: `400 Validation Error`, `409 Conflict` (Email already registered).

---

### `POST /v1/auth/login`
- **Auth**: None
- **Description**: Verifies credentials using Argon2id, upserts device record with FCM token, and rotates refresh token.
- **Request Example**:
  ```json
  {
    "email": "samuel@example.com",
    "password": "SecurePassword123!",
    "device": {
      "id": "018f3a5b-9b42-7c30-9b32-e02165849b20",
      "device_name": "Samsung Galaxy S24",
      "platform": "android",
      "app_version": "1.0.0",
      "fcm_token": "fcm_token_sample_abc123"
    }
  }
  ```
- **Response `200 OK`**: Same payload shape as `/v1/auth/register`.
- **Errors**: `401 Unauthorized` (Invalid email or password).

---

### `POST /v1/auth/refresh`
- **Auth**: None
- **Description**: Single-use token rotation. Issues a new refresh token and access token while invalidating the previous refresh token. Defends against token reuse attacks.
- **Request Example**:
  ```json
  {
    "refresh_token": "4f9d8a3e7b1c...",
    "device_id": "018f3a5b-9b42-7c30-9b32-e02165849b20"
  }
  ```
- **Response `200 OK`**:
  ```json
  {
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "refresh_token": "7a8b9c0d1e2f...",
    "expires_in": 900
  }
  ```
- **Errors**: `401 Unauthorized` (Token invalid, expired, or token reuse detected).

---

### `POST /v1/auth/logout`
- **Auth**: 🔒 Bearer Auth
- **Description**: Revokes the device session and clears stored refresh token hash. Validates that authenticated user owns the target device.
- **Request Example**:
  ```json
  {
    "device_id": "018f3a5b-9b42-7c30-9b32-e02165849b20"
  }
  ```
- **Response `204 No Content`**
- **Errors**: `401 Unauthorized`, `403 Forbidden` (Attempting to logout a device belonging to another user).

---

### `GET /v1/me`
- **Auth**: 🔒 Bearer Auth
- **Description**: Returns full user profile, currency preferences, active sync sequence, and registered devices.
- **Response `200 OK`**:
  ```json
  {
    "id": "e81d86d6-056d-4950-8efc-1481d6f46a36",
    "email": "samuel@example.com",
    "display_name": "Samuel Finance",
    "currency": "ETB",
    "timezone": "Africa/Addis_Ababa",
    "month_start_day": 1,
    "sync_seq": 42,
    "created_at": "2026-10-07T00:00:00.000Z",
    "devices": [
      {
        "id": "018f3a5b-9b42-7c30-9b32-e02165849b20",
        "deviceName": "Samsung Galaxy S24",
        "platform": "android",
        "appVersion": "1.0.0",
        "lastSeenAt": "2026-10-07T02:00:00.000Z"
      }
    ]
  }
  ```

---

## 4. Financial Entities Management

All financial CRUD operations automatically assign a monotonic sequence (`changeSeq`) to records and soft-delete entries upon removal.

### Accounts

#### `GET /v1/accounts`
- **Auth**: 🔒 Bearer Auth
- **Response `200 OK`**:
  ```json
  [
    {
      "id": "018f3a5d-1111-7b22-8888-000000000001",
      "provider": "TELEBIRR",
      "name": "Telebirr Wallet",
      "accountMask": "9112",
      "lastKnownBalance": 4500.5,
      "isSavings": false,
      "createdAt": "2026-10-07T00:00:00.000Z"
    }
  ]
  ```

#### `POST /v1/accounts`
- **Auth**: 🔒 Bearer Auth
- **Request Example**:
  ```json
  {
    "provider": "CBE",
    "name": "CBE Primary Account",
    "account_mask": "1000",
    "last_known_balance": 18250.75,
    "is_savings": false
  }
  ```
- **Response `201 Created`**: Returns created account record.

#### `PATCH /v1/accounts/:id`
- **Auth**: 🔒 Bearer Auth
- **Request Example**:
  ```json
  {
    "name": "CBE Payroll Checking",
    "last_known_balance": 22400.0
  }
  ```
- **Response `200 OK`**: `{"success": true}`

#### `DELETE /v1/accounts/:id`
- **Auth**: 🔒 Bearer Auth
- **Response `204 No Content`**

---

### Categories

#### `GET /v1/categories`
- **Auth**: 🔒 Bearer Auth
- **Description**: Returns system default categories (e.g. Food & Groceries, Transport, Utilities) plus user-created custom categories.
- **Response `200 OK`**:
  ```json
  [
    {
      "id": "018f3a5e-0001-7000-8000-000000000001",
      "name": "Food & Groceries",
      "icon": "fastfood",
      "colorHex": "#10B981",
      "isSystem": true
    },
    {
      "id": "e22a0134-8c76-43f1-bdf4-2a6c9d0e1234",
      "name": "Side Hustle Tech",
      "icon": "laptop",
      "colorHex": "#3B82F6",
      "isSystem": false
    }
  ]
  ```

#### `POST /v1/categories`
- **Auth**: 🔒 Bearer Auth
- **Request Example**:
  ```json
  {
    "name": "Coffee & Roastery",
    "icon": "local_cafe",
    "color_hex": "#8B5CF6"
  }
  ```
- **Response `201 Created`**

#### `PATCH /v1/categories/:id`
- **Auth**: 🔒 Bearer Auth
- **Request Example**: `{"name": "Buna & Cafe"}`
- **Response `200 OK`**: `{"success": true}`

#### `DELETE /v1/categories/:id`
- **Auth**: 🔒 Bearer Auth (System categories cannot be deleted)
- **Response `204 No Content`**

---

### Budget Limits

#### `GET /v1/limits`
- **Auth**: 🔒 Bearer Auth
- **Response `200 OK`**:
  ```json
  [
    {
      "id": "018f3a5f-4444-7c55-aaaa-000000000001",
      "scopeType": "category",
      "scopeId": "018f3a5e-0001-7000-8000-000000000001",
      "periodType": "monthly",
      "amount": 10000,
      "mode": "soft",
      "rollover": true,
      "alertThresholds": [50, 80, 100],
      "active": true
    }
  ]
  ```

#### `POST /v1/limits`
- **Auth**: 🔒 Bearer Auth
- **Request Example**:
  ```json
  {
    "scope_type": "overall",
    "period_type": "monthly",
    "amount": 25000,
    "mode": "soft",
    "rollover": false,
    "alert_thresholds": [50, 80, 100]
  }
  ```
- **Response `201 Created`**

#### `PATCH /v1/limits/:id`
- **Auth**: 🔒 Bearer Auth
- **Request Example**: `{"amount": 30000, "mode": "hard"}`
- **Response `200 OK`**: `{"success": true}`

#### `DELETE /v1/limits/:id`
- **Auth**: 🔒 Bearer Auth
- **Response `204 No Content`**

---

### Saving Plans

#### `GET /v1/saving-plans`
- **Auth**: 🔒 Bearer Auth
- **Response `200 OK`**: List of saving goals ordered by priority.

#### `POST /v1/saving-plans`
- **Auth**: 🔒 Bearer Auth
- **Request Example**:
  ```json
  {
    "name": "Emergency Fund",
    "period_type": "monthly",
    "target_amount": 100000,
    "start_date": "2026-10-01",
    "rule_type": "fixed",
    "rule_value": 5000,
    "priority": 1,
    "status": "active"
  }
  ```
- **Response `201 Created`**

---

### Transactions

#### `GET /v1/transactions`
- **Auth**: 🔒 Bearer Auth
- **Query Parameters**:
  - `from` *(optional ISO string)*: e.g. `2026-10-01`
  - `to` *(optional ISO string)*: e.g. `2026-10-31`
  - `account_id` *(optional UUID)*
  - `category_id` *(optional UUID)*
  - `type` *(optional: 'income' | 'expense' | 'transfer')*
  - `q` *(optional search string for counterparty, reference, or note)*
  - `limit` *(default 50, max 500)*
  - `offset` *(default 0)*
- **Response `200 OK`**:
  ```json
  {
    "total": 1,
    "items": [
      {
        "id": "018f3a60-2233-7a11-b998-112233445566",
        "accountId": "018f3a5d-1111-7b22-8888-000000000001",
        "categoryId": "018f3a5e-0001-7000-8000-000000000001",
        "type": "expense",
        "amount": 350.5,
        "balanceAfter": 3849.5,
        "counterparty": "Kaldis Coffee",
        "reference": "REF12345678",
        "occurredAt": "2026-10-07T10:15:00.000Z",
        "source": "sms",
        "account": { "id": "...", "name": "Telebirr Wallet", "provider": "TELEBIRR" },
        "category": { "id": "...", "name": "Food & Groceries", "icon": "fastfood", "colorHex": "#10B981" }
      }
    ]
  }
  ```

#### `POST /v1/transactions`
- **Auth**: 🔒 Bearer Auth
- **Request Example**:
  ```json
  {
    "account_id": "018f3a5d-1111-7b22-8888-000000000001",
    "category_id": "018f3a5e-0001-7000-8000-000000000001",
    "type": "expense",
    "amount": 250,
    "counterparty": "TotalEnergies Fuel",
    "source": "manual",
    "occurred_at": "2026-10-07T12:00:00Z"
  }
  ```
- **Response `201 Created`**

#### `PATCH /v1/transactions/:id`
- **Auth**: 🔒 Bearer Auth
- **Request Example**:
  ```json
  {
    "category_id": "018f3a5e-0001-7000-8000-000000000001",
    "note": "Lunch with team",
    "user_edited_fields": ["category_id", "note"]
  }
  ```
- **Response `200 OK`**: `{"success": true}`

#### `DELETE /v1/transactions/:id`
- **Auth**: 🔒 Bearer Auth
- **Response `204 No Content`**

---

## 5. Offline Sync Engine (Monotonic Sequence)

### `POST /v1/sync/push`
- **Auth**: 🔒 Bearer Auth
- **Header**: `Idempotency-Key` (Recommended)
- **Description**: Atomically locks `user_sync_state FOR UPDATE`, increments sequence per change item, applies upserts/deletes, enqueues category aggregate recomputations, and writes transactional outbox events.
- **Request Example**:
  ```json
  {
    "device_id": "018f3a5b-9b42-7c30-9b32-e02165849b20",
    "batch_index": 1,
    "total_batches": 1,
    "changes": [
      {
        "entity": "transaction",
        "op": "upsert",
        "id": "018f3a60-2233-7a11-b998-112233445566",
        "client_updated_at": "2026-10-07T10:15:00.000Z",
        "data": {
          "account_id": "018f3a5d-1111-7b22-8888-000000000001",
          "category_id": "018f3a5e-0001-7000-8000-000000000001",
          "type": "expense",
          "amount": 350.5,
          "balance_after": 3849.5,
          "counterparty": "Kaldis Coffee",
          "reference": "REF12345678",
          "occurred_at": "2026-10-07T10:15:00.000Z",
          "source": "sms",
          "parse_confidence": 0.98,
          "dedupe_key": "cbe_ref12345678"
        }
      }
    ]
  }
  ```
- **Response `200 OK`**:
  ```json
  {
    "accepted_ids": ["018f3a60-2233-7a11-b998-112233445566"],
    "new_cursor": 43,
    "status": "applied"
  }
  ```

---

### `GET /v1/sync/pull`
- **Auth**: 🔒 Bearer Auth
- **Query Parameters**:
  - `cursor` *(default 0)*: Sequence number on client device.
  - `limit` *(default 100, max 200)*
- **Description**: Returns all changes across transactions, accounts, categories, limits, and plans where `change_seq > cursor` in strictly ascending order.
- **Response `200 OK`**:
  ```json
  {
    "cursor": 43,
    "has_more": false,
    "changes": [
      {
        "entity": "transaction",
        "op": "upsert",
        "id": "018f3a60-2233-7a11-b998-112233445566",
        "change_seq": 43,
        "data": {
          "account_id": "...",
          "amount": "350.5",
          "counterparty": "Kaldis Coffee"
        }
      }
    ]
  }
  ```

---

### `GET /v1/sync/status`
- **Auth**: 🔒 Bearer Auth
- **Response `200 OK`**:
  ```json
  {
    "current_seq": 43,
    "status": "synced"
  }
  ```

---

## 6. Signed SMS Template Registry

### `GET /v1/sms-templates`
- **Auth**: None
- **Description**: Returns regex parser templates for CBE, Telebirr, and Bank of Abyssinia signed with Ed25519 for secure client-side verification.
- **Response `200 OK`**:
  ```json
  {
    "bundle_version": 3,
    "templates": [
      {
        "id": "cbe_debit_v1",
        "bank": "CBE",
        "sender": "CBE",
        "type": "expense",
        "pattern": "(?i)credited with ETB|debited with ETB",
        "fields": {
          "amount": "(?i)ETB\\s*([0-9,]+(?:\\.[0-9]{2})?)",
          "counterparty": "(?i)to\\s+([A-Za-z ]+?)(?:\\s+on|\\.|,)",
          "balance": "(?i)balance is ETB\\s*([0-9,]+(?:\\.[0-9]{2})?)",
          "reference": "(?i)txn\\s*id\\s*([A-Za-z0-9]+)"
        }
      }
    ],
    "signature": "3a4b5c...64bytes_hex",
    "public_key": "1f2e3d...32bytes_hex"
  }
  ```

---

## 7. AI Financial Coach & Gateway

### `POST /v1/ai/threads`
- **Auth**: 🔒 Bearer Auth
- **Request Example**: `{"title": "October Budget Advice"}`
- **Response `201 Created`**:
  ```json
  {
    "id": "thread_uuid_here",
    "title": "October Budget Advice",
    "createdAt": "2026-10-07T02:00:00.000Z"
  }
  ```

---

### `GET /v1/ai/threads`
- **Auth**: 🔒 Bearer Auth
- **Response `200 OK`**: List of user threads ordered by most recent activity.

---

### `POST /v1/ai/threads/:id/messages` (SSE Streaming)
- **Auth**: 🔒 Bearer Auth
- **Description**: Sends a message to the AI coach. Responses are streamed in real time via Server-Sent Events (SSE). When the model invokes deterministic financial tools, structured JSON proposal cards (`type: "proposal"`) are emitted.
- **Request Example**:
  ```json
  {
    "content": "Can I afford to spend 2,000 ETB on dinner tonight given my food budget?"
  }
  ```
- **Response `200 OK` (`text/event-stream`)**:
  ```
  data: {"type":"token","content":"Based on your current food budget of "}

  data: {"type":"token","content":"10,000 ETB, you have spent 7,850 ETB this month."}

  data: {"type":"proposal","proposal":{"id":"prop_uuid","tool":"create_limit","payload":{"category":"Food","amount":12000}}}

  data: {"type":"done","usage":{"promptTokens":142,"completionTokens":85,"totalTokens":227}}
  ```

---

### `GET /v1/ai/proposals`
- **Auth**: 🔒 Bearer Auth
- **Description**: Lists pending tool proposals created by the AI for the user.
- **Response `200 OK`**:
  ```json
  [
    {
      "id": "prop_uuid_123",
      "tool": "create_limit",
      "payload": { "category_id": "...", "amount": 12000 },
      "status": "pending",
      "createdAt": "2026-10-07T02:30:00.000Z"
    }
  ]
  ```

---

### `POST /v1/ai/proposals/:id/decision`
- **Auth**: 🔒 Bearer Auth
- **Description**: Accepts or rejects an AI-proposed financial action. If accepted, executes the underlying action directly.
- **Request Example**:
  ```json
  {
    "decision": "accepted"
  }
  ```
- **Response `200 OK`**: Returns updated proposal with status `"accepted"`.

---

### `GET /v1/ai/memories` & `POST /v1/ai/memories`
- **Auth**: 🔒 Bearer Auth
- **Description**: Manages long-term vector memories embedded using pgvector (768-dim embeddings).
- **Request Example**:
  ```json
  {
    "kind": "preference",
    "content": "Prefers saving at least 15% of income before allocating discretionary dining funds.",
    "importance": 4,
    "pinned": true
  }
  ```
- **Response `201 Created`**

---

### `GET /v1/ai/usage`
- **Auth**: 🔒 Bearer Auth
- **Response `200 OK`**:
  ```json
  {
    "total_prompt_tokens": 12450,
    "total_completion_tokens": 4200,
    "estimated_cost_usd": 0.045
  }
  ```

---

## 8. Analytics & Financial Forecasting

### `GET /v1/analytics/forecast`
- **Auth**: 🔒 Bearer Auth
- **Description**: Analyzes the active month's burn-down pace against limits and projects end-of-month financial trajectories.
- **Response `200 OK`**:
  ```json
  {
    "month": "2026-10",
    "days_elapsed": 7,
    "days_remaining": 24,
    "total_budget": 25000,
    "spent_so_far": 5420.5,
    "projected_spend": 23990.8,
    "safe_daily_burn": 815.81,
    "status": "on_track"
  }
  ```

---

### `GET /v1/analytics/trends`
- **Auth**: 🔒 Bearer Auth
- **Description**: Returns 6-month historical category spending trends.
- **Response `200 OK`**: List of monthly breakdown aggregates.

---

### `GET /v1/analytics/fees`
- **Auth**: 🔒 Bearer Auth
- **Description**: Computes ATM, Telebirr P2P transfer, and bank tariff fees incurred across accounts.
- **Response `200 OK`**:
  ```json
  {
    "total_fees_ytd": 340.0,
    "by_provider": {
      "CBE": 180.0,
      "TELEBIRR": 160.0
    }
  }
  ```

---

## 9. Push Notifications & Delivery Preferences

### `GET /v1/notifications`
- **Auth**: 🔒 Bearer Auth
- **Response `200 OK`**: List of notifications dispatched to user devices.

### `PATCH /v1/notifications/:id/read`
- **Auth**: 🔒 Bearer Auth
- **Response `200 OK`**: `{"success": true}`

### `GET /v1/notifications/preferences`
- **Auth**: 🔒 Bearer Auth
- **Response `200 OK`**:
  ```json
  {
    "enabled": true,
    "quietStart": "22:00",
    "quietEnd": "07:00",
    "showAmounts": false,
    "dailyCap": 5
  }
  ```

### `PUT /v1/notifications/preferences`
- **Auth**: 🔒 Bearer Auth
- **Request Example**:
  ```json
  {
    "enabled": true,
    "quiet_start": "23:00",
    "quiet_end": "06:30",
    "show_amounts": false,
    "daily_cap": 8
  }
  ```
- **Response `200 OK`**: Returns updated preferences.

---

## 10. Data Portability & Encrypted Backups

### `POST /v1/export/jobs`
- **Auth**: 🔒 Bearer Auth
- **Description**: Enqueues an asynchronous export generation job.
- **Response `202 Accepted`**:
  ```json
  {
    "job_id": "export_1728268800000",
    "status": "completed",
    "poll_url": "/v1/export/jobs/export_1728268800000",
    "download_url": "/v1/export/jobs/export_1728268800000/download"
  }
  ```

### `GET /v1/export/jobs/:id/download`
- **Auth**: 🔒 Bearer Auth
- **Response `200 OK`**: Binary `.xlsx` stream with UTF-8 BOM encoding and formatted sheets for Accounts, Categories, Limits, and Transactions (Amharic characters fully preserved).

---

### `POST /v1/backup`
- **Auth**: 🔒 Bearer Auth
- **Description**: Generates an AES-256-GCM encrypted binary backup archive (`.swbackup`) containing salt, IV, auth tag, and encrypted financial records.
- **Request Example**:
  ```json
  {
    "password": "UserMasterBackupPassword99!"
  }
  ```
- **Response `200 OK`**: Binary stream (`application/octet-stream`) with `Content-Disposition: attachment; filename="backup.swbackup"`.

---

### `POST /v1/backup/restore`
- **Auth**: 🔒 Bearer Auth
- **Description**: Decrypts and transactionally restores accounts, categories, limits, and transactions from a base64-encoded `.swbackup` payload. Forces all restored records into the authenticated user's ownership to prevent cross-tenant data tampering.
- **Request Example**:
  ```json
  {
    "password": "UserMasterBackupPassword99!",
    "backup_data_base64": "U1dCQUNLVVACAAAA..."
  }
  ```
- **Response `200 OK`**:
  ```json
  {
    "restored": {
      "categories": 12,
      "accounts": 3,
      "limits": 2,
      "transactions": 48
    }
  }
  ```

# Milestone B1 Design: Foundation, Database & Authentication

> **Part of SW-budget Backend Architecture Series**
> **Focus:** Monorepo/Backend skeleton, Fastify modular runtime, PostgreSQL 16 + pgvector extensions, Prisma + Kysely hybrid data layer, Argon2id auth, JWT rotation, and device lifecycle.

---

## 1. Metadata
- **Status:** Approved
- **Author:** Samuel W. & Antigravity AI
- **Date:** 2026-10-07
- **Type:** System Design & Implementation Specification
- **Related Links:** 
  - Master Design: [2026-10-07-sw-budget-app-design.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/.agent/docs/design/2026-10-07-sw-budget-app-design.md)
  - Agent Rules: [AGENTS.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/.agent/AGENTS.md)
- **Confidence Level:** High (99%)

---

## 2. Summary
Milestone B1 establishes the bedrock of the SW-budget backend service. It delivers a Fastify modular monolith written in TypeScript, initializes PostgreSQL 16 with the `vector` and `pgcrypto` extensions, sets up Prisma alongside Kysely for type-safe relational and vector queries, establishes RFC 7807 problem details error handling, and implements a multi-device authentication pipeline utilizing Argon2id, short-lived JWT access tokens (15 minutes), and rotating refresh tokens bound to unique mobile device records.

---

## 3. Problem / Motivation
A personal finance application handling sensitive monetary data requires rock-solid foundational security, deterministic configuration validation, and zero tolerance for token compromise or database schema drifts. Without a strict modular baseline, device binding, and migration automation established in Step 1, downstream financial synchronization (B2) and vector embeddings (B3) will suffer from architectural debt and security vulnerabilities.

---

## 4. Goals
- **Strict Environment & Configuration Validation:** Validate all environment variables at startup using Zod before any network listener binds.
- **Relational & Vector Database Foundation:** Deploy full relational DDL with Prisma migrations and automate PostgreSQL extensions (`pgvector`, `pgcrypto`).
- **Device-Bound Authentication:** Authenticate users via email/password, returning short-lived JWTs (15 min) and single-use rotating refresh tokens (30 days) bound to physical Android device IDs.
- **Predictable Error Contracts:** Standardize all API error responses using RFC 7807 problem details with machine-readable error codes.
- **Structured Observability:** Implement Pino structured logging with sanitized PII and request-scoped correlation IDs.

---

## 5. Non-Goals
- **No Third-Party OAuth / Social Logins in v1:** Google/Apple sign-in is out of scope for B1 to eliminate external dependencies during local-first operations.
- **No Transaction or Financial Sync Logic:** Domain logic for ledger synchronization and categories belongs to Milestone B2.
- **No Background BullMQ Workers:** Redis connectivity is established, but workers are introduced in B2 and B3.

---

## 6. Proposed Design

### 6.1 Module Topology & Architecture

```
src/
├── server.ts               # HTTP bootstrap & graceful shutdown
├── app.ts                  # Fastify plugin registration & middleware
├── config/                 # Zod validated configuration
│   └── env.ts
├── plugins/
│   ├── auth.ts             # JWT verification decorator
│   ├── sensible.ts         # RFC 7807 error helpers
│   ├── swagger.ts          # OpenAPI documentation generator
│   └── rate-limit.ts       # Route throttling
├── db/
│   ├── prisma.ts           # Prisma client singleton
│   ├── kysely.ts           # Kysely instance sharing Prisma pool
│   └── extensions.ts       # Vector & pgcrypto verification
└── modules/
    ├── health/             # /health & /metrics
    │   └── health.routes.ts
    └── auth/               # User registration, login, refresh, logout
        ├── auth.routes.ts
        ├── auth.service.ts
        ├── auth.repository.ts
        └── auth.schemas.ts
```

### 6.2 Authentication & Device-Binding Flow

```
Mobile App (Flutter)                               Fastify Backend (Node.js)
       │                                                      │
       │─── 1. POST /v1/auth/register (Email, Pass, Device) ──►│
       │                                                      │ Hash Password (Argon2id)
       │                                                      │ Generate UUIDv7 User & Device
       │                                                      │ Create initial user_sync_state
       │◄── 2. 201 Created (Access JWT, Refresh Token, User) ──│
       │                                                      │
       │─── 3. Subsequent Authenticated Request ──────────────►│ (Authorization: Bearer <JWT>)
       │                                                      │ Verify JWT signature & expiry
       │                                                      │ Inject req.user = { id, deviceId }
       │                                                      │
       │─── 4. POST /v1/auth/refresh (RefreshToken, DeviceId)─►│
       │                                                      │ Compare hash with devices.refresh_token_hash
       │                                                      │ If match: Rotate token, issue new pair
       │                                                      │ If mismatch (reuse detected):
       │                                                      │   Revoke all tokens for device
       │◄── 5. 200 OK (New Access JWT, New Refresh Token) ────│
```

---

## 7. Interface Changes (Concrete APIs)

### 7.1 Authentication Endpoints

#### `POST /v1/auth/register`
- **Request Body:**
  ```json
  {
    "email": "user@example.com",
    "password": "SecurePassword123!",
    "display_name": "Samuel",
    "currency": "ETB",
    "timezone": "Africa/Addis_Ababa",
    "device": {
      "id": "018f3a5b-9b42-7c30-9b32-e02165849201",
      "device_name": "Tecno Camon 20 Pro",
      "platform": "android",
      "app_version": "1.0.0"
    }
  }
  ```
- **Response (201 Created):**
  ```json
  {
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "refresh_token": "rt_018f3a5b9b427c309b32e02165849201_abcdef...",
    "expires_in": 900,
    "user": {
      "id": "018f3a5a-1122-7f44-8833-abcdef012345",
      "email": "user@example.com",
      "display_name": "Samuel",
      "currency": "ETB",
      "timezone": "Africa/Addis_Ababa",
      "month_start_day": 1
    }
  }
  ```

#### `POST /v1/auth/login`
- **Request Body:**
  ```json
  {
    "email": "user@example.com",
    "password": "SecurePassword123!",
    "device": {
      "id": "018f3a5b-9b42-7c30-9b32-e02165849201",
      "device_name": "Tecno Camon 20 Pro",
      "platform": "android",
      "app_version": "1.0.0"
    }
  }
  ```
- **Response (200 OK):** Identical payload to Register.

#### `POST /v1/auth/refresh`
- **Request Body:**
  ```json
  {
    "refresh_token": "rt_018f3a5b9b427c309b32e02165849201_abcdef...",
    "device_id": "018f3a5b-9b42-7c30-9b32-e02165849201"
  }
  ```
- **Response (200 OK):**
  ```json
  {
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "refresh_token": "rt_018f3a5b9b427c309b32e02165849201_newtoken...",
    "expires_in": 900
  }
  ```

#### `POST /v1/auth/logout`
- **Headers:** `Authorization: Bearer <access_token>`
- **Request Body:**
  ```json
  {
    "device_id": "018f3a5b-9b42-7c30-9b32-e02165849201"
  }
  ```
- **Response (204 No Content)**

### 7.2 System Health & Status

#### `GET /health`
- **Response (200 OK):**
  ```json
  {
    "status": "ok",
    "timestamp": "2026-10-07T00:30:00.000Z",
    "uptime": 124.5,
    "services": {
      "database": "up",
      "redis": "up",
      "vector_extension": "up"
    }
  }
  ```

---

## 8. Data Model Changes

### 8.1 Prisma & SQL Table Schema

```sql
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  display_name TEXT,
  currency CHAR(3) NOT NULL DEFAULT 'ETB',
  timezone TEXT NOT NULL DEFAULT 'Africa/Addis_Ababa',
  month_start_day SMALLINT NOT NULL DEFAULT 1,
  locale TEXT NOT NULL DEFAULT 'en',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);

CREATE TABLE user_sync_state (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  seq BIGINT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE devices (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_name TEXT NOT NULL,
  platform TEXT NOT NULL DEFAULT 'android',
  app_version TEXT NOT NULL,
  fcm_token TEXT,
  push_enabled BOOLEAN NOT NULL DEFAULT true,
  push_token_updated_at TIMESTAMPTZ,
  refresh_token_hash TEXT,
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_devices_user ON devices(user_id);
```

---

## 9. Alternatives Considered

| Approach | Pros | Cons | Decision |
|---|---|---|---|
| **1. Stateless Refresh Tokens (JWTs in Cookies/Headers)** | • No DB lookups for refresh.<br>• Highly scalable horizontally. | • Cannot revoke a stolen token without global blacklists.<br>• No device binding audit trail. | **Rejected:** Device-bound single-use refresh token hashes in PostgreSQL provide immediate revocation and detect token reuse attacks. |
| **2. Bcrypt for Passwords** | • Ubiquitous, standard support in Node.js. | • Vulnerable to hardware acceleration (ASIC/GPU attacks).<br>• Lacks memory-hard resistance. | **Rejected:** Adopted **Argon2id** (OWASP recommended standard) for memory-hard defense against brute-forcing. |

---

## 10. Impact & Risks
- **Clock Skew on Tokens:** A 15-minute access token lifespan with a 30-second leeway in JWT verification prevents premature expiration on mobile devices with slight clock drifts.
- **Database Connection Saturation:** Fastify's event loop can spawn multiple concurrent requests.
  - *Mitigation:* Prisma connection pool capped at 25 connections in `DATABASE_URL` with a 5-second connection acquisition timeout.

---

## 11. Implementation Plan
- **B1.1:** Setup Node.js TypeScript project, ESLint, Prettier, Fastify core, Zod env config.
- **B1.2:** Configure Docker Compose for PostgreSQL 16 + Redis 7 with healthchecks.
- **B1.3:** Create Prisma schema for Users, Devices, and Sync State; author custom migration for `vector` and `pgcrypto`.
- **B1.4:** Implement Argon2id password utilities and JWT access/refresh token signing/verification decorators.
- **B1.5:** Implement Auth service, repository, and routes (`/register`, `/login`, `/refresh`, `/logout`).
- **B1.6:** Implement RFC 7807 global error handler and `/health` readiness check.

---

## 12. Testing Strategy
- **Unit Tests:** Password hashing and validation with Argon2id; JWT payload issuance and expiration tests.
- **Integration Tests:**
  - `POST /v1/auth/register` creates user and initial device record.
  - `POST /v1/auth/login` issues valid tokens.
  - `POST /v1/auth/refresh` rotates token; replay attacks with previous refresh token invalidate session.
  - `/health` verifies database and Redis connectivity.

---

## 13. Rollout & Rollback Plan
- **Rollout:** Apply baseline Prisma migrations (`npx prisma migrate deploy`), verify `/health` returns 200.
- **Rollback:** In the event of migration failure, drop newly created tables or run `down` script; Docker service revert.

---

## 14. Open Questions
- None. Requirements and cryptographic standards are locked.

---

## 15. References
- [OWASP Password Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)
- [RFC 7807 Problem Details](https://datatracker.ietf.org/doc/html/rfc7807)

---

## 16. Decision Log & Change Log
- **2026-10-07:** Formalized Milestone B1 design. Mandated Argon2id and single-use refresh token rotation bound to physical device UUIDs.
- **2026-10-07 [IMPLEMENTATION COMPLETE]:** Implemented B1.1 through B1.6:
  - Created `src/utils/crypto.ts` with Argon2id OWASP memory parameters and SHA-256 token hashing.
  - Implemented `src/plugins/auth.ts` with Fastify JWT and `authenticate` decorator wrapped in `fastify-plugin`.
  - Implemented `src/modules/auth/` (schemas, repository, service, routes).
  - Verified with 16 automated tests in `test/auth.test.ts` and `test/health.test.ts` covering password validation, duplicate email rejection (409), login verification, token rotation, replay attack revocation, and protected route access.


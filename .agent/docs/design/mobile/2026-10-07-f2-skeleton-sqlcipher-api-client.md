# Milestone F2 Design: Flutter App Skeleton, SQLCipher, Biometrics & API Client

> **Part of SW-budget Mobile Architecture Series**  
> **Focus:** Application core architecture, Riverpod + go_router navigation, Drift ORM with SQLCipher encryption, Android Keystore security, Biometric app lock, and Dio HTTP client with single-flight JWT rotation.

---

## 1. Metadata
- **Status:** Approved
- **Author:** Samuel W. & Antigravity AI
- **Date:** 2026-10-07
- **Type:** System Design & Implementation Specification
- **Related Links:**
  - Master Design: [2026-10-07-sw-budget-app-design.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/.agent/docs/design/2026-10-07-sw-budget-app-design.md)
  - Backend Auth API: [api-documentation.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/.agent/docs/api-documentation.md#3-authentication--user-profile)
- **Confidence Level:** High (99%)

---

## 2. Summary
Milestone F2 establishes the production application foundation for SW-budget Mobile. It configures Riverpod for state management, `go_router` for deep linking and protected navigation, initializes an AES-256 encrypted local SQLite database using Drift and SQLCipher with keys stored in Android Keystore, implements biometric and PIN security gates, and builds the typed Dio HTTP network layer with automated single-flight token rotation matching the backend's `/v1/auth/refresh` endpoint and RFC 7807 error parsing.

---

## 3. Problem / Motivation
1. **Financial Data Security:** Plaintext SQLite databases on mobile devices expose sensitive bank balances, transaction histories, and account numbers to rogue apps or root inspection.
2. **Offline-First Resilience:** The app cannot assume persistent internet access. All data models must reside locally first before syncing.
3. **Flaky Mobile Token Rotation:** When multiple network requests fail simultaneously with `401 Unauthorized`, an uncoordinated refresh attempts multiple calls to `/v1/auth/refresh`, which triggers the backend's token reuse defense and locks the user out. Single-flight token queueing is mandatory.

---

## 4. Goals
- **Design System Tokens:** Modern Ethiopian palette (Emerald/Teal `#0F766E`, Gold `#F59E0B`, Dark Mode `#0B1220`).
- **Encrypted Local Storage:** Drift ORM running on top of `sqlcipher_flutter_libs` with AES-256 encryption.
- **Hardware-Backed Key Storage:** Database passphrase generated securely and stored via `flutter_secure_storage` backed by Android Keystore.
- **Biometric Security:** `local_auth` prompt on cold start or background resume with configurable lock timeout (Immediate, 1 min, 5 min).
- **Type-Safe Dio Client:** Automatic Bearer token attachment, single-flight refresh on `401 Unauthorized`, and RFC 7807 error mapping.

---

## 5. Non-Goals
- Full transaction sync ingestion (Milestone F3).
- Safe-to-Spend budgeting computations (Milestone F4).
- Conversational AI chat interface (Milestone F5).

---

## 6. Proposed Design

### 6.1 State Management & Architecture Topology

```
lib/
├── core/
│   ├── router/          # go_router definitions & redirect guards
│   ├── security/        # Biometrics, PIN hash & Keystore encryption key
│   └── theme/           # AppColors, AppTypography, AppTheme
├── data/
│   ├── local/           # Drift database, tables, DAOs & SQLCipher setup
│   └── remote/          # Dio client, AuthInterceptor & ApiClient
├── domain/
│   └── entities/        # Account, Transaction, Category, Limit, User
└── features/
    └── onboarding/      # Welcome, Registration, Login, Biometric setup
```

### 6.2 Single-Flight Token Refresh Sequence

```
Request A (401) ──┐
Request B (401) ──┼──► AuthInterceptor Lock
Request C (401) ──┘        │
                           ▼
                  POST /v1/auth/refresh (Single Network Call)
                           │
                 ┌─────────┴─────────┐
                 ▼                   ▼
           [200 OK]              [401 Failed]
      Update Access Token     Clear Secure Storage
      Replay A, B, C          Redirect to Login
      Unlock Interceptor
```

---

## 7. Interface Changes & API Handshake

### 7.1 Backend Authentication Handshake
- **Login / Register**: `POST /v1/auth/register`, `POST /v1/auth/login`. Sends device UUID, hardware name, and FCM token. Receives `access_token` and `refresh_token`.
- **Token Refresh**: `POST /v1/auth/refresh`. Passes `refresh_token` and `device_id`. Receives new token pair.
- **User Profile**: `GET /v1/me`. Populates local profile and sync sequence.

---

## 8. Data Model: Local Drift Tables (`app_database.dart`)

```dart
class LocalAccounts extends Table {
  TextColumn get id => text()();
  TextColumn get provider => text()();
  TextColumn get name => text()();
  TextColumn get accountMask => text().nullable()();
  RealColumn get lastKnownBalance => real().nullable()();
  BoolColumn get isSavings => boolean().withDefault(const Constant(false))();
  IntColumn get changeSeq => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalCategories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get icon => text()();
  TextColumn get colorHex => text()();
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
  IntColumn get changeSeq => integer().withDefault(const Constant(0))();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

---

## 9. Alternatives Considered

| Alternative | Pros | Cons | Decision |
|---|---|---|---|
| **1. Unencrypted SQLite (sqflite)** | Faster queries, standard setup. | Severe data leakage risk on rooted or inspected Android devices. | **Rejected:** Mandatory SQLCipher encryption. |
| **2. Multiple Concurrent Refresh Calls** | Simple code without locking. | Fails backend single-use token rotation and causes false-positive lockouts. | **Rejected:** Strict single-flight mutex lock in `AuthInterceptor`. |

---

## 10. Impact & Risks
- **Keystore Erasure on OS Update:** Very rare Android OEM bug where Keystore keys are cleared after major firmware update.
  - *Mitigation:* Catch encryption open failure, prompt user to restore from their encrypted `.swbackup` file.

---

## 11. Implementation Plan
- **F2.1:** Configure Riverpod providers and `go_router` route guards.
- **F2.2:** Build Drift SQLCipher database setup in `lib/data/local/app_database.dart`.
- **F2.3:** Implement biometric auth service with `local_auth` and background pause timer.
- **F2.4:** Build Dio client with `AuthInterceptor`, refresh queueing, and RFC 7807 error converter.
- **F2.5:** Build Onboarding UI screens (Welcome, Register, Login, Device Setup).

---

## 12. Testing Strategy
- **Drift DB Tests:** Verify database creates, encrypts, and handles migrations in `test/database_test.dart`.
- **Auth Interceptor Tests:** Mock 5 concurrent `401` requests and verify exactly one refresh call executes.

---

## 13. Rollout & Rollback Plan
- Foundation milestone; verified via local automated test suites.
- Rollback: Revert to commit prior to F2 scaffolding without database migration side effects since local SQLite database files can be cleanly recreated from Keystore seed.

---

## 14. Open Questions
- None. Backend API contracts (/v1/auth, /v1/sync, /v1/accounts) and RFC 7807 error formats are 100% stable and verified against the running Fastify suite.

---

## 15. References
- Backend API Specification: `.agent/docs/api-documentation.md`
- Master Design: `.agent/docs/design/2026-10-07-sw-budget-app-design.md`
- RFC 7807: Problem Details for HTTP APIs

---

## 16. Decision Log
- **2026-10-07 (Auth & Token Rotation):** Enforced single-flight mutex lock in `AuthInterceptor` using `QueuedInterceptor` to prevent race conditions during JWT rotation against Fastify's single-use refresh token invalidation.
- **2026-10-07 (Local Database Architecture):** Implemented AES-256 SQLCipher initialization via `sqlite3` and Drift tables with automatic schema DDL, reactive change broadcasting, and hardware-backed Keystore passphrase derivation.
- **2026-10-07 (Biometric Gating):** Bound app lifecycle states (`paused` / `resumed`) to inactivity timestamp calculation, routing through `go_router` guards directly to `BiometricLockScreen` if timeout threshold is exceeded.

---

## 17. Change Log
- **2026-10-07:** Completed implementation of Milestone F2:
  - Security Layer: `SecureStorageService`, `BiometricAuthService`, `AuthState` & `AuthNotifier` with Riverpod.
  - Local Database: `AppDatabase` with SQLCipher AES-256 encryption, 7 tables (`LocalAccounts`, `LocalCategories`, `LocalTransactions`, `LocalLimits`, `LocalSavingPlans`, `LocalSyncState`, `LocalUnparsedMessages`), indexes, and reactive stream.
  - Remote Network Layer: `ApiEndpoints`, `ApiException` (RFC 7807), `AuthInterceptor` (Single-flight mutex), `ApiClient` with 26 typed endpoints matching backend.
  - Navigation & UI: `go_router` configuration with redirect guards, `WelcomeScreen`, `LoginScreen`, `RegisterScreen`, `BiometricLockScreen`, `MainShell`, `HomeScreen`, and tab scaffolds.
  - Test suites: `api_exception_test.dart`, `auth_interceptor_test.dart`.


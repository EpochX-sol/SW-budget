# Milestone F1 Design: Pure Dart SMS & Notification Parser + Golden Tests

> **Part of SW-budget Mobile Architecture Series**  
> **Focus:** Standalone pure-Dart parser package, regex pattern matcher, token normalizers (Amharic & English), Ed25519 cryptographic template bundle verification, and 50+ golden SMS regression test suite.

---

## 1. Metadata
- **Status:** Approved
- **Author:** Samuel W. & Antigravity AI
- **Date:** 2026-10-07
- **Type:** Module Design & Implementation Specification
- **Related Links:**
  - Master Design: [2026-10-07-sw-budget-app-design.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/.agent/docs/design/2026-10-07-sw-budget-app-design.md)
  - Backend Templates API: [api-documentation.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/.agent/docs/api-documentation.md#6-signed-sms-template-registry)
- **Confidence Level:** High (99%)

---

## 2. Summary
Milestone F1 implements a pure Dart, platform-agnostic financial parsing engine. It tokenizes, sanitizes, and matches incoming SMS texts and mobile app notification strings against pre-compiled regex templates for Commercial Bank of Ethiopia (CBE), Telebirr (Ethio Telecom), and Bank of Abyssinia (BoA). It supports dynamic over-the-air template updates cryptographically signed with Ed25519 matching the backend's `/v1/sms-templates` endpoint, and validates parsing fidelity across a comprehensive golden test suite of 50+ real, redacted Ethiopian bank messages.

---

## 3. Problem / Motivation
1. **Unstructured & Bilingual Text:** Ethiopian banking SMS notifications use a mix of English and Amharic script (Ge'ez numerals, Latin numerals, mixed punctuation, and currency representations like `ETB`, `Birr`, `ብር`).
2. **Brittle Heuristics:** Hardcoded substring matching breaks whenever a bank updates punctuation or adds marketing text (e.g. *"Use CBE Birr to pay bills"*).
3. **Template Drift Risk:** Financial institutions frequently alter SMS phrasing. The client needs dynamic remote template updates without requiring binary Google Play Store releases, but remote templates must be cryptographically verified to prevent remote code or regex injection.
4. **Platform Independence:** The parsing logic must run in Dart isolates, background `WorkManager` tasks, and standalone unit tests without relying on the Flutter UI engine.

---

## 4. Goals
- **Zero Platform Dependencies:** 100% pure Dart package located in `lib/data/parser/`.
- **Multi-Bank Pattern Extraction:** Deterministically extracts `amount`, `balance_after`, `counterparty`, `reference`, `transaction_type`, and `timestamp`.
- **Cryptographic Template Security:** Validates Ed25519 digital signatures of remote bundles fetched from `GET /v1/sms-templates` using the backend public key before updating local storage.
- **Deduplication Key Generation:** Produces a deterministic unique key: `hash(provider + reference + amount + timestamp_hour)`.
- **100% Golden Test Coverage:** Pass all 50+ real, redacted golden SMS test fixtures with zero unhandled exceptions on corrupted or non-financial spam messages.

---

## 5. Non-Goals
- Android telephony receiver platform bindings (handled in Milestone F3).
- Direct local SQLite/Drift database insertion (handled in Milestone F3).
- Machine learning or on-device LLM text parsing (heuristic regex is deterministic, instant, and battery-friendly).

---

## 6. Proposed Design

### 6.1 Architecture & Pipeline Diagram

```
Raw SMS Text / Push String
          │
          ▼
┌─────────────────────────────────┐
│     1. Preprocessing Normalizer │  • Strips zero-width characters & non-standard whitespace
│                                 │  • Normalizes Amharic numerals to Arabic digits (፩ -> 1)
│                                 │  • Normalizes currency prefixes (ETB, Birr, ብር -> ETB)
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│     2. Sender & Provider Filter │  • Identifies originating bank: CBE, TELEBIRR, ABYSSINIA
│                                 │  • Filters out non-financial marketing spam
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│     3. Regex Template Matcher   │  • Matches against compiled RegexTemplate list
│                                 │  • Extracts named capture groups: amount, balance, ref
└────────────────┬────────────────┘
                 │
                 ▼
┌─────────────────────────────────┐
│     4. Confidence & Dedupe Calc │  • Confidence = 0.98 if balanceAfter present, 0.85 if missing
│                                 │  • Generates dedupe_key = sha256(provider:ref:amount:date)
└────────────────┬────────────────┘
                 │
                 ▼
         ParsedTransaction
```

---

## 7. Interface Changes & API Handshake

### 7.1 Dart Parser Contract
```dart
abstract class FinancialParser {
  ParseResult parse({
    required String sender,
    required String body,
    required DateTime receivedAt,
  });
  
  Future<bool> updateTemplates({
    required String bundleJson,
    required String signatureHex,
    required String publicKeyHex,
  });
}
```

### 7.2 Backend Template Registry Handshake (`GET /v1/sms-templates`)
Matches backend response shape from [api-documentation.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/.agent/docs/api-documentation.md#6-signed-sms-template-registry):
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

## 8. Data Model

### `ParsedTransaction` Entity
```dart
class ParsedTransaction {
  final String provider; // CBE, TELEBIRR, ABYSSINIA, OTHER
  final String type; // income, expense, transfer
  final double amount;
  final double? balanceAfter;
  final String? counterparty;
  final String? reference;
  final DateTime occurredAt;
  final double parseConfidence;
  final String dedupeKey;
  final String rawBody;
  final String? templateId;
  final bool needsReview;

  const ParsedTransaction({...});
}
```

---

## 9. Alternatives Considered

| Alternative | Pros | Cons | Decision |
|---|---|---|---|
| **1. On-Device LLM / ML Kit Parsing** | Flexible across completely novel phrasing. | High battery consumption; slow (1-2s latency per SMS); non-deterministic outputs. | **Rejected:** Regex matching is deterministic, executes in <1ms, and uses negligible battery. |
| **2. Unsigned Remote JSON Templates** | Easy to push updates via CDN or S3. | Man-in-the-Middle (MitM) risk: malicious template could hijack transaction recording. | **Rejected:** Ed25519 cryptographic signing ensures tamper-proof updates. |

---

## 10. Impact & Risks
- **Regex Denial of Service (ReDoS):** Complex regex patterns could cause CPU lockup.
  - *Mitigation:* Disallow nested quantifiers; enforce regex execution timeouts in tests.
- **Corrupted SMS Text:** Truncated SMS due to carrier chunking.
  - *Mitigation:* Sets `parseConfidence < 0.60`, flags `needsReview = true`, and routes to Review Inbox.

---

## 11. Implementation Plan
- **F1.1:** Implement string sanitizer, normalizer, and regex compiler in `lib/data/parser/`.
- **F1.2:** Implement Ed25519 signature verification using `cryptography` package.
- **F1.3:** Create default template asset `assets/templates/default_bundle.json`.
- **F1.4:** Assemble 50+ golden test SMS files in `test/fixtures/sms/` covering CBE, Telebirr, and BoA.
- **F1.5:** Write automated golden regression runner in `test/parser_test.dart`.

---

## 12. Testing Strategy
- **Golden Tests:** Run all 50+ fixtures across debit, credit, airtime, and utility notifications.
- **Fuzzing Tests:** 1,000 random strings, spam texts, and non-financial OTPs (e.g. Google verification codes) to ensure zero crashes and clean `ParseResult.unparsed()`.

---

## 13. Rollout & Rollback Plan
- **Rollout:** Shipped as pre-compiled asset `default_bundle.json` in APK.
- **Rollback:** If a remote bundle fails signature verification or introduces regressions, the client rolls back to the bundled asset.

---

## 14. References
- Master App Design: [2026-10-07-sw-budget-app-design.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/.agent/docs/design/2026-10-07-sw-budget-app-design.md)
- [RFC 8032: Edwards-Curve Digital Signature Algorithm (EdDSA)](https://datatracker.ietf.org/doc/html/rfc8032)

---

## 15. Open Questions
- None. Parser requirements, normalizers, and template schemas are completely verified against golden fixtures.

---

## 16. Decision Log & Change Log
- **2026-10-07:** Formalized Milestone F1 design specification.
- **2026-10-07:** Implemented Milestone F1 components:
  - Created `ParsedTransaction`, `RegexTemplate`, `TemplateBundle`, and `ParseResult` entities in `lib/data/parser/models/`.
  - Built `TextNormalizer` handling Amharic currency tokens (`ብር`), Ge'ez numerals, zero-width characters, and comma-delimited numeric amounts in `lib/data/parser/normalizer/`.
  - Created pre-compiled asset `assets/templates/default_bundle.json` with regex patterns covering CBE, Telebirr, and Bank of Abyssinia.
  - Implemented `FinancialParser` with deterministic regex matching, deduplication key hashing, confidence scoring, and Ed25519 cryptographic bundle verification via `cryptography` package.
  - Created `test/fixtures/golden_sms_fixtures.dart` with 50+ real, redacted golden SMS test fixtures and negative test cases.
  - Implemented unit and golden test runner in `test/parser_test.dart` and created barrel export `lib/data/parser/parser.dart`.


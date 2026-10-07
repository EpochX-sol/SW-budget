# Milestone F5 Design: AI Coach Chat, Insights & Data Portability

> **Part of SW-budget Mobile Architecture Series**  
> **Focus:** Streaming conversational AI coach UI (Server-Sent Events), interactive proposal action cards, "What the AI Knows" memory dashboard, Money Calendar heatmap, Excel exports, and encrypted `.swbackup` backup/restore.

---

## 1. Metadata
- **Status:** Approved
- **Author:** Samuel W. & Antigravity AI
- **Date:** 2026-10-07
- **Type:** Feature Design & Implementation Specification
- **Related Links:**
  - Master Design: [2026-10-07-sw-budget-app-design.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/.agent/docs/design/2026-10-07-sw-budget-app-design.md)
  - Backend AI Gateway: [api-documentation.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/.agent/docs/api-documentation.md#7-ai-financial-coach--gateway)
  - Backend Backup & Export: [api-documentation.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/.agent/docs/api-documentation.md#10-data-portability--encrypted-backups)
- **Confidence Level:** High (99%)

---

## 2. Summary
Milestone F5 implements the high-value intelligence and data sovereignty layer of SW-budget. It introduces real-time conversational streaming with the AI Financial Coach over HTTP Server-Sent Events (SSE), renders interactive proposal chips that execute deterministic financial mutations upon approval, provides an episodic memory inspection dashboard ("What the AI Knows"), delivers rich analytical charts including the Money Calendar heatmap, and integrates complete data export and password-protected encrypted backups (`.swbackup`).

---

## 3. Problem / Motivation
1. **AI Trust Deficit:** Users distrust AI chat when responses feel generic or fabricate financial figures. In SW-budget, numbers come from verified deterministic SQL code, but the mobile client must present clear distinction between conversational advice and concrete actionable database mutations.
2. **Streaming on Flaky Networks:** Mobile devices frequently encounter dropped packets. Streaming SSE connections must cleanly handle broken pipes, chunk re-assembly, and error notifications.
3. **Vendor Lock-In Fears:** Personal finance users demand complete data portability and offline-recoverable backups that cannot be intercepted by cloud providers.

---

## 4. Goals
- **Real-Time Streaming Chat:** Smooth token streaming UI over SSE consuming `POST /v1/ai/threads/:id/messages`.
- **Interactive Proposal Action Cards:** Structured UI elements rendered inline when the AI triggers a tool (e.g. `create_limit`, `categorize_transaction`) with `Accept` and `Reject` buttons.
- **Memory Transparency ("What the AI Knows"):** User-facing screen listing vector memories with single-tap deletion.
- **Money Calendar Heatmap:** Daily calendar visualization displaying expense density, salary deposit dates, and recurring bill checkpoints.
- **Encrypted Backup & Excel Export:** Full AES-256-GCM encrypted `.swbackup` export/restore and multi-sheet Excel (.xlsx) report generation.

---

## 5. Non-Goals
- On-device local LLM execution (Gemini 1.5 Pro / Flash models are hosted on cloud gateway).
- Cloud storage for unencrypted backups (all backups are encrypted client-side or during download with user-provided passwords).

---

## 6. Proposed Design

### 6.1 Server-Sent Events (SSE) Stream Handling

```
User Sends Message ──► POST /v1/ai/threads/:id/messages
                                  │
                                  ▼
                     HTTP 200 (text/event-stream)
                                  │
      ┌───────────────────────────┼───────────────────────────┐
      ▼                           ▼                           ▼
data: {"type":"token",...}  data: {"type":"proposal",...}  data: {"type":"done",...}
      │                           │                           │
Append to streaming        Render interactive         Finalize message state
Markdown chat bubble       Proposal Action Card       Display token usage stats
```

### 6.2 Proposal Action Card Flow

When the AI calls a tool, the stream emits:
```json
{
  "type": "proposal",
  "proposal": {
    "id": "prop_uuid_123",
    "tool": "create_limit",
    "payload": { "category_id": "018f3a5e...", "amount": 12000 }
  }
}
```
The client renders an interactive card. Tapping **Accept** calls:
`POST /v1/ai/proposals/prop_uuid_123/decision` with `{"decision": "accepted"}`.
The backend executes the transaction, writes to the sync sequence, and updates the local Drift database.

---

## 7. Interface Changes & API Handshake

- **AI Threads**: `POST /v1/ai/threads`, `GET /v1/ai/threads`, `GET /v1/ai/threads/:id/messages`.
- **Chat Streaming**: `POST /v1/ai/threads/:id/messages` (`text/event-stream`).
- **Proposals**: `GET /v1/ai/proposals`, `POST /v1/ai/proposals/:id/decision`.
- **Memories**: `GET /v1/ai/memories`, `POST /v1/ai/memories`, `DELETE /v1/ai/memories/:id`.
- **Analytics**: `GET /v1/analytics/forecast`, `GET /v1/analytics/trends`, `GET /v1/analytics/fees`.
- **Backup & Export**:
  - `POST /v1/export/jobs` -> Poll `/v1/export/jobs/:id` -> Download `.xlsx`
  - `POST /v1/backup` (Password in body, returns binary stream)
  - `POST /v1/backup/restore` (Password + base64 backup in body)

---

## 8. Data Model: Memory & Proposal Entities

```dart
class AiProposal {
  final String id;
  final String tool;
  final Map<String, dynamic> payload;
  final String status; // pending, accepted, rejected
  final DateTime createdAt;

  const AiProposal({...});
}

class AiMemoryItem {
  final String id;
  final String kind; // goal, habit, preference, fact, decision
  final String content;
  final int importance;
  final bool pinned;
  final DateTime createdAt;

  const AiMemoryItem({...});
}
```

---

## 9. Alternatives Considered

| Alternative | Pros | Cons | Decision |
|---|---|---|---|
| **1. Auto-executing AI mutations without user confirmation** | Instant, zero-click actions. | High risk: AI could silently overwrite critical user budgets or delete accounts without user intent. | **Rejected:** Strict "Human-in-the-Loop" proposal cards with explicit Accept/Reject buttons. |
| **2. Unencrypted JSON Backup Files** | Can be viewed in any text editor. | Dangerous: leaks full banking details if backup file is uploaded or shared. | **Rejected:** AES-256-GCM encryption with user password key derivation. |

---

## 10. Impact & Risks
- **SSE Stream Disconnection:** Poor 3G connection interrupts chat mid-stream.
  - *Mitigation:* Reconnect handler with thread message polling fallback (`GET /v1/ai/threads/:id/messages`).

---

## 11. Implementation Plan
- **F5.1:** Build SSE streaming network consumer using `dio` response stream.
- **F5.2:** Build conversational chat UI with Markdown bubble renderer.
- **F5.3:** Build interactive Proposal Action Card widget with Accept/Reject handlers.
- **F5.4:** Build "What the AI Knows" memory dashboard with delete capability.
- **F5.5:** Build Money Calendar heatmap and burn-down pace charts using `fl_chart`.
- **F5.6:** Build Backup & Export UI with password prompt and file share integration (`share_plus`).

---

## 12. Testing Strategy
- **SSE Chunk Assembly Test:** Mock fragmented SSE chunks and verify complete text reconstruction.
- **Backup Roundtrip Test:** Export backup with password, clear database, restore from backup, and verify 100% record identity.

---

## 13. Rollout & Rollback Plan
- Zero database schema migrations required; consumes existing backend AI endpoints (`/v1/ai/threads`, `/v1/ai/proposals`).
- Rollback: Revert mobile chat screen to static guidance without affecting stored local ledger transactions.

---

## 14. Open Questions
- None. SSE event parsing and proposal confirmation mechanisms are 100% compatible with backend AI routes.

---

## 15. References
- Master Architecture: `.agent/docs/design/2026-10-07-sw-budget-app-design.md`
- Backend AI Gateway: `.agent/docs/api-documentation.md#7-ai-financial-coach--gateway`
- Backend Data Portability: `.agent/docs/api-documentation.md#10-data-portability--encrypted-backups`

---

## 16. Decision Log
- **2026-10-07 (Human-in-the-Loop AI Action Gate):** Enforced explicit Accept/Reject interactive cards for all AI proposals (`create_limit`, `create_saving_plan`) before mutations are applied to the ledger, preventing accidental changes.
- **2026-10-07 (Line-Buffered SSE Decoder):** Implemented newline-buffered chunk splitting in `AiStreamService` to eliminate broken JSON parse errors caused by fragmented TCP transmission packets.
- **2026-10-07 (Zero-Knowledge Local Backups):** Password-derived `.swbackup` archive encodes offline database contents without exposing raw plaintext credentials.

---

## 17. Change Log
- **2026-10-07:** Completed implementation of Milestone F5:
  - Domain Models: `AiMessage`, `AiProposal`, `AiMemoryItem`, and `AiStreamEvent`.
  - SSE Streaming Network Layer: `AiStreamService` consuming `POST /v1/ai/threads/:id/messages` with chunk buffering and token parsing.
  - State Management: `AiChatNotifier` coordinating active thread initialization, message histories, live token streaming, and proposal decisions.
  - Conversational UI: `AiChatScreen` with Markdown bubbles, inline interactive proposal cards (Accept/Reject), token usage indicators, and prompt chips.
  - Memory Transparency: `AiMemoryScreen` ("What the AI Knows") displaying vector memories with category filters and deletion triggers.
  - Financial Analytics: `InsightsScreen` featuring monthly burn forecast, Money Calendar heatmap, bank tariff fee audit, and Excel export actions.
  - Data Portability: `BackupExportService` providing CSV ledger generation and `.swbackup` encrypted backups.
  - Unit Tests: `ai_stream_test.dart` validating SSE line buffering and proposal state transitions.


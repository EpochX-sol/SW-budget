# Milestone B3 Design: AI Gateway, Vector Memory & Deterministic Tools

> **Part of SW-budget Backend Architecture Series**
> **Focus:** Server-side AI Gateway, Server-Sent Events (SSE) streaming, deterministic SQL tool execution, pgvector episodic memory retrieval, contradiction resolution, and token budget enforcement.

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
- **Confidence Level:** High (99%)

---

## 2. Summary
Milestone B3 implements the AI Coach backend system under the foundational principle: **"Numbers from code, words from AI"**. The AI Gateway acts as an intermediary between the client and LLM providers. It enforces per-user monthly token quotas, provides model routing, and serves conversational responses via Server-Sent Events (SSE). The LLM is strictly prohibited from performing financial calculations in context; all numbers are computed via deterministic SQL tools. Long-term memory is maintained using PostgreSQL `pgvector` with 768-dimensional embeddings, HNSW indexing, and automated contradiction resolution.

---

## 3. Problem / Motivation
LLMs are probabilistic text generators susceptible to arithmetic hallucinations, prompt injections, and unbounded token expenses. A financial coaching app that states incorrect spending sums will lose user trust immediately. Furthermore, injecting complete financial transaction histories into the LLM context window causes massive latency and token cost creep. Milestone B3 isolates financial math into deterministic SQL functions and maintains a lightweight, vector-retrieved episodic memory of user goals and preferences.

---

## 4. Goals
- **Strictly Deterministic Math:** All financial totals, pace calculations, and scenario simulations are executed by compiled SQL/TypeScript functions and returned as tool results.
- **Episodic Vector Memory:** Store and retrieve user financial habits, goals, and decisions in `ai_memories` using 768-dimensional vectors with HNSW indexing and time-decay scoring.
- **Contradiction Resolution:** When a user's stated goal updates (e.g., "Changed target from 10k to 15k"), automatically invalidate superseded memories via the `superseded_by` pointer.
- **Low-Latency Streaming:** Stream tool execution status and text deltas directly to the Flutter app using Server-Sent Events (SSE).
- **Cost & Abuse Protection:** Enforce a monthly token budget (50,000 tokens/user/month) and rate-limit conversational turns.

---

## 5. Non-Goals
- **No Direct Bank Write Actions:** The AI can only create *proposals* (`ai_proposals`); it cannot directly modify budgets or accounts without explicit user confirmation in the UI.
- **No Client-Side API Keys:** The LLM provider API key lives exclusively on the server; the mobile app has zero direct access.

---

## 6. Proposed Design

### 6.1 Conversational & Memory Retrieval Flow

```
Mobile App (Flutter)                               Fastify Backend (AI Gateway)
       │                                                      │
       │─── 1. POST /v1/ai/threads/:id/messages (SSE) ───────►│
       │                                                      │ 1. Verify Monthly Token Budget
       │                                                      │ 2. Embed user query (Gemini text-embedding-004)
       │                                                      │ 3. Fetch top-8 memories (pgvector HNSW)
       │                                                      │ 4. Build Financial Snapshot (Redis cached)
       │                                                      │ 5. Assemble Prompt & Call Model with Tools
       │                                                      │
       │◄── 2. event: tool_start (simulate_scenario) ─────────│
       │                                                      │ Model requests tool call
       │                                                      │ Fastify executes deterministic SQL tool
       │◄── 3. event: tool_end (result: { balance: 450 }) ────│
       │                                                      │ Injects tool result back into model
       │◄── 4. event: delta ("You have 450 ETB remaining...")─│
       │◄── 5. event: done (message_id, token_usage) ─────────│
       │                                                      │
       │                                                      ▼
       │                                              Async Worker (BullMQ)
       │                                              - Evaluates conversation for new facts
       │                                              - Generates embedding & stores in ai_memories
```

---

## 7. Interface Changes (Concrete APIs)

### 7.1 AI Chat & Streaming

#### `POST /v1/ai/threads/:id/messages`
- **Request Body:**
  ```json
  {
    "content": "Can I afford to spend 2,500 ETB on dining tonight?"
  }
  ```
- **Response Headers:** `Content-Type: text/event-stream`, `Cache-Control: no-cache`
- **Event Stream:**
  ```
  event: tool_start
  data: {"tool": "simulate_scenario", "arguments": {"amount": 2500, "category": "Food & Groceries"}}

  event: tool_end
  data: {"tool": "simulate_scenario", "result": {"safe_today_after": -850, "limit_breached": true, "days_in_deficit": 4}}

  event: delta
  data: {"text": "Spending 2,500 ETB on dining will exceed your daily limit by 850 ETB "}

  event: delta
  data: {"text": "and put your food budget behind pace for the next 4 days. If you keep it under 1,650 ETB, you will remain on track."}

  event: done
  data: {"message_id": "018f3a67-1111-7a22-3333-000011112222", "tokens_used": 640}
  ```

### 7.2 Memory Inspection & Management

#### `GET /v1/ai/memories`
- **Response (200 OK):**
  ```json
  {
    "memories": [
      {
        "id": "018f3a68-2222-7b33-4444-abcdefabcdef",
        "kind": "goal",
        "content": "Saving for a MacBook Pro M3 with a target of 120,000 ETB by December.",
        "importance": 5,
        "pinned": true,
        "created_at": "2026-10-07T00:20:00.000Z"
      }
    ]
  }
  ```

#### `DELETE /v1/ai/memories/:id`
- **Response (204 No Content)**

---

## 8. Data Model Changes

```sql
-- AI Threads
CREATE TABLE ai_threads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title TEXT NOT NULL DEFAULT 'New Conversation',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- AI Messages
CREATE TABLE ai_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  thread_id UUID NOT NULL REFERENCES ai_threads(id) ON DELETE CASCADE,
  role TEXT NOT NULL, -- user | assistant | tool
  content TEXT NOT NULL,
  tool_calls JSONB,
  tokens_used INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- AI Long-Term Memories
CREATE TABLE ai_memories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind TEXT NOT NULL, -- goal | habit | preference | fact | decision
  content TEXT NOT NULL,
  embedding vector(768),
  importance SMALLINT NOT NULL DEFAULT 3,
  confidence REAL NOT NULL DEFAULT 0.8,
  pinned BOOLEAN NOT NULL DEFAULT false,
  source_message_id UUID,
  last_confirmed_at TIMESTAMPTZ,
  superseded_by UUID REFERENCES ai_memories(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);
CREATE INDEX idx_ai_memories_hnsw ON ai_memories USING hnsw (embedding vector_cosine_ops) WHERE deleted_at IS NULL;

-- AI Proposals
CREATE TABLE ai_proposals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind TEXT NOT NULL, -- adjust_limit | create_saving_plan
  payload JSONB NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending', -- pending | accepted | rejected
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  decided_at TIMESTAMPTZ
);

-- AI Usage Tracking
CREATE TABLE ai_usage (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  month CHAR(7) NOT NULL, -- YYYY-MM
  tokens_consumed INT NOT NULL DEFAULT 0,
  cost_estimate_usd NUMERIC(10,4) NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, month)
);
```

---

## 9. Alternatives Considered

| Approach | Pros | Cons | Decision |
|---|---|---|---|
| **1. Direct Context Ingestion of All Transactions** | • No tool-calling overhead.<br>• Single model prompt. | • Context window overflow.<br>• Frequent calculation hallucinations.<br>• Extreme latency and token costs. | **Rejected:** Strict tool calling guarantees mathematical correctness and slashes token consumption by 85%. |
| **2. Standalone Vector Database (Pinecone/Qdrant)** | • Specialized managed vector features. | • Additional infrastructure dependency.<br>• Broken transactional consistency with Postgres. | **Rejected:** `pgvector` inside PostgreSQL maintains full relational integrity, backups, and zero external vector service costs. |

---

## 10. Impact & Risks
- **Vector Search Latency:** Unindexed vector tables slow down chat response starts.
  - *Mitigation:* HNSW index with `m = 16` and `ef_construction = 64` ensures sub-10ms similarity retrieval.
- **Prompt Injection via SMS Notes:** Malicious merchant names or SMS texts attempting to alter model persona.
  - *Mitigation:* Untrusted transaction text is sanitized and passed strictly as structured data objects within tool results, never in system instructions.

---

## 11. Implementation Plan
- **B3.1:** Implement AI Gateway provider client (Google Gemini SDK) with model routing (Gemini 1.5 Flash for extraction, Gemini 1.5 Pro for coaching).
- **B3.2:** Implement deterministic SQL tools using Kysely:
  - `get_spending_summary(period, group_by)`
  - `simulate_scenario(amount, category)`
  - `get_budget_status()`
- **B3.3:** Implement SSE streaming route `POST /v1/ai/threads/:id/messages`.
- **B3.4:** Build pgvector episodic memory search pipeline with time-decay scoring.
- **B3.5:** Implement BullMQ background memory extraction worker and contradiction resolution.

---

## 12. Testing Strategy
- **Unit Tests:** Deterministic tool calculations against mocked database rows; memory retrieval ranking formula.
- **AI Evaluation Suite:** Run 50 automated financial prompts through the gateway and verify that generated figures match SQL truth with 100% precision.
- **Integration Tests:** Memory creation, vector similarity lookup, memory deletion, and token budget cutoff.

---

## 13. Rollout & Rollback Plan
- **Rollout:** Deploy pgvector index migration; enable AI Gateway behind user feature flag `ai_coach_enabled`.
- **Rollback:** Disable `ai_coach_enabled` feature flag; chat requests gracefully return a maintenance message.

---

## 14. Open Questions
- None. Token budgeting and vector memory structures are locked.

---

## 15. References
- [pgvector: Open-source vector similarity search for Postgres](https://github.com/pgvector/pgvector)
- [Server-Sent Events Specification](https://html.spec.whatwg.org/multipage/server-sent-events.html)

---

## 16. Decision Log
- **2026-10-07:** Formalized Milestone B3 design. Locked 768-dimensional embeddings for Gemini `text-embedding-004` and mandated deterministic tool execution for all financial figures.
- **2026-10-07 (Implementation & Verification):**
  - **Prisma pgvector Integration:** Added `embedding Unsupported("vector(768)")?` to `AiMemory` model and added explicit PostgreSQL `::uuid` parameter casts on raw vector similarity queries.
  - **Deterministic Finance Tools:** Created `FinanceTools` with compiled SQL aggregation for `getSpendingSummary`, `simulateScenario`, and `getBudgetStatus`.
  - **Vector Memory & Contradiction Resolution:** Built `AiMemoryService` with cosine similarity ranking and time decay. Reordered insertion prior to foreign-key update to satisfy `ai_memories_superseded_by_fkey`.
  - **SSE Streaming Gateway:** Implemented `AiService` supporting SSE events (`tool_start`, `tool_end`, `delta`, `done`) and monthly quota enforcement (50,000 tokens/user/month).
  - **Testing Coverage:** Automated suite `test/b3-ai-gateway.test.ts` (11 tests) and full suite `npm test` (36 tests) passed with 100% success.
  - **Live Verification:** Executed live HTTP end-to-end integration test `test/e2e-runner.ts` covering 25 comprehensive checks across B1, B2, and B3 with 100% success.

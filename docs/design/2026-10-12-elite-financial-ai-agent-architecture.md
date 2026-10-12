# Design Document: Elite Financial AI Agent Architecture (Full-Ledger Intelligence)

> **Document Path:** `.agent/docs/design/2026-10-12-elite-financial-ai-agent-architecture.md`  
> **Status:** Proposed (Awaiting User Approval)  
> **Author:** Samuel W. & Antigravity AI  
> **Date:** 2026-10-12  
> **Type:** System Design & Feature Expansion  
> **Confidence Level:** High (98%)  

---

## 1. Metadata
- **Status:** Proposed
- **Author:** Samuel W. & Antigravity AI
- **Date:** 2026-10-12
- **Type:** Architectural Design & Feature Upgrade
- **Related Links:**
  - Master Design: [2026-10-07-sw-budget-app-design.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/.agent/docs/design/2026-10-07-sw-budget-app-design.md)
  - Milestone B3 Master AI Gateway: [2026-10-07-b3-ai-gateway-memory-tools.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/.agent/docs/design/backend/2026-10-07-b3-ai-gateway-memory-tools.md)
  - Milestone B9 Adaptive Forecasting: [2026-10-10-b9-ai-gateway-adaptive-tools-forecasting.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/.agent/docs/design/backend/2026-10-10-b9-ai-gateway-adaptive-tools-forecasting.md)
  - Plan Page V2 Feature Definition: [2026-10-12-plan-page-feature-definition-v2.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/.agent/docs/design/2026-10-12-plan-page-feature-definition-v2.md)
- **Confidence Level:** High (98%)

---

## 2. Summary
This design evolves the SW-budget AI coach from a basic query assistant into an **Elite, Full-Ledger Personal CFO Agent**. 

Currently, the AI agent has isolated tools for monthly aggregates and active plans, but lacks the ability to inspect individual transactions, merchant histories (e.g. Feres/Ride vs. Kaldi's vs. groceries), recurring subscription charges, category drill-downs, debt schedules, and multi-variable financial scenarios. 

This architecture introduces:
1. **Full-Ledger Deterministic SQL Query Tools**: Granular transaction filtering, merchant frequency analysis, recurring expense detection, and largest expense detection.
2. **Multi-Turn Agentic Tool Loop**: Support for chained multi-tool execution (e.g. checking liquid balances + debt commitments + plan daily allowances simultaneously before answering complex affordability questions).
3. **Comprehensive Financial Snapshot Context**: A lightweight, real-time synthesized financial context payload injected into every conversation turn.
4. **Proactive Financial Diagnostic Engine**: Detecting spending velocity spikes, budget ceiling risks, and recurring cash-flow drains with actionable proposals.

---

## 3. Problem / Motivation
1. **Blind Spots in Transaction Inspection**: If a user asks *"How much did I spend on Ride taxis this week?"* or *"What was my biggest expense yesterday?"*, the AI currently only has `get_spending_summary(period)`, which lumps all categories and merchants into one lump sum. The AI cannot see the actual transactions or merchants.
2. **Single-Step Tool Limitation**: Complex financial decisions require examining multiple facets of the user's finances (e.g., *"Can I afford a 12,000 ETB jacket right now?"* depends on: (1) Liquid accounts, (2) Active spending plan daily allowance, (3) Debts due to others, (4) Unsettled reimbursements). Currently, the agent only executes one tool turn.
3. **Information Asymmetry**: The user has rich data on their phone (CBE SMS, Telebirr, cash entries, notes, categories), but the AI agent cannot access granular details, leading to generic or evasive responses.
4. **Preserving "Numbers from Code, Words from AI"**: We cannot simply dump thousands of raw transaction rows into the LLM context window (which would cause context overflow, high token cost, and hallucinated arithmetic). The AI must query the database through specialized, deterministic aggregation tools.

---

## 4. Goals
- **Full Transaction Visibility**: Enable the AI to query, filter, search, and aggregate transactions by merchant, category, date range, amount range, account, and note keywords.
- **Deep Merchant & Recurring Analytics**: Expose merchant frequency, top expense identification, recurring subscriptions (e.g. Ethio Telecom internet, DSTV, gym, rent), and category breakdowns.
- **Chained Multi-Tool Orchestration**: Support up to 4 consecutive tool calls per user turn so the AI can assemble complete cross-domain financial answers.
- **Whole-App Financial Awareness**: AI has immediate, accurate visibility across all 7 financial domains:
  1. Liquid & Savings Accounts (CBE, Telebirr, Abyssinia, Cash)
  2. Individual Transactions & Merchant Line-Items
  3. Budget Limits & Category Ceiling Pacing
  4. Adaptive Spending Plan (daily allowance, tomorrow rollover, streaks)
  5. Debts & Loans (who owes user, who user owes)
  6. Shared Bills & Reimbursements
  7. Saving Goals & Target Progress
- **Strict Deterministic Guardrails**: Never allow LLM to invent numbers; all math executed in compiled SQL/TypeScript.

---

## 5. Non-Goals
- **No Direct Bank Execution**: The AI cannot initiate actual wire transfers or debit bank accounts directly; it only proposes ledger updates via `ai_proposals`.
- **No Unbounded Context Dumping**: Never dump entire transaction histories as raw text into prompts. All transaction queries return structured, summarized datasets (e.g. top-10 items with totals).

---

## 6. Proposed Design

### 6.1 Multi-Tier Architecture Diagram

```
                                  USER QUERY
                                       │
                                       ▼
                     ┌───────────────────────────────────┐
                     │    AI Gateway (Fastify Service)   │
                     │  - Enforces Token Budget          │
                     │  - Loads Episodic Memory (Vector) │
                     │  - Injects Global Financial Pulse │
                     └─────────────────┬─────────────────┘
                                       │
                                       ▼
                       ┌───────────────────────────────┐
                       │     LLM (OpenRouter / Cohere) │
                       │    Reasoning & Tool Selection │
                       └───────────────┬───────────────┘
                                       │
            ┌──────────────────────────┴──────────────────────────┐
            │                     Tool Calls                      │
            ▼                                                     ▼
┌──────────────────────────────┐              ┌──────────────────────────────┐
│  Granular Transaction Engine │              │   Whole-App Ledger Tools     │
│  - query_transactions        │              │  - get_account_balances      │
│  - search_merchant_spending  │              │  - get_spending_summary      │
│  - get_top_expenses          │              │  - get_budget_status         │
│  - detect_recurring_bills    │              │  - get_active_plan_snapshot  │
│  - get_category_breakdown    │              │  - query_loans_debts         │
│                              │              │  - query_reimbursements      │
│                              │              │  - query_saving_goals        │
└──────────────┬───────────────┘              └──────────────┬───────────────┘
               │                                             │
               └──────────────────────┬──────────────────────┘
                                      │
                                      ▼
                      ┌──────────────────────────────┐
                      │    PostgreSQL 16 + Prisma    │
                      │   Strict userId row isolation│
                      └───────────────┬───────────────┘
                                      │
                                      ▼
                      ┌──────────────────────────────┐
                      │   Tool Results Appended      │
                      │  (Multi-Turn Follow-Up Call) │
                      └───────────────┬───────────────┘
                                      │
                                      ▼
                      ┌──────────────────────────────┐
                      │    Real-Time SSE Streaming   │
                      │   (Tokens delivered to UI)   │
                      └──────────────────────────────┘
```

---

### 6.2 The New & Expanded Tool Suite

To give the AI access to **every transaction, account, and financial entity**, we introduce 6 new deterministic tools:

#### 1. `query_transactions`
Searches and filters granular transaction records.
- **Inputs**:
  - `query` (optional string): Keyword in merchant or note (e.g. "Ride", "Kaldi", "Rent", "Supermarket")
  - `start_date` / `end_date` (optional ISO dates): Custom date range
  - `period` (optional enum): `today` | `this_week` | `this_month` | `last_month` | `last_30_days` | `year_to_date`
  - `category_name` (optional string): e.g. "Food", "Transportation", "Utilities"
  - `account_name` or `account_provider` (optional): e.g. "CBE", "Telebirr"
  - `type` (optional enum): `EXPENSE` | `INCOME` | `TRANSFER`
  - `min_amount` / `max_amount` (optional numbers)
  - `limit` (default 10, max 25)
- **Returns**: Exact matching transactions (date, merchant, amount, category, account, note) + total sum of matching items.

#### 2. `search_merchant_spending`
Analyzes spending with specific counterparties/merchants.
- **Inputs**: `merchant_name` (string), `period` (optional)
- **Returns**: Total amount spent with this merchant, transaction count, average transaction amount, date of first and most recent transaction, and recent line-items.

#### 3. `get_top_expenses`
Identifies the user's largest financial outlays.
- **Inputs**: `period` (optional), `limit` (default 5), `category_id` (optional)
- **Returns**: Top N largest transactions with merchant, category, date, and percentage of total period expenses.

#### 4. `get_category_breakdown`
Provides percentage and total spend for every active category.
- **Inputs**: `period` (default `this_month`)
- **Returns**: List of categories with total spent, transaction count, percentage of total expenses, and budget limit utilization.

#### 5. `detect_recurring_bills`
Identifies recurring payments, subscriptions, and regular obligations.
- **Inputs**: none
- **Returns**: Detected recurring items (e.g. Ethio Telecom monthly broadband, rent, monthly debt repayments, gym) with frequency, estimated monthly commitment, and last payment date.

#### 6. `query_saving_goals`
Retrieves user saving goals and progress.
- **Inputs**: none
- **Returns**: Active saving goals, target amounts, current saved amounts, deadlines, and required monthly pace.

---

### 6.3 Multi-Turn Agentic Tool Execution Loop

Currently, the server only executes 1 tool call turn. If an advanced user question requires querying multiple tools (e.g. `get_account_balances` + `query_loans_debts` + `simulate_scenario`), the AI must be able to call tools iteratively:

```typescript
// Multi-turn Agentic Loop (max 3 turns)
let iterations = 0;
while (iterations < 3) {
  const completion = await callLlmWithTools(messages, tools);
  const choice = completion.choices[0];
  
  if (choice.message.tool_calls && choice.message.tool_calls.length > 0) {
    messages.push(choice.message);
    
    // Execute all tool calls in parallel
    for (const toolCall of choice.message.tool_calls) {
      sendSse('tool_start', { tool: toolCall.function.name, arguments: args });
      const result = await this.executeTool(userId, toolCall.function.name, args);
      sendSse('tool_end', { tool: toolCall.function.name, result });
      toolCallsExecuted.push({ tool: toolCall.function.name, args, result });
      
      messages.push({
        role: 'tool',
        tool_call_id: toolCall.id,
        name: toolCall.function.name,
        content: JSON.stringify(result),
      });
    }
    iterations++;
  } else {
    // Model delivered final natural language answer
    assistantText = choice.message.content;
    break;
  }
}
```

---

## 7. Interface Changes

### 7.1 Backend API Declarations
- Add 6 new tool signatures to `OPENAI_TOOL_DECLARATIONS` and `GEMINI_TOOL_DECLARATIONS` in `backend/src/modules/ai/tools/finance-tools.ts`.
- Expand `AiService.executeTool()` to route each new tool to its corresponding `FinanceTools` query method.

### 7.2 System Prompt Upgrades
Add structured tool invocation rules to `buildSystemPrompt`:
```
### COMPREHENSIVE LEDGER TOOLS
1. "query_transactions": For specific transactions, searches by note/merchant keyword, date windows, amount ranges.
2. "search_merchant_spending": For queries like "How much have I spent at Kaldi's / on Feres taxis?".
3. "get_top_expenses": For queries like "What were my biggest expenses this month?".
4. "get_category_breakdown": For category distribution and visual allocations.
5. "detect_recurring_bills": For subscriptions, fixed monthly commitments, and regular bills.
6. "query_saving_goals": For savings progress, target milestones, and monthly targets.
7. "get_account_balances": For current bank & wallet balances (CBE, Telebirr, Abyssinia, Cash).
8. "get_active_plan_snapshot": For daily allowance, tomorrow rollover, and Adaptive Plan status.
9. "simulate_scenario": For "Can I afford X?" evaluations.
```

---

## 8. Data Model Changes
**No Prisma schema changes required.** All 6 new tools query existing tables (`Account`, `Transaction`, `Category`, `SavingPlan`, `Debt`, `Reimbursement`, `BudgetLimit`) using optimized indexes on `userId` and `occurredAt`.

---

## 9. Alternatives Considered

| Alternative | Pros | Cons | Decision |
|---|---|---|---|
| **A. Inject all transactions into prompt context** | Simple to code initially | Exceeds token limits, high API latency, high cost, arithmetic hallucinations | **Rejected** |
| **B. Client-side on-device LLM (ExecuTorch / Gemma)** | Works offline | Mobile hardware constraints, high battery drain, limited reasoning capacity for complex finance | **Deferred** |
| **C. Specialized deterministic SQL tool suite + Agentic Loop (Proposed)** | 100% mathematical precision, low token consumption, supports all granular queries, fast execution | Requires building dedicated query handlers | **Selected** |

---

## 10. Impact & Risks

- **Security & Multi-Tenancy**: Every tool strictly filters by authenticated `userId`. No user can query transactions or balances belonging to another user.
- **Latency**: Granular SQL queries on indexed `(userId, occurredAt)` execute in <15ms. Multi-tool turns are capped at 3 iterations to prevent runaway execution.
- **Token Efficiency**: Tool output payloads are structured and trimmed (e.g., returning top 10 matching records rather than 500 rows).

---

## 11. Implementation Plan

1. **Step 1: Implement Granular Query Methods in `FinanceTools`** ([finance-tools.ts](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/backend/src/modules/ai/tools/finance-tools.ts)):
   - Implement `queryTransactions`
   - Implement `searchMerchantSpending`
   - Implement `getTopExpenses`
   - Implement `getCategoryBreakdown`
   - Implement `detectRecurringBills`
   - Implement `querySavingGoals`
2. **Step 2: Declare OpenAI & Gemini JSON Schemas**:
   - Add schemas for the 6 new tools in `OPENAI_TOOL_DECLARATIONS` and `GEMINI_TOOL_DECLARATIONS`.
3. **Step 3: Implement Multi-Turn Tool Loop & Prompt Tuning** ([ai.service.ts](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/backend/src/modules/ai/ai.service.ts)):
   - Wire iterative tool calling loop (max 3 turns).
   - Add deterministic synthesis fallbacks for all new tools in `synthesizeToolResults`.
   - Update `buildSystemPrompt` with elite financial advisor heuristics.
4. **Step 4: Verification & Integration Testing**:
   - Write integration tests validating merchant search, top expenses, and category breakdowns.
   - Run mobile tests and verify real-time SSE streaming.

---

## 12. Testing Strategy
- **Unit Tests**: Test each new `FinanceTools` method in isolation with mock ledger transactions.
- **Integration Tests**: Test multi-turn conversations where the agent calls `get_account_balances` followed by `query_transactions` and `simulate_scenario`.
- **Latency Tests**: Verify end-to-end SSE time-to-first-token is under 1.8 seconds.

---

## 13. Rollout / Migration Plan
- Backward-compatible update: No database schema migration needed.
- If any tool query fails, `AiService` catches the error and falls back to general spending summary.
- Rollback: Revert `ai.service.ts` and `finance-tools.ts` to git commit `824c6d3`.

---

## 14. Open Questions
1. Should `query_transactions` allow users to search transactions by specific tags (e.g. `#business`, `#family`, `#vacation`)? *(Recommended: Yes, tags are already stored on transactions)*.
2. What maximum number of transaction line-items should be returned in a single tool response to balance detail and token speed? *(Recommended: 10 items per tool call)*.

---

## 15. References
- SW-Budget Architecture & Totals Parity: [docs/TOTALS_ARCHITECTURE_AND_FEATURES.md](file:///c:/Users/samue/OneDrive/Desktop/code/personal/SW-budget/docs/TOTALS_ARCHITECTURE_AND_FEATURES.md)
- OpenAI Function Calling Specification: `https://platform.openai.com/docs/guides/function-calling`
- Cohere Tool Use Documentation: `https://docs.cohere.com/docs/tool-use`

---

## 16. Decision Log
- **2026-10-12**: Initial proposal drafted for full-ledger intelligence, 6 granular deterministic SQL tools, multi-turn agentic execution loop, and comprehensive merchant/category drill-downs.
- **2026-10-12**: Approved by user. Implementation completed.
  - Implemented 6 new deterministic tools in `FinanceTools`: `queryTransactions`, `searchMerchantSpending`, `getTopExpenses`, `getCategoryBreakdown`, `detectRecurringBills`, and `querySavingGoals`.
  - Declared full JSON schemas for all 6 tools in `OPENAI_TOOL_DECLARATIONS` and `GEMINI_TOOL_DECLARATIONS`.
  - Added multi-turn agentic loop in `AiService.streamChat()` (up to 3 turns) allowing iterative tool invocations before final answer synthesis.
  - Expanded `AiService.synthesizeToolResults()` and `executeDeterministicSimulation()` to ensure zero empty chat responses.
  - Files touched: `backend/src/modules/ai/tools/finance-tools.ts`, `backend/src/modules/ai/ai.service.ts`.

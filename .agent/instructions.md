# Agent Instructions

> This file governs how the AI agent operates in this `frappe-bench` workspace.
> It is read at the start of every session. If any instruction here conflicts
> with a direct user request in-chat, ask before deviating — do not silently
> override this file, and do not silently override the user.

---

## 0. Operating Principles (read first)

1. **Never guess when you can check.** If a claim about the codebase can be
   verified by reading a file, running a command, or grepping — do that
   before stating it as fact.
2. **State your mode before acting.** Every response that does non-trivial
   work opens with one line: `Mode: DESIGN | UPDATE | BUGFIX | EXPLORE | REVIEW`.
3. **Small, reversible steps over big leaps.** Prefer a sequence of verified
   changes over one large unverified one.
4. **Silence is not confirmation.** If you assumed something because the user
   didn't specify it, say so explicitly in your response — don't bury it.
5. **You are not done when the code compiles.** You are done when it's
   tested, documented per this file's standards, and traceable to a design
   doc or issue.

---

## 1. Mode Detection

Determine mode from the request. If ambiguous, ask — do not default silently.

| Trigger phrases | Mode |
|---|---|
| "design", "new idea", "propose", "plan a feature", "how should we build X" | **DESIGN** |
| "update", "modify", "refactor", "change X", "extend Y" | **UPDATE** |
| "fix", "bug", "broken", "error", "not working" | **BUGFIX** |
| "explain", "how does X work", "where is Y" | **EXPLORE** (read-only, no edits) |
| "review this", "check my PR", "does this look right" | **REVIEW** (no edits, feedback only) |

**Mode-switch rule:** if mid-task new information reveals the wrong mode was
picked (e.g. a "fix" turns out to require an architecture change), stop,
state the mode switch explicitly, and get confirmation before continuing.

---

## 2. DESIGN MODE

### 2.1 Before writing the doc
- Restate the problem back in your own words in 1–2 sentences before
  designing anything. If your restatement doesn't match what the user
  meant, better to find out now than after the doc is written.
- Search the codebase for prior art: similar DocTypes, similar API patterns,
  existing services that do something adjacent. Reuse patterns rather than
  inventing new ones for their own sake.
- Check `.agent/docs/design/` for a doc that already covers this or an
  adjacent area. Link to it rather than duplicating context.

### 2.2 Do NOT write implementation code yet
Design mode produces a document, not a diff. Exception: small illustrative
pseudocode inside the doc itself is fine; real files are not.

### 2.3 File location & naming
- Path: `.agent/docs/design/YYYY-MM-DD-<kebab-case-feature-name>.md`
- One doc per feature/decision. Don't append unrelated features to an
  existing doc — cross-link instead.

### 2.4 Required section structure
Never delete a header. If a section doesn't apply, write `N/A` and one
clause explaining why (not just the bare word).

1. **Metadata** — status, author, date, type, related links, **confidence**
   (low/medium/high — how sure are you this is the right approach?)
2. **Summary**
3. **Problem / Motivation**
4. **Goals**
5. **Non-Goals**
6. **Proposed Design** — architecture, data flow, mermaid/ASCII diagrams
7. **API / Interface Changes** — full request/response shapes, not just
   endpoint names
8. **Data Model Changes** — DocType fields added/changed, migrations needed,
   any impact on existing data (backfill required? nullable?)
9. **Alternatives Considered** — minimum two, with concrete pros/cons, not
   strawmen
10. **Impact & Risks** — performance, security, backward compatibility,
    permissions/roles affected
11. **Implementation Plan** — ordered, each step small enough to be one
    commit
12. **Testing Strategy** — see §6
13. **Rollout / Migration Plan** — feature flags, patch scripts, staged
    rollout, and an explicit **rollback plan**
14. **Open Questions** — things you genuinely don't know; don't fake
    certainty to fill this in
15. **References**
16. **Decision Log** — append-only. Every time the design changes after
    initial approval, add a dated entry: what changed, why, who asked.

### 2.5 Gate before implementation
After drafting, stop. Do not proceed to UPDATE MODE / code until the user
explicitly approves. Flag any section marked "low confidence" as needing
extra scrutiny before approval.

---

## 3. UPDATE MODE

### 3.1 Reconnaissance (mandatory, before any edit)
- Locate and read the current implementation: relevant DocType, API handler,
  service files, and any tests that already cover this behavior.
- Trace the actual data flow — don't infer it from naming conventions alone;
  read the code.
- Check `.agent/docs/design/` for an existing doc on this feature.
  - **Exists** → read it fully, then update in place (see §3.2). Do not
    create a parallel doc.
  - **Doesn't exist** → create one using the DESIGN MODE structure, type =
    "Update", with §5 Current State filled in thoroughly before proposing
    any change.

### 3.2 Updating an existing design doc
- Update "Current State", "Proposed Design", and "Impact & Risks" directly.
- Do not delete the prior content of those sections — move superseded
  content into the **Decision Log** with a date, so history isn't lost.

### 3.3 Before editing code
List explicitly, in your response, before touching files:
- Which files/functions will change
- Why each one needs to change (tie back to the goal, not "seemed related")
- Anything that will change but is *not* obviously part of the ask (e.g. a
  shared utility used elsewhere) — flag this loudly, it's the most common
  source of silent regressions

### 3.4 Implementing
- One logical change per commit-sized unit. Don't mix refactoring with
  behavior changes in the same edit — do them as separate passes.
- Follow the layer separation rules in §5 without exception.

### 3.5 After implementing
- Add a **Change Log** entry to the relevant design doc: date, what changed,
  why, which files.
- Re-run/describe the tests in §6 relevant to the changed area.
- Note any follow-up work you deliberately deferred, and why.

---

## 4. BUGFIX MODE

1. **Reproduce or explain, before fixing.** State the root cause in one or
   two sentences before touching code. If you can't identify root cause
   confidently, say so and treat the fix as provisional.
2. **Distinguish symptom from cause.** A fix that only suppresses the
   symptom (e.g. adding a null check without asking why the value was null)
   must be flagged as a workaround, not a fix, in your response.
3. **Scope check:** if the fix requires touching more than the DocType
   controller / one API handler / one service function, or requires a data
   migration, stop and switch to UPDATE MODE — bugfixes should not sprawl
   into undocumented architecture changes.
4. Add a regression test that fails before the fix and passes after, where
   feasible.

---

## 5. Project & Bench Conventions

### 5.1 Paths & naming
- Design docs: `.agent/docs/design/YYYY-MM-DD-<kebab-case-feature-name>.md`
- ISO-8601 dates, kebab-case filenames, always.
- App-specific standards live at `apps/<app_name>/.agents/rules/` — read
  the relevant app's rules file before working in that app. If it's absent,
  say so rather than assuming defaults.

### 5.2 Three-tier layer separation (strict, no exceptions without a design doc)

| Layer | Location | Responsibility | Must NOT contain |
|---|---|---|---|
| **DocType Controller** | `doctype/<name>/<name>.py` | Lifecycle hooks only: `validate`, `before_insert`, `on_update`, `on_submit`, etc. | Business logic that doesn't belong to *this document's* lifecycle; direct calls to other doctypes' business logic |
| **API Handler** | `api/v1/<resource>.py` | `@frappe.whitelist`, request parsing/validation, permission checks, response formatting | Direct DB queries; business rules; transaction logic |
| **Service Layer** | `services/<resource>_service.py` | Business logic, DB operations, transactions, orchestration across doctypes | HTTP concerns (status codes, request objects); UI concerns |

If a change seems to require breaking this separation, that's a signal to
write a design doc explaining why, not to quietly bend the rule.

### 5.3 Frappe-specific conventions
- Use `frappe.db.get_value` / `get_all` with explicit `fields=[...]`, never
  unfiltered `select *` equivalents.
- Wrap multi-document writes in `frappe.db.savepoint()` or explicit
  transaction handling when partial failure would leave inconsistent state.
- Permissions: any new API endpoint must state which roles can call it, and
  the API handler must enforce it — don't rely on DocType-level permissions
  alone if the endpoint does anything beyond simple CRUD.
- Any new DocType field affecting existing records: state explicitly in the
  design doc's "Data Model Changes" section whether a patch/migration is
  needed to backfill it.

---

## 6. Testing Standards (applies to UPDATE, BUGFIX, and post-DESIGN implementation)

- **Unit tests**: cover the Service Layer logic in isolation.
- **Integration tests**: cover DocType lifecycle hooks + API handler
  together where they interact.
- **Permission tests**: for any new/changed API endpoint, test that
  unauthorized roles are rejected, not just that authorized roles succeed.
- **Edge cases to always check**: empty/null input, duplicate submission,
  concurrent modification, and permission boundaries.
- State test coverage explicitly in your response — don't just say "added
  tests," name what they cover and, more importantly, what they *don't*.

---

## 7. Security & Data Handling

- Never log or print sensitive fields (passwords, tokens, personal data)
  even in debug output.
- Any change touching user-submitted input must state how it's validated
  and sanitized in the relevant design doc or your response.
- Flag — don't silently fix — anything you notice that looks like an
  existing security gap outside the scope of the current task. Report it,
  let the user decide priority.

---

## 8. Communication & Traceability

- Reference the relevant design doc filename in every commit message and
  PR description for UPDATE-mode work.
- If you deviate from an approved design doc during implementation (because
  reality didn't match the plan), say so explicitly and update the doc's
  Decision Log — don't let code and doc silently drift apart.
- When uncertain about intent, ask one specific question rather than making
  a silent assumption and proceeding.

---

## 9. General Rules (apply to all modes)

- Always state your mode before starting substantial work.
- Never skip straight to code for DESIGN MODE requests.
- Keep design docs and code changes traceable to each other.
- Ask for clarification when a request doesn't clearly map to a mode, or
  when proceeding on an assumption would be costly to undo.
- Prefer flagging a concern over silently working around it.
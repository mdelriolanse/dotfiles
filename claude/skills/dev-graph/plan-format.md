Reference for the dev-graph skill. Not a skill and not a slash command.
Follow this format when writing a plan. Do not invoke `/plan`.

# Plan Report Format

## For the human reviewer — emit this format

When producing a user-facing plan (overview, impl plan, or any plan-mode report), output ONLY the sections below. No code snippets, no reasoning monologues. Dense bullets, minimal prose. Think "caveman."

---

### 1. Header (1–2 lines)

```
GOAL: <what>
SCOPE: <total files / est lines>
```

Example: `GOAL: add input validation to user parser` / `SCOPE: 3 files, ~40 lines`

---

### 2. Execution Strategy

```
ORCHESTRATOR: yes|no
SUBAGENTS: N total  (P parallel + S sequential + M mixed)
```

- `ORCHESTRATOR yes` → master agent drives; single pass, no sub-agents.
- `ORCHESTRATOR no` → use sub-agents; specify parallel vs sequential.

**Precedent check:** Before suggesting an approach, search the codebase for similar patterns already in use. Briefly cite 1–2 existing examples as justification. If none found, say "no precedent found."

Example:
> Approach: add middleware pipeline stage via `compose()`.
> Precedent: `src/auth/middleware.ts:42` and `src/logging/middleware.ts:18` both extend the pipeline this way.

---

### 3. Changes (N files, ~X lines)

| ID | File | What | Why | Lines |
|---:|---|---|---|---|
| 01 | `src/foo.ts` | add `validateX()` | enforce input sanity before `parse()` | +15/-3 |
| 02 | `src/bar.ts` | replace `legacyY()` with `newY()` | #442 migration path | +8/-12 |
| 03 | `src/baz.ts` | delete `deadZ()` | no callers since v2.0 | +0/-8 |

- Decimal IDs (01, 02, ...) so you can reference by number in follow-up.
- `Lines` column is per-file diffstat. Header shows total.
- No code blocks. No inline diffs. No multi-line cells — let text flow.

---

### 4. Dependencies

2–3 sentence intelligible synopsis of which architectural layers / modules / APIs are touched. Not a repeat of the file list — explain the *impact surface* in plain English.

Example: "Touches the request pipeline layer (`src/middleware/`) and the auth module (`src/auth/`). The parser change (#01) feeds into downstream validators, so any new validation rule here propagates to all POST endpoints using the shared input schema."

---

### 5. Open Questions

| # | Question | Blocking? |
|---|---|---|
| 1 | Should `validateX()` throw or return `Result`? | yes |
| 2 | Keep `legacyY()` as deprecated wrapper? | no |

None → write `NONE`.

---

## What NOT to emit

- Code snippets, fenced blocks, "here is what I will write" prose.
- Reasoning monologues — internal thought goes in hidden context, not the report.
- Multi-paragraph explanations. If a "why" needs more than 12 words, it belongs in a design doc.

---

## When the user references a change by ID

If the user says "skip 03" or "expand on 02," comply directly. Re-emit the plan section affected, keeping the same format where possible. No need to recapitulate the full header.

---

## SOP: Approach Justification via Codebase Precedent

Whenever suggesting an approach (execution strategy, implementation pattern, library choice, or architectural decision):

1. **Search first.** Use codebase-memory MCP `search_graph` or `search_code` to find similar patterns already implemented.
2. **Cite examples.** Reference 1–2 specific file paths/locations where the codebase already solves this or a similar problem.
3. **Explain the fit.** One sentence on why the precedent supports the suggested approach.
4. **If none found.** State "no precedent found — proposing new pattern."

This answers "How does the codebase generally resolve this issue?" before the user asks.

## Persist

After emitting the report to the conversation, write it to
`./docs/plans/<slug>.md` (create `./docs/plans/` if missing). `<slug>` is a
short kebab-case name derived from the plan goal (e.g. `add-input-validation`,
`resolve-review-round-1`). If a file with that name already exists, suffix
`-2`, `-3`, etc. to avoid clobbering.

The persisted file is the canonical plan record — downstream steps (build,
review, resolve) read it from there. The in-conversation emission is for the
human reviewer to read inline; the file is for the workflow.

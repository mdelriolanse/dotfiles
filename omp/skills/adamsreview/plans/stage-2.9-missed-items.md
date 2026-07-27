# Stage 2.9 — Detection hardening for missed items (L2 + L5 prompt tunes, prior-fix reversion, holistic L7)

**Status:** drafted 2026-04-20, awaiting user review.
**Preceded by:** Stage 2.8 (comment freshness — done).
**Followed by:** Stage 4 (fragment shrink — planned).
**Pattern:** mirrors Stage 2.5/2.6/2.7/2.8 — detection-only hardening pass, no Phase 7–9 surface touched, no schema version bump.

---

## Context

**Trigger.** On ray/ray-finance `feat/import-apple` (the C13 real-repo case study — see `plans/stage-2.6-freshness-origin.md`, BUILD Stage 2.6 close-out), a one-off Opus prompt with full-branch context ("please review all our work in this branch vs main ... prioritized list of issues") surfaced six findings that our ensemble `/adams-review` run did not fully cover:

### P1-class misses (detection gaps)

**P1.1 — Manual Accounts label regression at `cli/commands.ts:178,213`.** A prior commit `54de955` fixed a "Manual Accounts (manual)" label regression by treating `is_manual=true` rows separately. A later SQL refactor in this PR (`3836d3f`) broadened the predicate `access_token = 'manual'` in a way that re-introduces the old bug. Zero findings in our artifact reference the changed lines or the `is_manual` / `access_token='manual'` discriminator.

**P1.2 — Apple Card interest_rate NULL rendered as 0% APR.** `upsertLiability` at `apple-import.ts:511-518` leaves `interest_rate` NULL on import; `getDebts` at `queries/index.ts:537-538` COALESCEs NULL → 0; `ai/tools.ts:get_debts` renders "0% APR"; `computeInsights` feeds the AI advice stream, so the user can be told "pay off Apple Card last — it's 0%" even when it sits behind a 5% student loan. F002 and F016 land in the same files but on different concerns.

### P2-class misses (pattern-shaped detection gaps — surfaced by a separate pass on the same branch)

**P2.4 — `checkAchievements` runs on inconsistent state at `commands.ts:1169` after `postImportError`.** Same line as our F029 but a different failure mode: ours is "uncaught throw crashes the process"; theirs is "runs on inconsistent state, may unlock stale-state achievement." F029's narrow try/catch fix doesn't address the stale-state guard. Pattern: **multi-failure-mode analysis at the same site** — an L2 same-block-adjacency check was intended to catch this but didn't.

**P2.5 — `recategorization.ts:74-80` re-evaluates ALL transactions during Apple-import.** A recategorization pass fires on every transaction when `ray import-apple` runs, silently re-evaluating Plaid rows that weren't part of this import. Three nearby recat findings (F001, F005, F024) miss the cross-provider scope question. Pattern: **cross-provider / domain-scope check** — "when this fires in path X, what does it do to data owned by path Y?"

**P2.6 — `apple-import.ts:176-180` `parseDate` is MM/DD/YYYY-only; warning doesn't reveal expected format.** L5-ux currently prompts for flow gaps (loading/empty/error states, destructive confirmations). It does not push on copy-quality: does the warning text actually help the user diagnose? Pattern: **warning / error-message diagnostic quality**.

**P2.7 — `queries/index.ts:511-519` `getDebts` JOIN duplicates rows if a liabilities row has multiple types per account.** `apple-import` upserts with `ON CONFLICT(account_id, type)` uniqueness, which *permits* multi-type rows per account. The read-side JOIN on `account_id` alone can therefore fan out. F017 mentions the upsert-side uniqueness but doesn't connect to the JOIN-cardinality risk. Pattern: **SQL JOIN vs. target-table UNIQUE-constraint cardinality check**.

**P2.8 — `commands.ts:1155-1158` recat buffer error-flush ordering edge case.** No finding in that line range. Pattern: the "careful senior reviewer catches the edge case" class — not mechanically prompt-able without bloating prompts.

(P2.3 is out of scope: same observation as our F013 but the reviewer concluded "intentional spinner-feedback trade-off" where we said "fix target." This is a Phase 4 validation-nuance miss, not a detection issue. P2.9 is a correctness confirmation, not a finding.)

### Why we missed each — six patterns collapse into four detection levers

| Miss | Pattern | Lever |
|---|---|---|
| P1.1 | Prior-fix reversion — "does this PR undo a prior commit whose message signaled 'fix'?" | Deterministic helper + L2 prompt addendum |
| P1.2 | NULL/default-value propagation to user-visible / AI-consumer surfaces | L2 outer-pass prompt bullet |
| P2.5 | Cross-provider / domain scope when the diff runs inside one data-path | L2 outer-pass prompt bullet |
| P2.7 | SQL JOIN vs. target-table UNIQUE-constraint cardinality | L2 inner-pass checklist item |
| P2.6 | Warning / error-message diagnostic quality | L5-ux prompt addition |
| P2.4, P2.8 | Unknown-unknown "careful reader catches it" class | Holistic L7 Opus lens (ensemble-gated) |

Four levers:

1. **L2 structural prompt tune** (P1.2, P2.5, P2.7). Three new prompt additions: outer-pass consumer-surface NULL trace, outer-pass cross-provider scope, inner-pass JOIN-vs-UNIQUE checklist item.
2. **L5-ux prompt tune** (P2.6). New diagnostic-copy-quality guidance in `lens-ux-reference.md`, feeding L5's existing prompt via the preprocessor include.
3. **Prior-fix reversion detection** (P1.1). New deterministic helper `prior-fix-diff.sh`; output feeds L2's prompt as a suspects list; L2 judges whether the current diff undoes any suspect.
4. **Holistic L7 Opus lens** (P2.4, P2.8, unknown-unknowns). Ensemble-gated parallel Opus with unconstrained "skeptical senior reviewer" prompting and full repo access.

Each lever is narrow and additive. Phase 2 Sonnet dedup already unions `source_families[]` from overlapping lenses, so when L2 + L7 both flag the same bug (likely), the finding auto-graduates into Phase 4 (Phase 3 gate: "≥ 2 source families → advance"). That's the intended strengthening mechanism, not redundancy.

**Stage sizing.** Fits the Stage 2.5/2.6/2.7/2.8 pattern — one helper, three fragment rewires, one new lens prompt block, smoke growth. No schema changes. No `docs/archive/` updates (frozen per CLAUDE.md preamble). `/adams-review-walkthrough`, `/adams-review-fix`, `/adams-review-promote` untouched.

---

## 1. Goal

Close four detection gaps before Stage 4 fragment shrink:

1. **L2 outer + inner pass extended** to walk NULL/default-value into user-visible consumers, to check cross-provider scope when the diff runs inside one data-path, and to sanity-check SQL JOINs against target-table UNIQUE constraints.
2. **L5-ux prompt extended** to flag warning and error messages that don't help the user diagnose (missing expected format, generic text where specific context is available).
3. **Phase 1 computes a prior-fix suspects list** from git history and feeds it to L2's prompt so L2 can judge whether the current change undoes a prior fix.
4. **Holistic L7 Opus lens** runs under `--ensemble` as a safety net for cross-layer bugs the focused lenses' narrower prompts don't reach.

**Done when:**

1. Re-running `/adams-review --ensemble` on `feat/import-apple` produces findings covering P1.1, P1.2, P2.5, P2.6, and P2.7 (precise line ranges not required — any finding that walks the relevant pattern counts). P2.4 / P2.8 are "nice to have" — their appearance validates L7's value; their absence becomes Stage 2.9 open-issue follow-up, not a blocker.
2. `test/smoke.sh` passes; new PF-* (prior-fix-diff) and L7-* assertions green.
3. L2 prompt changes visible in `01-detection.md`; L5 prompt changes visible in `lens-ux-reference.md`; no regressions in existing lens behavior against fixtures.
4. `CLAUDE.md` Phase 1 lens count updated for L7.
5. `BUILD.md` stage index + Stage 2.9 close-out section filled in.

---

## 2. Ground rules (restated)

- **Bash 3.2 portable.** `#!/usr/bin/env bash` + `set -euo pipefail`. No `declare -A`, no `mapfile`.
- **Exit codes reuse `_common.py` / existing Bash conventions.** 0 success, 1 EXIT_VALIDATION, 5 EXIT_MISSING_DEP, 64 usage.
- **Error-as-prompt on every helper.** ERROR → context → Valid values → Did you mean → Action.
- **Commits:** one per sub-item, imperative mood, Co-Authored-By trailer per CLAUDE.md Operational rule 11.
- **Directly to `main`**, no feature branches. Worktree: `.claude/worktrees/missed-items` during drafting; merge cleanup at close-out.
- **No schema change.** Additive lens output uses existing candidate shape. New `source_families[]` value `"holistic-family"` is a string literal — `source_families[]` is `"type": "string"` with no enum in `schema-v1.json`, no bump needed.
- **No DESIGN-archive updates.** `docs/archive/` is frozen (CLAUDE.md preamble). New behavior lives in CLAUDE.md + this plan file + in-fragment prose comments.

---

## 3. Scope — work items

Five sub-items:

- **2.9.A** — L2 prompt tune (three additions: consumer-surface, cross-provider, JOIN-vs-UNIQUE)
- **2.9.B** — L5-ux prompt tune (diagnostic copy quality)
- **2.9.C** — Prior-fix reversion detection (new helper + L2 wiring)
- **2.9.D** — Holistic L7 Opus lens (ensemble-gated)
- **2.9.E** — CLAUDE.md + BUILD close-out

### 3.1 Intentionally NOT in scope

- **Always-on holistic L7.** Ensemble-gated for this stage. If ensemble runs consistently show L7 net-worth-its-cost, a follow-up stage can demote the gate.
- **Prior-fix detection via LLM agent.** The helper is deterministic (git log + line-overlap regex); L2 is the judge. No dedicated "regression lens."
- **Cross-repo history** (downstream fork whose upstream has a fix the downstream is undoing).
- **Phase 4 validation-nuance improvements (P2.3).** "Is this pattern likely intentional given the surrounding code?" is a validator-prompt question — separate follow-up stage.
- **Schema version bump.** All new data rides on existing fields.
- **Renderer changes.** L7 findings render through the existing renderer via their impact_type / disposition.
- **Phase 5 cross-cutting, Phase 7–9 surface.** Untouched.
- **`--holistic` flag independent of `--ensemble`.** Flag proliferation deferred.

---

## 4. Scope details

### 4.1 — 2.9.A — L2 prompt tune

**Goal:** extend L2 structural's prompt to cover three specific patterns missed on the ray-finance C13 case study.

**File touched:** `commands/_shared/01-detection.md` — L2 prompt block (currently lines ~208–286, "L2 — structural / blast-radius").

#### 4.1.1 — Outer-pass addition: consumer-surface value trace (P1.2)

The outer-pass bullet list (currently ~222–231) gains a new bullet after "What invariants does the surrounding code assume? Does the diff preserve them?":

> - **Consumer-surface value trace.** For every column, field, API response, template variable, LLM tool output, report line, or other value the diff introduces or whose writer it modifies, walk the full path from writer through storage to user-visible output. If a writer can produce NULL, zero, empty string, or a default value, trace what each consumer does with it:
>   - Does a SQL reader COALESCE it to a sentinel (e.g. `COALESCE(rate, 0)`)? If so, is the sentinel distinguishable from a legitimate zero?
>   - Does a template / render layer display the sentinel as a real value (`"0% APR"`, `"$0.00 balance"`, `"Manual account"`)?
>   - Does an LLM tool schema, prompt helper, or insight generator feed the sentinel into an AI-generated recommendation? AI-consumer surfaces are especially dangerous because the pipeline may be storage-layer correct but present-layer misleading — the model acts on `0%` as if it were a real rate.
>   - Does a downstream filter / ORDER BY / conditional branch change behavior because the value is the default rather than the original?
>
>   Flag cases where the writer's NULL/default can propagate to a user-facing output that reads as honest (real rate of 0%, real balance of $0, real "Manual" classification) but actually represents missing data. This is the "semantic-layer correctness" cousin of the structural / mechanical "does the INSERT happen?" check — both matter.

#### 4.1.2 — Outer-pass addition: cross-provider / domain scope (P2.5)

After the consumer-surface bullet above, add:

> - **Cross-provider / domain-scope check.** When the diff changes a function that runs inside a specific data-path (`ray import-apple`, `syncPlaid`, a payroll upload, a user-initiated flow), identify which data entities the function's reads and writes touch. If the function's query surface is broader than the data-path's intent — e.g. a recategorization pass triggered by Apple-import that re-evaluates *all* transactions, not just the newly-imported Apple ones — flag it. The failure mode is subtle: the function is correct in isolation, but its scope crosses a provider / domain boundary the user did not consent to. Specifically check:
>   - Does the function filter by source / provider / import-batch / user-initiated-id before reading or writing?
>   - If the function runs during a specific command, do its side effects stay scoped to that command's intent?
>   - When the same function runs in multiple paths (Apple-import and Plaid-sync share a recategorizer), does the caller scope the work, or does the callee?

#### 4.1.3 — Inner-pass addition: SQL JOIN vs. target-table UNIQUE constraint (P2.7)

The existing inner-pass checklist (five items: sibling parsers, catch scope, EOF invariants, filter-predicate / COALESCE sweeps, same-block adjacency) gains a sixth item. Insert after item 4 (filter-predicate sweeps) so the flow reads SQL→SQL→adjacency:

> 5. **SQL JOIN join-key vs. target-table UNIQUE-constraint cardinality.** For any SQL JOIN the diff adds, modifies, or reads from, identify the JOIN's join-key column(s). Then find the target table's UNIQUE / PRIMARY KEY constraint in the schema (grep migrations / `CREATE TABLE` / `ALTER TABLE`). If the JOIN's join-key is NOT the uniqueness key, the JOIN can fan out when the target table legitimately holds multiple rows per join-key value. This is especially likely when:
>    - An UPSERT on the target table uses `ON CONFLICT(a, b)` — meaning multiple rows per `a` are permitted, one per `b`.
>    - The JOIN in question only keys on `a`.
>    - The read path treats each joined row as "the" row for `a`, producing duplicate rows or incorrect aggregates.
>
>    Trace an example: if `liabilities` has `UNIQUE(account_id, type)` and a query `JOIN liabilities ON a.account_id = l.account_id`, a single account with both `credit_card` and `mortgage` types will produce two rows for that account — and any downstream `SUM`/`COUNT`/`ORDER BY` silently double-counts. Flag.

(Existing item 5 "Same-block adjacency" is renumbered to 6.)

#### 4.1.4 — No change to dispatch, model, or permissions

L2 remains `model: opus, subagent_type: general-purpose`, inheriting Read + Bash(git:*) + Bash(grep:*) grants. Prompt growth is ~30 lines; token overhead on Opus is negligible.

### 4.2 — 2.9.B — L5-ux prompt tune (diagnostic copy quality, P2.6)

**Goal:** extend L5-ux to flag warning/error messages that don't help the user diagnose (missing expected format, generic text where specific context is available).

**File touched:** `commands/_shared/lens-ux-reference.md` (inlined into L5's prompt via the preprocessor include at `01-detection.md` step 1.3 L5 prompt, line ~340).

**What to add.** A new sub-section to `lens-ux-reference.md` — exact placement depends on the file's current structure (to be confirmed during execution). Topic:

> **Warning / error-message diagnostic quality.** When the diff adds or modifies a warning, error, or toast message shown to the user — especially ones triggered by parsing, validation, or input rejection — check whether the message helps the user diagnose and fix:
>
> - Does the message reveal the expected format when input is rejected? A `parseDate` that only accepts `MM/DD/YYYY` should say so in the warning, not "Invalid date."
> - Does the message name the specific value that failed? "Invalid amount" is weaker than "'abc' is not a valid amount — expected a number like 42.50."
> - When the underlying context is available (file path, row number, column name, field name, upstream source), is it in the message? A parser-error message that buries line number in debug logs while showing the user "Something went wrong" is a diagnostic-quality gap.
> - For batch / buffered operations (flush-after-N-errors, debounced save), does an empty-buffer or mid-flush failure produce a generic message when a specific one is cheap? "Save failed" on an empty buffer suggests the user lost data they didn't write.
>
> Flag as `impact_type: "ux"` with source_family: "ux-family". Fix proposals should include concrete message-text suggestions.

**No change to L5's dispatch block in 01-detection.md** — the prompt already inlines `lens-ux-reference.md` via `!`cat` `. Adding content to the reference file propagates automatically.

**Verification concern.** L5's prompt file is read at command-inline time (preprocessor), not at sub-agent-dispatch time. Confirm during execution that the new content actually lands in L5's prompt — the inline mechanism has subtle edge cases.

### 4.3 — 2.9.C — Prior-fix reversion detection (P1.1)

**Goal:** surface regressions where the current PR undoes a prior commit whose message signals "fix" / "bug" / "regression" and that touched the same lines. Deterministic helper produces suspects; L2 judges whether the suspect is actually being reverted.

**New helper: `commands/_shared/tools/prior-fix-diff.sh`**

Bash. For each file in `$reviewed_files_all`, for each hunk in the PR's diff against `$comparison_ref`, runs `git log -L` to find prior commits touching the same lines, filters by fix-intent message keywords, emits a suspects array.

**Interface:**

```
prior-fix-diff.sh \
  --comparison-ref <ref> \
  --reviewed-files <csv|@-> \
  [--lookback-days <N>]
```

- `--comparison-ref <ref>` — required. Phase 0 reconciled `$comparison_ref`.
- `--reviewed-files <csv|@->` — required. CSV or stdin.
- `--lookback-days <N>` — optional, default 365. Bounds history walk.

**Output (stdout):** JSON array of suspect records:

```json
[
  {
    "file": "cli/commands.ts",
    "current_hunk_range": [175, 220],
    "prior_fix_commit_sha": "54de955",
    "prior_fix_commit_short": "54de955",
    "prior_fix_commit_message_subject": "Fix 'Manual Accounts (manual)' label regression",
    "prior_fix_commit_date": "2025-11-12T14:22:03-08:00",
    "prior_fix_touched_lines": [178, 213]
  }
]
```

Empty array is valid.

**Algorithm:**

1. Parse args (Bash 3.2 arg-loop per Stage 2.6/2.8 convention).
2. Validate `$comparison_ref` via `git rev-parse --verify --quiet` (error-as-prompt on failure).
3. Validate `--reviewed-files` non-empty; read CSV or stdin.
4. Compute `since_date = now() - lookback_days` as ISO-8601.
5. For each file:
   - Skip if file doesn't exist at HEAD.
   - Compute the PR's hunks: `git diff --unified=0 "$comparison_ref..HEAD" -- "$file"` → parse hunk headers → post-image `{start, end}` pairs.
   - For each hunk:
     - `git log --all --since="$since_date" -L "$start,$end:$file" --pretty=format:'%H|%s|%cI' --no-patch`.
     - Parse each line; filter by fix-intent regex: `(?i)(^|[\s\[(:-])(fix(es|ed)?|bug|regress(ion)?|revert|restore|correct|hotfix|patch)\b`.
     - Filter reachable from `$comparison_ref` via `git merge-base --is-ancestor` — we want only commits predating the PR.
     - For each survivor, compute `prior_fix_touched_lines`: parse hunks from `git diff-tree -r --no-commit-id --unified=0 "$sha" -- "$file"` → post-image line numbers → intersect with current hunk range.
     - Emit one record per (file, hunk, prior-fix commit).
6. Wrap records in JSON array; emit stdout.

**Stderr audit grammar** (matches `origin-crosscheck.sh` / `comment-freshness.sh`):

```
prior_fix_diff: file=<path> hunks=<n> suspects=<n> [reason=<short>]
prior_fix_diff_skipped: file=<path> reason=<short>
```

Per-file `git log -L` failures skip the file, don't abort.

**Exit codes:** 0 success, 1 EXIT_VALIDATION, 5 EXIT_MISSING_DEP, 64 usage.

**Performance.** `git log -L` is O(file-age) per hunk. `--lookback-days 365` caps it. Per-file soft 10s timeout. Worst-case ~5–15s added to Phase 1 on a 20-file PR; within the 2.6-budget precedent.

**Wiring into Phase 1 — `01-detection.md`:**

New step **1.2b** (between ensemble-readiness gate at 1.2a and dispatch at 1.3):

```
### 1.2b. Prior-fix suspect scan

Before dispatching lenses, scan git history for prior-fix commits whose
changes overlap the PR's diff. Output feeds L2's prompt so L2 can judge
whether the current change undoes any suspect fix.

Skipped when $trivial_mode is true (L2 is skipped too):

```bash
if [[ "$trivial_mode" != "true" ]]; then
    reviewed_files_csv=$(printf '%s\n' "$reviewed_files_all" \
      | awk 'NF' | paste -sd, -)

    prior_fix_suspects=$(
        ~/.claude/commands/_shared/tools/prior-fix-diff.sh \
          --comparison-ref "$comparison_ref" \
          --reviewed-files "$reviewed_files_csv" \
          2> >(tee -a "$trace_log_path" >&2)
    ) || prior_fix_suspects="[]"
else
    prior_fix_suspects="[]"
fi
```

On helper non-zero exit: fall back to `[]`. L2's prior-fix check becomes
a no-op — correct degraded behavior.
```

**L2 prompt addendum** (inserted after inner-pass checklist item 6 "Same-block adjacency", before "Read function BODIES, not just signatures"):

> **Prior-fix reversion check.** The following prior commits (matched on
> "fix"/"bug"/"regression" patterns, reachable from the base) touched lines
> that this PR also modifies:
>
> ```
> $prior_fix_suspects
> ```
>
> (Empty array → nothing to check; skip this section.)
>
> For each suspect, compare the current diff's changes at the overlapping
> lines against what the prior fix commit did. Flag as a candidate when the
> current diff appears to undo the prior fix — either by reverting to the
> pre-fix line content, by introducing a parallel code path that behaves
> like the pre-fix code, or by broadening a narrow condition the prior fix
> specifically narrowed. Include the prior fix commit's short SHA and
> subject in your `claim` so the reviewer can trace the history.
>
> `impact_type` for a regression-of-prior-fix: `correctness`.
> `source_family`: `structural-family`.

**Why L2 and not a standalone lens.** L2 already has Opus judgment, full-file access, and a blast-radius mandate. Adding one prompt section is cheaper than spawning a new Opus. Suspects list is short (typically 0–5 records), so prompt growth is small.

**Tool grant.** `commands/adams-review.md` allowlist gains `Bash(/Users/.../tools/prior-fix-diff.sh:*)`. Absolute path per CLAUDE.md Operational rule 10; `scripts/install.sh` substitutes `$HOME`.

### 4.4 — 2.9.D — Holistic L7 Opus lens (ensemble-gated)

**Goal:** ensemble-gated parallel Opus sub-agent with unconstrained "senior reviewer" prompting and full repo access, as a safety net for cross-layer bugs the focused lenses' narrower prompts don't reach (P2.4, P2.8, and the unknown-unknowns class in general).

**Files touched:**

- `commands/_shared/01-detection.md`:

  **Step 1.1** (decide which lenses run) — add row:

  ```
  | L7 — holistic review | opus | ensemble_mode == true AND trivial_mode != true |
  ```

  Skip-note examples updated for L7.

  **Step 1.3** (dispatch) — new sub-section after L6, before "Ensemble fan-out":

  ```
  #### L7 — holistic review (Opus; ensemble_mode only; skipped if trivial_mode)

  Launch one Agent tool-use with model: opus, subagent_type:
  general-purpose. Inherits Read + Bash(git:*) + Bash(grep:*).

  Prompt essence:

  > Review this PR as a skeptical, careful senior engineer who was just
  > handed it and asked to find bugs the test suite and linter will miss.
  > Read the diff between $comparison_ref and HEAD, plus any surrounding
  > code you need to understand it. Use git blame / git log freely.
  >
  > **No checklist — scan for anything wrong.** Other agents are running
  > in parallel with narrower prompts (L1 diff-local, L2 structural, L3
  > CLAUDE.md, L4 comments, L5 UX, L6 security). Your job is to catch
  > things those miss: semantic correctness across layer boundaries,
  > misleading state visible to users or AI consumers, latent bugs a
  > careful human reader would notice, regressions of prior behavior,
  > multi-failure-mode issues at the same call site.
  >
  > Places to look especially hard:
  >
  > - **Cross-layer semantic value.** When a field can be NULL / default
  >   / missing, follow every consumer and check whether the user-visible
  >   or AI-visible output is honest. A NULL rate rendered as "0% APR" in
  >   an LLM tool output is a real bug even when the SQL is correct.
  >
  > - **Regression of prior behavior.** When the diff changes behavior
  >   in an area that had a named fix commit, check whether the fix is
  >   being undone. Use `git log --all -L <range>:<file>` filtered to
  >   "fix"/"bug"/"regression" message patterns. A broadened SQL predicate
  >   or a consolidated branch that re-introduces the pre-fix behavior is
  >   the characteristic pattern.
  >
  > - **Cross-provider / domain scope.** When a function runs inside a
  >   path named for one data source (Apple import, Plaid sync, payroll),
  >   check whether its queries and writes stay scoped to that source,
  >   or whether it silently re-evaluates unrelated data.
  >
  > - **Multi-failure-mode at the same call site.** When the diff
  >   addresses one failure mode (e.g. wraps a throwing call in
  >   try/catch), enumerate other ways the same call can go wrong:
  >   inconsistent state, partial writes, stale cache, out-of-order
  >   side effects. A "fix" that addresses one mode while leaving
  >   another live is a partial fix worth flagging.
  >
  > - **Misleading user / AI interfaces.** Outputs that look correct
  >   but mislead — "0% APR" for a missing rate, "Manual" for a
  >   non-manual account, silent failures rendered as successes,
  >   partial updates reported as complete, generic error messages
  >   when specific context was available.
  >
  > - **Parallel paths whose invariants have diverged.** Two similar
  >   functions/queries where only one got updated; one strict parser
  >   and one lenient; a write-side that now allows NULL and a read-side
  >   that assumes non-null.
  >
  > - **Assumptions that don't hold.** Invariants the code assumes but
  >   the diff breaks; ordering assumptions; concurrency; JOIN cardinality
  >   against target-table UNIQUE constraints.
  >
  > Over-flag; Phase 3 filters. Err toward sharing a half-confident bug.
  >
  > Return a JSON array of candidates:
  >
  > ```
  > {
  >   "file": "src/path/to/file.ts",
  >   "line_range": [start, end],
  >   "claim": "one-sentence description of the issue",
  >   "evidence_snippet": "exact code lines (or multi-file trace if cross-layer)",
  >   "impact_type": "correctness" | "security" | "ux" | "policy" | "architecture",
  >   "origin": "introduced_by_pr" | "pre_existing" | "unknown",
  >   "origin_confidence": "high" | "medium" | "low",
  >   "source_family": "holistic-family"
  > }
  > ```
  >
  > Default `origin: "introduced_by_pr"`, `origin_confidence: "high"` unless
  > the implicated code is clearly unchanged by this diff.
  ```

  **Step 1.4** (collect candidates) — extend collection-loop's lens-tag list: `L7-holistic` in `sources[]`, `lens_7_holistic` in `log-tokens.sh --agent-role`. Join the existing L1–L6 entries (~440–444).

- `commands/_shared/tools/assign-finding-ids.sh` — source-priority table extended:

  ```
  Priority: L1-diff-local → L2-structural → L3-claude-md → L4-comments
          → L5-ux → L6-security → L7-holistic → external-pr → codex
          → coderabbit
  ```

  Read current table format during execution; edit the single priority-order line.

- `commands/adams-review.md` — `allowed-tools` already includes the parent `Bash(git:*)` grant L7 needs. No change unless the current grant list is narrower than remembered (verify at execution).

- `CLAUDE.md` — Pipeline-shape block: update `Phase 1 — Detection` narrative from "6 parallel lens agents" to "6 internal lens agents (7 under `--ensemble`)".

- No `schema-v1.json` change.

**Dispatch parallelism.** L7 launches in the same turn as L1–L6 (§13.12). Full ensemble adds one more tool-use block: 6 lens Agents + 1 L7 Agent + 2 CLI Bash + 1 PR scrape = 10. Within Claude Code's practical parallel cap.

**Join path.** L7 flows through the same pipeline as L1–L6 (origin-crosscheck, line-range-check, assign-ids, `--add-finding`). Source-family-agnostic helpers require no changes.

**Cost.** L7 ≈ 1.5–2x L2's spend. Ensemble runs shift from ~$X to ~$1.5X–$2X per PR. Non-ensemble unaffected. User can disable L7 by removing the 1.1 table row — contained change.

**Origin-crosscheck interaction.** Same as L1–L6. When L7 flags a bug in pre-existing code, origin-crosscheck routes it to `pre_existing_report`. For P1.1 (reverting line IS PR-introduced per blame) this doesn't trigger. For P1.2 (writer is new, consumer is pre-existing) L7 likely files against the writer line, keeping PR-introduced.

### 4.5 — 2.9.E — CLAUDE.md + BUILD close-out

**Files touched:**

- `CLAUDE.md`:
  - Pipeline-shape ASCII block — Phase 1 narrative: "6 parallel lens agents" → "6 internal lens agents (7 under `--ensemble`)".
  - No other changes.

- `BUILD.md`:
  - Stage index row: "Stage 2.9 — Detection hardening" with status `done`.
  - New Stage 2.9 section matching Stage 2.5/2.6/2.7/2.8 template (goal, files landed, verification evidence, open issues). Include ray-finance re-run transcript reference.
  - Current-state bullet updated.
  - Cross-stage note dated 2026-04-20: "Added L2 outer-pass consumer-surface + cross-provider-scope bullets; L2 inner-pass JOIN-vs-UNIQUE check; L5-ux warning-diagnostic-quality content in lens reference; prior-fix-diff helper with L2 prompt wiring; holistic L7 Opus lens (ensemble-gated). Closes P1.1, P1.2, P2.5, P2.6, P2.7 patterns from the ray-finance C13 case study."

- `plans/stage-2.9-missed-items.md` (this file) — retained at close-out per Stage 2.5/2.6/2.7/2.8 convention.

---

## 5. Verification

### 5.1 — `test/smoke.sh` additions

New `Stage 2.9 — Detection hardening` block. Pattern matches Stage 2.6 OC-* and Stage 2.8 CF-* blocks — scratch two-commit repo setup, hand-crafted fixtures.

**PF-1..PF-7 — prior-fix-diff helper.**

- **PF-1.** Empty repo history → empty array, exit 0.
- **PF-2.** Three commits, none fix-intent → empty array.
- **PF-3.** Three commits: base adds, middle "Fix X regression" narrows predicate, head broadens — suspect record naming middle commit.
- **PF-4.** Fix-message match without line overlap → empty.
- **PF-5.** PR's own fix-message commits filtered out via `--is-ancestor` check.
- **PF-6.** Usage errors: missing `--comparison-ref` → exit 64; unknown ref → exit 1; non-repo → exit 1.
- **PF-7.** Lookback cap: fix-message commit outside `--lookback-days` window → not in suspects.

**L7-1..L7-3 — holistic lens plumbing.**

- **L7-1.** `assign-finding-ids.sh` slots L7-holistic source-priority correctly (synthetic JSON fed through helper).
- **L7-2.** L7-holistic source_family passes `artifact-validate.sh`.
- **L7-3.** origin-crosscheck flips L7 candidate's origin when entire blame range predates `$comparison_ref` — same behavior as L1–L6.

**Total new assertions: 10.** Running total target: (current baseline) + 10. Confirm baseline during 2.9.A work via `bash test/smoke.sh | tail -1`.

### 5.2 — Real-PR re-run on ray-finance `feat/import-apple`

**Pre-condition.** Fresh checkout of `feat/import-apple`; local `main` up to date with origin. No uncommitted changes in the ray-finance repo.

**Procedure.**

1. Run `/adams-review --ensemble` on the branch.
2. Open `~/.adams-reviews/<slug>/feat-import-apple/<review_id>/artifact.md`.
3. Grep findings for each expected pattern:

| Expected | What to look for | Source |
|---|---|---|
| P1.1 | Finding at `cli/commands.ts:~178` or `~213` citing `is_manual` / `access_token='manual'` broadening / the `'Manual Accounts (manual)'` label regression | L2 (prior-fix addendum) or L7 |
| P1.2 | Finding walking `apple-import.ts` NULL write → `queries/index.ts` COALESCE → `ai/tools.ts` 0% render | L2 (consumer-surface) or L7 |
| P2.5 | Finding at `recategorization.ts:~74-80` citing cross-provider scope / Plaid rows touched during Apple-import | L2 (cross-provider scope) or L7 |
| P2.6 | Finding at `apple-import.ts:~176-180` citing parseDate warning copy quality / expected-format guidance | L5-ux or L7 |
| P2.7 | Finding at `queries/index.ts:~511-519` citing JOIN-vs-UNIQUE cardinality | L2 (inner-pass 5) or L7 |
| P2.4 (nice-to-have) | Finding at `commands.ts:~1169` citing `checkAchievements` running on inconsistent state | L7 (primary expectation) |
| P2.8 (nice-to-have) | Finding at `commands.ts:~1155-1158` citing recat buffer ordering | L7 |

4. Open `trace.md`:
   - `prior_fix_diff: file=cli/commands.ts hunks=<n> suspects=<n ≥ 1>` with `54de955` named in the suspects.
   - L7 dispatch in `tokens.jsonl` with `agent_role: lens_7_holistic`, `model: opus`.
   - No `lens_dropped_unparseable: lens=L7-holistic`.
   - Phase 2 dedup unioned `source_families[]` on overlap cases (visible in artifact findings with `sources[]` length ≥ 2).

5. Document outcome in BUILD.md Stage 2.9 section.

**Fallback ladder if expected findings still missed.**

- **If P1.1, P1.2, P2.5, P2.6, or P2.7 is missed** (the five "should"s) → prompt-tune round 2. Inspect what L2 / L5 / L7 did produce; adjust prompts narrowly; re-run. Cap at one prompt-tune iteration inside Stage 2.9; further iteration becomes plan-drift and should escalate.
- **If P2.4 or P2.8 is missed** (the two "nice-to-have"s) → record as Stage 2.9 open issue. Not a blocker for stage close-out. A clean miss here is the honest signal that L7's unconstrained prompt has limits and a pattern-specific extension may be warranted in a follow-up stage.
- **If the helper runs but produces no suspects where we know they exist** → investigate `git log -L` behavior on the specific file; the line-tracking may have lost the range across renames. Helper bug, Stage 2.9 open issue.

### 5.3 — Regression checks (non-new-behavior)

- `bash test/smoke.sh` — all existing assertions green; 10 new additive.
- Non-ensemble small-PR `/adams-review` run:
  - Phase 1 dispatches 6 lenses (no L7).
  - prior-fix-diff runs (it's always-on when `trivial_mode=false`, not ensemble-gated).
  - Wall-clock Phase 1 within 1.5x pre-2.9 baseline (prior-fix-diff adds ~1–10s).
- `--ensemble` small-PR run:
  - Phase 1 dispatches 7 lenses.
  - L7 tokens logged; origin-crosscheck ran on L7 output.
  - Phase 2 dedup unions L7 with L2/L6 overlaps.

---

## 6. Risk notes

- **L2 prompt growth.** Three new bullets plus prior-fix addendum push L2's prompt to ~2x its current length. Opus handles it fine, but the prompt becomes harder to maintain. Mitigation: Stage 4 fragment-shrink is the right place to consider externalizing lens prompts into their own reference files (already the pattern for L5-ux + L6-security).

- **Prior-fix-diff false positives.** Fix-intent regex is generous (fix, bug, regress, revert, restore, correct, hotfix, patch). Some commits match spuriously. L2 judges whether the suspect is actually a reversion — false positives cost prompt tokens but don't produce false findings. Acceptable.

- **Prior-fix-diff performance.** `git log -L` is O(file-age) per hunk. `--lookback-days 365` caps it; per-file 10s soft timeout handles pathological cases. Worst case: a file skipped with `reason=log-L-timeout` audit line, rest of scan continues.

- **L7 cost doubling Opus spend on ensemble runs.** Genuine. Ensemble is already the "willing to pay" mode. User can rip L7's table row if cost becomes prohibitive — two-line change in `01-detection.md`.

- **L7 / L2 overlap producing duplicate findings.** Phase 2 dedup unions `source_families[]`; duplicates strengthen via Phase 3 auto-graduation (≥ 2 source families). Designed behavior. Watch for dedup underperformance in re-run — fix is in Phase 2 prompt, not here.

- **L5-ux prompt file indirection.** Adding to `lens-ux-reference.md` relies on the `!`cat`` preprocessor include at command-inline time. Confirm during execution that the new content actually lands in L5's dispatched prompt. Same risk applies to `lens-security-reference.md` changes historically — Stage 2.5 tested the pattern, so the path is known-working.

- **Origin-crosscheck downgrading L7 findings to pre_existing_report.** For P1.1 (reverting line IS PR-introduced per blame) this doesn't trigger. For P1.2 (writer new, consumer pre-existing) L7 should file against the writer line — if it files against the reader, the finding routes to the footnote section, still visible to the user.

- **Prompt-tuning iteration discipline.** The ray-finance re-run is the only empirical signal; one prompt-tune round is budgeted; further drift should escalate to a follow-up stage rather than indefinite iteration inside 2.9.

- **CLAUDE.md + README drift.** Pipeline-shape block is the only CLAUDE.md change; README doesn't enumerate lenses so no change. Low-risk.

---

## 7. Critical files modified (summary)

| File | Nature of change |
|------|------------------|
| `commands/_shared/01-detection.md` | L2 prompt: outer-pass +2 bullets, inner-pass +1 item; new step 1.2b; new L7 dispatch block in 1.3; step 1.1 table + skip note; step 1.4 collection lens-tag list |
| `commands/_shared/lens-ux-reference.md` | New diagnostic-copy-quality section |
| `commands/_shared/tools/prior-fix-diff.sh` | **New** Bash helper |
| `commands/_shared/tools/assign-finding-ids.sh` | Source-priority table + `L7-holistic` |
| `commands/adams-review.md` | `allowed-tools` gains prior-fix-diff.sh grant |
| `CLAUDE.md` | Pipeline-shape lens count update |
| `test/smoke.sh` | 10 new assertions (PF-1..7, L7-1..3) |
| `BUILD.md` | Stage index row; Stage 2.9 close-out section; cross-stage note |

---

## 8. Execution order

1. **2.9.C helper** — `prior-fix-diff.sh` + PF-1..PF-7 smoke. Self-contained. One commit.
2. **2.9.C wiring** — `01-detection.md` step 1.2b + L2 prompt addendum + `adams-review.md` allowed-tools grant. One commit.
3. **2.9.A** — L2 outer + inner pass additions (consumer-surface, cross-provider, JOIN-vs-UNIQUE). One commit.
4. **2.9.B** — L5-ux diagnostic-copy-quality content in `lens-ux-reference.md`. One commit.
5. **2.9.D** — L7 lens: step 1.1 table, step 1.3 dispatch block, step 1.4 collection tag, `assign-finding-ids.sh` priority, CLAUDE.md pipeline-shape + L7-1..L7-3 smoke. One commit.
6. **ray-finance re-run** — execute `/adams-review --ensemble` on `feat/import-apple`; capture artifact + trace.md; confirm expected findings surface. If all five "should"s land: proceed to 2.9.E. If not: iterate on specific prompt (one-round drift commit inside Stage 2.9) and re-run.
7. **2.9.E close-out** — BUILD.md stage row + section + cross-stage note; this plan file's status line updated. One commit.

~6–7 commits (5 if ray-finance re-run passes first try; 6–7 with one prompt-tune round).

Each commit ends with:

```
Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

---

## 9. Decisions (locked 2026-04-20)

All seven pre-execution open questions resolved during the planning pass; every decision matched the recommended option. Recorded here so a cold-opening future reader sees the locked state without re-chasing conversation history.

| # | Question | Decision |
|---|---|---|
| 1 | `prior-fix-diff.sh` default `--lookback-days` | **365** |
| 2 | Holistic L7 gating | **Ensemble-gated** (runs only under `--ensemble`) |
| 3 | Prior-fix-diff helper gating | **Always-on when `trivial_mode=false`** — not ensemble-gated |
| 4 | Prompt-tune iteration cap if re-run misses | **One round inside Stage 2.9**; escalate to follow-up stage beyond |
| 5 | Fix-intent regex | **Ship proposed as-is**: `(?i)(^\|[\s\[(:-])(fix(es\|ed)?\|bug\|regress(ion)?\|revert\|restore\|correct\|hotfix\|patch)\b` |
| 6 | P2.4 + P2.8 close-out expectation | **Both nice-to-have**; absence becomes Stage 2.9 open issue, not a close-out blocker |
| 7 | L5-ux diagnostic-copy-quality content location | **`commands/_shared/lens-ux-reference.md`** (reference file L5 already inlines via preprocessor) |

All seven match the recommended options in §4 and §5. Execute per §8.

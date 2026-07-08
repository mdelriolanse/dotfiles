# Stage 2.7 — Detection parallelization (Phase 1 + Phase 1.5)

**Status:** drafted 2026-04-18, awaiting user review.
**Preceded by:** Stage 2.6 (freshness + origin cross-check — done).
**Followed by:** Stage 3 (`/adams-review-fix`) — same pre-Stage-3 hardening pattern as 2.5 / 2.6.

---

## Context

Why this stage exists: on `--ensemble` runs, Phase 1 (6 internal lens Agent dispatches) runs to completion *before* Phase 1.5 (CodeRabbit CLI + Codex CLI + PR bot-comment scrape + Sonnet normalizer) even starts. The fragments are sequenced by `!cat` includes in `commands/adams-review.md:131-139`, so the orchestrator naturally executes them in order. There is no data dependency between them — Phase 2 (dedup) is the first cross-phase consumer — yet the serial ordering costs 30–50% of detection wall-clock on ensemble runs (observed ~5m 5s for Phase 1; ensemble CLIs add ~10-15m serially on top).

**Outcome this stage delivers.** When `--ensemble` is set, internal lens dispatches and external CLI launches happen in one orchestrator turn. Finding IDs are assigned at a single post-dispatch join point. A pre-dispatch readiness gate surfaces missing-CLI prompts BEFORE any tokens are spent. Non-ensemble runs are unaffected.

This stage is the last piece of pre-Stage-3 hardening; Stage 3 adds Phases 7–9 on top of a detection surface that's now parallel-friendly.

---

## Validation of BUILD.md §Stage 2.7

I checked each claim in BUILD.md against the current source:

1. **"Phase 1 runs to completion before Phase 1.5"** — ✓ Confirmed. `adams-review.md:131-139` sequences fragments via `!cat` preprocessor; nothing in the orchestrator contract says they may interleave.
2. **"Finding ID assignment races"** — ✓ Confirmed. `01-detection.md:267` ("Monotonically assign finding ids … keep a counter in your working context") and `02-ensemble-adapter.md:282-283` ("Continue the F0xx id sequence from Phase 1") both mutate the same counter; concurrent claims would collide.
3. **"Ensemble readiness check (1.5.1) is user-blocking"** — ✓ Confirmed. `02-ensemble-adapter.md:75-82` uses `AskUserQuestion` AFTER the 6 lenses have already burned tokens.
4. **"Progress UI assumes sequential phases"** — Partial. The TaskList guidance in `adams-review.md:26-28` says "one task per phase". Having two concurrent `in_progress` tasks works fine in the UI; this is really a *documentation* tweak, not code.
5. **"No hidden data dependency"** — ✓ Confirmed. The normalizer prompt (`02-ensemble-adapter.md:211-267`) only reads external inputs; Phase 2 dedup is the first cross-phase consumer.

**Small refinements I'm proposing on top of BUILD.md's written spec** (call out now so the user can course-correct before code lands):

- **Readiness-gate placement.** BUILD.md says "between 1.1 and 1.3". 1.2 ("Build the shared input") sits between them. Clean slot: a new step **1.2a** (mirrors the 0.2a freshness-gate pattern). Under `ensemble_mode=false`, 1.2a is a one-line no-op.
- **Join step number.** BUILD.md calls it "step 1.9". That leaves a gap. Cleaner: renumber current 1.5 "Log Phase 1 summary" → 1.6, and place the new "Join + assign IDs + add-finding" at **1.5**. Still reads top-to-bottom; no phantom step numbers.
- **Assignment helper, not inline prose.** BUILD.md's 2.7.C says "synthesize two candidate batches … assert IDs are monotonic". But the assignment logic is currently *fragment prose* telling the orchestrator what to do. Smoke tests can only hit a helper. Proposal: extract a small Bash/jq helper **`assign-finding-ids.sh`** (takes pooled candidate JSON on stdin, emits IDed candidate JSON on stdout). Matches DESIGN's helper-script pattern, testable, keeps assignment deterministic.
- **Scrape stays synchronous.** Under parallel dispatch, the PR scrape (`02-ensemble-adapter.md:138-150`) can either stay foreground or move to background. Staying foreground in the same orchestrator turn is fine — it just delays the turn's return by the gh-api duration (seconds, not minutes). Keeping it foreground avoids adding another `BashOutput` polling path.
- **phases.jsonl overlap.** Under parallel, each phase still logs its own `elapsed_sec`. Phase 1 elapsed = dispatch-turn-start → last lens returned. Phase 1.5 elapsed = dispatch-turn-start → normalizer returned. The overlapping `ts` timestamps are what makes the concurrency observable in the log. BUILD.md's done-when #3 (`phase_1.elapsed_sec ≈ phase_1_5.elapsed_sec ≈ max(internal, external)`) is satisfied modulo the normalizer tail (which is Phase 1.5's work, so Phase 1.5 is typically a bit longer — not a problem).

No other hidden dependencies surfaced during validation.

---

## Goal

Close three gaps so ensemble runs fan out Phase 1 and Phase 1.5 concurrently:

1. **Pre-dispatch readiness gate.** Hoist `02-ensemble-adapter.md` §1.5.1 (CodeRabbit + Codex availability + AskUserQuestion) into `01-detection.md` as new step 1.2a, running BEFORE any Agent dispatch. Under `ensemble_mode=false`, the gate is a no-op.
2. **Joint dispatch + pooled collection.** Step 1.3 grows to launch both the 6 internal lens Agent calls AND (if `ensemble_mode=true`) the CodeRabbit + Codex background Bash + synchronous PR scrape — all in one orchestrator turn. Step 1.4 becomes "collect candidates into an un-IDed pool"; the ensemble normalizer's output joins the same pool.
3. **Single join point.** New step 1.5 "Join + assign IDs + add-finding" calls a new helper `assign-finding-ids.sh` that takes the pooled candidates, sorts deterministically by source, assigns `F001…F0NN`, and emits IDed candidates for the single `--add-finding` sweep.

**Done when:**

1. On `--ensemble` runs, Phase 1 lens dispatches and Phase 1.5 CLI launches happen in the **same orchestrator turn** (verifiable by inspecting session transcripts — single turn with ≥8 tool-use blocks: 6 Agent + 2 background Bash + 1 foreground Bash for scrape).
2. Finding IDs remain monotonic and non-colliding across the pooled detection set. `test/smoke.sh` gains assertions exercising `assign-finding-ids.sh` against synthetic pools (internal-only, ensemble-only, mixed).
3. `phases.jsonl` records Phase 1 and Phase 1.5 with overlapping time windows — an ensemble pr-mode run produces roughly `phase_1.elapsed_sec ≈ phase_1_5.elapsed_sec ≈ max(internal, external)` rather than `phase_1 + phase_1_5`.
4. Non-ensemble runs behave unchanged — Phase 1 dispatches alone; step 1.2a no-ops; the 02-ensemble-adapter fragment's skip note fires; join step iterates the internal-only pool.
5. Readiness gate surfaces `AskUserQuestion` BEFORE any lens agent dispatches, so a user who picks "stop so I can set them up first" isn't billed for the 6 internal lens tokens.
6. DESIGN §4 narrative + new §13.12 land with the refactor.
7. BUILD.md stage index + Stage 2.7 section filled in with before/after wall-clock evidence from a real ensemble run.

---

## Ground rules (restated)

- **Bash:** `#!/usr/bin/env bash` + `set -euo pipefail`. Bash 3.2-safe.
- **Exit codes:** reuse `_common.py` / existing Bash conventions. No new codes.
- **Error-as-prompt:** ERROR → context → Valid values → Did you mean → Action.
- **Commits:** one per sub-item, imperative mood, DESIGN §-refs, `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>` trailer.
- **Directly to `main`**, no feature branches. Symlink dev layout is live.
- **§13.12 is normative** (like §13.10/§13.11), not a clarification — folds into a single commit with the code that implements it.

---

## Scope — work items

### 3.1 Intentionally NOT in scope

- Parallelizing Phase 2 / 3 / 4 against each other. They have real data dependencies (Phase 3 needs Phase 2 dedup results; Phase 4 needs Phase 3 scores). No wall-clock win without deeper refactors.
- Token-cost changes. Each agent still dispatches once; the saving is wall-clock only.
- Timeout handling changes. The existing 10-min CLI timeout per `02-ensemble-adapter.md` step 1.5.4 already tolerates slow reviewers; parallelism just means the timeout clock starts earlier.
- Phase-tracker UI beyond the documentation tweak in §4.1.
- Schema version bump. No new artifact fields.
- Any Stage 3 (`/adams-review-fix`) surface.

---

## 4. Scope details

### 4.1 — 2.7.A — DESIGN §4 + new §13.12

**New DESIGN sub-section §13.12 — "Detection parallelization"** (normative).

Prose essence:

> When `--ensemble` is set, Phase 1 internal lens dispatches and Phase 1.5 external CLI launches fan out from the same orchestrator turn. The pipeline remains two logical phases (for schema, logging, and audit attribution) but their wall-clock windows overlap.
>
> **Invariants:**
> 1. **Single dispatch turn.** The orchestrator's dispatch turn contains the 6 applicable lens `Agent` tool-use blocks, the CodeRabbit + Codex background `Bash` launches, and the foreground PR-scrape `Bash` call. Waiting a turn between blocks serializes them and negates the stage's entire value.
> 2. **No IDs during collection.** Both phases collect their candidate arrays into a shared pool with no `id` field set. Partial `--add-finding` writes during collection would break atomicity and produce collision errors.
> 3. **Single join point.** After every lens and the Sonnet normalizer have resolved, a single step assigns `F001…F0NN` across the pooled set (sorted by source: L1, L2, L3, L4, L5, L6, ensemble-normalizer). One `--add-finding` sweep commits the pool.
> 4. **Pre-dispatch readiness gate.** The ensemble CLI readiness check (CodeRabbit version + auth, Codex companion + ready) runs BEFORE either phase dispatches. `AskUserQuestion` on missing CLIs surfaces ahead of token spend.
> 5. **Non-ensemble runs.** `ensemble_mode=false` short-circuits the readiness gate and the ensemble dispatches. Phase 1 fans out alone; the join step iterates the internal-only pool.
>
> **Token accounting.** Unchanged from §11 — each lens + the normalizer are logged per-agent under their owning phase (`phase_1` for lenses, `phase_1_5` for the normalizer). External CLIs remain untracked per §11's existing carve-out.
>
> **phases.jsonl.** Each phase still logs its own record with its own `elapsed_sec`, computed from its own dispatch-start epoch to its own last-input-resolved epoch. The overlapping `ts` timestamps make concurrency observable; `elapsed_sec` reflects each phase's longest path.

**DESIGN §4 narrative edits** (in `DESIGN.md` around line 128-187):

- Phase 1 heading: add a pointer paragraph noting that under `--ensemble`, dispatch is joint with Phase 1.5 — see §13.12.
- Phase 1.5 heading: matching pointer; note the readiness gate has moved to pre-dispatch (in the Phase 1 fragment).
- ASCII pipeline diagram (§4 lines 81-100): update the Phase 1 / Phase 1.5 lines to show a fan-out brace when `--ensemble` is set. (Small cosmetic — preserve single-column layout for readability.)

**Files touched for 2.7.A:**
- `DESIGN.md` — new §13.12 block, Phase 1 / Phase 1.5 narrative tweaks, pipeline diagram tweak.

---

### 4.2 — 2.7.B — Fragment refactor

**Files touched:**
- `commands/_shared/01-detection.md`
- `commands/_shared/02-ensemble-adapter.md`
- `commands/adams-review.md` (TaskList note in §"Execution overview")
- `commands/_shared/tools/assign-finding-ids.sh` (new)

#### 4.2.1 — `01-detection.md` changes

**New step 1.2a — Ensemble readiness gate** (inserted between current 1.2 and 1.3):

- Guard: `if ensemble_mode != true`, log one line to trace.md ("Ensemble readiness gate skipped — --ensemble not set"), capture `coderabbit_available=false, codex_available=false`, continue.
- Else: run the CodeRabbit version + auth probe (today at `02-ensemble-adapter.md:50-56`) and the Codex companion probe (today at `02-ensemble-adapter.md:60-73`). Capture `coderabbit_available`, `codex_available`, `CODEX_COMPANION`.
- If both available: proceed silently.
- If either unavailable: `AskUserQuestion` with two options (same as current `02-ensemble-adapter.md:75-82`):
  - "Proceed with what's available" → record skipped reviewers in trace.md + set the corresponding `*_available=false`.
  - "Stop so I can set them up first" → exit the command with remediation commands surfaced.
- Capture `phase_1_5_start_epoch=$(date +%s)` here (hoisted from current 1.5.1) — ensures Phase 1.5's elapsed clock starts at the actual dispatch boundary.

**Step 1.3 (Dispatch) edits** — add this guidance block after the existing lens dispatch table:

> If `ensemble_mode == true`, ALSO dispatch in this same orchestrator turn (per §13.12):
>
> - CodeRabbit launch — see `02-ensemble-adapter.md` step 1.5.2 for the exact command. Run-in-background; capture `coderabbit_shell_id`.
> - Codex launch — see `02-ensemble-adapter.md` step 1.5.2. Run-in-background; capture `codex_shell_id`. (Write the prompt file inline; no separate turn.)
> - PR comment scrape — see `02-ensemble-adapter.md` step 1.5.3. Foreground Bash call. Skipped in local mode.
>
> All launches occur as tool-use blocks in the single dispatch turn alongside the 6 lens Agent blocks. Total block count: 6 lenses + 2 background Bash + 1 foreground Bash (PR mode) or 6 + 2 (local mode with CLIs available).

**Step 1.4 (Collect) edits** — rename to "**Collect lens candidates into pool**". Change semantics:

- Per-lens-result steps 1 (log tokens) and 2 (JSON repair) unchanged.
- Step 2a (origin cross-check) unchanged — still per-lens, still deterministic, no inter-batch dep.
- **Step 3 changes:** do NOT call `--add-finding`. Instead append the lens's corrected candidates (from 2a) to an in-orchestrator-context pool variable `internal_candidates` (array of partial candidate objects, no `id`). The jq-build-and-add-finding block moves to new step 1.5.
- Remove the per-iteration finding counter prose.
- Add note: "the pool is in your working context, not on disk; do NOT write intermediate state to the artifact."

**New step 1.5 — Join + assign IDs + add-finding** (replaces current 1.5 "Log Phase 1 summary"; summary becomes 1.6):

> Wait until every internal lens has returned AND (if `ensemble_mode == true`) the ensemble normalizer has emitted its candidate array into `external_candidates` per `02-ensemble-adapter.md` step 1.5.5.
>
> Combine the two pools:
>
> ```bash
> pooled=$(jq -nc \
>   --argjson internal "$internal_candidates" \
>   --argjson external "${external_candidates:-[]}" \
>   '$internal + $external')
> ```
>
> Hand the pool to `assign-finding-ids.sh` (new helper — see 4.2.4). Helper deterministic-sorts by source and assigns `F001…F0NN`:
>
> ```bash
> ided=$(printf '%s' "$pooled" | ~/.claude/commands/_shared/tools/assign-finding-ids.sh)
> ```
>
> Then, for each element in `ided`, build the full schema-valid finding and call `artifact-patch.py --add-finding`. Use the existing jq-n idiom from the current 1.4 step 3 (with `.id` already populated from the helper — skip the `--arg id` binding).
>
> On non-zero exit for any single `--add-finding`, error-as-prompt naming the offending finding id; retry once; drop-with-trace on second failure (matches existing per-candidate failure policy).

**Step 1.6 — Log Phase 1 summary** (renamed from current 1.5). Unchanged content; phase_1 elapsed still = `date +%s - phase_1_start_epoch` at join-point end.

**Working-set-delta section** — note that `internal_candidates` and (if ensemble) `external_candidates` live in orchestrator context only; nothing persists to disk until 1.5.

#### 4.2.2 — `02-ensemble-adapter.md` changes

The fragment shrinks. It remains the authoritative spec for Phase 1.5-owned work (launches, normalizer, Phase 1.5 summary) — but now dispatched-from-01.

Changes:

- **Remove** step 1.5.1 (readiness + AskUserQuestion) — moved to 01-detection.md 1.2a. Replace with a one-line pointer: "Readiness gate runs in 01-detection.md step 1.2a before either phase dispatches. Under `ensemble_mode=true`, by the time you reach this fragment, `coderabbit_available`, `codex_available`, `CODEX_COMPANION`, and `phase_1_5_start_epoch` are already captured."
- **Remove** the scratch_dir `mkdir -p` from the removed 1.5.1; move that one line into a new terse preamble at the top of 1.5.2.
- **Step 1.5.2 (Launch CLIs)** — keep launch commands. Add preamble: "These launches happen from the 01-detection.md step 1.3 dispatch turn alongside the lens Agent blocks. Reference this section from there; the launch specs remain authoritative here."
- **Step 1.5.3 (PR scrape)** — unchanged semantics; same preamble pointer.
- **Step 1.5.4 (Collect CLI outputs)** — unchanged; happens on orchestrator turns after dispatch, before normalizer.
- **Step 1.5.5 (Normalize)** — unchanged logic. Add note: "Emit the normalized array to the `external_candidates` working-set variable; the join step in 01-detection.md 1.5 consumes it. Do NOT call `--add-finding` here."
- **Step 1.5.6 (Append external candidates + log tokens)** — split:
  - "Log the normalizer's tokens under `phase_1_5`" — stays here.
  - The `--add-finding` loop and jq transformation — **removed**. Moves to 01-detection.md step 1.5.
  - The schema-guard repair for `file: null` / `line_range: null` — moves to the normalizer post-processing (same step 1.5.5) so the external pool is already repaired before joining.
- **Step 1.5.6b (scratch cleanup)** — unchanged.
- **Step 1.5.7 (Log Phase 1.5 summary)** — unchanged. phase_1_5 elapsed = `date +%s - phase_1_5_start_epoch` (epoch captured in 1.2a).
- **Working-set-delta section** — note that external candidates pool into `external_candidates` and are committed at 01-detection.md step 1.5.

#### 4.2.3 — `adams-review.md` TaskList guidance tweak

In the "Execution overview — read this first" section (lines 20-52), add one sentence to the "Parallel fan-outs are expensive" bullet:

> Under `--ensemble`, Phase 1 and Phase 1.5 dispatch as a joint fan-out in one orchestrator turn (see §13.12). The TaskList can still carry two tasks; mark both `in_progress` when you fire the dispatch turn, and both `completed` after the single join step.

#### 4.2.4 — New helper `assign-finding-ids.sh`

Small Bash/jq helper at `commands/_shared/tools/assign-finding-ids.sh`. Interface:

```
Usage:
  assign-finding-ids.sh < pooled_candidates.json
  echo "$pooled" | assign-finding-ids.sh

Stdin: JSON array of candidate objects. Each should have at minimum
  `source_family` (singular) or `sources` (array) so source-priority
  sorting can run.

Stdout: same array, same element order after deterministic sort,
  with `.id` set to F001, F002, … (zero-padded to 3 digits).

Exits: 0 success; 1 malformed input JSON (non-array, missing source keys).
```

Source-priority sort order (deterministic; matches current per-lens sequencing in 01-detection.md 1.4):

1. `L1-diff-local`
2. `L2-structural`
3. `L3-claude-md`
4. `L4-comments`
5. `L5-ux`
6. `L6-security`
7. `external-pr:*` (bot comments; sub-ordered by bot login)
8. `codex`
9. `coderabbit`

Tie-breaker within source: input array order (stable sort).

Implementation sketch (~40 lines of Bash + jq):

```bash
#!/usr/bin/env bash
set -euo pipefail

input=$(cat)

# Validate it's a JSON array.
if ! echo "$input" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "ERROR: stdin is not a JSON array." >&2
    echo "Valid input: JSON array of candidate objects." >&2
    echo "Action: pipe pooled candidates (e.g. \$internal + \$external) to this helper." >&2
    exit 1
fi

# Assign a numeric source-priority key, stable-sort, assign F### ids.
echo "$input" | jq -c '
  def src_priority:
    (.sources[0] // "") as $s |
    if   $s == "L1-diff-local" then 1
    elif $s == "L2-structural" then 2
    elif $s == "L3-claude-md"  then 3
    elif $s == "L4-comments"   then 4
    elif $s == "L5-ux"         then 5
    elif $s == "L6-security"   then 6
    elif ($s | startswith("external-pr:")) then 7
    elif $s == "codex"         then 8
    elif $s == "coderabbit"    then 9
    else 99 end;

  # Preserve input order via an index, combine with source priority.
  to_entries
  | map(.value + {_idx: .key, _src: (.value | src_priority)})
  | sort_by(._src, ._idx)
  | to_entries
  | map(.value + {id: ("F" + (((.key) + 1) | tostring | ("000" + .) | .[-3:]))})
  | map(del(._idx, ._src))
'
```

(Exact jq golf will be tuned during 2.7.B implementation; the semantics above are the contract.)

---

### 4.3 — 2.7.C — Smoke tests

**File touched:** `test/smoke.sh`

Add a new block after Stage 2.6.C (currently ends around line 1072). Heading:

```
# ------------------------------------------------------------------ Stage 2.7
# assign-finding-ids.sh — deterministic source-priority sort + monotonic F###
# assignment over pooled internal + external candidates.
```

Assertions (mirror the FR-*/OC-*/RH-* style):

- **AI-1 (assignment: internal only).** Pool = 3 L1 + 2 L2 + 1 L3. Expect `[F001..F006]`, sorted L1 → L2 → L3.
- **AI-2 (assignment: ensemble mixed).** Pool = 2 L1 + 1 L6 + 1 `external-pr:greptile[bot]` + 1 `codex` + 1 `coderabbit`. Expect L1 → L6 → external-pr → codex → coderabbit, IDs `F001..F006`.
- **AI-3 (stable within source).** Pool = 4 L1 candidates with distinct `file` values in input order A, B, C, D. Expect the output preserves that order (stable sort within same priority bucket).
- **AI-4 (empty pool).** Stdin = `[]`. Expect stdout `[]`, exit 0.
- **AI-5 (malformed stdin).** Stdin = `not-json`. Expect exit 1 with error-as-prompt ("Valid input: JSON array …", "Action: pipe pooled candidates …").
- **AI-6 (non-array stdin).** Stdin = `{}` (JSON object, not array). Expect exit 1 with same error-as-prompt.
- **AI-7 (unknown source).** Pool has one candidate with `sources: ["some-future-source"]`. Expect priority 99 → placed last. ID still assigned. (Forward-compat safety.)

Each assertion uses a small inline JSON literal as stdin — no fixture files needed. The pattern matches how OC-1..OC-7 assertions work in the existing smoke.sh.

No real CLI, no real Agent dispatch — helper-level only, matches the scope BUILD.md calls out.

**Integration-level smoke for joint-dispatch timing** — NOT added at this stage. It requires an actual ensemble run and real CLI availability; covered by done-when #3 + #7 via a real-repo re-run whose evidence lands in BUILD.md.

---

### 4.4 — 2.7.D — BUILD.md close-out

**File touched:** `BUILD.md`

Update:

1. Stage index row (line 60) for Stage 2.7: status `not started` → `done`, plan pointer `plans/stage-2.7-detection-parallel.md`.
2. Stage 2.7 section (currently at line 413) — append a "**Close-out 2026-MM-DD:**" sub-section with the Stage 2.6-style walk-through:
   - Commits landed on main (newest first).
   - Before/after wall-clock from a real ensemble run. If a user-time ensemble re-run is not feasible pre-close-out, note it explicitly and budget for Stage 3 validation (same pattern as Stage 2.6's "ray-finance re-run deferred" note).
   - Deviations from scope (if any).
   - Open items / known gaps (if any).
3. `plans/stage-2.7-detection-parallel.md` — create by copying `/Users/adammiller/.claude/plans/sleepy-enchanting-tulip.md` (this plan) into the repo under its permanent name. Same pattern as the 2.6 close-out.

---

## 5. Commit cadence

Estimated 3-5 commits, one per sub-item:

1. **2.7.A** DESIGN §13.12 + §4 narrative + pipeline-diagram tweak — 1 commit.
2. **2.7.B** Fragment refactor (01-detection.md + 02-ensemble-adapter.md + adams-review.md TaskList note) + new `assign-finding-ids.sh` helper — 1-2 commits (may split "helper + its test assertions" from "fragment refactor" for smaller diffs).
3. **2.7.C** smoke assertions AI-1 through AI-7 — folded into 2.7.B or 1 commit.
4. **2.7.D** BUILD.md close-out + durable plan at `plans/stage-2.7-detection-parallel.md` — 1 commit.

Plan-approval round-trip: REQUIRED — behavior change touches orchestration pattern; affects every ensemble run.

---

## 6. Risks and open questions

1. **Turn-count realism.** Orchestrator dispatching 6 Agent + 2 background Bash + 1 foreground Bash in a single turn is a lot of tool-use blocks. I'm confident this works (Claude Code supports many tool uses per turn), but I haven't verified via a real ensemble run. If it turns out there's a practical limit (e.g. tool-use block count or prompt-size), the fallback is dispatching the 6 lenses in one turn and the 3 ensemble calls in the immediately-following turn — still parallel wall-clock-wise because background Bash + Agent runs are both async. Flag during 2.7.B.

2. **phases.jsonl consumer assumptions.** Nothing in the current codebase reads `phases.jsonl` and *assumes* non-overlapping time windows. Grepped — no consumer parses elapsed_sec math across phases. Safe.

3. **Readiness gate surfacing UX.** Moving the AskUserQuestion to before any dispatch is a user-facing behavior change. Under the prior ordering, a user saw Phase 1 fan-out progress updates before the ensemble prompt. Under the new ordering, the prompt appears promptly after Phase 0 completes. This is strictly a UX improvement (no wasted tokens if they stop), but worth noting in DESIGN §13.12.

4. **`assign-finding-ids.sh` as a new helper surface.** One more script under `commands/_shared/tools/`. Small and well-contracted. No schema impact. Smoke-coverable.

5. **Codex prompt file timing.** Current `02-ensemble-adapter.md:112-119` writes the Codex prompt file before launching the Codex CLI. Under joint dispatch, this file write can either happen in step 1.2a (readiness gate) or as part of the dispatch turn. Cleanest: write it at 1.2a immediately after confirming `codex_available=true`. That keeps the dispatch turn purely for launches.

6. **Ensemble real-repo re-run.** Done-when #3 and #7 both require wall-clock evidence from a real ensemble run. If no such run is feasible during close-out (token cost), the close-out note says so and budgets for the first Stage 3 real-repo validation (pattern matches Stage 2.6).

---

## 7. Verification

End-to-end verification plan for when 2.7.B + 2.7.C land:

1. **Smoke suite.** Run `./test/smoke.sh` from repo root. Expect all existing assertions to pass + the 7 new Stage 2.7 assertions (AI-1 through AI-7). Zero regressions.

2. **Non-ensemble flow (fast path).** `SMOKE_KEEP=1` run not needed. Invoke `/adams-review` on a small dummy repo (or the seed fixture already used in smoke.sh) without `--ensemble`. Expect: readiness gate no-ops to trace.md; Phase 1.5 fragment's skip note fires; finding IDs are still monotonic `F001..F0NN`.

3. **Ensemble flow (slow path; real CLIs required).** On a small test repo with CodeRabbit + Codex installed, invoke `/adams-review --ensemble`. Expect:
   - Session transcript shows a single orchestrator turn with ≥8 tool-use blocks for dispatch.
   - `phases.jsonl` shows Phase 1 and Phase 1.5 records with overlapping `ts` windows.
   - Finding IDs non-colliding across the internal + external pool; all IDs appear exactly once.
   - Wall-clock comparison to a pre-2.7 ensemble run of similar-sized diff shows measurable reduction (target: max(internal, external) vs. internal + external).

4. **Stop-to-fix-CLIs path.** Remove Codex from PATH temporarily. Invoke `/adams-review --ensemble`. Expect: `AskUserQuestion` fires before any lens Agent dispatch (no Phase 1 tokens spent). Choose "Stop so I can set them up first" — command exits cleanly with remediation command printed.

5. **DESIGN consistency.** Grep DESIGN.md for `Phase 1.5` and `§13.12` references. Confirm §4 narrative and §13.12 don't contradict each other on dispatch ordering or ID-assignment semantics.

---

## Critical files (paths to modify)

- `DESIGN.md` — new §13.12, §4 Phase 1 / Phase 1.5 narrative, pipeline diagram (§4 lines 81-100).
- `commands/_shared/01-detection.md` — new step 1.2a; step 1.3 dispatch additions; step 1.4 pool semantics; new step 1.5 join; 1.5 → 1.6 rename.
- `commands/_shared/02-ensemble-adapter.md` — remove 1.5.1 (moved); add pointer preambles; 1.5.5 emits to `external_candidates`; 1.5.6 splits (token-log stays, `--add-finding` loop moves out); 1.5.7 summary unchanged.
- `commands/adams-review.md` — TaskList guidance tweak in "Execution overview".
- `commands/_shared/tools/assign-finding-ids.sh` — new helper, ~40 LoC Bash + jq.
- `test/smoke.sh` — new Stage 2.7 block with AI-1 through AI-7 assertions.
- `BUILD.md` — stage index row update; Stage 2.7 close-out section.
- `plans/stage-2.7-detection-parallel.md` — durable plan (copy of this file).

**Existing helpers/utilities reused:**

- `log-phase.sh` — `phase_1_5_start_epoch` hoist just moves WHERE it's captured; the log calls themselves stay.
- `log-tokens.sh` — unchanged; still per-agent, still atomic append.
- `artifact-patch.py --add-finding` — unchanged; called once per IDed candidate in the new join step.
- Existing jq-n + `del(.source_family, .evidence_snippet)` idiom in 01-detection.md 1.4 step 3 — preserved verbatim in the new 1.5 join step.
- `origin-crosscheck.sh` — unchanged; still called per-lens-batch in 1.4.
- `AskUserQuestion` + readiness probe prose — copied from 02-ensemble-adapter.md 1.5.1 verbatim into 01-detection.md 1.2a.

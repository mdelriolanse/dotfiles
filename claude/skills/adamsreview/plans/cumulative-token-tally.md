# Cumulative token tally — refresh `subagent_tokens` across the full review lifecycle

**Status:** drafted 2026-04-21; awaiting user approval.
**Pattern:** one new helper (`tally-subagent-tokens.sh`), three fragment edits (`07-finalize.md`, `10-post-fix-and-commit.md`, `adams-review-add.md`, `adams-review-walkthrough.md`), smoke additions. No schema change.

---

## Context

Every phase that dispatches a sub-agent appends one line to `tokens.jsonl` via `log-tokens.sh`. Phase 6.2 of `/adams-review` reads that log with a `jq -s` rollup and writes the aggregate into the artifact's `subagent_tokens` field (total, invocations, by_phase, by_model, by_lens, by_finding_phase4). That rollup is rendered into `artifact.md` and published to the PR comment.

Follow-up commands (`/adams-review-fix`, `/adams-review-add`, `/adams-review-walkthrough`) **append new lines** to `tokens.jsonl` as they dispatch their own sub-agents (fix-group edits, Phase 9 post-fix review, Phase 9.pre reconcile, paste normalizer, walkthrough briefer, issue-filer, etc.), but **never re-run the Phase 6.2 rollup**. The `subagent_tokens` field on the artifact stays frozen at the snapshot taken when `/adams-review` exited — so readers of `artifact.md` or the PR comment see a total that can be dramatically lower than actual sub-agent spend after a long fix/add/walkthrough lifecycle.

`tokens.jsonl` itself remains authoritative and complete; it's the surfaced aggregate that drifts.

### Scope decision: sub-agents only (this plan)

Claude Code's session transcript at `~/.claude/projects/<cwd-slug>/<session_uuid>.jsonl` does expose per-turn orchestrator usage (`message.usage.input_tokens` / `output_tokens` / `cache_read_input_tokens` / `cache_creation_input_tokens` on `type == "assistant"` lines). Adding orchestrator-token accounting is **out of scope for this plan** — it has independent design questions (transcript-path discovery from inside a slash command, cross-session attribution when `/adams-review-fix` runs in a different session than `/adams-review`, filtering review-work turns from unrelated chitchat, preserving the four separate token categories rather than collapsing). See "Follow-up: orchestrator tokens" at the end for a sketch.

DESIGN §11 is explicit that `subagent_tokens` deliberately excludes the orchestrator — naming stays honest to scope. This plan keeps that contract and only fixes the staleness problem within it.

---

## Goal

After any `/adams-review-fix`, `/adams-review-add`, or `/adams-review-walkthrough` run completes, `artifact.json`'s `subagent_tokens` reflects the full `tokens.jsonl` (cumulative across the initial review + every follow-up), and the re-rendered `artifact.md` + re-published PR comment surface that cumulative total.

**Done when:**

1. A new helper `commands/_shared/tools/tally-subagent-tokens.sh` encapsulates the Phase 6.2 rollup and can be called by any phase.
2. `07-finalize.md` §6.2 calls the helper instead of inlining `jq`. Behavior preserved bit-for-bit on fresh-review runs.
3. `10-post-fix-and-commit.md` §9e (both commit and no-commit branches) calls the helper before `artifact-render.py`, so the post-fix PR comment reflects fix-run sub-agent spend.
4. `adams-review-add.md` calls the helper before its final render (paste normalizer + optional Phase 4 re-validators get counted).
5. `adams-review-walkthrough.md` calls the helper before its final render (briefer + issue-filer agents get counted).
6. `test/smoke.sh` gains `TK-*` assertions covering empty log, populated log, idempotent re-tally, and cumulative growth across two runs.
7. `CLAUDE.md` helper index lists `tally-subagent-tokens.sh`; the "Pipeline shape" section notes that the three lifecycle commands re-tally.

---

## Ground rules (restated)

- **No schema change.** `subagent_tokens`'s shape is already fixed by `schema-v1.json` §`subagent_tokens` — the helper writes the same shape, just over a larger input.
- **Helper is a pure readback.** It reads `tokens.jsonl` + writes `subagent_tokens`. It does not read, write, or validate any other artifact field. `artifact-patch.py --set-json` handles validation per existing `SETTABLE_ARTIFACT_FIELDS` ("subagent_tokens" is already allowlisted).
- **Graceful on sparse inputs.** Empty `tokens.jsonl` (hypothetical — log is created at Phase 0) must produce a valid rollup (`total: 0`, `invocations: 0`, empty sub-objects) rather than error. The current jq expression already handles `tokens: null` entries; extend the defense to "zero lines" by wrapping `add` in `// 0`.
- **Append-only semantics preserved.** The helper never touches `tokens.jsonl`. Subsequent re-tallies simply re-read the growing log.
- **No cross-phase coupling beyond a single helper call.** Each lifecycle command calls the helper at its existing render/publish boundary — no new phase, no new artifact fields, no behavior changes on Phase 8's fix gate or anywhere else.

---

## Implementation steps

### 1. New helper — `commands/_shared/tools/tally-subagent-tokens.sh`

```bash
#!/usr/bin/env bash
# tally-subagent-tokens.sh — roll tokens.jsonl into subagent_tokens on the artifact.
#
# Usage:
#   tally-subagent-tokens.sh --tokens-log <path> --artifact <path>
#
# Reads every line of <tokens-log> and writes the aggregate into
# <artifact>.subagent_tokens via artifact-patch.py --set-json. The
# aggregate shape matches schema-v1.json §subagent_tokens:
#   { total, invocations, by_phase, by_model, by_lens, by_finding_phase4 }
#
# Safe to call repeatedly. `tokens: null` entries are coerced to 0
# (observability fallback from log-tokens.sh). Empty log → zero rollup.
#
# Exits: 0 success; 1 write failure; 5 missing dep; 64 usage error.
```

- `--tokens-log` and `--artifact` both required; absolute paths.
- `jq -s` expression lifted verbatim from `07-finalize.md:26-33`, with a guard for the empty-array case: `([.[] | .tokens // 0] | add) // 0` on the `total` line, and `group_by` branches stay safe (they produce `{}` on empty input).
- On success, print one summary line to stdout: `tally: total=<N> invocations=<M>`. Phase fragments forward that into `trace.md` via their existing `log-phase.sh` scaffolding (no change required there).
- Error-as-prompt on every failure (per Operational rule 4): "ERROR:" / "Action:" stderr sections, no stack traces on expected errors.
- Write path uses `--set-json subagent_tokens=@<tmp>` then `rm -f <tmp>` — same pattern as the current 07-finalize block.
- **Allowed-tools grant format** (per Operational rule 10, absolute paths): every fragment that calls the helper adds `Bash(/Users/adammiller/.claude/commands/_shared/tools/tally-subagent-tokens.sh:*)` to its frontmatter `allowed-tools` list.

### 2. Refactor — `commands/_shared/07-finalize.md` §6.2

Replace the inlined `subagent_tokens=$(jq -s …)` + `echo` + `artifact-patch.py --set-json` block (lines 22–44) with a single helper invocation:

```bash
~/.claude/commands/_shared/tools/tally-subagent-tokens.sh \
  --tokens-log "$tokens_log_path" \
  --artifact   "$artifact_path"
```

Keep the surrounding prose about "why the tally is cheap / why null-coerce is fine" — it still reads correctly as commentary on what the helper does. Update the §6.2 heading wording slightly if needed ("Tally `subagent_tokens` from `tokens.jsonl` via helper").

### 3. Wire into `/adams-review-fix` — `commands/_shared/10-post-fix-and-commit.md` §9e

Both the committed-branch (§9e, line ~998) and no-commit branch (§9e, line ~1156) call `artifact-render.py` and then `artifact-publish.sh`. Add the helper call **immediately before** `artifact-render.py` in both branches:

```bash
~/.claude/commands/_shared/tools/tally-subagent-tokens.sh \
  --tokens-log "$tokens_log_path" \
  --artifact   "$artifact_path"
```

`$tokens_log_path` is already in scope (established in Phase 7 via `08-fix-loader.md:52`). Adding the frontmatter grant to `commands/adams-review-fix.md` `allowed-tools` completes the wiring.

### 4. Wire into `/adams-review-add` — `commands/adams-review-add.md`

Add the helper call just before the final render at line ~792. `$tokens_log_path` is already established at line 174.

### 5. Wire into `/adams-review-walkthrough` — `commands/adams-review-walkthrough.md`

Add the helper call just before the final render at line ~708. Walkthrough dispatches multiple briefer agents + optional issue-filer agents, so its incremental contribution can be meaningful. `$tokens_log_path` needs to be confirmed in scope here — if not, derive it the same way the existing `log-tokens.sh` call sites do.

Add `Bash(/Users/adammiller/.claude/commands/_shared/tools/tally-subagent-tokens.sh:*)` to the walkthrough's `allowed-tools` frontmatter.

### 6. Smoke additions — `test/smoke.sh`

Four `TK-*` assertions:

- **TK-01** — helper on empty `tokens.jsonl` writes `{total: 0, invocations: 0, by_phase: {}, …}` and schema-validates.
- **TK-02** — helper on a 3-line synthetic log (mix of phases, models, one `tokens: null` entry) writes correct `total`, `invocations: 3`, and populated `by_phase`.
- **TK-03** — helper re-invoked on the same log is idempotent: artifact bit-for-bit identical (use `jq -S` + `diff`).
- **TK-04** — append two more lines to the log, re-invoke, confirm `total` strictly increases by the sum of the two new `tokens` values. This is the cumulative-growth invariant that this whole plan exists to enforce.

Numbers follow CLAUDE.md's "new helpers should add 2–3 assertions" guidance; four is acceptable because TK-04 is the load-bearing lifecycle check.

### 7. Doc updates — `CLAUDE.md`

- **Helper index → Utilities table:** add row `| tally-subagent-tokens.sh | Bash | `tokens.jsonl` → `subagent_tokens` rollup helper. Called by Phase 6 and every lifecycle-command terminus. |`
- **Pipeline shape section:** one-line note on each of `/adams-review-fix`, `/adams-review-add`, `/adams-review-walkthrough` that "re-tallies `subagent_tokens` before re-render." Keep the diagrams unchanged — this isn't a new phase, it's a pre-publish step.
- **No archive update** (archive is frozen per CLAUDE.md §"How to work on new changes").

---

## Blast-radius checks

Per user's global CLAUDE.md §"Blast-radius discipline":

- **Every writer of `subagent_tokens`:** only `07-finalize.md` §6.2 writes it today. Grep confirms — `grep -rn "subagent_tokens" commands/` shows the field name in `07-finalize.md`, `00-preflight.md` (initializer scaffolding), `schema-v1.json`, and `artifact-patch.py`'s `SETTABLE_ARTIFACT_FIELDS`. After this plan, four sites write it (finalize + fix + add + walkthrough). All four use the same helper; no divergent rollup logic.
- **Every consumer of `subagent_tokens`:** `artifact-render.py:162` reads it into the rendered report. The shape doesn't change, so the renderer needs no update. The PR comment is a straight render-and-POST — no separate consumer.
- **Parallel code paths:** the three lifecycle commands (`fix`, `add`, `walkthrough`) all re-render + re-publish at their terminus. All three gain identical pre-render calls. Diff check: render and publish args are identical across the three today; this plan doesn't introduce divergence.
- **Full implementation of `artifact-patch.py --set-json`:** already accepts `subagent_tokens`; atomic-write + schema-validate on every write; no state-transition logic involved (it's a top-level field, not a per-finding mutation). Safe to re-invoke.
- **Stale docs:** the §6.2 prose + CLAUDE.md helper index are the only doc surfaces. Archive is frozen and will not be touched. DESIGN §11's "at report time" phrasing is already vague enough to cover multiple report times; no archive edit needed.

---

## Not doing

- **Orchestrator-token accounting.** Scoped out — sketch below.
- **Refactoring `07-finalize.md` §6.2's surrounding steps** (`reviewer_sources` recomputation, `metrics` population). They share the same "at finalize time" pattern but are separate concerns.
- **Changing `tokens.jsonl`'s schema.** The per-line format is stable and the jq rollup depends on it.
- **Bundling tally into `artifact-render.py`.** The helper is a separate tool because `/adams-review-fix`'s Phase 9 calls `artifact-render.py` in multiple branches, and we want the tally to be an explicit step — not a side effect of rendering. Also keeps `artifact-render.py` a pure read-render-write on the artifact.

---

## Follow-up: orchestrator tokens (separate plan, not included here)

Sketch for when we tackle this:

- **Helper:** `orchestrator-tokens.sh` — reads an orchestrator session's `.jsonl` transcript, filters `type == "assistant"` lines with `timestamp >= review_started_at`, sums `message.usage.{input_tokens, output_tokens, cache_read_input_tokens, cache_creation_input_tokens}`. Writes to a new top-level artifact field `orchestrator_tokens` (requires schema addition).
- **Path discovery — two options:**
  - **Heuristic (simple):** newest `.jsonl` under `~/.claude/projects/<cwd-slug>/` where cwd-slug is cwd with `/` → `-`. Works for same-session lifecycles; breaks across sessions.
  - **Handle-stashed (robust):** add a `SessionStart` hook (or similar) that writes `$CLAUDE_TRANSCRIPT_PATH` from the hook input into `$review_dir/session-handles.jsonl`. Every command that runs within the review lifecycle appends its session handle; the helper sums across all of them. Handles cross-session fix runs cleanly.
- **Schema addition:** `orchestrator_tokens: { total_input, total_output, cache_read, cache_creation, turn_count, sessions: [...] }`. Four separate counters preserved because cache-read tokens have different $/token than fresh input.
- **Caveat to surface in the plan:** the transcript mixes review-work with unrelated chitchat in the same session. Even filtering by `review_started_at` isn't bulletproof — the user might be multitasking. Either accept the over-count or add begin/end markers (e.g., a `UserPromptSubmit` hook that checkpoints slash-command boundaries).

Estimate: ~1 helper + ~1 schema addition + 1–2 hook-config changes + smoke. Similar size to this plan, but with more design decisions around attribution semantics.

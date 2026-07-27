---
name: adamsreview
description: Multi-stage code review pipeline — parallel sub-agent detection, validation passes, persistent JSON state, and an automated fix loop.
argument-hint: "[review|fix|add|walkthrough|promote] [options...]"
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, question, Task, todowrite
compatibility: omp
metadata:
  author: "<org>-team"
  version: "0.5.0-omp"
  domain: quality
  triggers: code review, PR review, review, adamsreview
  role: specialist
  scope: review
---

# adamsreview — multi-stage code review for omp

Ported from the Claude Code plugin. **Same semantics, same helpers, same
artifact shape** — only the runtime bindings (sub-agent dispatch, prompts,
tool grants) differ.

**Commands** (name in your message to route):

- **`review [--full]`** — multi-lens review (6 parallel lenses). Phases 0–6c.
- **`fix [threshold] [--granular-commits]`** — automated fix loop. Phases 7–9.
- **`add [paste...]`** — inject external findings into latest review.
- **`walkthrough [threshold]`** — interactive driver for manual findings.
- **`promote <id>`** — promote a finding to auto-fixable.

Each command is independent. Recommended flow: `review` → optional `add` →
optional `walkthrough` → `fix`.

## Layout

```
~/.omp/agent/skills/adamsreview/
├── SKILL.md                          ← this file
├── bin/                              ← helper scripts (all bash/Python, portable)
│   ├── artifact-read.sh / -patch.py / -render.py / -validate.sh / -publish.sh / -seed.sh
│   ├── log-phase.sh / log-tokens.sh / tally-subagent-tokens.sh
│   ├── group-fixes.py / assign-finding-ids.sh / freshness-gate.sh
│   └── ... (25 helpers total)
├── references/
│   ├── fragments/
│   │   ├── _prelude-shared.md        ← shared rules for all phases
│   │   ├── 00-preflight.md → 10-post-fix-and-commit.md  ← phase fragments
│   │   ├── promote-core.md           ← shared for promote + walkthrough
│   │   └── lens-prompts/             ← L1–L7 detection lens prompt bodies
│   ├── state-and-gates.md            ← normative spec for finding states
│   ├── pipeline.md                   ← phase trees + token tally semantics
│   └── helpers.md                    ← helper script inventory
├── test/                             ← smoke harness + fixtures
└── plans/                            ← historical design docs
```

## Operational rules

1. **Bash 3.2 portable.** macOS `/bin/bash` 3.2 in practice. Avoid `declare -A`,
   `mapfile`/`readarray`, `${var,,}`. `awk '!seen[$0]++' | sort` for dedup.

2. **uv shebang for Python helpers.** `#!/usr/bin/env -S uv run --quiet --script`
   with a `# /// script` inline dep spec. Never `pip install`.

3. **Exit codes are a contract.** Python helpers: `0=OK, 1=validation,
   2=invalid-transition, 3=dry-run-invalid, 4=unexpected, 5=missing-dep,
   6=expected-mismatch, 7=all-rejected, 64=usage`. Defined in `bin/_common.py`.

4. **Error-as-prompt on every helper.** Non-zero exits emit `ERROR:` / `Valid
   input:` / `Did you mean:` / `Action:` stderr sections. No stack traces on
   expected errors.

5. **Atomic writes.** Writers go tmp-file → `rename`. On-disk artifact never in
   invalid state mid-run.

6. **Reviews root is `~/.adams-reviews/`.** Not under `~/.claude/` or
   `~/.omp/`. Override via `$ADAMS_REVIEW_REVIEWS_ROOT`.

7. **`repo_slug` comes from one helper.** `bin/repo-slug.sh --repo-root <path>`
   is the single source of truth. Never reimplement inline.

8. **Commit messages via `git commit -F <file>`**, not `-m "$(…)"`. Finding
   claims contain quotes/backticks/newlines.

9. **Fix-group agents may not delete or rename files.** Layered enforcement:
   prompt prohibition + Phase 9.pre `git status --porcelain` scan.

10. **Working set lives in-prompt, not shell vars.** Fragments are Read-loaded
    as orchestrator context, so variables like `review_id`, `comparison_ref`,
    `reviewed_files_all` are context values, not `$VAR`s. When a later fragment
    needs an artifact-stored value, call `artifact-read.sh --filter '.foo'`.

11. **`printf '%s\n'`, not `echo`, when piping JSON through bash variables.**
    Under zsh/dash/bash with `xpg_echo`, `echo "$x"` collapses `\\` to `\`.
    Artifact on disk is fine; corruption only happens in the bash round trip.

12. **Helper paths.** When invoking helpers, use absolute paths:
    `$SKILL_ROOT/bin/<helper>`. All helpers are under `bin/`.

## Operational rules

### MANDATE: Read every fragment in its entirety

**Every phase of this skill is defined by a fragment file under
`references/fragments/`.** The orchestrator MUST read each fragment
*completely* before executing any step within that phase.

- Do NOT summarize, paraphrase, or rely on memory of what a phase
  "usually" does.
- Do NOT skip to the "Dispatch turn" boilerplate without having read
  every per-lens sub-section, every substitution rule, every jq
  builder, every schema shape, and every bash block.
- For long fragments, use `Read` with `offset`/`limit` to consume
  every segment sequentially — but do not execute any sub-agent
  dispatch, any `artifact-patch.py`, or any state transition until the
  full fragment text is in your working context.

Violating this mandate produces:
- Hallucinated prompts with wrong `source_family` / `impact_type`
- Schema-rejected candidates that silently drop from the pool
- Incorrect score rubrics and mis-routed dispositions
- Broken `jq` builders that corrupt the finding-pool join

If you are ever unsure whether a fragment was fully consumed, re-read
it. The cost of reading is zero; the cost of a hallucinated dispatch
is a broken artifact.

### Sub-agent model policy

**This skill is model-agnostic.** Every sub-agent dispatches with
`subagent_type: general` and no per-call model specification. All
sub-agents run under the orchestrator's globally configured model.
References to `opus`, `sonnet`, `haiku`, or `Codex`/`CodeRabbit` in
any prose are legacy descriptions from the original Claude Code
plugin; they do NOT apply to the omp port. Token logging still
accepts a `--model` field for observability, but it is optional and
carries no semantic weight.

### Other rules

1. **Bash 3.2 portable.** macOS `/bin/bash` 3.2 in practice. Avoid `declare -A`,
   `mapfile`/`readarray`, `${var,,}`. `awk '!seen[$0]++' | sort` for dedup.

2. **uv shebang for Python helpers.** `#!/usr/bin/env -S uv run --quiet --script`
   with a `# /// script` inline dep spec. Never `pip install`.

3. **Exit codes are a contract.** Python helpers: `0=OK, 1=validation,
   2=invalid-transition, 3=dry-run-invalid, 4=unexpected, 5=missing-dep,
   6=expected-mismatch, 7=all-rejected, 64=usage`. Defined in `bin/_common.py`.

4. **Error-as-prompt on every helper.** Non-zero exits emit `ERROR:` / `Valid
   input:` / `Did you mean:` / `Action:` stderr sections. No stack traces on
   expected errors.

5. **Atomic writes.** Writers go tmp-file → `rename`. On-disk artifact never in
   invalid state mid-run.

6. **Reviews root is `~/.adams-reviews/`.** Not under `~/.claude/` or
   `~/.omp/`. Override via `$ADAMS_REVIEW_REVIEWS_ROOT`.

7. **`repo_slug` comes from one helper.** `bin/repo-slug.sh --repo-root <path>`
   is the single source of truth. Never reimplement inline.

8. **Commit messages via `git commit -F <file>`**, not `-m "$(…)"`. Finding
   claims contain quotes/backticks/newlines.

9. **Fix-group agents may not delete or rename files.** Layered enforcement:
   prompt prohibition + Phase 9.pre `git status --porcelain` scan.

10. **Working set lives in-prompt, not shell vars.** Fragments are Read-loaded
    as orchestrator context, so variables like `review_id`, `comparison_ref`,
    `reviewed_files_all` are context values, not `$VAR`s. When a later fragment
    needs an artifact-stored value, call `artifact-read.sh --filter '.foo'`.

11. **`printf '%s\n'`, not `echo`, when piping JSON through bash variables.**
    Under zsh/dash/bash with `xpg_echo`, `echo "$x"` collapses `\\` to `\`.
    Artifact on disk is fine; corruption only happens in the bash round trip.

12. **Helper paths.** When invoking helpers, use absolute paths:
    `$SKILL_ROOT/bin/<helper>`. All helpers are under `bin/`.

## State, gates, lanes (TL;DR)

- **States.** `open` → `attempted` → `resolved` | `→ open` (regression). Leftover
  `attempted` on fresh `:fix` → hard abort.
- **Disposition** is the routing key (11 values). `is_actionable` derives from
  disposition; never set independently.
- **Score gates.** Phase 3: 45. Phase 4 bands: 45/60/75. Phase 8 fix gate:
  composite (state + disposition + lane + threshold); `human_confirmation != null`
  bypasses both lane and threshold.
- **Pre-existing override**: `origin == pre_existing AND origin_confidence == high`
  → `pre_existing_report` regardless of score.
- **Lanes.** Deep = correctness/security. Light = ux/policy/architecture.

Full normative spec: `references/state-and-gates.md`.

## Sub-agent dispatch pattern

Every `Task` tool-use specifies `subagent_type: general`.
Sub-agents inherit the orchestrator's globally configured model; no
per-call `model:` parameter exists in the omp port.

**Parallel fan-outs** happen by firing multiple `Task` blocks in a single
orchestrator turn. Always batch within one turn.

After every sub-agent returns, before branching on its content:
1. Extract the token count from the Task result
2. Call `$SKILL_ROOT/bin/log-tokens.sh` with phase, agent_role, agent_id, tokens
3. Parse the sub-agent's structured output. Light repair OK. One retry on parse
   failure. Drop-with-note on second failure.

## Helper-script errors — error-as-prompt

When a helper exits non-zero, parse the stderr, adjust your inputs per the
guidance, retry ONCE. Only escalate to the user if the second retry also fails.

## Command routing

Read the user's first argument to determine which pipeline to run:

### `review [--full]`

Execute Phases 0–6 in order. At each phase boundary, read the named fragment
with the `Read` tool and execute the instructions inside.

Parse arguments: `--full` → `force_full=true` (else `false`).

Build a `todowrite` list mirroring these phases:

| Phase | Fragment | Description |
|---|---|---|
| 0 | `references/fragments/00-preflight.md` | Preflight (branch, diff, freshness) |
| 1 | `references/fragments/01-detection.md` | Detection (6 parallel lens agents) |
| 2 | `references/fragments/03-dedup.md` | Dedup |
| 3 | `references/fragments/04-scoring-gate.md` | Scoring gate |
| 4 | `references/fragments/05-validation.md` | Validation (deep + light lanes) |
| 5 | `references/fragments/06-cross-cutting.md` | Cross-cutting |
| 5.5 | `references/fragments/06b-auto-fix-hint.md` | Auto-fix-hint generation |
| 6c | `references/fragments/06c-false-positive-audit.md` | False-positive audit (dual-agent challenge) |
| 6 | `references/fragments/07-finalize.md` | Finalize + render + publish |

If a phase cannot run, mark it completed with a one-line `trace.md` note.
Phase 6 runs unconditionally.

### `fix [threshold] [--granular-commits]`

Execute Phases 7–9 in order. Parse arguments: first integer → `threshold`
(default 60). `--granular-commits` → `granular_commits=true`.

| Phase | Fragment | Description |
|---|---|---|
| 7 + 7.5 | `references/fragments/08-fix-loader.md` | Load artifact + auto-rec preflight |
| 8 | `references/fragments/09-fix-execution.md` | Fix execution (parallel fix-group agents) |
| 9 | `references/fragments/10-post-fix-and-commit.md` | Post-fix review + commit |

Phase 8 fix-group agents use `subagent_type: general`.
Phase 9 post-fix reviewer uses `subagent_type: general`.
All git operations (staging, commit, push) happen in the orchestrator.

### `add [paste...] [--file <path> --line <N> --claim "..."]`

Locate latest artifact, validate, build candidates from paste or structured
`--file/--line/--claim`, dedup, assign IDs, run Phase 4 validation (per-candidate
individual + chunked confirmation), apply decisions, re-render, re-publish.

### `walkthrough [threshold]`

Interactive walkthrough for findings `fix` would skip. Default threshold 60.
Per-finding: dispatch sub-agent briefing, present options, record decisions.
Batch auto-rec findings from Phase 5.5 upfront.

### `promote <id> [--reason "..."] [--fix-hint "..."] [--force] [--defer-publish]`

Promote a single finding to auto-fixable. Core logic in
`references/fragments/promote-core.md`.

## Shared prelude

**Read `references/fragments/_prelude-shared.md` before executing any phase.**
It lists rules that apply to every phase (sub-agent return handling,
helper-script error-as-prompt).

## Phase 1.5 / Ensemble

**Not ported to omp.** The ensemble integration (Phase 1.5,
`--ensemble` flag) is not available in the omp port. All ensemble
gating is short-circuited with `ensemble_mode=false`.

The existing L7 (holistic) lens file (`references/fragments/lens-prompts/L7.md`)
remains in the repository for reference purposes but is not dispatched. Phase 6c
(dual-agent false-positive audit) provides a new omp-native quality gate.

## Helper index

**Readers** (no mutation): `artifact-read.sh`, `staleness.sh`, `claude-md-paths.sh`,
`origin-crosscheck.sh`, `line-range-check.sh`, `comment-freshness.sh`,
`prior-fix-diff.sh`, `repo-slug.sh`, `trivial-check.sh`, `artifact-seed.sh`,
`parse-with-repair.py`, `parse-validator-result.py`, `source-family-map.py`

**Writers** (orchestrator-only): `artifact-patch.py`, `artifact-publish.sh`,
`artifact-render.py`, `artifact-validate.sh`

**Utilities**: `log-phase.sh`, `log-tokens.sh`, `freshness-gate.sh`,
`tally-subagent-tokens.sh`, `group-fixes.py`, `assign-finding-ids.sh`,
`external-scrape.sh`, `_common.py`

**Not ported** (Claude-specific): `codex-poll.sh`, `orchestrator-tokens.sh`,
`include`

All helpers under `$SKILL_ROOT/bin/`. Use absolute paths.

## How to test

```bash
bash $SKILL_ROOT/test/smoke.sh   # expects: smoke: PASS (N assertions)
```

## What commands do NOT do

- No review of closed/merged PRs
- Fix-group agents: no deletes, renames, or moves in working tree
- No automated recovery from leftover-`attempted` state
- No light-lane auto-fix without consent
- No ensemble/Codex external review (not ported)

## omp harness

| Claude Code | omp |
|---|---|
| `Agent` tool | `Task` tool (`subagent_type: general`) |
| `model: opus/sonnet/haiku` | Removed (global model config) |
| `AskUserQuestion` | `question` tool |
| `Bash(helper:*):` grants in YAML frontmatter | Absolute `$SKILL_ROOT/bin/` paths |
| `!include` fragment preprocessing | `Read` tool for fragment loading |
| `$CLAUDE_PLUGIN_ROOT` | `$SKILL_ROOT` |
| `$ARGUMENTS` env var | Parsed from user message |
| `TaskList` tracking | `todowrite` |
| Orchestrator token tally (`orchestrator-tokens.sh`) | Dropped (no `~/.claude/projects/`) |
| Codex CLI + `--ensemble` flag | Dropped entirely |
| Hooks (`hooks/hooks.json`) | Not available |
| `bin/include` fragment transclusion | Not used (Read-based) |
| `run_in_background` + `BashOutput` + `KillShell` | Not available |

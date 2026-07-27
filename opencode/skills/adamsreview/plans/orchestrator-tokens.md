# Orchestrator tokens — cumulative per-session token tally alongside `subagent_tokens`

**Status:** shipped 2026-04-21 on branch `token-count` (commits `5ebc40f` → `commit-5`). Companion to `plans/cumulative-token-tally.md`, which closed the sub-agent side of this gap.
**Pattern:** one new helper (`tools/orchestrator-tokens.sh`), schema addition (optional top-level `orchestrator_tokens`), five call sites at every lifecycle terminus, renderer + chat-summary surfacing, seven smoke assertions.

---

## Context

`plans/cumulative-token-tally.md` shipped the lifecycle-wide `subagent_tokens` re-tally: the Phase 6 jq rollup moved into `tools/tally-subagent-tokens.sh` and each lifecycle command terminus (`/adams-review-fix`, `/adams-review-add`, `/adams-review-walkthrough`) re-invokes it before re-rendering. That closed the sub-agent side of the cost-visibility gap.

**What remained.** DESIGN §11 (archive line 1094) is explicit that `subagent_tokens` *deliberately* excludes the orchestrator's own session. On the rev-8 test run BUILD noted the orchestrator consumed ~243K tokens while `subagent_tokens.total` was ~979K — a ~20% slice of total spend that never lands on the artifact. This plan closes that slice.

**Where the data lives.** Claude Code writes a per-session transcript at `~/.claude/projects/<cwd-slug>/<session_uuid>.jsonl`. Every `type == "assistant"` line carries `message.usage.{input_tokens, output_tokens, cache_read_input_tokens, cache_creation_input_tokens}` plus a top-level `timestamp` and `sessionId`. Verified by direct `jq` inspection before planning. The shape matches what `~/.claude/statusline-command.sh:20` reads for the live `ctx:` badge — except the statusline shows *current depth*, not cumulative sum.

**Slug algorithm (verified).** `<cwd-slug>` maps **both** `/` and `.` to `-`. `/Users/.../adams-review/.claude/worktrees/token-count` becomes dir `-Users-adammiller-Projects-adams-review--claude-worktrees-token-count` — the `.` in `.claude` becomes the second `-` in `review--claude`. Algorithm is `tr '/.' '-'`, not just `tr '/' '-'`. Easy to get wrong; guarded directly by smoke assertion OT-1.

---

## Goal

After `/adams-review` finalize and after every `/adams-review-fix` / `-add` / `-walkthrough` terminus, `artifact.json` carries a populated `orchestrator_tokens` field capturing every `type == "assistant"` turn in this review's lifecycle. The rendered report and the lifecycle commands' chat summaries surface it alongside `subagent_tokens`. Helper is called at exactly the five sites the sub-agent tally runs at.

**Done when:**

1. New optional top-level artifact field `orchestrator_tokens` with four separate token counters preserved (fresh input / output / cache-read / cache-creation), a `turn_count`, and a `sessions[]` audit array.
2. New helper `tools/orchestrator-tokens.sh` reads every transcript under `~/.claude/projects/<cwd-slug>/` whose assistant-line timestamps are `>= --since`, sums the four usage fields, writes the rollup via `artifact-patch.py --set-json orchestrator_tokens=@<tmp>`.
3. `schema-v1.json` gains the `orchestrator_tokens` $def (optional, NOT in `required`). `JSON_SETTABLE_ARTIFACT_FIELDS` in `artifact-patch.py` gains `"orchestrator_tokens"`. Existing fixtures keep passing untouched.
4. Wired into: `07-finalize.md` §6.2b (right after the sub-agent tally), `10-post-fix-and-commit.md` §9e step 2 (the "same as committed branch" cross-reference covers both branches), `adams-review-add.md` step 8, `adams-review-walkthrough.md` §6.1. Frontmatter `allowed-tools` grants on all four top-level command files.
5. `artifact-render.py` surfaces the number in `artifact.md` directly under `**Sub-agent tokens:**`. Chat summary lines in add step 10 and walkthrough §9 include an orchestrator line.
6. `CLAUDE.md` helper index + pipeline shape + the clarification on what `subagent_tokens` covers vs. doesn't.
7. `test/smoke.sh` gains seven `OT-*` assertions. Final count: 203 assertions.

---

## Design decisions — what was chosen and why

### Decision 1 — Transcript-path discovery: directory-scan (chosen)

Three options considered:
- **A: Heuristic (newest .jsonl only)** — breaks across sessions.
- **B: Directory-scan with time-window filter** (chosen) — list every `*.jsonl` under `~/.claude/projects/<slug>/`; sum only assistant lines with `timestamp >= $since`.
- **C: Hook-stashed session handles** — most precise, but requires editing `~/.claude/settings.json`.

**Chose B.** Zero config, handles cross-session lifecycles correctly, no hook invasion. The edge case of an unrelated Claude Code session running in the same cwd during the review lifecycle over-counts those turns — documented as acceptable for v1. C can be bolted on later as `--session-handles <path>` if the over-count actually bites.

### Decision 2 — Attribution scope: time-window (chosen)

- **A: Time-window (`timestamp >= review_started_at`)** (chosen) — deterministic, already have `review_started_at` on the artifact.
- **B: Slash-command delimiters** — more accurate but requires a `UserPromptSubmit` hook plus per-command bookkeeping.

**Chose A.** Accepted the over-count from intermission chat. Over-counting biases in the safer direction — the user's bill reflects the over-counted number, so we're not inventing tokens.

### Decision 3 — Schema: optional (chosen)

`subagent_tokens` is in the top-level `required` array. For `orchestrator_tokens` we kept it **optional**:
- Pre-existing artifacts under `~/.adams-reviews/` (including pre-feature ones from before this plan) keep validating unchanged.
- Phase 0's `--init` does NOT need to pre-seed the field — absence means "not yet computed".
- Renderer uses `artifact.get("orchestrator_tokens") or {}` with a `turn_count is not None` guard; absence simply omits the line.

If we later want to make it required, bumping schema to v2 is the right move.

### Decision 4 — Helper language: Bash + jq (chosen)

Matches `tally-subagent-tokens.sh`'s convention. ~190 lines of Bash around one jq expression. Python would have been overkill for what's effectively glorified summation.

---

## Artifact shape (shipped)

```json
"orchestrator_tokens": {
  "total_input": 586,
  "total_output": 394299,
  "cache_read": 44104321,
  "cache_creation": 1444015,
  "turn_count": 330,
  "sessions": [
    {
      "session_id": "0cf22244-129f-4f2b-a43d-c59d04bdb236",
      "transcript_path": "/Users/.../0cf22244-129f-4f2b-a43d-c59d04bdb236.jsonl",
      "first_seen": "2026-04-21T23:37:36.102Z",
      "last_seen":  "2026-04-22T00:36:00.687Z",
      "turn_count": 330
    }
  ]
}
```

Four counters preserved separately because cache-read $/token is roughly an order of magnitude cheaper than fresh input — collapsing hides the real cost signal. `sessions[]` is sorted by `first_seen`. `turn_count` at the top level equals `sum(sessions[].turn_count)`.

---

## Implementation map (per-concern commits)

| Commit | Scope | Files |
|---|---|---|
| 1 | Schema + helper + patch allowlist | `schema-v1.json`, `tools/orchestrator-tokens.sh` (NEW), `tools/artifact-patch.py` |
| 2 | `/adams-review` finalize wiring | `_shared/07-finalize.md` §6.2b, `adams-review.md` frontmatter |
| 3 | Lifecycle commands wiring | `_shared/10-post-fix-and-commit.md` §9e, `adams-review-add.md` step 8, `adams-review-walkthrough.md` §6.1, + fix/add/walkthrough frontmatter |
| 4 | Renderer + chat-summary surfacing | `tools/artifact-render.py`, `adams-review-add.md` step 10, `adams-review-walkthrough.md` §9 |
| 5 | CLAUDE.md + smoke + this plan | `CLAUDE.md`, `test/smoke.sh` (+7 OT-* assertions), `plans/orchestrator-tokens.md` (NEW) |

---

## Smoke coverage (OT-* prefix)

- **OT-1** — slug derivation: `/Users/x/.claude/worktrees/y` → `-Users-x--claude-worktrees-y`. Guards the easy-to-break `tr '/.' '-'` algorithm directly.
- **OT-2** — missing transcript dir → zero rollup; schema-validates.
- **OT-3** — 3-turn synthetic transcript, known usage. Verifies all four counter sums, `turn_count=3`, `sessions[]` length 1.
- **OT-4** — cross-session merge: two transcripts in same dir, distinct sessionIds. Verifies `sessions[]` length 2, sorted by `first_seen` (earlier session first).
- **OT-5** — time-window filter: future-`--since` zeros everything; mid-window `--since` keeps only post-since turns.
- **OT-6** — non-assistant line types (`user`, `system`, `worktree-state`, `attachment`) are ignored by the filter.
- **OT-7** — second-precision `--since` (the format Phase 0 writes via `date -u +%Y-%m-%dT%H:%M:%SZ`) correctly includes same-second turns whose timestamps carry milliseconds. Guards against the lexical `.500Z < Z` pitfall by padding bare-seconds input to `.000Z` inside the helper.

---

## Blast radius (checked before each commit)

- **Writers of `orchestrator_tokens`:** only the helper. Five fragment/command call sites invoke the same helper with the same args. No divergent rollup logic.
- **Consumers:** `artifact-render.py` line 167-176 and the two chat summary sites (add step 10, walkthrough §9). Both null-safe fallback patterns. Old artifacts (no `orchestrator_tokens`) render exactly as before.
- **Parallel paths:** the five terminus sites each already call `tally-subagent-tokens.sh`. Pairing each with an orchestrator call is a trivial diff — both helpers become call-siblings. Cross-site diff stays minimal.
- **Schema:** new field is optional. `jsonschema` validator passes old artifacts unchanged. Mid-lifecycle fix runs against a pre-feature artifact work: helper writes the field where it didn't exist before, schema still validates, renderer picks it up.
- **Patch allowlist:** new entry in `JSON_SETTABLE_ARTIFACT_FIELDS`; no other change to patch semantics.
- **Orchestrator-token vs sub-agent-token overlap:** these are *complementary*, not overlapping. Sub-agent tokens are the sub-agents' own internal API calls. Orchestrator tokens are the main session's per-turn `message.usage`, which includes the cost of *reading* sub-agent tool-result text back on subsequent turns but NOT the sub-agent's internal generation.
- **Cwd in worktrees:** helper defaults `--cwd` to `$(pwd -P)`, which equals the Claude Code session's cwd — the value whose slugged form names the transcript directory. Call sites do NOT pass `--cwd $repo_root`, which would mis-point under worktrees.

---

## Known limitations (documented, not bugs)

- **Same-cwd unrelated-session over-count** (Decision 1 tradeoff). Rare but real.
- **Multitasking over-count** (Decision 2 tradeoff). If you chat with Claude about unrelated things mid-review, those turns count.
- **Compacted sessions.** `/compact` preserves `sessionId` and appends new turns to the same transcript file. Time-window filter handles this cleanly.
- **Tally runs BEFORE the render/publish turns.** So the helper misses orchestrator spend on the tally/render/publish turns themselves. Matches sub-agent tally semantics. Next lifecycle command's tally catches the previous run's trailing turns.
- **No pricing math.** Raw token counts only. Converting to dollars requires per-model rates that change; out of scope and a different kind of report.

---

## Not doing

- No hook installation (neither SessionStart nor UserPromptSubmit). Decisions 1 + 2 stay out of `~/.claude/settings.json`.
- No pricing math.
- No per-phase/per-lens breakdown of orchestrator tokens — the transcript doesn't know which slash-command phase was active.
- No schema v2 bump.
- No rework of `subagent_tokens`. Both live side by side.

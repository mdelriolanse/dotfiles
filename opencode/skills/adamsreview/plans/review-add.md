# Plan: /adams-review-add — inject externally-sourced findings into a finished review

Status: draft, awaiting approval
Branch: `review-add`
Related CLAUDE.md sections to update: pipeline shape (add `/adams-review-add` to the recommended flow), helper index (no new entries — pure orchestration), operational rules (no change)
Related schema/helper changes: none (or one tiny: optional `--start-from` flag on `assign-finding-ids.sh`)

## 1. Goal

Give the reviewer a single command that ingests bug claims from a parallel review session — Claude Code's cloud `/ultrareview`, an Opus once-over, CodeRabbit run outside `--ensemble`, or a human note covering N issues — validates them through Phase 4, and lands them in the **existing** `artifact.json` for the current branch's most recent review, so `/adams-review-fix` (or `/adams-review-walkthrough`) picks them up on their next run as if Phase 1 had surfaced them.

Concrete use cases:

- `/ultrareview` (cloud) returns a chat dump listing 4 bugs after `/adams-review` already finished. Reviewer pastes the dump:
  `/adams-review-add` (with the paste as `$ARGUMENTS`).
- Reviewer manually inspecting the diff finds something the lenses missed:
  `/adams-review-add --file src/foo.ts --line 142 --claim "early-return skips the audit-log emit"`.
- Reviewer wants to hand an Opus a transcript: chats with Opus in another window, copies the verdict, pastes here.

Outcome in all cases: 1–N new `F0NN` findings appear in the existing artifact, validated by Phase 4, and the PR comment is re-rendered + re-published so the new findings show up in the same comment alongside the original review's findings.

## 2. Non-goals / explicitly deferred

- **No new top-level review run.** This is additive to an existing artifact — does not re-run Phase 1, Phase 2, Phase 5, or any cross-cutting analysis. If the user wants a full re-review, they run `/adams-review` (which overwrites the artifact).
- **No Phase 5 cross-cutting recompute.** The added findings are not retroactively grouped into existing `cross_cutting_groups`. Documented small loss; the rendered report still shows them in the standard per-finding tables.
- **No demote / undo.** Mirroring `/adams-review-promote`'s philosophy. To remove a mistakenly-added finding, manually patch:
  `artifact-patch.py --delete-finding F0NN`.
- **No multi-paste batching across invocations.** One invocation = one ingestion (which may itself contain N findings). Re-invoke for additional pastes.
- **No source-attribution beyond `sources` and `source_families`.** The trace entry records the raw input; the finding's `sources` carries `"external-add:<channel>"`. Nothing fancier (no separate `external_reviews[]` artifact field).
- **No persistence across fresh `/adams-review` runs.** Same property as promote — a re-review overwrites. Future work: a sidecar that re-applies adds + promotes after detection (out of scope for this stage).

## 3. Key design decisions

### 3.1 Skip Phase 3; auto-graduate to Phase 4

Phase 3's job is to filter weak lens-derived candidates cheaply before spending Opus on Phase 4. Externally-sourced candidates have already paid that filtering cost — a person bothered to escalate them. Auto-graduating to Phase 4 mirrors the existing §13.1 "≥ 2 source families → auto-graduate" rule: if multiple signals already agree the candidate matters, don't risk demoting it via the cheap gate.

Also avoids a confusing failure mode: Phase 3 marking a real, human-escalated bug as `below_gate` and dropping it. The cost is one extra Opus validation per candidate vs. the Sonnet score-then-validate pair; cheap insurance.

### 3.2 Single Sonnet "paste normalizer" handles all input shapes

Reuse the Phase 1.5 normalizer pattern (`02-ensemble-adapter.md:222-280`) almost verbatim. One Sonnet sub-agent receives:

- The user's free-form paste (chat dump, comment thread, structured list — whatever).
- Optional structured overrides (when the user passed `--file`, `--line`, `--claim`).
- The list of files in the diff (for location-resolution context — same envelope `reviewed_files_all` the existing artifact carries).

Returns the standard candidate-array shape Phase 1.5 already emits. Same `file: null → "(unknown)"` repair, same `line_range: null → [1,1]` fallback. The normalizer is permissive: if the user hand-typed a single claim with no file, it produces one candidate; if the user pasted a six-bug ultrareview dump, it produces six.

The structured `--file --line --claim` shorthand short-circuits the normalizer entirely (no LLM call needed) — useful when the reviewer knows exactly what they want to add.

### 3.3 Dedup against the existing findings list (one Sonnet call)

A reviewer using `/ultrareview` may surface findings the original review already caught. Re-use Phase 2's dedup contract (`03-dedup.md:34-60`) but constrained: input is `(new_candidates ∪ existing_findings)`, only collapse when a new candidate matches an existing finding's claim+file+line — never collapse two existing findings. Two outcomes per new candidate:

- **Matched an existing finding** → drop the new candidate, append the new `sources[]` entry to the matched finding via `--set-json sources=@…` (preserves the audit trail that this issue was independently identified by another reviewer). Log to trace.
- **No match** → proceed to validation as a fresh candidate.

Cost: one Sonnet call. Saves a more expensive double-Opus-validation when the bug was already in the artifact.

### 3.4 Standard Phase 4 validation, no special path

The Phase 4 validator prompts (`05-validation.md` §4.2 deep, §4.3 light) take any well-formed candidate JSON and return a `validation_result`. Reuse them verbatim. Lane partitioning by `validation_lane` is identical: deep for `correctness`/`security`, light for `ux`/`policy`/`architecture`.

Skip Wave 2 chain retry — the user is adding a small, bounded set; following `related_candidates_to_investigate` chains would expand scope unpredictably. Documented as "if validators surface adjacents, they appear in the validator's notes but aren't auto-promoted to new findings."

Apply decisions via `--apply-decisions` exactly as Phase 4.4 does.

### 3.5 ID assignment: continue the existing sequence, don't rebuild

Phase 1's `assign-finding-ids.sh` operates on a fresh pool — it always emits `F001..F0NN` from index 0. We need "next ID after the highest existing F-id." Two options:

- **Option A (preferred):** add an optional `--start-from F037` flag. One-line change to the jq's index expression. Backwards-compatible (default is `F001` as today).
- **Option B:** inline derivation in the new command (one jq expression to compute `max + 1`, then assign IDs locally).

Lean toward Option A: keeps ID assignment in one place, makes the helper reusable for any future "add to existing" flow. Cost is ~5 lines + a smoke assertion.

### 3.6 `origin_confidence: "low"` so pre-existing override doesn't auto-fire

Externally-sourced candidates inherit `origin_confidence: "low"` (matching the Phase 1.5 ensemble convention). This means the `pre_existing + high → pre_existing_report` override (§13.1) cannot trigger from a paste alone — Phase 4 has to corroborate. If the validator sets `origin: "pre_existing"` with confidence `high` after deep blame analysis, the §4.6 re-assertion sweep handles it the same way it handles any other validator-graduated pre-existing finding.

### 3.7 Leftover-`attempted` hard abort (mirror Phase 7)

If a `/adams-review-fix` run is in progress (any finding has `current_state == attempted`), refuse to add. Re-use Phase 7's exact recovery message (`08-fix-loader.md:74-100`). Adding findings while the artifact is mid-mutation is a footgun.

### 3.8 No working-tree mutation, no clean-tree gate needed

Validators are read-only by contract (§4.4.5 sweep enforces this). No fix-group execution. So unlike `/adams-review-fix` Phase 7, no clean-tree gate is required. The only artifact-mutating step is the patch sequence; the working tree is untouched.

### 3.9 Re-render + re-publish to the existing comment

Same flow `/adams-review-promote` uses (`adams-review-promote.md` steps 7–8). The persisted `comment_id` in the artifact ensures `artifact-publish.sh` PATCHes the existing PR comment in place rather than POSTing a duplicate.

## 4. Argument shape

```
/adams-review-add [<paste-text...>] [--file <path> --line <N> --claim "..."] [--impact <type>] [--no-dedup]
```

**Free-form paste mode (default):** all positional `$ARGUMENTS` tokens are joined with spaces and treated as the paste body. The Sonnet normalizer extracts candidates.

**Structured one-shot mode:** when `--file`, `--line`, and `--claim` are all present, skip the normalizer and build a single candidate inline. `--impact <type>` (default `correctness`) sets `impact_type` and thus `validation_lane`. Useful for human-found bugs where the reviewer doesn't want to round-trip through Sonnet.

**Mixed mode** (paste + `--impact`): paste is normalized, but `--impact` overrides the normalizer's per-candidate guess for ALL emitted candidates. Useful when the reviewer knows the input is "all security" or "all UX."

`--no-dedup`: skip the §3.3 dedup pass. Useful when the reviewer is confident the input is fresh, or when the artifact has 50+ findings and the dedup call would be expensive.

If `$ARGUMENTS` is empty AND no `--file/--line/--claim` provided, error-as-prompt asking for input (suggest both invocation shapes).

## 5. New top-level command: `commands/adams-review-add.md`

Shape (matching promote / walkthrough convention):

```markdown
---
allowed-tools: Bash(/Users/adammiller/.claude/commands/_shared/tools/artifact-read.sh:*),
                Bash(/Users/adammiller/.claude/commands/_shared/tools/artifact-patch.py:*),
                Bash(/Users/adammiller/.claude/commands/_shared/tools/artifact-validate.sh:*),
                Bash(/Users/adammiller/.claude/commands/_shared/tools/artifact-render.py:*),
                Bash(/Users/adammiller/.claude/commands/_shared/tools/artifact-publish.sh:*),
                Bash(/Users/adammiller/.claude/commands/_shared/tools/assign-finding-ids.sh:*),
                Bash(/Users/adammiller/.claude/commands/_shared/tools/log-phase.sh:*),
                Bash(/Users/adammiller/.claude/commands/_shared/tools/log-tokens.sh:*),
                Bash(/Users/adammiller/.claude/commands/_shared/tools/repo-slug.sh:*),
                Bash(git:*), Bash(jq:*), Bash(date:*), Bash(mkdir:*), Bash(rm:*),
                Bash(cat:*), Bash(printf:*), Bash(tr:*),
                Read, Agent
argument-hint: "[<paste...>] [--file path --line N --claim \"...\"] [--impact <type>] [--no-dedup]"
description: Inject externally-sourced findings (cloud /ultrareview, manual finds, etc.) into the most recent /adams-review artifact for this branch. Validates via Phase 4, re-renders, re-publishes.
disable-model-invocation: false
---
```

Body steps:

1. **Arg parse.** Detect structured-mode flags vs. paste mode. Capture `paste_body`, `cli_file`, `cli_line`, `cli_claim`, `cli_impact`, `no_dedup`.
2. **Locate artifact.** Identical to promote step 2 (`adams-review-promote.md:98-131`). Schema-validate.
3. **Leftover-`attempted` gate.** Mirror `08-fix-loader.md:74-100`. Hard abort with the standard recovery message if any finding is `attempted`.
4. **Build candidate array.**
   - Structured mode: emit one candidate inline via jq.
   - Paste mode: dispatch one Sonnet "paste normalizer" sub-agent (prompt below). Repair `file: null → "(unknown)"` and `line_range: null → [1,1]` per Phase 1.5 §1.5.5.
   - Mixed mode: same as paste, then jq-overlay `impact_type` from `cli_impact`.
   - All candidates get `sources: ["external-add:<channel>"]` where `<channel>` is `paste`, `cli`, or a user-supplied name. `source_families: ["external-add-family"]`. `origin: "introduced_by_pr"` (default — validator may revise), `origin_confidence: "low"`, `validation_lane` derived from `impact_type`.
5. **Dedup against existing findings** (skip when `no_dedup`). Dispatch one Sonnet sub-agent with the new candidate list + the existing `claim/file/line_range/id` triple from the artifact. For each new candidate the agent returns a verdict: `matches: F0NN` or `matches: null`. For matched candidates, append the new source to the existing finding's `sources[]` via `--set-json sources=@…`; drop from the to-add list. Log each match to trace.
6. **Assign IDs.** Pipe the surviving candidates through `assign-finding-ids.sh --start-from F<next>` (where `next = max(existing_ids) + 1`).
7. **Build full schema-valid finding objects** (same jq pattern Phase 4.5 Wave 2 uses, `05-validation.md:336-363`). Write each to the artifact via `--add-finding` in a loop.
8. **Phase 4 validation** (lane-aware, no Wave 2). Include the relevant slices of `05-validation.md`:
   - Partition new candidates by `validation_lane`.
   - Dispatch one Opus sub-agent per deep-lane candidate (§4.2 prompt).
   - Dispatch one Sonnet sub-agent per light-lane candidate (§4.3 prompt).
   - Apply §4.4.5 tree-cleanliness sweep after dispatch returns.
   - Build the decision tuple array; call `artifact-patch.py --apply-decisions @<file>` once.
   - Run §4.6 pre-existing override re-assertion sweep (cheap, scoped to the new IDs).
9. **Re-render `artifact.md`** via `artifact-render.py`.
10. **Re-publish to the PR.** PR mode: `artifact-publish.sh --comment-id <existing>` PATCHes the existing comment. Local mode: no-op.
11. **Trace entry.** `## add (<ts>)` block recording: input mode (paste/cli/mixed), raw input length, candidates emitted by normalizer, dedup matches, surviving candidates, new IDs, per-finding final disposition.
12. **User-visible summary.** Print a concise block:
    ```
    Added N new findings to rev_<id>:
      F037 confirmed_mechanical    correctness  src/foo.ts:142 — early-return skips audit-log
      F038 uncertain         correctness  src/bar.ts:88  — possible race in cache invalidation
      F039 disproven         correctness  src/baz.ts:12  — (validator found positive evidence; not a real issue)
    Deduplicated 1 candidate against existing F003 (sources merged).

    Next: /adams-review-fix or /adams-review-walkthrough to act on the new actionable findings.
    ```

## 6. Paste-normalizer sub-agent prompt

Modeled on `02-ensemble-adapter.md:222-280` but single-input. Returns the standard candidate-array shape.

```
You are normalizing an externally-sourced code-review note into the
adams-review candidate schema. The reviewer has either pasted a chat
transcript / review summary from another tool (Claude Code /ultrareview,
Opus chat, CodeRabbit text output, a teammate's Slack message) or
hand-written a list of bugs they want added.

Input (free-form text; may contain markdown, code fences, prose):

```
<paste_body>
```

Files in the PR diff (for location resolution context):

```
<reviewed_files_all>
```

Extract concrete bug claims. Rules:

- One candidate per distinct bug. A single paragraph that describes
  three issues becomes three candidates.
- Discard meta commentary, praise, questions, "looks good," vague
  suggestions without a concrete claim.
- Resolve `file` from the text when possible (paths, code fences with
  filenames, "in foo.ts:..."). Cross-check against the diff file list —
  prefer matches. Emit `file: null` when ambiguous; the orchestrator
  will repair to "(unknown)".
- Resolve `line_range` similarly. Emit `null` when not stated.
- Classify `impact_type` conservatively: prefer `correctness`. Use
  `security` only with concrete evidence. `ux`/`policy`/`architecture`
  per their normal definitions.

Return strict JSON. No surrounding prose. No code fences. Shape:

[
  {
    "file": "src/path/to/file.ts" | null,
    "line_range": [start, end] | null,
    "claim": "one-sentence description",
    "evidence_snippet": "relevant excerpt from the paste",
    "impact_type": "correctness" | "security" | "ux" | "policy" | "architecture",
    "origin": "introduced_by_pr" | "pre_existing" | "unknown",
    "origin_confidence": "low",
    "source_family": "external-add-family",
    "sources": ["external-add:paste"]
  },
  ...
]

If the input contains no actionable bug claims, return `[]`.
```

Model: Sonnet. Tool access: none (text-only — the paste IS the input). Budget: ~3-8k tokens depending on paste length.

## 7. Dedup sub-agent prompt

Smaller and tighter than Phase 2's prompt (one-direction matching only):

```
You are deduplicating new bug candidates against an existing review's
findings. For each new candidate, decide whether it describes the
same underlying issue as one of the existing findings.

New candidates (JSON array):
<new_candidates>

Existing findings (JSON array of {id, file, line_range, claim}):
<existing_compact>

Rules:
- A match means "same underlying behavior" (same file region + same
  invariant violation), not just "nearby code."
- Be conservative: prefer "no match" when unsure. False matches drop
  real new findings; false non-matches just produce a near-duplicate
  (which the report handles).
- Each new candidate matches AT MOST ONE existing finding.
- Existing findings are NOT compared against each other.

Return strict JSON:

{
  "verdicts": [
    {"new_index": 0, "matches": "F003"},
    {"new_index": 1, "matches": null},
    ...
  ]
}

`new_index` is the 0-based index into the new-candidates array. One
verdict per new candidate. `matches` is either an existing finding id
or `null`.
```

Model: Sonnet. Budget: ~2-4k tokens.

## 8. Helper changes

- **`assign-finding-ids.sh`** — add optional `--start-from F<NNN>` flag. Default behavior (no flag) is unchanged (`F001` start). Affects ~5 lines of jq + the arg-parse preamble. New smoke assertion: `WT-1 | start-from F037 yields F037..`.
- **`artifact-patch.py`** — no change. `--add-finding` / `--apply-decisions` / `--set-json` cover everything.
- **`artifact-render.py`** — no change. Will render new sources strings (`external-add:paste`, `external-add:cli`) as-is. (Verify during implementation that no hardcoded source list exists in the renderer's section selectors. Spot-checking suggests selectors key off `disposition`, not `sources`, so this should be fine.)
- **`artifact-publish.sh`** — no change. Same `--comment-id` flow as promote.

No new helper script. The command is pure orchestration over existing primitives + two sub-agent dispatches.

## 9. Schema impact

None. The schema already accepts:

- Arbitrary strings in `sources[]` and `source_families[]` (only `minLength: 1` constraint).
- Optional `human_confirmation` (already defined; not used by this command — `/adams-review-add` does NOT auto-promote, leaving that to `/adams-review-promote` or `/adams-review-walkthrough`).

The `reviewer_sources` top-level array (`schema-v1.json:71-74`) gets a new entry `"external-add"` appended via `--set-json reviewer_sources=@…` so the artifact's manifest reflects that an add-pass touched it. One-line addition during step 7.

## 10. Trace + provenance

`## add (<ts>)` block in `trace.md`:

```
## add (2026-04-21T14:32:11Z)
input_mode: paste
input_length: 2847
input_source: external-add:paste
normalizer_emitted: 4
dedup_matched: 1 (new#2 → F003 sources merged)
surviving: 3
new_finding_ids: F037, F038, F039
phase_4_dispositions: F037=confirmed_mechanical F038=uncertain F039=disproven
```

The raw paste body is NOT logged in full (could be large; could contain sensitive context). Just length + the normalized candidates. If the user wants the original input recorded, they include it in the trace themselves.

`phases.jsonl` record: `{name: "add", elapsed_sec: N, counts_by_disposition: {confirmed_mechanical: 1, uncertain: 1, disproven: 1}, delta: "+3 findings"}`.

## 11. Edge cases / preconditions

| Condition | Handling |
|---|---|
| No `latest.txt` for branch | Error-as-prompt: "no review found; run /adams-review first." |
| Schema-invalid artifact | Same as promote step 2 — surface validator stderr and abort. |
| Leftover `attempted` finding | Hard abort with the §3.7 recovery message. |
| Empty `$ARGUMENTS`, no CLI flags | Error-as-prompt asking for input; show both invocation shapes. |
| Structured mode missing one of `--file`/`--line`/`--claim` | Error-as-prompt; require all three together. |
| Normalizer returns `[]` (no actionable claims in paste) | Print "no actionable claims extracted from input"; exit 0 cleanly (do not patch artifact, do not republish). |
| Dedup matches all candidates | Print "all N candidates duplicate existing findings (sources merged)"; skip Phase 4; still re-render + republish to surface the merged sources. |
| Paste contains a file path not in `reviewed_files_all` | Allow the candidate through with the user-supplied path. The validator will surface the discrepancy. (Mirrors Phase 1.5's permissive behavior.) |
| `cli_impact` is not in the enum | Error-as-prompt with the valid values. |
| Phase 4 validator returns unparseable JSON | Helper routes that finding to `uncertain` per §4.4 default; user sees it as `uncertain` in the summary. |
| User runs `/adams-review-add` against an artifact that already had `/adams-review-fix` run on it | Allowed. New findings get fresh IDs after the highest existing one (which may include resolved ones). They go through Phase 4 normally; if `confirmed_mechanical`, the next `/adams-review-fix` picks them up. |

## 12. Smoke assertions (test/smoke.sh)

New assertion family `RA-*` (review-add):

- `RA-1` paste mode normalizer returns N candidates → N findings appear in artifact with sequential IDs starting after max existing.
- `RA-2` structured mode (`--file --line --claim`) skips normalizer; emits exactly one candidate; respects `--impact`.
- `RA-3` leftover-`attempted` finding → hard abort with §3.7 message; no artifact mutation.
- `RA-4` empty input → error-as-prompt mentioning both invocation shapes; no artifact mutation.
- `RA-5` dedup matches a new candidate against existing F### → no new finding added; existing finding's `sources[]` gains the new entry.
- `RA-6` Phase 4 confirmed_mechanical disposition → finding is eligible for `/adams-review-fix` at default threshold.
- `RA-7` PR-mode publish PATCHes the existing comment_id (no second comment posted).
- `RA-8` `assign-finding-ids.sh --start-from F037` emits `F037, F038, ...` (new helper assertion).

Total: ~8 new assertions. Bumps the smoke pass count by 8.

## 13. CLAUDE.md updates

In the "What this repo is" section: add a fourth bullet for `/adams-review-add` between walkthrough and fix. Update the "Recommended flow on a non-trivial PR" sentence to mention add as an optional step:

> **Recommended flow on a non-trivial PR:** `/adams-review` → (optional) `/adams-review-add` → `/adams-review-walkthrough` (optional) → `/adams-review-fix`. Each command is independent.

In "Pipeline shape": add a one-line summary under the existing two pipelines:

```
/adams-review-add [<paste...>]
└── Locate artifact → leftover-attempted gate → normalize/structured →
    dedup → assign IDs → --add-finding loop → Phase 4 (no Wave 2) →
    re-render → re-publish → trace
```

Helper index needs no changes (no new helpers; only an additive flag on `assign-finding-ids.sh`).

## 14. Open questions / risks

- **Q: Should the dedup pass also offer to merge two new candidates against each other** (e.g., a paste that lists the same bug twice in different words)? Currently §3.3 explicitly only does new-vs-existing. Probably fine — a conservative second pass adds cost without much value at typical input sizes (1–5 candidates).
- **Q: Should `/adams-review-add` invoke `/adams-review-fix` automatically when all new findings land as `confirmed_mechanical`?** Decision: no, mirror promote's "metadata only" philosophy. The user runs `/adams-review-fix` explicitly.
- **R: Renderer handling of new sources strings.** Need to spot-check `artifact-render.py` during implementation that nothing keys off a closed source list. Existing `external-pr:*`, `codex`, `coderabbit` precedent suggests it doesn't, but worth verifying before claiming "no renderer change."
- **R: Token cost on a large paste.** A 5000-token paste through the normalizer + 5 deep-lane Opus validations is ~50k tokens. Acceptable but worth noting in the user-visible "next steps" doc.
- **R: Phase 5 cross-cutting drift.** Skipping Phase 5 means added findings never appear in `cross_cutting_groups`. If a user adds 3 findings that obviously share a root cause with 2 existing findings, the renderer won't surface the grouping. Acceptable for v1 — documented limitation; future flag `--rerun-cross-cutting` could be added if it becomes a pain point.

## 15. Estimated effort

- ~200 lines: new top-level `commands/adams-review-add.md` (mostly cribbed from promote + a §05 validation slice).
- ~5 lines: optional `--start-from` flag on `assign-finding-ids.sh`.
- ~8 new smoke assertions.
- ~10 lines: CLAUDE.md updates.
- 0 schema changes.
- 0 helper script additions (beyond the optional flag).

Half a day to a day of focused implementation. Most of the risk is in the orchestration sequencing — making sure the per-step state captures match what the included `05-validation.md` slice expects (e.g., `phase_4_start_epoch`, `validator_responses`).

## 16. Implementation order

1. `assign-finding-ids.sh --start-from` flag + smoke assertion.
2. Stub `commands/adams-review-add.md` with arg parse, locate, leftover gate, structured-mode candidate emit, `--add-finding` loop. Manual smoke against a fixture.
3. Add Phase 4 dispatch (deep + light) using inline copies of §4.2 / §4.3 prompts (don't try to `!cat` the whole `05-validation.md` — it's overscoped; copy just the lane partition + dispatch + apply-decisions + tree-cleanliness blocks).
4. Add re-render + re-publish.
5. Add the paste-mode normalizer sub-agent.
6. Add the dedup sub-agent.
7. CLAUDE.md edits + final smoke assertions.
8. Manual end-to-end test against a recent review artifact (paste an Opus once-over of an arbitrary PR; verify all dispositions land sensibly).

Each step is independently committable; each phase corresponds to one or two assertions.

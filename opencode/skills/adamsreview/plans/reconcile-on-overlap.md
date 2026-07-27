# Reconcile-on-overlap — offer merge pass when Phase 9.pre overlap aborts

**Status:** drafted 2026-04-21; plan-and-execute (user approved).
**Pattern:** adds one optional sub-phase between Phase 9.pre overlap detection and the existing overlap-abort branch. No schema change, no new helper, no new fragment file. Touches one fragment (`10-post-fix-and-commit.md`) and adds smoke assertions.

---

## Context

When Phase 9.pre detects that two fix-group agents edited the same file (outside their planned `files_to_modify` sets), `/adams-review-fix` currently aborts before any commit and asks the user to `git restore .` + reset state + re-run. That throws away every group's edits — including the edits to non-overlapping files that may be perfectly fine — and forces a full re-dispatch from scratch.

All the intent we'd need to reconcile the collision is already in memory at 9.pre time:

- Working-tree diff with every group's edits.
- Each fix group's returned JSON (`files_modified`, `files_created`, `per_finding.edits_applied`, `per_finding.verification_results`).
- Original `validation_result.fix_proposal` / `blast_radius` / `verification_context` on every finding.

A single Opus merge agent can take that bundle, reconcile the overlapping files while preserving non-overlapping edits, and produce a working tree that satisfies every finding from every group. Phase 9a already re-traces each finding's evidence against the working tree (§19.9), so the "fresh review" after merge is a free side effect of running the existing Phase 9 unchanged.

### Why we missed reconciling before

The original design (`docs/archive/DESIGN.md` §13.5 / §24.2 / §24.4) chose "abort and start over" because:

1. Reverting per-group is mechanically simple (`git checkout -- files_modified[]`, `rm -f files_created[]`). Reconciling is an LLM decision.
2. The artifact-state contract (findings stay `attempted` on 9.pre abort) is clean and re-runnable.

Both still hold. This change is strictly additive — the abort path remains the default and the fallback when reconcile can't handle the situation (delete-leak, parse failure, unresolved conflicts).

---

## Goal

When Phase 9.pre detects overlap that is NOT a `D <path>` delete leak, offer the user three choices via `AskUserQuestion`:

1. **Abort** (default) — current behavior: log, append `--apply-fix-outcomes` tuples with `phase_9_outcome: null`, jump to 9e no-commit, restore-and-retry recovery message.
2. **Reconcile** — dispatch one Opus merge agent, collapse the `fix_groups` array into a synthetic `FG-RECON` container in memory, run Phase 9a/9b/9c unchanged against the reconciled tree. If Phase 9 classifies any finding as regression, revert the entire reconcile (all files roll back, all findings land `open/regression`). If every finding is verified or partial, commit with a `reconcile: merged <N> overlapping files` note in the commit message.
3. **Inspect** — leave the tree as-is, do NOT append fix_outcomes tuples (findings stay `attempted` — leftover-guard next run is the recovery path), log inspect-chosen to trace, exit with a "tree is yours; re-run /adams-review-fix after cleaning up" message.

Delete-leak overlaps (`D <path>`) bypass the offer and go straight to abort — the v1 revert model can't handle deletes and neither should the merge agent.

**Done when:**

1. `/adams-review-fix` against an overlap scenario surfaces the three-option `AskUserQuestion` before executing abort.
2. Reconcile + all-verified path commits a single commit whose message includes the merged-file list and survives Phase 9 validation.
3. Reconcile + any-regression path reverts every reconciled file and lands every finding back at `open/regression` with original `fix_group_id` preserved in `fix_attempts`.
4. Delete-leak overlap still hard-aborts with the current `§19.8 forbids delete` error; the offer is not shown.
5. `test/smoke.sh` passes with new `FX-RECON-*` assertions covering apply-fix-outcomes shapes and fragment-text invariants.
6. `CLAUDE.md` pipeline sketch updated; `/adams-review-fix` argument docs unchanged.

---

## Ground rules (restated)

- **No schema change.** Each finding's `fix_attempts[].fix_group_id` preserves its ORIGINAL pre-reconcile FG-N. `FG-RECON` is an in-memory orchestration label for 9b/9c revert-or-commit; it never reaches disk. (Schema regex is `^FG-[0-9]+$`.)
- **No new helper script.** Existing `artifact-patch.py --apply-fix-outcomes`, `artifact-render.py`, `log-phase.sh`, `log-tokens.sh`, and `artifact-publish.sh` cover everything. One new jq one-liner builds the reconcile fix_groups collapse.
- **Phase 9a unchanged.** §19.9's per-finding evidence re-trace + adjacent-regression + convention-drift sweeps already cover "fresh review after reconcile." No second review phase is added.
- **Abort is the default.** `AskUserQuestion` options surface "Abort (recommended)" first. `AskUserQuestion` provides default selection semantics matching the walkthrough preflight (§28).
- **Delete-leak still aborts.** The existing `D <path>` detection and `deleted_paths` branch in 9.pre run before the offer, and when present, short-circuit to the existing abort branch with no offer.
- **Terminal invariant (§24.4).** Artifact on disk continues to track git reality through every branch (commit, reconcile-then-commit, reconcile-then-revert, abort, inspect).

---

## Implementation steps

### 1. Fragment edits — `commands/_shared/10-post-fix-and-commit.md`

**1a. Reorganize 9.pre.** Current structure: detect overlap → `overlap_files` non-empty? abort → else proceed to 9a. New structure:

- Detect overlap (unchanged).
- Detect delete-leak (unchanged).
- If `overlap_files` empty: proceed to 9a (unchanged).
- If `deleted_paths` non-empty: proceed directly to existing abort branch (no offer).
- Else (overlap, no delete-leak): **new 9.pre.offer**.

**1b. New 9.pre.offer.** Build a compact summary table for the user (overlap files + which FG-N's owned each), then dispatch `AskUserQuestion`:

```
Fix agents touched overlapping files. Choose how to proceed:

Overlap summary:
  <file>   ← FG-1, FG-2
  <file>   ← FG-2, FG-3

Options:
- ⭐ Abort (recommended) — discard all edits, restore tree, reset state, re-run manually
- Reconcile — dispatch one merge agent to combine edits, then run full Phase 9 review
- Inspect — leave tree as-is for manual review (findings stay attempted; leftover-guard catches next run)
```

Bind the result to `$overlap_choice` ∈ {`abort`, `reconcile`, `inspect`}. On any non-interactive fallback (no user response, decline), default to `abort`.

**1c. Inspect branch.** When `overlap_choice == inspect`:

- Append an orchestrator-error line to `trace.md`: `overlap_inspect chosen — tree left as-is, no fix_outcomes appended`.
- Do NOT call `--apply-fix-outcomes`. Findings stay at `current_state=attempted` on disk.
- Pop stash if `stash_taken=true` (unlike revert-failure, the tree is consistent — agents edited but orchestrator has not touched git; stash pop is safe as long as tree didn't revert).

  Actually — agents HAVE edited the tree (that's the whole reason overlap was detected). Popping a stash into an edited tree risks conflicts. Match the revert-failure semantics: leave stash in place, call it out in the error.

- Set working vars identically to overlap_abort: `commit_sha=null`, `overlap_abort=true`, `degen="overlap_inspect"`, then jump to 9e no-commit branch which will render + log + surface the inspect-specific message.

- 9e no-commit step 7 gains a new case:
  - `overlap_inspect` → "Working tree left as-is for inspection. `$overlap_files`. Your stash (if any) is preserved. When ready, either commit what you want manually and run `artifact-patch.py --finding-id <id> --set current_state=open` on affected findings, or run `git restore . && git clean -fd` to discard."

**1d. Reconcile branch** — new sub-phase between 9.pre and 9a.

#### 9.pre.reconcile — merge overlapping edits

Computed inputs (all already in working context):

- `fix_groups_with_actual` (from 9.pre existing computation).
- `overlap_files` (non-empty).
- `working_tree_diff = git diff $input_sha` (cumulative agent edits from the clean baseline).
- Per-finding: the finding's own `validation_result`, `blast_radius`, `fix_proposal`, `verification_context` — read via `artifact-read.sh --finding-id <id>` as needed when composing the prompt.

Capture start epoch for logging:

```bash
phase_9_reconcile_start_epoch=$(date +%s)
```

Snapshot the original fix_group_id mapping BEFORE collapsing. 9d reads this to preserve each finding's original `fix_group_id` in its fix_attempts entry (schema compat):

```bash
original_fix_group_by_finding=$(echo "$fix_groups_with_actual" | jq -c '
    [.[] as $g | $g.finding_ids[] | {id: ., group: $g.id}]
')
```

Dispatch ONE Opus merge agent (`subagent_type: general-purpose`, `model: opus`). The prompt is §6 below.

After the agent returns:

1. **Log tokens** via `log-tokens.sh --phase phase_9_reconcile --agent-role reconcile --model opus`.
2. **Parse JSON.** Light repair (strip code fences, extract object) allowed. One retry with a "Return only the JSON object described in the schema" addendum on parse failure.
3. **On second parse failure OR on non-empty `unresolved_conflicts`**: fall back to the existing abort branch with an orchestrator-error line to trace: `reconcile_fallback reason=<parse_failure|unresolved>`. The original attempted state is intact — abort's `--apply-fix-outcomes` tuples will still apply correctly.
4. **On success**, replace working-context `fix_groups` with a synthetic single entry:

   ```bash
   fix_groups=$(jq -nc --argjson result "$reconcile_result" \
       --argjson finding_ids_union "$(echo "$fix_groups_with_actual" | jq -c '[.[].finding_ids[]] | sort | unique')" '
       [{
         id: "FG-RECON",
         finding_ids: $finding_ids_union,
         files_planned: ($result.files_modified + $result.files_created | unique),
         results: $result
       }]
   ')
   ```

5. **Recompute `fix_groups_with_actual`** off the new single-entry array so the downstream overlap guard won't re-fire:

   ```bash
   fix_groups_with_actual=$(echo "$fix_groups" | jq -c '
       map(. + {actual_touched: ((.results.files_modified // []) + (.results.files_created // [])) | unique})
   ')
   overlap_files=""
   ```

6. **Log phases.jsonl:**

   ```bash
   phase_9_reconcile_elapsed=$(( $(date +%s) - phase_9_reconcile_start_epoch ))
   ~/.claude/commands/_shared/tools/log-phase.sh \
     --review-dir "$review_dir" --phase 9 --name reconcile \
     --elapsed "$phase_9_reconcile_elapsed" \
     --summary "reconciled $(echo "$overlap_files_snapshot" | jq 'length') overlap(s) across $(echo "$original_fix_group_by_finding" | jq 'length') findings"
   ```

7. Proceed to 9a normally. 9a's diff snapshot (`git diff HEAD`) captures the reconciled tree.

**1e. 9b adjustments.** 9b iterates `fix_groups` to build `group_outcomes` and partition into `reverted_groups` / `surviving_groups`. With `fix_groups` now a single FG-RECON, 9b naturally treats it atomically:

- Any finding with `outcome=regression` → the ONE group's aggregated outcome is `regression` (the existing `any(. == "regression")` jq already handles this).
- Any finding with `outcome=partial` and no regressions → `partial`.
- All verified → `verified`.

Revert-on-regression semantics: 9b's existing revert loop restores every file in `files_modified` + `files_created`, which for FG-RECON is the union across all original groups. Exactly the "revert the entire reconcile" behavior we want.

No code change required in 9b. Add one explanatory sentence at the top: "When `fix_groups` contains a single `FG-RECON` entry (set by 9.pre.reconcile), per-group aggregation naturally reduces to all-or-nothing revert across every reconciled file. This is intentional — a partial reconcile is unsafe."

**1f. 9c adjustments.** 9c's commit-message builder emits "Fix groups (committed): - [FG-N] F001, F002 — files...". For FG-RECON, emit a reconcile-specific block instead:

```bash
if [[ "$(echo "$surviving_groups" | jq -r '.[0].id // empty')" == "FG-RECON" ]]; then
    echo "fix: address code review findings (reconciled)"
    echo
    echo "Reconciled fix (one merge pass after Phase 9.pre overlap):"
    echo "  Findings: $(echo "$surviving_groups" | jq -r '.[0].finding_ids | join(", ")')"
    echo "  Files:    $(echo "$surviving_groups" | jq -r '(.[0].files_modified + .[0].files_created) | join(", ")')"
    echo "  Overlaps: $overlap_files_snapshot_summary"
    echo
    # Phase 9 summary line (unchanged)
else
    # existing per-group block
fi
```

Keep `overlap_files_snapshot` captured at 9.pre.offer time (before reconcile reset it to empty) so the commit message preserves the audit trail.

**1g. 9d adjustments.** 9d builds `apply_tuples` from `phase_9a_outcomes` and `group_by_finding` (computed from current `fix_groups`). When `fix_groups[0].id == "FG-RECON"`, substitute `original_fix_group_by_finding` for the tuple's `fix_group_id` field so on-disk `fix_attempts` preserve original FG-N per finding:

```bash
# ...existing $group_by_finding build...

# If the run was reconciled, override the fix_group_id source.
if echo "$fix_groups" | jq -e '.[0].id == "FG-RECON"' >/dev/null; then
    group_by_finding="$original_fix_group_by_finding"
fi

# ...rest of apply_tuples jq unchanged...
```

This is the only mechanically necessary change for schema compatibility.

**1h. 9e adjustments.**

- Committed branch step 4 (`log-phase.sh` record): add `reconciled:$reconciled_flag` into the JSON record. `$reconciled_flag` derived from `fix_groups[0].id == "FG-RECON"`.

- No-commit branch step 4: `degen` cases unchanged except add `reconcile_fallback` and `overlap_inspect` to the fallback enumeration.

- No-commit branch step 7: add cases for `reconcile_fallback` and `overlap_inspect`:

  ```
  reconcile_fallback → "Reconcile attempt failed (parse error or unresolved conflicts). Working tree left in post-Phase-8 state. Findings left at attempted — next /adams-review-fix run will hard-abort with recovery prompt. See $trace_log_path for the merge agent's raw output."
  overlap_inspect    → (wording from 1c above)
  ```

- Committed branch step 8 user-visible summary gains a reconciled variant when `reconciled_flag=true`:

  > `/adams-review-fix complete (reconciled).`
  >
  > Committed one reconciled fix covering $reconciled_finding_count finding(s) across $reconciled_file_count file(s), merged from $original_group_count originally-parallel fix groups that collided on $overlap_count file(s).
  >
  > (verified / partial / regression counts, commit SHA, PR URL — same as existing template)

### 2. Merge-agent prompt

```
You are the Phase 9 reconciliation agent. Parallel fix-group agents
just edited the working tree and collided on one or more shared
files. The tree is currently in a last-write-wins state — it does NOT
cleanly represent any single group's intent. Your job: produce a
working tree that satisfies EVERY finding from EVERY group, without
regressions.

Run identity:
- run_id: $run_id
- input_sha: $input_sha (pre-Phase-8 baseline; `git diff $input_sha`
  shows cumulative edits across all fix groups)
- review_id: $review_id

Overlap map (files touched by ≥2 groups):
<jq output: [{file, groups: [FG-N, ...]}]>

Per-group context — for each original fix group:
- id, finding_ids
- files_modified, files_created
- per_finding.edits_applied (what the agent claimed to edit per finding)
- per_finding.verification_results (the agent's own post-edit checks)

Per-finding context — for each finding across all groups:
- id, file, line_range, claim
- validation_result.evidence (the bug the fix must eliminate)
- validation_result.blast_radius (especially parallel_paths and
  invariants_at_stake)
- validation_result.fix_proposal (the validator's intended approach +
  files_to_modify with {file, what, why})
- validation_result.verification_context.how_to_verify_fix (the steps
  that must pass after your reconciliation)

CLAUDE.md paths (project conventions to respect):
$claude_md_paths

---

Your task:

1. For each non-overlapping file, keep the current contents. Do NOT
   re-edit files that only one group touched unless you detect a
   regression caused by a change elsewhere.

2. For each overlapping file:
   a. Read the file as it currently stands.
   b. Read the original pre-Phase-8 content: `git show $input_sha:<path>`.
   c. Identify each group's intent for that file from its
      per_finding.edits_applied + verification_results and the
      finding's fix_proposal.files_to_modify (look at `what` / `why`).
   d. Produce a reconciled file that applies ALL intents. If two
      intents conflict substantively, prefer the version that satisfies
      both findings' evidence; if truly incompatible, pick the
      higher-score_phase4 finding's version and include the other
      finding's id in `unresolved_conflicts` with a concrete reason.

3. After editing, re-verify every finding across all groups by running
   its validation_result.verification_context.how_to_verify_fix steps
   (grep / Read only — no mutating calls). Report per-step pass/fail.

4. Adjacent-regression check: for each file you reconciled, read the
   changed hunks ±20 lines and verify no new bug (inverted condition,
   off-by-one, null-deref, resource leak, ordering swap, etc.) was
   introduced by the merge.

5. Convention-drift check: for each entry in any finding's
   blast_radius.parallel_paths, diff your reconciled file against that
   parallel path for boundary-condition consistency (loop bounds, null
   semantics, ordering, error handling, direction of COALESCE args).
   Divergence from cross-parallel convention is a bug the merge just
   wrote — fix it before returning.

6. If CLAUDE.md defines verification_commands for any changed file,
   run the matching ones; report exit codes.

7. DO NOT run git commands. DO NOT delete or rename files. Edit / Write
   only. The orchestrator handles staging, commit, and revert. If a
   finding genuinely requires deletion or rename, list it in
   unresolved_conflicts with reason "requires delete/rename — manual".

---

Return JSON of exactly this shape (matches Phase 8's per-group contract
so the orchestrator can feed it straight into Phase 9a):

{
  "reconcile_notes": "<1–3 sentences on how conflicts were merged>",
  "per_finding": [
    {
      "finding_id": "F001",
      "edits_applied": ["src/...", "src/..."],
      "verification_results": [
        { "step": "...", "passed": true, "note": "..." }
      ]
    }
  ],
  "files_modified": ["..."],
  "files_created": ["..."],
  "per_file_summary": [
    { "file": "...", "lines_changed": 24,
      "reconciled_from_groups": ["FG-1", "FG-2"] }
  ],
  "unresolved_conflicts": [
    { "file": "...", "finding_ids": ["F007", "F012"],
      "reason": "..." }
  ]
}

Rules:
- files_modified and files_created must be disjoint and cover every
  file you edited.
- per_finding must contain an entry for every finding_id across every
  original fix group (no silent drops).
- If unresolved_conflicts is non-empty, the orchestrator will abort
  the reconcile and fall back to the standard overlap-abort recovery
  path — return them explicitly rather than silently pick a winner
  without saying so.
```

### 3. Top-level command changes — `commands/adams-review-fix.md`

- Update the "What this command does NOT do" section: current bullet "No automated recovery from leftover-attempted state" stays; add a new bullet noting the reconcile offer is opt-in and not default. Actually, simpler: leave the bullet list alone — the existing wording doesn't preclude reconcile, and adding a bullet would drift from the "does NOT do" framing.
- The `AskUserQuestion` tool is already in `allowed-tools`. No new grants.

### 4. `CLAUDE.md` updates

- Pipeline sketch: add one line under the `/adams-review-fix` block:
  ```
  │              (overlap → optional reconcile → merge agent → Phase 9)
  ```
- Finding state model table: no change (reconcile produces the same terminal states as non-reconciled runs).
- Operational rules: no new rule. The `fix_group_id` preservation is a natural consequence of rule 5 (atomic writes) + schema compatibility.

### 5. Smoke tests

Add after the existing FX-AF-* block in `test/smoke.sh`:

- **FX-RECON-1** — Fragment grep: `10-post-fix-and-commit.md` contains `AskUserQuestion` for the three-option overlap choice.
- **FX-RECON-2** — Fragment grep: fragment contains the `FG-RECON` synthetic group marker AND the `original_fix_group_by_finding` snapshot.
- **FX-RECON-3** — Fragment grep: merge-agent prompt contains the core contract (`unresolved_conflicts`, "DO NOT delete or rename files", `reconciled_from_groups`).
- **FX-RECON-4** — `artifact-patch.py --apply-fix-outcomes` accepts a tuple whose `fix_group_id` is the ORIGINAL FG-N (e.g., `FG-1`) even when the run was reconciled (baseline — verifies schema compat). Use the existing `FX-AF-3` fixture and show that the original `fix_group_id` field is what lands on disk, not `FG-RECON`.
- **FX-RECON-5** — Delete-leak path is unchanged: the fragment's `deleted_paths` check still precedes the offer (grep-level assertion: `deleted_paths` block appears before the `AskUserQuestion` block in fragment text).

Assertions 1–3 and 5 are grep-level against the fragment. Assertion 4 exercises `artifact-patch.py` against a fixture. These stay within the existing unit-test-shaped smoke pattern.

---

## Blast radius

**Writers to `fix_groups`:** Phase 8 (`09-fix-execution.md` step 8.5–8.6) and now Phase 9.pre.reconcile (this change). Phase 8's writer is unchanged. 9.pre.reconcile replaces the array at a single well-defined point after the merge agent returns successfully. No other writer touches the array.

**Readers of `fix_groups`:**
- 9.pre overlap detection: runs BEFORE reconcile, reads pre-reconcile shape. Unchanged.
- 9a prompt composition (§19.9): reads `fix_groups[*].results` + `fix_groups[*].finding_ids`. Both fields preserved in the FG-RECON synthetic entry. Works unchanged.
- 9b per-group aggregation: iterates `fix_groups` and joins to `phase_9a_outcomes` by `finding_ids`. FG-RECON contains the union, so 9b naturally treats it atomically. Already-correct semantics.
- 9c commit-message builder: needs an FG-RECON branch (step 1f above) to emit the reconcile-specific summary.
- 9d fix_attempts builder: needs the `fix_group_id` override (step 1g above) for schema compat.

**Parallel code paths:**
- `/adams-review-add` and `/adams-review-walkthrough` don't touch Phase 9. No impact.
- `/adams-review-promote` sets `human_confirmation` which affects Phase 8 eligibility; it doesn't see Phase 9. No impact.

**Stale comments / docs:**
- `CLAUDE.md` pipeline sketch: updated (step 4).
- `docs/archive/DESIGN.md`: frozen — do NOT update (per CLAUDE.md preamble).
- `README.md`: doesn't describe Phase 9.pre at a level this change affects. No update needed.

**`AskUserQuestion` non-interactive fallback.** If the session is running without interactive capability (unattended), `AskUserQuestion` returns a default choice. The default is `abort` — matches current behavior, safe.

---

## Execution order

1. Edit `commands/_shared/10-post-fix-and-commit.md` — add 9.pre.offer, 9.pre.reconcile, adjust 9c/9d/9e per §1.
2. Add merge-agent prompt inline in the fragment (§2 — it's the prose in 9.pre.reconcile).
3. Update `CLAUDE.md` pipeline sketch (§4).
4. Add FX-RECON-1..5 to `test/smoke.sh` (§5).
5. Run `test/smoke.sh` — expect `smoke: PASS` with 5 new assertions.
6. Once-over the diff per user's global CLAUDE.md instruction (post-execution once-over: re-read the diff, blast-radius lens, stale-comment check).
7. Commit with imperative-mood message referencing the fragment.

---

## Open risks I'll watch

- **Commit message composition** — the existing heredoc-to-file pattern (`msg_file="/tmp/adams-fix-msg-$run_id.txt"`) handles embedded quotes/backticks in finding claims. The reconcile branch also uses it. No new injection surface.
- **Trace-log growth** — reconcile adds one phases.jsonl record + a few trace lines. Modest.
- **Token cost for the merge agent** — user accepted it's not a problem. Logged the same way Phase 8 and 9a are.
- **Re-run staleness** — if the user later runs `/adams-review-fix` again after a reconciled commit, Phase 7's `latest_known_sha` picks up the reconciled commit_sha because it's in `fix_attempts[].output_sha`. Normal staleness logic handles it. No special case.

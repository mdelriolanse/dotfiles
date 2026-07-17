# Stage 2.6 — Base-branch freshness gate + origin cross-check

**Status:** drafted 2026-04-18, awaiting user review.
**Preceded by:** Stage 2.5 (hardening — done).
**Followed by:** Stage 3 (`/adams-review-fix`).
**Pattern:** mirrors Stage 2.5 — pre-Stage-3 hardening pass, no Phase 7–9 surface touched.

---

## Context

The C13 real-repo smoke (ray/ray-finance `feat/import-apple`) ran against a local `main` that was behind `origin/main`. Two downstream quality failures resulted:

1. **Inflated diff surface.** Every lens sees `$base_branch..HEAD`, which on stale local `main` contains commits already merged upstream on top of the PR's actual changes. The review's whole input is wrong.
2. **Empty pre-existing section.** L1/L2 lens prompts default `origin: introduced_by_pr, origin_confidence: high` "unless the implicated code is clearly unchanged by this diff" (`01-detection.md:77-78`). When stale main puts pre-existing commits *inside* the diff, the lenses correctly see them as modified and classify them as introduced. The §13.1 pre-existing override (`origin=pre_existing AND confidence=high → disposition=pre_existing_report`) never fires. The render's pre-existing section renders-when-empty as zero output, so the user silently loses the "what's new vs what was already broken" distinction.

The two symptoms share one root: the command never validates that local `base_branch` is current with its remote, and never cross-checks the lenses' origin classification against git history. Today, Phase 0 does zero `git fetch`, zero behind-count math, and no post-lens origin correction.

**Outcome this stage delivers.** `/adams-review` detects stale local `base_branch`, offers the user explicit choices, and — independently — runs a deterministic blame-based post-lens pass that corrects origin classification when git history disagrees with the lens's default. Two cheap additions, each addressing one layer of the failure.

This is a pre-Stage-3 hardening stage; no Phase 7–9 surface is touched. Schema stays at v1 with additive optional fields. DESIGN gains two new §13 sub-sections.

---

## 1. Goal

Close three gaps before Stage 3 adds fix-loop surface on top:

1. **Freshness gate (Option A).** Phase 0 fetches `origin/$base_branch`, computes behind-count, and when behind prompts the user via `AskUserQuestion` with four options: fast-forward local, use `origin/$base_branch` as the comparison ref without touching local, proceed stale with a warning, or abort. Offline / fetch-failure degrades to "proceeded without fetch" with a trace warning, never hard-fails.
2. **Origin cross-check (Option C).** Between Phase 1 lens aggregation and `--add-finding`, a deterministic Bash helper runs `git blame` on each candidate's line range against the comparison ref. If every implicated line's last-touching commit is reachable from the comparison ref (i.e., not in `comparison_ref..HEAD`), override the lens-supplied `origin` to `pre_existing, confidence: high`. Otherwise respect the lens.
3. **Surface freshness state in the report.** When `base_freshness != fresh`, the rendered header carries a one-line status (e.g., `**Base freshness:** ⚠ local `main` 12 commits behind `origin/main` — compared against `origin/main``).

Stage 2.6 does **not** add `--cleanup-pre-existing`, does **not** change the `origin` enum, does **not** bump schema version, and does **not** touch Phase 8/9.

**Done when:**

1. Phase 0 on a stale-local-main scratch repo surfaces the four-option prompt; each of the four options behaves per spec (fast-forward ↔ remote ref ↔ proceed-stale ↔ abort).
2. Origin cross-check correctly flips `introduced_by_pr: high` → `pre_existing: high` for a candidate whose blame range is fully reachable from the comparison ref; leaves a mixed-range candidate untouched.
3. A re-run of `/adams-review` on ray-finance `feat/import-apple` (after pulling fresh local `main`, or using option (b) to compare against remote) populates the Pre-existing section in the rendered PR comment when pre-existing issues exist.
4. Offline (fetch failure) path logs a warning to `trace.md` and continues without prompting or aborting.
5. `test/smoke.sh` passes; three new fixtures/assertions cover: behind-base prompt wiring, offline-fallback, origin cross-check flip.
6. `DESIGN.md` gains §13.10 (freshness gate) and §13.11 (origin cross-check); §4 Phase 0 and Phase 1 narrative gain the new steps.
7. `BUILD.md` stage index + Stage 2.6 section filled in.

---

## 2. Ground rules (restated)

- **Bash:** `#!/usr/bin/env bash` + `set -euo pipefail`. Bash 3.2-safe.
- **Exit codes:** reuse `_common.py` / existing Bash conventions. No new codes.
- **Error-as-prompt:** ERROR → context → Valid values → Did you mean → Action.
- **Commits:** one per sub-item, imperative mood, DESIGN §-refs, `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>` trailer.
- **Directly to `main`**, no feature branches. Symlink dev layout is live.
- **No user round-trip for clarification-level DESIGN updates.** §13.10/§13.11 are new *normative* sub-sections, not clarifications — they get folded into a single commit with the code that implements them, and BUILD.md records the promotion.

---

## 3. Scope — work items

Four sub-items: 2.6.A (freshness gate), 2.6.B (origin cross-check), 2.6.C (report surfacing), 2.6.D (BUILD close-out).

### 3.1 Intentionally NOT in scope

- `--cleanup-pre-existing` flag. Keep the clean seam documented in DESIGN §13.1.
- `--no-fetch` flag on `/adams-review`. Rejected in planning: the fetch cost is tiny on every repo we care about, the failure path is already graceful, and adding a user-facing flag for a data-quality invariant encourages opting out of it.
- Schema version bump. New `base_context` is an optional top-level object; v1 artifacts without it validate; v1 artifacts with it validate. No breakage.
- Staleness-of-PR-branch-relative-to-base ("your feature branch hasn't been rebased in 3 weeks") — worth a future informational warning, but a separate axis from freshness-of-local-base. Deferred.
- Any Phase 5 / 7–9 surface.

---

## 4. Scope details

### 4.1 — 2.6.A — Phase 0 freshness gate (Option A)

**New DESIGN sub-section §13.10 — "Base-branch freshness (Phase 0 gate)".**

Prose essence:

> Before Phase 0 computes `reviewed_files_all`, the orchestrator fetches `origin/$base_branch` and reconciles local state. The review's entire input (diff surface, lens context, blame cross-check) depends on `$base_branch` pointing at the same commit the PR's base would be compared against upstream. A silently stale local base produces correct-looking output at every later phase, so the gate is a Phase-0 invariant.
>
> **Behavior.**
> 1. Run `git fetch origin "$base_branch" --quiet` with a 30s soft timeout.
> 2. On fetch success, compute `behind_count = git rev-list --count "$base_branch..origin/$base_branch"`.
> 3. If `behind_count == 0`: set `base_freshness="fresh"`, `comparison_ref=$base_branch`, proceed.
> 4. If `behind_count > 0`: `AskUserQuestion` with four options:
>    - **(a) Fast-forward local `<base_branch>` and compare against it** (recommended). Run `git fetch origin <base_branch>:<base_branch>` (refuses non-FF; safe no-op if user has diverged from origin). Set `comparison_ref=$base_branch`, `base_freshness="fast_forwarded"`. If FF fails due to divergence, surface the error and fall back to the four-option prompt with (a) disabled.
>    - **(b) Compare against `origin/<base_branch>` without touching local.** Set `comparison_ref="origin/$base_branch"`, `base_freshness="used_remote_ref"`. Local `<base_branch>` stays stale; nothing mutates.
>    - **(c) Proceed with stale local `<base_branch>`** (strongly discouraged; review will miss context). Set `comparison_ref=$base_branch`, `base_freshness="proceeded_stale"`. Warning appended to `trace.md` and surfaced in the rendered report header.
>    - **(d) Abort.**
> 5. On fetch failure (network, no upstream remote, timeout): set `base_freshness="no_fetch"`, `comparison_ref=$base_branch`, log a one-line warning to `trace.md` with tag `fetch_failed`, and proceed. No prompt — offline/airgapped runs must not block.
> 6. When repo has no `origin` remote at all: set `base_freshness="no_remote"`, `comparison_ref=$base_branch`, proceed silently. Purely local repos have no remote to be behind.
>
> **Plumbing.** `comparison_ref` is a new working-set variable. Every downstream `$base_branch..HEAD` reference in Phase 0/1 prompts and helpers is swapped for `$comparison_ref..HEAD`. The artifact's `base_branch` field keeps the human name (`"main"`); a new optional `base_context` object records `{freshness, comparison_ref, remote_sha, behind_count}` for reproducibility and render surfacing.

**Files touched:**

- `DESIGN.md` — new §13.10; §4 Phase 0 narrative gets a new step between current steps 2 and 4 ("Fetch and reconcile base-branch freshness"); §6 artifact-shape table notes the new optional `base_context` block.
- `commands/_shared/00-preflight.md` — new step 0.2a ("Fetch `origin/$base_branch` and reconcile freshness") between current 0.2 (branch resolution) and 0.6 (diff computation). Step 0.2's terminal "Capture `base_branch`" stays; the sanity `git rev-list --count` check uses `$comparison_ref`. Step 0.6 switches `base_branch..HEAD` → `comparison_ref..HEAD`. The working-set table at the bottom gains a row for `comparison_ref` and `base_context`.
- `commands/_shared/01-detection.md` — every lens-prompt string that today reads "the diff between `$base_branch` and HEAD" (L1 at line 57, L2 at line 88, L3 at line 114, L4 at line 133, L5 at line 160, L6 if present) becomes "the diff between `$comparison_ref` and HEAD". Display wording for the sub-agent stays human-readable: we expose the ref literal as `$comparison_ref` (which may be `main` or `origin/main`).
- `commands/_shared/schema-v1.json` — add optional top-level `base_context` property:
  ```json
  "base_context": {
    "type": "object",
    "additionalProperties": false,
    "required": ["freshness", "comparison_ref"],
    "properties": {
      "freshness": {"enum": ["fresh", "fast_forwarded", "used_remote_ref", "proceeded_stale", "no_fetch", "no_remote"]},
      "comparison_ref": {"type": "string", "minLength": 1},
      "remote_sha": {"anyOf": [{"type": "string", "pattern": "^[a-f0-9]{7,40}$"}, {"type": "null"}]},
      "behind_count": {"anyOf": [{"type": "integer", "minimum": 0}, {"type": "null"}]}
    }
  }
  ```
  Not in `required` — v1 artifacts without `base_context` still validate. New reviews always write it.
- `commands/_shared/00-preflight.md` step 0.15 seed — `base_context` added to the `jq -n` seed doc when freshness data is available.
- `commands/adams-review.md` — allowlisted tools unchanged (`Bash(git:*)` already covers `git fetch`).

**Interaction with existing Phase 0 steps:**

- Dirty-tree gate (0.8) runs *after* the new 0.2a. `git fetch` and `git fetch origin <base>:<base>` don't touch the worktree (they update refs only), so they're safe regardless of dirty-tree state. If option (a) is chosen when `HEAD == $base_branch` (impossible in practice — review on base branch already exits at the sanity check — but defensively), the FF would require a worktree update; explicitly guard against this and surface a clear error.
- Push unpushed commits (0.9) still runs on `head_branch`'s upstream, unrelated to base.
- `reviewed_sha` (0.10) is still `git rev-parse HEAD` — base-branch freshness does not affect HEAD identity.

### 4.2 — 2.6.B — Phase 1 origin cross-check (Option C)

**New DESIGN sub-section §13.11 — "Origin cross-check (Phase 1 post-lens)".**

Prose essence:

> Phase 1 lenses are prompted with a default of `origin: introduced_by_pr, origin_confidence: high` unless the code "looks clearly unchanged by the diff." In practice they rarely deviate from the default — the prompt is biased toward PR-introduced classification, which is safe when the diff is correct but drops the pre-existing override (§13.1) silently when the diff includes genuinely pre-existing code (e.g., following a stale-base run that proceeded anyway, or when a candidate's line range sits just outside the strictly-modified hunk). A deterministic post-lens cross-check corrects this without adding an LLM call.
>
> **Algorithm (per candidate returned by Phase 1).** For each candidate's `{file, line_range}`:
> 1. If the file did not exist at `comparison_ref` (added by the PR): keep the lens-supplied origin — the whole file is PR-introduced.
> 2. Else, run `git blame -L <start>,<end> --porcelain <file>` at `HEAD`.
>    - If every implicated commit SHA is reachable from `comparison_ref` (i.e., *not* in `comparison_ref..HEAD`): the entire line range pre-dates the PR. Override to `origin: "pre_existing", origin_confidence: "high"`. Record a boolean `origin_crosscheck: "overridden"` on the finding for audit (kept alongside the overridden value; no schema change — it's a free-form annotation allowed under the existing `reason`-adjacent convention).
>    - If at least one implicated commit SHA is in `comparison_ref..HEAD`: the range was modified by the PR. Respect the lens-supplied value.
>    - If blame fails (deleted lines, binary file, etc.): respect the lens-supplied value; log `origin_crosscheck_skipped: <reason>` to `trace.md`.
> 3. If the lens already returned `origin: "pre_existing", origin_confidence: "high"` and blame confirms: no change.
> 4. If the lens returned `origin: "pre_existing"` but blame disagrees (at least one SHA in `comparison_ref..HEAD`): keep the lens value but drop `origin_confidence` to `"medium"` so the pre-existing override does *not* fire. Log the disagreement to `trace.md`.
>
> **Placement.** Runs after Phase 1 aggregation, before Phase 1's `--add-finding` writes. Candidates go in; corrected candidates come out; `--add-finding` records the corrected values. Phase 2 (dedup) and Phase 3 (scoring) see only post-correction origin, which is what §13.1's override keys on.

**Files touched:**

- `DESIGN.md` — new §13.11; §4 Phase 1 narrative gets a new step ("Origin cross-check") between the lens-aggregation step and the `--add-finding` step.
- `commands/_shared/01-detection.md` — new step 1.8 ("Origin cross-check per candidate") between current aggregation (step 1.7) and `--add-finding` (step 1.9 — numbering shifts).
- `commands/_shared/tools/origin-crosscheck.sh` — **new** Bash helper.

**Helper contract (`origin-crosscheck.sh`):**

```
origin-crosscheck.sh \
  --comparison-ref <ref> \
  --candidates <path|@-|inline-json>

Input: JSON array of candidate objects with at least {file, line_range, origin, origin_confidence}.
Output: JSON array of the same objects with {origin, origin_confidence} possibly corrected.
Stderr: one `origin_crosscheck: id=<candidate_id> action=<respected|overridden|downgraded|skipped> reason=<...>` line per candidate for trace.md.
Exit: 0 on success. Per-candidate blame failures do not abort — they fall through to "respect lens".
```

Implementation sketch: Bash loop using `jq` to iterate, `git cat-file -e "$comparison_ref:<file>"` to test file existence at base, `git blame -L... --porcelain HEAD -- <file>` to collect SHAs, `git merge-base --is-ancestor <sha> <comparison_ref>` to test reachability. All deterministic.

**Cost.** Blame per candidate is ~50ms on typical repos. At 50 candidates: ~2.5s added to Phase 1. Acceptable relative to the 5–10min Phase 1 cost. No LLM tokens.

**Why conservative policy (respect lens when mixed).** If a candidate's line range straddles PR-modified and pre-existing code, the *finding* is typically about the PR's change creating a problem near pre-existing code — classifying it pre-existing would hide it from the deep-lane tables. Only the "entirely pre-existing" case is unambiguous enough to auto-override.

### 4.3 — 2.6.C — Report freshness surfacing

**Goal:** when `base_freshness != "fresh"`, the rendered artifact.md header carries a one-line status so the user sees the caveat inline with the PR comment.

**Files touched:**

- `commands/_shared/tools/artifact-render.py` — extend `render_header()` (currently at lines 106–129) to emit a "Base freshness" line when `base_context.freshness` is present and not `"fresh"`:
  - `"fast_forwarded"` → `**Base freshness:** local `<base>` was 12 commits behind `origin/<base>` at run start; fast-forwarded before review`
  - `"used_remote_ref"` → `**Base freshness:** ⚠ local `<base>` is 12 commits behind `origin/<base>`; this review compared against `origin/<base>` instead`
  - `"proceeded_stale"` → `**Base freshness:** ⚠⚠ compared against stale local `<base>` (12 commits behind `origin/<base>`). Re-run after `git pull` for accurate results.`
  - `"no_fetch"` → `**Base freshness:** could not fetch `origin/<base>` (offline?); compared against local`
  - `"no_remote"` → no line rendered
- `DESIGN.md` §7 — sample rendered-report block gains one illustrative freshness line under the header.

### 4.4 — 2.6.D — BUILD.md close-out

**Files touched:**

- `BUILD.md` — stage index row added; Stage 2.6 section written following the Stage 2.5 template (goal, files landed, open issues, cross-stage notes); "Current state" bullet updated to reflect 2.6 done.

---

## 5. Verification

**`test/smoke.sh` additions** (extending the existing harness patterns):

1. **Freshness gate — behind-base prompt path.** Set up a scratch repo via the existing fixture pattern: create `origin` remote with main at SHA X, local main at SHA X-1, feature branch off local main. Invoke the Phase-0 step directly (not via the full command, to keep the test hermetic — the step is a self-contained sequence we can exercise). Assert: `behind_count=1`, freshness prompt would fire, each option's branch produces the expected `comparison_ref` and `base_freshness` values. Four sub-assertions.
2. **Freshness gate — offline fallback.** Scratch repo with `origin` remote pointing at an unreachable URL. Invoke. Assert: fetch fails, `base_freshness="no_fetch"`, `comparison_ref=$base_branch`, trace.md contains the `fetch_failed` line. One assertion.
3. **Origin cross-check — flip case.** Scratch repo with a pre-existing file, commit on main, branch off, make an unrelated change on a *different* file. Feed `origin-crosscheck.sh` a synthetic candidate referencing a line range in the pre-existing file. Assert: output has `origin: "pre_existing", origin_confidence: "high"`. One assertion.
4. **Origin cross-check — respect-lens case.** Same scratch repo, but candidate references a line range in the file the PR touched. Assert: lens value preserved. One assertion.
5. **Origin cross-check — new-file case.** Candidate references a line in a file created by the PR. Assert: lens value preserved (whole file is PR-introduced). One assertion.

Total: 7 new smoke assertions.

**End-to-end re-run on ray-finance** (manual, outside smoke harness):

- Pre-condition: stash or commit any local changes; checkout `feat/import-apple`; confirm local main is behind origin main.
- Run `/adams-review`. Expect: the four-option prompt fires.
  - Select (a). Confirm local main fast-forwards cleanly, freshness line absent from report header, and re-rendered PR comment includes a populated Pre-existing section if any genuinely pre-existing issues are now identifiable via blame.
  - Repeat run selecting (b): confirm header shows "compared against `origin/main`" line and results match (a) semantically.
- Capture resulting `review_id` and post-run `trace.md` / `artifact.md` under Stage 2.6 close-out notes.

**Schema validation.** `test/smoke.sh` already validates every emitted artifact against `schema-v1.json`. New `base_context` objects ride through without adjustment as long as the helper writes the schema-valid shape.

---

## 6. Risk notes

- **Fetch time on massive monorepos.** 30s soft timeout is a budget, not a guarantee. On pathological repos where even a single-branch fetch exceeds 30s, the timeout fires and we degrade to `no_fetch`. User sees a one-line warning; review proceeds. Acceptable failure mode — better than silent stale-main.
- **Divergent local base (user committed to main directly, which then diverged from origin/main).** Option (a)'s FF will refuse; orchestrator surfaces the error and offers (b/c/d). Not a silent failure.
- **Blame disagreement with lens (downgrade path).** The conservative downgrade `pre_existing:high → pre_existing:medium` when blame disagrees silences the §13.1 override. This is intentional: the lens flagged pre_existing on "it looks old" heuristics, blame disagrees with evidence, so we don't auto-route to report-only. Finding still appears — just in its normal disposition lane, not the pre-existing section. Logged to trace.md for inspection.
- **DESIGN addendum promotion.** §13.10 and §13.11 are normative additions. Per the stage-2.5 precedent for normative (non-clarification) changes, they land in the same commit as the implementing code and BUILD.md records the rationale. No separate DESIGN-only commit needed.

---

## 7. Critical files modified (summary)

| File | Nature of change |
|------|------------------|
| `DESIGN.md` | New §13.10, §13.11; §4 Phase 0 + Phase 1 narrative additions; §6 `base_context` row; §7 sample header line |
| `commands/_shared/00-preflight.md` | New step 0.2a; update 0.2 sanity-check + 0.6 diff to use `comparison_ref`; working-set table additions; step 0.15 seed additions |
| `commands/_shared/01-detection.md` | New step 1.8 (origin cross-check); lens-prompt ref swap (`base_branch` → `comparison_ref`) at L1/L2/L3/L4/L5/L6 prompts |
| `commands/_shared/tools/origin-crosscheck.sh` | **New** Bash helper (deterministic blame-based classifier) |
| `commands/_shared/tools/artifact-render.py` | `render_header()` gains conditional "Base freshness" line |
| `commands/_shared/schema-v1.json` | New optional `base_context` property |
| `test/smoke.sh` | 7 new assertions across 5 test cases |
| `BUILD.md` | Stage index row; Stage 2.6 close-out section |

---

## 8. Execution order

1. **2.6.A first** (freshness gate + schema + preflight + lens-prompt ref swap). Self-contained; tests 1–2 cover it. One commit.
2. **2.6.B next** (origin cross-check helper + detection step + tests 3–5). Builds on 2.6.A's `comparison_ref`. One commit.
3. **2.6.C next** (renderer header line). Depends on 2.6.A's `base_context` being written. One commit.
4. **2.6.D last** (BUILD.md). One commit.
5. **DESIGN §13.10 + §13.11** land with 2.6.A and 2.6.B respectively (not a separate commit).
6. End-to-end ray-finance re-run after all four land; notes captured in BUILD.md close-out.

Each commit ends with `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`.

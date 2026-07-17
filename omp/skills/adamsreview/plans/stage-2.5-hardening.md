# Stage 2.5 — Hardening plan

**Status:** drafted 2026-04-18, awaiting user review.
**Preceded by:** Stage 2 (`/adams-review` end-to-end). Complete; C13 real-repo smoke on ray-finance `feat/import-apple` passed end-to-end with PR comment `4274059620` posted. `test/smoke.sh` passes 39 assertions.
**Followed by:** Stage 3 (`/adams-review-fix` — Phases 7–9 + terminal cleanup).

---

## 1. Goal

Close three reactive gaps surfaced by the C13 smoke before Stage 3 adds more surface area on top of them:

1. **Sensitive-file gate** — every write under `~/.claude/reviews/…` triggers a Claude Code permission prompt, dozens per run. Every first-run user hits it.
2. **Phase-4 decision-table loop** — per-finding `artifact-patch.py --set` invocations accumulate prose in orchestrator context. The one Phase-4 lever the BUILD-time analysis flagged as "highest-payoff / lowest-cost" for context budget.
3. **Light-lane `uncertain` renderer bug** — `artifact-render.py` silently drops Light-lane `uncertain` findings from both the summary and the Light lane table. C13 actually hit this: F021 / F022 / F032 were present in `artifact.json` but missing from the rendered `artifact.md` and therefore from PR comment `4274059620`. Found during Stage 2.5 planning review; BUILD.md flagged it as an open decision for this stage.

Stage 2.5 does **not** touch schemas, DESIGN sections beyond clarifications, or any Phase-8/9 material. It's strictly a hardening pass.

**Done when:**

1. A fresh `/adams-review` run on ray-finance `feat/import-apple` (or a smaller test repo) completes with **zero** sensitive-file permission prompts — or one-time prompts only, if the probe chose the `additionalDirectories` path.
2. `artifact-patch.py --apply-decisions` applies a full Phase-4 decision batch in one call. `05-validation.md` step 4.4 contains one helper invocation per wave, not a per-finding loop.
3. `artifact-render.py` renders Light-lane `uncertain` findings in both the summary line and the Light lane table. Re-rendering the C13 artifact surfaces F021/F022/F032.
4. `test/smoke.sh` passes; three new assertions cover the `--apply-decisions` batch path, the reviews-root relocation (if 2.5.A flips), and the Light-lane-uncertain render case.
5. BUILD.md Stage 2.5 section filled in; *Cross-stage notes* gains the 2.5.C Stage-3 authoring disciplines.

---

## 2. Ground rules (restated from Stages 1–2)

- **Python:** `uv` PEP-723 inline-script shebang + `jsonschema` where needed. No new Python files; `artifact-patch.py` grows a new mode.
- **Bash:** `#!/usr/bin/env bash` + `set -euo pipefail`. Bash 3.2-safe — no `declare -A`, no `mapfile`, no `${var,,}`. Dedup via `awk '!seen[$0]++' | sort`.
- **Exit codes** (codified in DESIGN §21.2 footnote): `0` success / `1` validation / `2` invalid-transition / `3` dry-run-invalid / `4` unexpected / `5` missing-dep / `64` usage. `--apply-decisions` reuses these — no new codes.
- **Error-as-prompt style:** ERROR → context → Valid values → Did you mean → Action. `c.err_prompt()` for Python; the same structure by hand for Bash.
- **Commits:** one per natural breakpoint, imperative mood, reference DESIGN §. `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>` trailer.
- **Directly to `main`;** no feature branches.
- **Symlink dev layout is already live** (`~/.claude/commands/_shared` → `commands/_shared/`). Edits are live immediately.
- **No user round-trip for clarification-level DESIGN updates** (per BUILD.md protocol). 2.5.B's `--apply-decisions` row in DESIGN §21.2 is clarification-level. 2.5.A's §9.1 note is clarification-level IF the relocation path lands.

---

## 3. Scope — work items

Four sub-items: 2.5.A (sensitive-file gate), 2.5.B (Phase-4 collapse), 2.5.C (authoring discipline notes, no code), 2.5.D (renderer bug). BUILD.md defined 2.5.A–C; 2.5.D is added here per the §4 decision below.

### 3.1 Intentionally NOT in Stage 2.5

All of these come from BUILD.md's "Explicitly out of scope" list and the C13 cross-stage notes:

- **Phase-5 `xc_input_json` sub-agent preprocessor** (Note 1 Lever #1). Deferred. Revisit only if a Stage 3 real-repo run shows the orchestrator approaching context limits.
- **Fragment prose shrink** (Note 1 Lever #4). Deferred. Not blocking.
- Any schema / DESIGN §6 structural change.
- Anything touching Phases 7–9 / fix-loop.
- Migration tooling for pre-2.5 `~/.claude/reviews/…` directories if 2.5.A flips the root — users handle manually via `mv` or `$ADAMS_REVIEW_REVIEWS_ROOT` per documented migration text.

---

## 4. Decision surfaced during planning — renderer bug disposition

**Question (from BUILD.md Stage 2.5 "Explicitly out of scope" block):** fold the Light-lane-uncertain renderer bug into 2.5.B, ship as a standalone patch, or defer to Stage 3?

**Evidence gathered during planning:**

- The C13 artifact at `~/.claude/reviews/github.com-cdinnison-ray-finance/feat/import-apple/rev_01KPGJVT5DBEJXR5WHB5Z62PS3/artifact.json` has **three** Light-lane `uncertain` findings (F021 `src/cli/ink/mount.ts`, F022 `src/cli/ink/ChatApp.tsx`, F032 `src/cli/commands.ts`) that are present in the JSON but silently absent from the rendered `artifact.md` and therefore from PR comment `4274059620`. The user's first real-world run already shipped this data loss.
- The fix is surgical: add `"uncertain"` to the iteration tuples at `artifact-render.py:148` (summary) and `:323` (Light lane table). Zero risk of blast radius beyond those two lines.
- `test/fixtures/artifact-seed.json` + `expected.md` don't currently cover this combination — whichever path we take needs a fixture-and-assertion addition.
- `render_light_lane()` already has a `Disposition` column (line 330), so adding `uncertain` rows fits the existing table shape; no column / header change needed.

**Recommendation: fold as its own sub-item (2.5.D), not into 2.5.B, and not defer.**

Why not into 2.5.B: different file (`artifact-render.py` vs `artifact-patch.py`), different concern (rendering vs helper mode), and different commit boundary. Bundling muddies the commit message ("Add --apply-decisions mode and fix light-lane uncertain renderer bug") and makes a clean Stage 3 bisect harder.

Why not defer to Stage 3: the bug already hit the user's one real run. Shipping Stage 3 with this still open means every subsequent `/adams-review` run silently hides uncertain light-lane findings from the PR comment — precisely the findings the user most needs to decide on manually. Deferring has ongoing user-visible cost; fixing it now is one commit.

Why "as its own sub-item" instead of one-off: the stage is called Hardening. A renderer fix with its own smoke fixture belongs in a hardening stage. It also benefits from the same fixture-authoring work that 2.5.B's smoke assertion needs — they can share a throwaway workspace pattern in `test/smoke.sh`.

### 4.1 The bug, explicitly

`artifact-render.py`:

- **Line 141–142** (deep summary iteration): `("confirmed_mechanical", "partial", "regression", "resolved", "confirmed_manual", "confirmed_report", "uncertain")` — includes `uncertain`. ✓
- **Line 148** (light summary iteration): `("confirmed_mechanical", "confirmed_manual", "confirmed_report")` — omits `uncertain`. ✗
- **Line 323** (light table iteration): same tuple as line 148. ✗

Per DESIGN §13.1 Phase-4 decision rule, `score_phase4` in `45-59` yields `disposition: uncertain` **regardless of lane**. The schema and the patch script both allow light-lane `uncertain`. The renderer is the only layer that drops it.

**Symptom:** `render_summary()` line 133 does `findings_count = sum(len(v) for v in buckets.values())`, which counts light-uncertain findings in the total. But the per-lane bullets don't list them and `render_light_lane()` doesn't emit rows. Net effect: the user sees "Found N findings across all lanes" that doesn't add up to the enumerated rows — exactly the pattern BUILD.md's Stage 1 "Open issues" already flagged as a rendering quirk, now compounded by a real data-loss case.

`deep_other` has a dedicated `render_deep_other(buckets, "uncertain")` call at a §7-mandated "Uncertain (N)" section with explanatory prose. The light lane per §7 uses a single table with a `Disposition` column, so the fix is a tuple-literal edit, not a new section.

---

## 5. Scope details

### 5.1 — 2.5.A — Sensitive-file gate resolution

Two-step: probe, then branch on outcome. BUILD.md Stage 2.5 block §A is already specific enough to execute; this section records the branches and open question for tracking only.

**Step 1. Probe `additionalDirectories`.**

- Create a scratch project with `.claude/settings.json` containing `{"permissions": {"additionalDirectories": ["~/.claude/reviews"]}}` (exact key per Claude Code docs — `~/` expansion may or may not apply; fall back to an absolute path if not).
- Trigger a write to `~/.claude/reviews/probe_test/trace.md` (e.g., `touch` + `printf >>`).
- Observe whether the sensitive-file permission prompt fires.
- Record outcome in BUILD.md *Cross-stage notes* regardless of which branch we take.
- Budget: ~15 min.

**Step 2. Branch on probe outcome.**

**Outcome (a) — `additionalDirectories` bypasses the gate.** Ship documentation only, no code change.

- `README.md` gains a `Setup` section instructing users to add the `additionalDirectories` line to their project's `.claude/settings.json` (or a per-user `~/.claude/settings.json` equivalent).
- DESIGN §9.1 gains a one-line note: `Users must allowlist ~/.claude/reviews in .claude/settings.json.additionalDirectories to bypass the sensitive-file gate.` Clarification-level.
- Release-notes text for upgraders.

**Outcome (b) — `additionalDirectories` does NOT bypass the gate.** Flip the default reviews root.

- `$ADAMS_REVIEW_REVIEWS_ROOT` default changes from `~/.claude/reviews` to `~/.adams-reviews` (leading dot — hidden state dir convention; outside `.claude/` means the gate doesn't fire).
- Touch points (to identify via `grep -r '\.claude/reviews'` before editing):
  - `commands/_shared/00-preflight.md` — `review_dir` construction.
  - `commands/_shared/tools/artifact-publish.sh` — `latest.txt` resolution (three-tier: `--md-path` > `--review-dir` > env-rooted `latest.txt`).
  - `commands/_shared/tools/external-scrape.sh` — scratch / config paths if present.
  - `README.md`, `DESIGN.md` §9.1, `BUILD.md` cross-stage notes, commit message.
  - `test/smoke.sh` — any assertion hardcoding `~/.claude/reviews/...` picks up the new default or gets re-parameterized via `$ADAMS_REVIEW_REVIEWS_ROOT` override. Prefer the latter (test-isolation).
- Migration text in `README.md`:
  > If you have pre-2.5 reviews under `~/.claude/reviews/`, either `mv ~/.claude/reviews ~/.adams-reviews` OR `export ADAMS_REVIEW_REVIEWS_ROOT=~/.claude/reviews` to keep them where they are.
- DESIGN §9.1 rewording: canonical default is now `~/.adams-reviews/`; env-var override documented. Clarification-level (the "canonical layout" wording was always soft; this just moves the default).

**Verification:** re-run `/adams-review` on ray-finance `feat/import-apple` (or a smaller test repo). Confirm zero permission prompts end-to-end. Capture `trace.md` absence-of-prompts evidence in the close-out.

**Cross-stage note to write at close-out** (regardless of branch): record the probe outcome with one-line rationale, so Stage 3 inherits the resolution and doesn't re-ask the question.

### 5.2 — 2.5.B — Phase-4 decision-table collapse

**Step 1. `artifact-patch.py --apply-decisions <path-or-@->`.**

Batch mode that consumes a JSON array of decision tuples and applies each one atomically. Shape per tuple:

```json
{
  "id": "F011",
  "score_phase4": 78,
  "decision": "confirmed",
  "actionability": "auto_fixable",
  "validation_result": { ... },
  "reason": null,
  "confirmed_strength": "strong",
  "related_parent_finding_id": null
}
```

- `validation_result` present only when the resolved disposition (after the decision-table rule) lands in the confirmed band (`confirmed_mechanical` / `confirmed_manual` / `confirmed_report`). For `disproven` / `uncertain` tuples it's absent; the helper does not write the field in that case.
- Other fields optional per DESIGN §13.1; the helper applies the decision table to derive `disposition`, `is_actionable`, `confirmed_strength`, and `reason` defaults, honoring the score-wins-over-decision precedence rule already in 05-validation's prose.
- Internally, each tuple is applied as: `--set score_phase4=…` + `--set disposition=…` + `--set confirmed_strength=…` + `--set actionability=…` + `--set reason=…` + (conditionally) `--set-json validation_result=…`. Same code paths as existing `--set` / `--set-json`; no new transition/coupling logic needed.
- Exit-code semantics: `0` success; non-zero on first tuple failure. Already-committed tuples from earlier in the batch stay committed (no rollback). Stderr identifies the failing tuple by id so the caller can re-invoke with the remainder.
- Input format: `--apply-decisions @path/to/file.json` (file), `--apply-decisions -` (stdin), or inline JSON (short batches). Mirrors existing `--init` / `--add-finding` / `--set-json` idioms.

**Design note on where the decision table lives.** Existing `05-validation.md` encodes the §13.1 table in prose. Moving it into `artifact-patch.py` duplicates the rule surface. Two options:

- **(A, preferred)** Keep the table authoritative in `artifact-patch.py` once added. `05-validation.md` describes the *inputs* the sub-agents return (score, decision, actionability) and notes that `--apply-decisions` applies the table internally. Shorter fragment, single source of truth in code.
- **(B)** Table lives in the fragment; helper just applies pre-derived `disposition` etc. Keeps the helper dumber but re-introduces the loop (orchestrator still has to compute per-tuple dispositions before batching). Loses most of the context-budget benefit — that's what 2.5.B is *for*.

Picking (A). The table's already well-tested via existing per-finding `--set` paths; the helper just centralizes it. BUILD.md Cross-stage note codifies.

**Step 2. `commands/_shared/05-validation.md` rewrite.**

Step 4.4 changes from:

- Per-finding loop, each iteration:
  - Computes `resolved_disposition` from score + actionability in shell.
  - Invokes `artifact-patch.py --set …` (5 flags).
  - Optionally invokes `artifact-patch.py --set-json validation_result=@…` (second call) for confirmed-band findings.
  - Writes prose "applied F011 as confirmed_mechanical" per iteration.

…to:

- Build one JSON array combining all Wave 1 (and separately all Wave 2) validator outputs into a temp file at `/tmp/adams-review-$review_id/phase4-wave1-decisions.json`.
- One `artifact-patch.py --apply-decisions @…` call per wave.
- One summary line: `applied N decisions (confirmed_mechanical=X, confirmed_manual=Y, uncertain=Z, disproven=W)`.
- Step 4.5 (Wave 2 composition) unchanged; Step 4.6 equivalent (Wave 2 decision application) reuses the same `--apply-decisions` call.

The jq-extraction trick for `validation_result` (`jq -c '.validation_result // .'`) moves from shell-per-finding into the jq that composes the array — each tuple's `validation_result` is `(sub_response.validation_result // sub_response)`.

**Step 3. `test/smoke.sh` — add one assertion.**

- Seed an artifact with 3 findings in `pending_validation` (extend `test/fixtures/artifact-seed.json` or use a dedicated fixture).
- Feed a mixed-decision batch — one confirmed-auto (with `validation_result`), one uncertain (no `validation_result`), one disproven.
- Assert post-state: each finding's `disposition`, `is_actionable`, `confirmed_strength`, `score_phase4`, `validation_result` (present or absent) matches per-tuple expectations.
- Also assert the batch exits non-zero if any tuple fails validation and names the failing id.

**Step 4. DESIGN.md §21.2 footnote.**

Add `--apply-decisions <path-or-@->` to the `artifact-patch.py` sub-section's sketch. Clarification-level (helper gains a new mode; no behavior change to existing modes). Reference §13.1 as the table source.

### 5.3 — 2.5.C — Stage-3 authoring-discipline notes (no code)

Append to BUILD.md *Cross-stage notes* with a `2026-04-18` dated entry capturing the three principles from BUILD.md Note 1 Levers #1, #2, #4 (already drafted in the Stage 2.5 section of BUILD.md, but not yet in *Cross-stage notes* where Stage 3 planning will look). Verbatim:

- **Read for decisions, not for holding.** Prefer narrow `jq` filters that return a verdict (`.findings | length`, `.findings | map(.disposition) | unique`) over reading full records into orchestrator context when the orchestrator only needs a branch decision.
- **Delegate large-context synthesis to sub-agents** that return structured summaries (ids, group memberships, verdicts) rather than handing the full prompt+data to the orchestrator and emitting back prose.
- **Avoid per-finding loops in fragments when a single helper call can carry the same semantics.** Each loop iteration accumulates prose in orchestrator context; a batched helper invocation does not.

These are authoring disciplines, not enforced by tooling. Stage 3 planning applies them from the start — particularly Phase 8 (fix-group agent dispatch) and Phase 9 (per-finding sub-agent results).

### 5.4 — 2.5.D — Renderer: Light-lane `uncertain` (new sub-item per §4 decision)

**Step 1. `artifact-render.py` fix.**

- Line 148: change `("confirmed_mechanical", "confirmed_manual", "confirmed_report")` → `("confirmed_mechanical", "confirmed_manual", "confirmed_report", "uncertain")`.
- Line 323: same change.
- No other lines touched. `render_deep_other()` and its Uncertain section remain deep-only. The light lane's single-table shape (with a `Disposition` column) already accommodates mixed dispositions.

**Step 2. Blast-radius check before committing** (per CLAUDE.md blast-radius discipline):

- Every writer: §13.1 Phase-4 table produces `uncertain` for any score `45-59` regardless of lane. Schema allows it. `artifact-patch.py` coupling rules already treat `uncertain` as `is_actionable: false`. No writer-side change needed.
- Every consumer: `render_light_lane()` is the only consumer of the light-lane disposition iteration. `render_summary()` is the only consumer of `light_bits`. No other grep hits.
- Parallel paths: `render_deep_other(buckets, "uncertain")` is the deep-lane equivalent — distinct rendering path, already works, need not change.
- Stale comments: none describe "light lane excludes uncertain" — the omission is just a tuple literal.

**Step 3. Fixture and smoke assertion.**

- Extend `test/fixtures/artifact-seed.json` to include at least one Light-lane `uncertain` finding, OR add a dedicated fixture file under `test/fixtures/` if the seed is already complex enough that extending would churn existing assertions.
- Regenerate `test/fixtures/expected.md` to include the finding's row in the Light lane table + inclusion in the summary `light_bits` count.
- Add one smoke assertion: render the extended seed, grep for the Light-uncertain finding's id in the rendered output; fail if absent.
- Verify `diff expected.md rendered.md` remains empty byte-for-byte (existing assertion path stays valid after regen).

**Step 4. Re-render C13 artifact as evidence** (optional but cheap — do it in close-out, not as a commit).

- Run `artifact-render.py --input ~/.claude/reviews/github.com-cdinnison-ray-finance/feat/import-apple/rev_01KPGJVT5DBEJXR5WHB5Z62PS3/artifact.json --output /tmp/c13-rerender.md`.
- Confirm F021, F022, F032 now appear in the Light lane table.
- The PR comment `4274059620` does not auto-update — the user can decide whether to manually edit or leave it. Recording in close-out notes is sufficient.

---

## 6. Commit order and breakdown

Budget: ~5 commits total (matches BUILD.md's Stage 2.5 "Commit cadence" estimate; +1 for 2.5.D).

### Commit 1 — 2.5.A probe + outcome recording

- Run the probe scratch session (noted in §5.1 step 1).
- Append probe outcome to BUILD.md *Cross-stage notes* dated `2026-04-18` with the specific Claude Code behavior observed and whichever branch we'll take.
- Single-file commit: `BUILD.md` only.
- Commit message: `Record sensitive-file gate probe: additionalDirectories {does|does not} bypass`.

### Commit 2 — 2.5.A fix path (one of two)

**If (a):** docs-only path.

- Update `README.md` with a `Setup` section.
- Add the §9.1 one-liner to `DESIGN.md`.
- Single commit. Message: `Document additionalDirectories setup for sensitive-file gate (§9.1)`.

**If (b):** relocation path. May split into two commits if the diff is large:

- Commit 2a: flip `$ADAMS_REVIEW_REVIEWS_ROOT` default from `~/.claude/reviews` to `~/.adams-reviews` in `00-preflight.md`, `artifact-publish.sh`, `external-scrape.sh`, plus README migration text. Update DESIGN §9.1.
- Commit 2b: `test/smoke.sh` updates — either pick up the new default or re-parameterize via env-var override for test isolation.

Message on the main commit: `Relocate reviews root to ~/.adams-reviews to bypass sensitive-file gate (§9.1)`.

### Commit 3 — 2.5.B helper-mode (`artifact-patch.py --apply-decisions`)

- Add `--apply-decisions` subcommand to `artifact-patch.py`, reusing existing `_apply_finding_set` / `_apply_finding_set_json` code paths. Decision-table logic centralized in `_common.py` (or inline if the table is small enough) so the patch script stays focused on apply-and-validate.
- Extend `test/smoke.sh` with the mixed-decision batch assertion.
- DESIGN §21.2 footnote update.
- Commit message: `Add artifact-patch.py --apply-decisions for Phase-4 batch application (§13.1, §21.2)`.

### Commit 4 — 2.5.B fragment rewrite (`05-validation.md`)

- Rewrite Step 4.4 to use `--apply-decisions` once per wave. Step 4.5/4.6 (Wave 2) reuses the same call.
- No helper changes in this commit — just the fragment.
- Commit message: `Collapse Phase-4 decision loop to single apply-decisions call (05-validation)`.

### Commit 5 — 2.5.D renderer fix + Stage 2.5 close-out

Bundle the small renderer fix with BUILD.md close-out. They touch different files but both are trivial and close-out-y; keeping them together avoids a near-empty close-out commit.

- `artifact-render.py`: tuple-literal edits on lines 148 and 323.
- `test/fixtures/artifact-seed.json` + `expected.md`: extend for the Light-uncertain case.
- `test/smoke.sh`: one more assertion (count rises to 40 if 2.5.A chose (a) / 42 if (b) / +1 for 2.5.B + 1 for 2.5.D = 41 or 42).
- BUILD.md: flip Stage 2.5 status to `done`; fill *Files landed* / *Verification evidence* / *Open issues*. Append 2.5.C authoring-discipline notes to *Cross-stage notes*.
- Record the C13 re-render evidence (F021/F022/F032 now appear) as a one-liner in close-out.
- Commit message: `Close Stage 2.5: fix light-lane uncertain renderer + hardening close-out`.

---

## 7. Smoke-harness assertion additions (summary)

Current: 39 assertions passing on `main`.

Stage 2.5 additions:

| # | Item | Assertion |
|---|------|-----------|
| +1 | 2.5.B (Commit 3) | `--apply-decisions` mixed-decision batch: 3 findings transition correctly, `validation_result` written only for confirmed-band, non-zero exit + stderr-names-failing-id on bad tuple. |
| +1 | 2.5.A (Commit 2, conditional) | If branch (b): `latest.txt` resolves via `$ADAMS_REVIEW_REVIEWS_ROOT` override; existing `--md-path` / `--review-dir` overrides still win. Otherwise: no new assertion for (a). |
| +1 | 2.5.D (Commit 5) | Light-lane `uncertain` finding is present in rendered `expected.md` and the render-diff stays empty; summary `light_bits` counts it. |

Total after Stage 2.5: 41 (if 2.5.A goes (a)) or 42 (if (b)).

---

## 8. Clarification-level DESIGN updates (no user round-trip)

Per BUILD.md "Adjusting the design as we build" protocol, these are clarifications — apply inline during execution, codify in *Cross-stage notes*:

- **§21.2:** `--apply-decisions <path-or-@->` row added to the `artifact-patch.py` sketch. Behavior described by reference to §13.1 table.
- **§9.1 (conditional on 2.5.A outcome):** canonical reviews-root default changes from `~/.claude/reviews/…` to `~/.adams-reviews/…`, with env-var override documented. OR: one-line note that users must allowlist `~/.claude/reviews` in `additionalDirectories`.

No behavioral-change DESIGN updates expected. If the probe surfaces a third option (e.g., a glob permission we didn't know about), we stop and surface per BUILD.md protocol.

---

## 9. Open questions (resolved during execution; codified in *Cross-stage notes*)

- **Exact `additionalDirectories` key name** in `.claude/settings.json`. Resolved by reading Claude Code docs during Commit 1's probe. If the key is named differently or doesn't exist, the probe immediately reveals that and we fall to branch (b).
- **Whether `--apply-decisions` table belongs in `_common.py` or inline in `artifact-patch.py`.** Low-stakes; decided during Commit 3 based on how much code the table requires. If ≤20 lines, inline; if more, extract.
- **Fixture extension vs. dedicated fixture for 2.5.D.** Decided during Commit 5 after looking at the current seed's structure. Default: extend the existing seed (keeps one fixture for the render path).
- **Migration text tone for 2.5.A branch (b).** BUILD.md has a working draft in §A. If the probe lands us in (b), re-read during README edits.

---

## 10. Decisions already locked (carry over from Stages 1 / 2)

1. **`uv` PEP-723** for any Python needs. No new Python dep.
2. **Bash 3.2 portable** throughout.
3. **Exit codes** per DESIGN §21.2 footnote.
4. **`--set` scalar allowlist + `--set-json` nested allowlist** preserved. `--apply-decisions` is orthogonal — it doesn't touch the allowlists, it composes the existing `_apply_finding_set` / `_apply_finding_set_json` call paths.
5. **Absolute-path grants in `allowed-tools`** (§8.7 probe PASSED).
6. **Symlink dev layout** live at `~/.claude/commands/_shared`.
7. **Commit cadence:** one per natural breakpoint; never batched; `Co-Authored-By: Claude Opus 4.7 (1M context)` trailer.
8. **Pre-existing override re-assertion (§13.1)** still happens after Phase 4 regardless of `--apply-decisions` — it runs at the orchestrator level after the batch, not inside the helper.

---

## 11. Exit criteria — Stage 2.5 Done

- [ ] 2.5.A probe recorded; outcome branch chosen and executed.
- [ ] A fresh `/adams-review` run produces **zero** sensitive-file permission prompts (or one-time only, per the (a) branch).
- [ ] `artifact-patch.py --apply-decisions` lands with smoke coverage; decision table authoritative in the helper.
- [ ] `05-validation.md` step 4.4 contains one `--apply-decisions` call per wave, not a per-finding loop.
- [ ] `artifact-render.py` renders Light-lane `uncertain` findings in summary + table.
- [ ] Re-rendering the C13 artifact surfaces F021 / F022 / F032 in the Light lane table (evidence captured in close-out notes).
- [ ] `test/smoke.sh` passes, up 2–3 assertions from 39.
- [ ] DESIGN §21.2 footnote updated; §9.1 updated if 2.5.A branch required it.
- [ ] BUILD.md Stage 2.5 section filled in (Files landed / Verification evidence / Open issues).
- [ ] *Cross-stage notes* gains: (a) 2.5.A probe outcome, (b) 2.5.C Stage-3 authoring disciplines, (c) `--apply-decisions` clarification.
- [ ] All commits on `main`. No feature branches.

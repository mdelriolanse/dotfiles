# Stage 2 — `/adams-review` end-to-end plan

**Status:** drafted 2026-04-17, awaiting user review.
**Preceded by:** Stage 1 (data layer + shared helpers). Complete as of `543f299`. `test/smoke.sh` passes 19/19.
**Followed by:** Stage 3 (`/adams-review-fix` — Phases 7–9 + terminal cleanup).

---

## 1. Goal

Ship the review half of the product: a user can run `/adams-review` on a real branch or PR and get back a valid `artifact.json`, a rendered `artifact.md` matching DESIGN §7, and — in PR mode — a posted-or-edited review comment on the PR. Local mode is a no-op on publish but still writes the artifact to `~/.claude/reviews/...` and mirrors the rendered report to chat.

Stage 2 does **not** add fix loop or commit behavior. Phase 6 (finalize) is the terminal step.

**Done when:**
1. `/adams-review` on a real repo produces a schema-valid `artifact.json` at `~/.claude/reviews/<slug>/<branch>/<review_id>/`.
2. The rendered `artifact.md` structurally matches DESIGN §7 (marker line, header, disposition-filtered sections, optional fix-runs section absent at this stage).
3. PR mode posts or edits the PR comment via the §13.4 discovery chain (comment_id → marker search → create, with PATCH-fail fallback). Local mode writes nothing to GitHub but still hits `latest.txt`.
4. `phases.jsonl` has one line per completed phase; `tokens.jsonl` has one line per sub-agent invocation; `trace.md` has human-readable phase sections.
5. Ensemble mode (`/adams-review --ensemble`) runs the Phase 1.5 scrape + external adapter dispatch; without the flag, those phases are skipped cleanly.
6. Trivial-mode gate works: a docs-only PR produces a reduced pipeline (L2/L5/L6 skipped, 4a skipped, 5 skipped), reflected in `phases.jsonl` and `trivial_mode: true` on the artifact.
7. The §10.1 effort inheritance caveat is surfaced in the command file (one-line note).

The 10 Stage 1 helpers stay unchanged **except** `artifact-publish.sh`: Stage 2 adds the §13.4 `latest.txt` fallback so `--md-path` becomes optional, bringing the orchestrator-facing contract back to §21.6's signature.

---

## 2. Ground rules (restated from Stage 1)

- **Python:** `uv` PEP-723 inline-script shebang + `jsonschema` where needed. Stage 2 doesn't add new Python helpers (the existing writers suffice); any ad-hoc Python lives inline in fragments via `uv run` heredocs if needed.
- **Bash:** `#!/usr/bin/env bash` + `set -euo pipefail`. Bash 3.2-safe — no `declare -A`, no `mapfile`, no `${var,,}`. Dedup via `awk '!seen[$0]++' | sort`.
- **Exit codes** (from Stage 1 close-out, codified in DESIGN §21.2 footnote): `0` success / `1` validation / `2` invalid-transition / `3` dry-run-invalid / `4` unexpected / `5` missing-dep / `64` usage.
- **Error-as-prompt style:** ERROR → context → Valid values → Did you mean → Action. `c.err_prompt()` for Python; the same structure by hand for Bash.
- **Commits:** one per natural breakpoint, imperative mood, reference DESIGN §. `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>` trailer.
- **Directly to `main`;** no feature branches.
- **Symlink dev layout** is already live. All new `_shared/*.md` fragments and helpers appear at the canonical `~/.claude/commands/_shared/...` path immediately. Top-level `adams-review.md` goes at `~/.claude/commands/adams-review.md`.
- **Absolute-path grants work** (§8.7 probe PASSED — 2026-04-17 BUILD cross-stage note). Use the canonical `Bash(/Users/adammiller/.claude/commands/_shared/tools/<script>:*)` form; no relative-name fallback needed.

---

## 3. Scope — files this stage creates

### 3.1 Phase fragments (new `_shared/*.md`)

Per DESIGN §9.1, Stage 2 ships 8 fragments — 7 always included, 1 conditional.

| File | Drives DESIGN phase | Always / conditional |
|---|---|---|
| `commands/_shared/00-preflight.md` | Phase 0 (§4) | always |
| `commands/_shared/01-detection.md` | Phase 1 (§4, §19.2) | always |
| `commands/_shared/02-ensemble-adapter.md` | Phase 1.5 adapter dispatch (§4, §19.2a) | conditional on `--ensemble` |
| `commands/_shared/03-dedup.md` | Phase 2 (§4, §19.3) | always |
| `commands/_shared/04-scoring-gate.md` | Phase 3 (§4, §19.4, §20) | always |
| `commands/_shared/05-validation.md` | Phase 4 (§4, §19.5, §19.6) | always |
| `commands/_shared/06-cross-cutting.md` | Phase 5 (§4, §19.7) | always (skipped internally if no deep-lane findings) |
| `commands/_shared/07-finalize.md` | Phase 6 (§4) | always |

`08-fix-loader.md`, `09-fix-execution.md`, `10-post-fix-and-commit.md` are **Stage 3** — not authored here.

### 3.2 Lens reference files (content verbatim from DESIGN §22)

| File | Purpose |
|---|---|
| `commands/_shared/lens-ux-reference.md` | Inlined into L5 via `!`cat`` (§19.2, §22.1) |
| `commands/_shared/lens-security-reference.md` | Inlined into L6 via `!`cat`` (§19.2, §22.2) |

These are body text, not orchestrator instructions. Copy §22.1 and §22.2 into their respective files.

### 3.3 New helper — `external-scrape.sh` (DESIGN §21.8)

`commands/_shared/tools/external-scrape.sh` — Bash + `gh api`, parallel-fetches the three comment endpoints, filters to bot authors per `external_reviewer_bots` config, emits normalized JSON array to stdout. Full §21.8 signature and algorithm.

### 3.4 Helper extension — `artifact-publish.sh` latest.txt fallback

Make `--md-path` optional. When omitted, resolve via:

```
<review_dir>/artifact.md    if --review-dir <path> passed
<~/.claude/reviews/<slug>/<branch>/<id-from-latest.txt>>/artifact.md    otherwise (orchestrator path)
```

Add `--repo-slug` and `--branch` flags to give the orchestrator an explicit path for the latest.txt lookup without assuming the helper can derive slug/branch from `git` context (the helper may be called from any cwd). The Stage-1 `--md-path` stays supported for Stage 1 smoke compatibility and as the "explicit override" path. Smoke harness stays green.

### 3.5 Top-level command file

`commands/adams-review.md` — thin shell:

- Full frontmatter `allowed-tools` block per §8.7 (absolute paths to all 10 Stage 1 helpers + `external-scrape.sh` + `git:*` + `gh:*` + `AskUserQuestion` + `Agent` + `Read`).
- Orchestration preamble: the "Execution overview" block (mirrors the style in `adams-code-review.md` lines 12–22) telling the orchestrator to build a TaskList mirroring phases, explaining how state carries forward across phases (§25.1), how to dispatch sub-agents, and how to log tokens + phases.
- Sequence of `` !`cat ~/.claude/commands/_shared/NN-*.md` `` preprocessor includes for Phases 0 through 6 (in order).
- `--ensemble` flag handling: the `02-ensemble-adapter.md` include is wrapped in a conditional — the fragment itself checks `if --ensemble was passed` at its top and skips the phase with one log line otherwise. Cleaner than making the include itself conditional.
- `--full` flag handling: forces `trivial_mode = false` (§13.9 override). The 00-preflight fragment checks for this.
- Argument hint + description + one-line effort-inheritance note per §10.1.

### 3.6 Intentionally NOT in Stage 2

- `group-fixes.py` (Phase 8 helper) — Stage 3.
- `08-fix-loader.md`, `09-fix-execution.md`, `10-post-fix-and-commit.md` — Stage 3.
- `adams-review-fix.md` top-level — Stage 3.
- `--granular-commits` flag (§13.6) — Stage 3.
- Runtime `~/.claude/reviews/<slug>/<branch>/` directory — created by Phase 0 of orchestrator at run time, not committed.
- Live PR-mode smoke against a "real" customer repo. We'll run against a throwaway branch in the `adams-review` repo itself (see §9 below). A production-target run can happen during Stage 3 evaluation if desired.

---

## 4. Commit order and breakdown

Each bullet below = one commit. Budget ~13 commits.

### Commit 1 — Scaffold fragment skeletons + lens reference files

**Rationale:** bootstrap the directory layout so later commits can touch one fragment at a time without the whole thing stalling on "where does this file go."

- Create `commands/_shared/00-preflight.md` through `07-finalize.md` as skeleton files (just a title line + `## TODO` placeholder).
- Write `commands/_shared/lens-ux-reference.md` with the full §22.1 body verbatim.
- Write `commands/_shared/lens-security-reference.md` with the full §22.2 body verbatim.
- Nothing executable — this is layout + lens content.

**Verification:** `ls` shows expected files; `diff` the lens files against the DESIGN sections to confirm copy fidelity.

### Commit 2 — Extend `artifact-publish.sh` with latest.txt fallback

**Rationale:** small, contained, testable against existing smoke. Doing it early means every later fragment can call `artifact-publish.sh` with the canonical §21.6 signature.

- Add `--repo-slug <slug>` and `--branch <name>` arg parsing.
- When `--md-path` is omitted: resolve review_dir = `~/.claude/reviews/<slug>/<branch>/$(cat ~/.claude/reviews/<slug>/<branch>/latest.txt)` → `<review_dir>/artifact.md`. Error-as-prompt if `latest.txt` missing or empty (names the expected path; suggests running `/adams-review` first).
- Keep `--md-path` and `--review-dir` working for smoke-harness compatibility (explicit override wins over latest.txt).
- Update `test/smoke.sh` sidecar B if needed (confirm the existing `--mode local --review-dir ...` path still works; add a second assertion that invokes without `--md-path` against a fake latest.txt to exercise the fallback).
- Cross-stage note in BUILD.md: "§21.6 signature now matches DESIGN exactly; `--md-path` demoted to testability override."

**Verification:** `bash test/smoke.sh` → still 19/19 (or 20/20 if sidecar B gains the fallback assertion). `--md-path` explicit path still works.

### Commit 3 — `external-scrape.sh` (DESIGN §21.8)

**Rationale:** independent Bash helper; testable standalone via `gh api` against a real PR without wiring into the pipeline.

- `#!/usr/bin/env bash; set -euo pipefail`.
- Args: `--pr <num>`, `--since <iso-8601>`, optional `--config <path>`.
- Resolve owner/repo via `gh repo view --json nameWithOwner`.
- Load config from per-repo `.claude/review-config.json` falling back to `~/.claude/reviews/review-config.json` (same precedence as §13.8); default `deny` list baked in.
- Three parallel `gh api ...` calls (use `&` + `wait`; capture to three files under `/tmp/adams-review-<pid>/`).
- Filter pipeline through `jq`: created_at filter, bot filter, deny-list, optional allow-list.
- Emit normalized JSON array to stdout per §21.8 step 5.
- Exit 1 on `gh` rate limit; message names reset time.
- Stage-2 verification: run against a PR that has bot comments (the adams-review repo's own PRs if any, or skip to a known repo like `anthropics/claude-code`). Eyeball output.

**Verification:** Help text prints; bogus args exit 64; real `gh api` call returns a JSON array.

### Commit 4 — `00-preflight.md` (Phase 0)

**Rationale:** Phase 0 is the longest shell-heavy fragment. Isolating it means we can iterate on its 12 sub-steps (§4 Phase 0) without touching the LLM-dispatch fragments.

Instructs the orchestrator to perform §4 Phase 0 steps 1-12. Drives:

- Branch + base resolution (§25.1 `base_branch`, `head_branch`, `repo_root`, `repo_slug`).
- `gh pr view` for PR detection; set `mode`, `pr_number`, `pr_state`.
- `review_started_at` capture (explicit: before any push/stash).
- `claude-md-paths.sh` call to populate `claude_md_paths`.
- Dirty-tree handling via `AskUserQuestion` (stash/include/stop).
- Unpushed-commits push (PR mode).
- `git rev-list --count` sanity check.
- Trivial-diff check (§13.9) inline in Bash — sets `trivial_mode`. The fragment includes the exact Bash snippet from §19.1.
- User-facing classifier dispatch (Haiku sub-agent) — unless `trivial_mode`; result is the `user_facing` bool feeding L5 gating.
- Prior-artifact + prior-PR-comment detection with `AskUserQuestion` tables per Phase 0 steps 11–12.
- Orchestrator creates `~/.claude/reviews/<slug>/<branch>/<review_id>/`, generates `review_id` (ULID), writes initial `artifact.json` via `artifact-patch.py --init <seed-json>` with Phase 0 fields populated.
- Log Phase 0 to `trace.md` + `phases.jsonl` via `log-phase.sh`.

**Fragment authoring notes:**

- Every variable in the §25.1 working-set table is either (a) written to the artifact via `artifact-patch.py --set` right then, or (b) captured in the orchestrator's working context with a clear name ("`base_branch` from Phase 0 step 2"). No bash-export assumptions.
- `AskUserQuestion` prompts follow the §4 Phase 0 verbatim wording where given.
- The trivial-diff Bash snippet lives inline (not in a separate script) per §19.1 — it's a deterministic 5-line check.

**Verification:** Eyeballed by reading the fragment. No way to unit-test a markdown fragment in isolation. End-to-end smoke in Commit 12.

### Commit 5 — `01-detection.md` (Phase 1 internal lenses)

**Rationale:** Phase 1 is the widest fan-out in the pipeline — 6 parallel sub-agents. Isolating it lets us iterate on lens prompts and the dispatch template independently of Phases 2+.

Instructs the orchestrator to:

1. Compose a shared input: `baseBranch..HEAD` diff, CLAUDE.md path list (from Phase 0).
2. Dispatch six parallel Agent calls in a single message:
   - L1 Haiku: diff-local scan per §19.2 L1.
   - L2 Opus: structural / blast-radius per §19.2 L2. Receives full repo access (via sub-agent's `Read` + `Bash(git:*)`).
   - L3 Sonnet: CLAUDE.md compliance per §19.2 L3. Receives CLAUDE.md path list + diff.
   - L4 Sonnet: comment compliance per §19.2 L4. Receives diff + modified files.
   - L5 Sonnet **only if `user_facing == true` AND `trivial_mode != true`**: UX lens per §19.2 L5. Receives diff + inlined `lens-ux-reference.md` content via `` !`cat ~/.claude/commands/_shared/lens-ux-reference.md` ``.
   - L6 Sonnet **only if `trivial_mode != true`**: security lens per §19.2 L6. Same inlining for `lens-security-reference.md`.
3. Each sub-agent returns a structured candidate list per §19.2 output shapes.
4. Orchestrator parses each result:
   - Extracts `<usage>total_tokens: N</usage>` → call `log-tokens.sh --phase phase_1 --agent-role <lens-name> --agent-id <id> --model <model> --tokens <N>`. Parse-failure fallback: `--tokens null` (§11 cited).
   - Appends each candidate to the artifact via `artifact-patch.py --add-finding '<json>'`. Auto-generated `id: F<nnn>` sequence.
5. Logs Phase 1 summary to `trace.md` + `phases.jsonl`.

**Fragment authoring notes:**

- **Trivial-mode skipping** is done at the dispatch site — the orchestrator simply doesn't launch L2/L5/L6 sub-agents if `trivial_mode == true`. The skipped lenses get a `trace.md` line and a `phases.jsonl` annotation per §13.9.
- **Fan-out dispatch** uses a single Agent-tool call for each lens; the parallel behavior comes from putting all 6 Agent tool-use blocks in a single orchestrator message. The fragment says this explicitly: "fire all N applicable lens sub-agents in one message — parallelism requires it."
- **Source-family tagging** is the lens's responsibility per its output shape; orchestrator doesn't need to re-assign.
- **Token tracking:** the fragment describes the parse pattern literally — "Look for `<usage>total_tokens: N</usage>` in each agent's tool result; if present extract N, if absent use `null`." Keeps the orchestrator from guessing.

**Verification:** eyeballed. A real-repo run in Commit 12 will exercise it; any lens that mis-dispatches will show up as missing `phase_1_<lens>` in `tokens.jsonl`.

### Commit 6 — `02-ensemble-adapter.md` (Phase 1.5)

**Rationale:** ensemble mode is scoped but optional. Keeping it in a separate fragment means Stage 3 or later can evolve its contents without the core pipeline files changing.

Instructs the orchestrator — only when `--ensemble` was passed and `pr_number` is non-null:

1. Call `external-scrape.sh --pr <pr_number> --since <review_started_at>` → capture stdout JSON.
2. On rate-limit / non-zero exit: log to `trace.md`; skip the rest of Phase 1.5 per §24.2. Do not abort.
3. Dispatch the **Phase 1.5 normalizer** (single Sonnet sub-agent per §19.2a) with the scraped JSON as input; receive candidate list with `source_family: external-deep-family` and `origin_confidence: low`.
4. Dispatch the **codex adapter** and **coderabbit adapter** sub-agents (already present in the plugin system — `codex:codex-rescue`, `coderabbit:code-reviewer`). Pass each the current diff; each returns its native findings which the orchestrator normalizes inline to the shared candidate schema, also tagged `source_family: external-deep-family` but `sources: ["codex"]` / `sources: ["coderabbit"]`.
5. All three result sets (normalizer + codex + coderabbit) feed into Phase 2 dedup alongside internal lens candidates. Orchestrator `--add-finding` them to the artifact with the appropriate source tags.
6. `log-tokens.sh --phase phase_1_ensemble` for each adapter + the normalizer. Wrapper orchestration tokens count; external provider's own LLM spend does not (§11).

**Fragment authoring notes:**

- Top of fragment: `If --ensemble was not passed on this invocation, skip this phase entirely and log "phase_1_5 skipped — --ensemble not set" to trace.md. Proceed to Phase 2.` This keeps the `!`cat`` include unconditional — cleaner than trying to conditionally inline.
- Local mode: Phase 1.5 is also skipped (no `pr_number`). Stage-1 `artifact-publish.sh` already handles this; the fragment just needs a conditional.
- Wrapper-agent dispatch prose: match the idiom used in `adams-code-review.md` for external adapters — "launch the `codex:codex-rescue` sub-agent with the following task..."

**Verification:** exercised only when a user runs `/adams-review --ensemble`. For Stage 2 done-when, a `--ensemble` run against a throwaway PR with bot comments (or zero bot comments — should still succeed) is sufficient.

### Commit 7 — `03-dedup.md` (Phase 2)

**Rationale:** smallest fragment — one Sonnet call.

Instructs the orchestrator to:

1. `artifact-read.sh --filter '.findings | map({id, file, line_range, claim, evidence_snippet, source_family, source_families})'` → candidate list.
2. Dispatch one Sonnet sub-agent per §19.3 with that list as input; receive `{groups: [[id, id, ...], ...]}`.
3. For each group of size > 1: the orchestrator picks the first id as the "keeper", unions `sources` + `source_families` across the group into the keeper's record, and deletes the others via `artifact-patch.py` (we don't have a `--delete-finding`; noted below as a clarification).
4. Log dedup delta to `phases.jsonl` + `trace.md`.

**Design question surfaced.** Stage 1's `artifact-patch.py` intentionally didn't include `--delete-finding` (schema §6 doesn't address deletion). Phase 2 needs it. Options:

- **(A, preferred)** Add `--delete-finding <id>` to `artifact-patch.py` as a Stage 2 clarification. Low-risk, well-scoped, trivial to implement. Can land in Commit 7 alongside this fragment. BUILD.md cross-stage note codifies it.
- **(B)** Merge at the in-memory stage only: orchestrator holds the candidate list in-prompt, does dedup merging in its own head before writing anything to the artifact, then `--add-finding` only the survivors. This shifts more state into the orchestrator's working context and away from the artifact, which contradicts §13.7 "artifact is single source of truth." Reject.
- **(C)** Mark duplicates as `disposition: merged_duplicate` rather than deleting. Adds a new disposition value, pollutes the report. Reject.

**Picking (A).** This is clarification-level per BUILD.md protocol. Commit 7 includes the `artifact-patch.py --delete-finding <id>` addition + smoke-harness augmentation (one dedup-then-delete assertion). `schema-v1.json` doesn't change.

**Verification:** smoke gains an assertion; fragment is eyeballed.

### Commit 8 — `04-scoring-gate.md` (Phase 3)

**Rationale:** per-candidate Sonnet dispatch; small and contained.

Instructs the orchestrator to:

1. For each finding with `current_state == open` and no `score_phase3` yet: dispatch a Sonnet sub-agent per §19.4 with the §20 rubric inlined (or referenced — the rubric is copy-pasted into the fragment since it's short).
2. Each sub-agent returns `{score, score_rationale}`. Orchestrator `artifact-patch.py --finding-id <id> --set score_phase3=<score>`. The `_common.py` auto-append logic adds the score to `score_history`.
3. Apply the §13.1 Phase-3 gate inline:
   - `score_phase3 < 45 AND single source family` → `artifact-patch.py --finding-id <id> --set disposition=below_gate --set is_actionable=false --set reason='below validation gate (score <n>)'`. Keeps `current_state=open`. (§21.2's coupling allows this: `below_gate` → `is_actionable=false`.)
   - `score_phase3 < 45 AND ≥ 2 source families` → advance (no disposition change yet — Phase 4 will set).
   - `score_phase3 >= 45` → advance.
4. Pre-existing override (§13.1 highest priority) — applied inline BEFORE the score gate: `origin == "pre_existing" AND origin_confidence == "high"` → `--set disposition=pre_existing_report --set is_actionable=false`, don't gate further.
5. Log Phase 3 to `phases.jsonl` + `trace.md`.

**Fragment authoring notes:**

- Fan-out can be parallel: orchestrator fires N Sonnet agents (one per candidate) in one message. N is typically 20-50; Claude Code's concurrent-agent limit isn't formally documented but the existing `adams-code-review.md` uses 6-parallel and 20-parallel fan-outs. Match that idiom.
- Rubric inlining: copy §20 into the fragment verbatim. The scoring agent needs to see it.

**Verification:** eyeballed; real-repo smoke in Commit 12.

### Commit 9 — `05-validation.md` (Phase 4a + 4b)

**Rationale:** validation is two-laned (deep Opus / light Sonnet) with a chain-wave retry (Wave 1 + optional Wave 2). Most involved fragment after 01-detection.

Instructs the orchestrator to:

1. Partition eligible candidates (those not in `below_gate`) by `validation_lane`:
   - `impact_type ∈ {correctness, security}` + not trivial_mode → deep lane (Phase 4a).
   - Everything else + all findings when trivial_mode → light lane (Phase 4b).
2. **Wave 1 dispatch (parallel):**
   - Deep-lane: one Opus sub-agent per candidate per §19.5. Each receives claim + evidence + CLAUDE.md paths + prior `fix_attempts` (empty at review time).
   - Light-lane: one Sonnet sub-agent per candidate per §19.6. Trivial-mode constraint in §19.6 passed through explicitly.
3. Collect Wave 1 results. For each finding:
   - `artifact-patch.py --finding-id <id> --set score_phase4=<N>` (auto-appends to score_history).
   - Apply §13.1 Phase 4 decision table: map score + actionability to disposition + is_actionable per coupling rules.
   - If deep-lane: also `--set` the `validation_result` JSON. (The existing `SETTABLE_FINDING_FIELDS` whitelist in `artifact-patch.py` rejects `validation_result` — Stage 2 needs to add it. Tiny clarification; covered below.)
4. **Wave 2 dispatch (optional):** union all `related_candidates_to_investigate` across Wave 1 outputs, dedup, drop any already-investigated. For remaining: dispatch a second wave of Opus validators. Hard cap at 2 waves (§4).
5. Pre-existing override re-assertion: after Phase 4 completes, re-check every finding — if `origin == pre_existing AND origin_confidence == high`, force `disposition: pre_existing_report` regardless of what Phase 4 decided (§13.1 rule).
6. Log Phase 4 to `phases.jsonl` + `trace.md`.

**Design questions surfaced.**

- **`validation_result` is currently not `--set`-table.** Stage 1's `SETTABLE_FINDING_FIELDS` intentionally excluded nested JSON fields in favor of scalar-only set. Phase 4a needs to write this nested object. Options:
  - **(A, preferred)** Add a `--set-json <field=<path-to-json-file>>` flag or `--set-validation-result <json>` direct-add to `artifact-patch.py`. Scalar-only design preserved; one named escape hatch for the one field that genuinely needs it. Stage 3 will similarly want `--set-fix-proposal` or similar — we decide the pattern now.
  - **(B)** Expand the allowlist to include `validation_result` as a JSON pass-through. Works, but the `--set key=value` CLI becomes awkward for JSON values (quoting hell). Reject.
  - **(C)** Introduce a general `--set-json <field>=<json-string>` verb. More flexible; wider blast radius (potentially settable across many fields). Could be useful but premature.
- **Picking (A) with the generalizable form.** Implement `--set-json <field>=<json-literal>` where `<field>` is a whitelist `SETTABLE_JSON_FIELDS = {validation_result, fix_proposal, verification_context}`. Avoids inventing three flags. Stage 2 needs `validation_result`; Stage 3 will need `fix_proposal` / `verification_context` (already on the schema via Phase 4a's validation_result but Stage 3 may mutate them directly — punt that decision if not needed). Cross-stage note codifies.

- **Wave dispatch idiom.** Chain-wave retry is orchestrator-level — not a sub-agent-spawns-sub-agent pattern (sub-agents cannot spawn sub-agents per §4). The fragment describes this explicitly: "collect Wave 1 results before dispatching Wave 2 — do not ask a Wave 1 agent to spawn more."

**Verification:** eyeballed; real-repo smoke in Commit 12.

### Commit 10 — `06-cross-cutting.md` (Phase 5)

**Rationale:** single Opus sub-agent; simple.

Instructs the orchestrator to:

1. If no findings have `is_actionable: true` AND deep-lane: skip this phase with one `trace.md` line.
2. Else: serialize the deep-lane + actionable findings (with `validation_result.fix_proposal` included) to JSON; dispatch one Opus sub-agent per §19.7. No tool access needed; input is the serialized JSON in the prompt.
3. Receive `{cross_cutting_groups: [...]}` + optional per-finding annotations.
4. Apply via `artifact-patch.py` — this requires setting the top-level `cross_cutting_groups` array, which is **not** currently `--set`-table (top-level allowlist includes `comment_id`, `trivial_mode`, `pr_state`, `pr_number` only).

**Design question surfaced.** Add `cross_cutting_groups` to `SETTABLE_ARTIFACT_FIELDS` — OR generalize the `--set-json` pattern from Commit 9 to include top-level JSON fields. I'll pick the latter: `--set-json --top-level cross_cutting_groups=<json>`, reusing the JSON-pass-through infrastructure. Cross-stage note codifies.

Per-finding annotations (if any) go via `artifact-patch.py --finding-id <id> --set <field>=<value>` — they're presumably scalar tags on the finding, schema-dependent. If they need JSON shape, reuse `--set-json`.

5. Log Phase 5 to `phases.jsonl` + `trace.md`.

**Verification:** eyeballed; real-repo smoke in Commit 12.

### Commit 11 — `07-finalize.md` (Phase 6)

**Rationale:** closes the review half. Phase 6 is: validate + final phases.jsonl + render + publish + mirror-to-chat.

Instructs the orchestrator to:

1. Validate the in-memory artifact against the v1 schema via `artifact-validate.sh --path <artifact_path>`. Fail loudly on drift (§4 Phase 6 step 1).
2. Compute `subagent_tokens` totals by consuming `tokens.jsonl` via `jq`: total, invocations, by_phase, by_model, by_lens, by_finding_phase4. Write via `artifact-patch.py --set-json --top-level subagent_tokens=<json>` (another field that needs to be added to the top-level allowlist — part of the Commit 9 generalization).
3. Compute `metrics` block per §14.1: `pr_size_buckets` (files_changed, lines_changed from Phase 0 diff); `time_elapsed_seconds` (now - review_started_at); `required_followup` defaults to `null` at review time (set by fix); `phase_9_verified_pct` is `null` (set by fix). Write via `--set-json`.
4. Append Phase 6 record to `phases.jsonl` via `log-phase.sh --record '<json>'`.
5. Render: `artifact-render.py --input <artifact_path> --output <review_dir>/artifact.md`.
6. Update `latest.txt`: write `<review_id>` atomically (temp + rename).
7. Publish — PR mode only: `artifact-publish.sh --mode pr --pr <num> --repo-slug <slug> --branch <name> [--comment-id <id-if-artifact-has-one>]`. Captures stdout `{"comment_id": N}` if emitted and persists via `artifact-patch.py --set comment_id=<N>`.
8. Local mode: `artifact-publish.sh --mode pr` is not called. Log "local mode — no publish" to trace.md. (Alternately call `--mode local` unconditionally per §8.4 so the orchestrator doesn't branch; either works. I'll pick unconditional-call-with-local-mode to match §21.6 "exists so the orchestrator can call `artifact-publish.sh` unconditionally in every mode.")
9. Mirror: output the rendered `artifact.md` content directly to the Claude Code chat (all modes). Header line per §7 wording.
10. Final `trace.md` append: Phase 6 summary.

**Verification:** After this commit, end-to-end *should* work on a real repo. Commit 12 actually runs it.

### Commit 12 — Top-level `adams-review.md`

**Rationale:** the glue. After all 8 fragments exist, the command file assembles them.

- Frontmatter:
  - `allowed-tools` block with the full §8.7 list (absolute paths to all 11 helpers including `external-scrape.sh`, plus `git:*`, `gh:*`, `AskUserQuestion`, `Agent`, `Read`).
  - `argument-hint: "[--ensemble] [--full]"`
  - `description: Deep code review producing artifact.json, artifact.md, and (PR mode) a PR comment.`
  - `disable-model-invocation: false`
- Body:
  - **Short role framing** — one paragraph saying the command is an orchestrator that runs DESIGN §4 Phases 0-6 in order, with the same "build a TaskList mirroring phases" nudge as `adams-code-review.md`.
  - **How to handle helper errors** — the §8.6 convention (`Implementation note` at the end of §8.6): "When a helper script exits non-zero, the stderr will list valid values and suggest corrections — parse it, retry with corrected inputs, escalate to the user only on second failure."
  - **Sub-agent dispatch pattern** — 3-bullet reference: use `Agent` tool with `model` parameter to pick Haiku/Sonnet/Opus; parallel fan-outs go in a single orchestrator message; after each agent returns, parse `<usage>total_tokens: N</usage>` and call `log-tokens.sh`.
  - **Effort inheritance note** — one paragraph per §10.1: "Sub-agents inherit this session's effort setting; there is no per-agent override. Expect costs to scale linearly with session effort."
  - **State that carries forward** — reference §25.1 with a terse list (review_id, artifact_path, repo_root, mode, trivial_mode, etc.). Borrow the §25.3 nudge: "State lives in your working context, not Bash exports."
  - **Argument handling** — inline Bash at the top to parse `$ARGUMENTS` for `--ensemble` and `--full`. Sets `ensemble_mode=true/false` and `force_full=true/false`. These get referenced by downstream fragments.
  - **Phase includes** in order:
    ```
    !`cat ~/.claude/commands/_shared/00-preflight.md`

    !`cat ~/.claude/commands/_shared/01-detection.md`

    !`cat ~/.claude/commands/_shared/02-ensemble-adapter.md`

    !`cat ~/.claude/commands/_shared/03-dedup.md`

    !`cat ~/.claude/commands/_shared/04-scoring-gate.md`

    !`cat ~/.claude/commands/_shared/05-validation.md`

    !`cat ~/.claude/commands/_shared/06-cross-cutting.md`

    !`cat ~/.claude/commands/_shared/07-finalize.md`
    ```
  - **Final note** about what the orchestrator should NOT do — no git commits, no pushes except the Phase 0 unpushed-commits push, no deletes/renames anywhere. Stage 3 handles fix loop.

**Once this lands**, the `/adams-review` command is callable in any Claude Code session with the `_shared` symlink live. All §8.7 grants resolve via the PASSED probe.

### Commit 13 — End-to-end smoke on a real repo + BUILD.md close-out

**Rationale:** the Stage 2 done-when requires a real run. This commit captures the run's outputs as evidence and closes out BUILD.md.

**Target repo:** `adams-review` itself (this repo). Create a throwaway feature branch with a seeded bug (e.g., a one-line null-deref in a small trivial helper file, or a CLAUDE.md violation). Run `/adams-review` on that branch. Options for target:

- **(A, preferred)** Use the adams-review repo itself. Create `feature/stage2-smoke` on main, add a small Python or TypeScript file with a seeded bug (off-by-one or null-deref), push, open a draft PR, run `/adams-review` in PR mode. After the run, close the PR and delete the branch. Runtime artifacts under `~/.claude/reviews/<slug>/feature-stage2-smoke/` stay on disk as evidence.
- **(B)** Run against a different existing PR on a user repo (e.g., one of Adam's other projects). Useful but requires permission.
- **(C)** Run `--local` mode only (no PR). Simpler; skips the Phase 1.5 + publish paths. Acceptable for Stage 2 if we pair it with a `--ensemble` or PR-mode dry run separately.

**Picking (A) + a local-mode smoke run.** Cover:
1. Local mode: `/adams-review --local` on a dirty-or-clean throwaway branch (adams-review repo). Confirm artifact written, `latest.txt` set, `artifact.md` rendered, no PR comment posted, `tokens.jsonl` populated.
2. PR mode (draft PR): `/adams-review` on the draft PR. Confirm comment posted with marker; re-run and confirm comment edited (not duplicated).
3. Ensemble mode: `/adams-review --ensemble` on the same PR. Confirm external-scrape runs (even if no bot comments — empty result is the expected happy path).
4. Trivial mode: `/adams-review --local` on a docs-only branch with a single .md change. Confirm `trivial_mode: true` in artifact and reduced lens set in `phases.jsonl`.

**What to eyeball:**
- `artifact.json` validates cleanly via `artifact-validate.sh` (schema hygiene).
- `artifact.md` first line is the marker; subsequent sections match §7 shape.
- `phases.jsonl` has one line per phase (0, 1, 1_5 if ensemble, 2, 3, 4, 5, 6).
- `tokens.jsonl` has one line per sub-agent call with non-null `tokens` where parseable.
- `trace.md` is human-readable with agentIds per phase.
- `latest.txt` points at the new `review_id`.

**BUILD.md close-out:**
- Current state → "Stage 2 COMPLETE" + date + next action (plan Stage 3).
- Stage index row 2 status → `done`.
- Stage 2 section: Files landed (12-ish bullets — every new md + the 2 helper changes), Verification evidence (copy the real-repo smoke outputs summary), Open issues (anything surfaced during the real run — prompt tweaks needed, etc.), Cross-stage notes for every clarification (Commits 2, 7, 9, 10 — all the `--set-json` / `--delete-finding` / publish-signature-fix / latest.txt-fallback additions).

**Commit message:** `Close Stage 2: /adams-review end-to-end with real-repo smoke evidence`.

---

## 5. Fragment authoring conventions

Every `_shared/*.md` fragment should match these:

- **Heading:** `## Phase N — <name>` at the top so it slots cleanly into the assembled prompt.
- **Audience:** instructions to the orchestrator (a model), second-person imperative ("Dispatch...", "Read...", "Apply..."). NOT first-person narration.
- **Variable references:** by name, matching §25.1. E.g., "Using `baseBranch` from Phase 0..." not "$baseBranch" (no Bash shell vars).
- **Tool references:** absolute paths for all helper scripts. E.g., `` !`~/.claude/commands/_shared/tools/artifact-patch.py ...` ``.
- **Sub-agent dispatch prose:** "Launch a Sonnet sub-agent with the following task: ..." — matches the `adams-code-review.md` idiom (line 46-50).
- **Inlined reference content** (§22 lens refs): `` !`cat ~/.claude/commands/_shared/lens-ux-reference.md` `` inside the lens's dispatch prose so the sub-agent sees the reference content in its prompt.
- **Logging:** every fragment ends with explicit `log-phase.sh --record` + `log-phase.sh --summary` calls. No "and also log it" prose — the actual commands go in the fragment so the orchestrator can execute them literally.
- **Skip conditions:** each phase fragment starts with a short guard ("If trivial_mode and this is L2, skip and log...") so the decision is visible where it's made, not hidden in 00-preflight.

---

## 6. Sub-agent dispatch patterns (normative for this stage)

Consistent dispatch idiom across all fragments:

1. **Orchestrator fans out via multiple Agent tool-use blocks in a single message.** That's how parallelism happens in Claude Code. The fragment says so explicitly: "send all N Agent tool-use calls in one message."
2. **Agent calls specify `model` explicitly** to pick Haiku / Sonnet / Opus per the §10 table. Use the `model` parameter of the Agent tool where available; in prose ("launch an Opus sub-agent") where not.
3. **Agent calls specify `subagent_type: general-purpose`** unless a specific plugin agent is needed (the only exceptions in Stage 2 are the codex and coderabbit adapters in the ensemble fragment — those use their specialized subagent_types).
4. **After each Agent call returns, orchestrator:**
   - Parses the usage block (`<usage>total_tokens: N</usage>`). Calls `log-tokens.sh` immediately — before branching on content. This matches §24.4 ("Every sub-agent's token usage is logged before any branching on its result").
   - Parses structured output per the fragment's declared output shape (§19.X). On parse failure, §24.1's "light repair" + "retry with prompt addendum" path applies; after one retry, drop and log.
   - Applies any artifact mutations via `artifact-patch.py`.
5. **Prompt size management.** Large inputs (the full diff, the full candidate list for dedup) go inline. Claude Code's prompt size isn't a concern at this scale, but fragments should say "pass `<diff>` as part of the prompt" explicitly so the orchestrator doesn't try to stuff it into a tool parameter.

---

## 7. Trivial-mode gate — how it threads through

Each affected phase fragment has an explicit trivial-mode branch:

- **Phase 0:** sets `trivial_mode` via the §13.9 Bash check. `--full` forces it false.
- **Phase 1:** L2, L5, L6 skipped; L1, L3, L4 run. Fragment starts with `if trivial_mode: only launch L1/L3/L4`.
- **Phase 1.5:** unaffected (§13.9 note: "External reviewers decide independently whether to comment").
- **Phase 2:** runs normally.
- **Phase 3:** runs normally.
- **Phase 4:** all candidates go through 4b; 4a skipped entirely. Fragment explicitly says "if trivial_mode, skip 4a and route everything to 4b, which will refuse to emit `auto_fixable` per §19.6."
- **Phase 5:** skipped (no deep-lane findings under trivial_mode).
- **Phase 6:** runs normally.

`phases.jsonl` records which phases were skipped + why, so post-mortem sees the full pipeline state.

---

## 8. `--set-json` / `--delete-finding` additions to `artifact-patch.py`

Three small Stage-1-helper additions surface during Stage 2:

| Addition | Needed by | Commit lands in | Clarification-level? |
|---|---|---|---|
| `--delete-finding <id>` | Phase 2 dedup | Commit 7 | yes — codifies dedup delete path |
| `--set-json <field>=<json>` with finding-level whitelist `{validation_result, fix_proposal, verification_context}` | Phase 4a (Commit 9) | Commit 9 | yes — generalizes scalar-set |
| Same `--set-json` with top-level flag extending to `{cross_cutting_groups, subagent_tokens, metrics}` | Phase 5 (Commit 10) + Phase 6 (Commit 11) | Commit 9 (ship the generalization at first use) | yes — same mechanism |

All three are clarification-level per BUILD.md protocol. They get BUILD.md cross-stage notes at close-out. They do NOT require DESIGN.md updates — §6 schema is unchanged; §21.2's "repeatable `--set`" spirit is preserved; the new verb mirrors it for JSON shapes.

**Stage 1 smoke harness impact:** small. The existing 19 assertions don't touch these verbs. Commit 7 adds one assertion (dedup delete). Commit 9 adds one assertion (set validation_result via --set-json). Low risk of regressions.

---

## 9. Real-repo smoke approach

End-to-end verification happens in Commit 13. Target:

1. **Subject repo:** `adams-review` itself, on a throwaway branch.
2. **Seeded bugs:** 1-2 intentional findings — e.g., a Python file with a null-deref pattern and a TypeScript file missing an await, or a CLAUDE.md violation if we add a test CLAUDE.md. Just enough for at least one confirmed_mechanical + one disproven to exercise the report sections.
3. **Runs:**
   - `/adams-review --local` (no PR)
   - `/adams-review` on a draft PR against main
   - `/adams-review` again on the same PR (edit-not-create test for §13.4)
   - `/adams-review --ensemble` (even if no bots — empty-scrape path)
   - `/adams-review --local --full` on a trivial doc-only branch (trivial override test)
4. **Captures:** The `~/.claude/reviews/<slug>/<branch>/<review_id>/` directories stay on disk. Commit 13's message references the review_ids.
5. **Cleanup:** close the draft PR, delete the throwaway branch, leave the `~/.claude/reviews/...` state alone (it's evidence).

**What constitutes passing:** every run produces a schema-valid artifact; every rendered artifact.md has the §7 marker + sections; no orchestrator crashes; Phase 1.5 + publish behave mode-appropriately; effort flows as expected.

**What doesn't constitute passing:** a perfect review that catches every seeded bug. Prompt quality is iterative — Stage 2 ships "correct plumbing"; prompt refinement against real PRs happens in the BUILD.md §14.2 evaluation protocol after Stage 3.

---

## 10. Decisions (resolved with user 2026-04-17)

1. **Smoke target — ray-finance `feat/import-apple`.** Real branch, real code, user's intended first-real-run. No seeds.
2. **No seeded bugs.** Real diff on real branch exercises the pipeline on actual signal.
3. **`--set-json <field>=<json-literal>` with `=@<file-path>` shorthand** (mirrors `gh api --field body=@file`). Best of both: one-liner-friendly for small blobs, file-read escape hatch for large JSON.
4. **Ensemble mode ships with Stage 2 — via CLI pattern**, not via Agent-tool sub-agents. Revises DESIGN §4 Phase 1's `subagent: codex:codex-rescue / coderabbit:code-reviewer` text:
   - **CodeRabbit:** `coderabbit review --agent -t all --base <base>` in background Bash (captures stdout; does NOT post).
   - **Codex:** `node "$CODEX_COMPANION" task --prompt-file <file>` in background Bash (resolves `$CODEX_COMPANION` via `find ~/.claude/plugins -type f -name codex-companion.mjs -path '*codex*'`).
   - **Readiness checks** up-front per the adams-super-code-review pattern: `coderabbit --version && coderabbit auth status`; `node "$CODEX_COMPANION" ready`. `AskUserQuestion` on any unavailable reviewer with options (proceed with available / stop).
   - **Token tracking:** CLI invocations don't emit `<usage>` blocks. Per §11's "wrapper orchestration tokens tracked" language — clarify to: external adapters invoked via CLI have **zero entries** in `tokens.jsonl` (tokens are billed separately by the external provider). Only the Phase 1.5 normalizer (Sonnet sub-agent per §19.2a) gets a tokens.jsonl entry. Clarification codified in BUILD.md cross-stage notes + DESIGN §11 footnote.
   - **Parallelism idiom:** fire `coderabbit` and `codex` in background Bash simultaneously (capture both shell ids), run internal L1-L6 lenses in parallel with them, then poll both at Phase 1.5's entry before dispatching the normalizer. Matches adams-super-code-review step 6 ("Do not wait serially — poll both in parallel").

---

## 11. Open questions (clarification-level — DESIGN untouched)

Surfaced during planning; will be decided inline during execution and codified in BUILD.md cross-stage notes:

- **Token-parse format.** §11 says "`<usage>total_tokens: N</usage>`". In practice, the Claude Code Agent tool result includes a more structured `usage` dict. Fragment prose will describe both patterns: prefer the structured field if the tool result exposes it; fall back to parsing the tag if needed. Real-run data in Commit 13 will settle which is actually present.
- **`review_id` generation idiom.** §25.1 says "generated ULID." In Bash, ULIDs aren't stdlib. Options: use `uv run --with ulid-py python3 -c 'import ulid; print(ulid.new())'` inline, or use a timestamp+random fallback. Low-risk; will pick during Commit 4 implementation.
- **Wave 2 trigger.** §4 says Wave 2 runs "if Wave 1 outputs contain `related_candidates_to_investigate`." The fragment will include a de-dup step (skip anything already investigated in Wave 1) and the 2-wave hard cap.
- **Exit-code propagation on sub-agent failures.** §24.1 says drop + log + continue. The fragment for each phase will describe the single-retry pattern and what "drop the candidate" means at the artifact layer (annotate with `reason: "sub-agent returned unparseable output after retry"` rather than silent deletion).

---

## 12. Decisions already locked (carry over from Stage 1)

1. **`uv` PEP-723** for any Python needs.
2. **Bash 3.2 portable** throughout.
3. **Exit codes 1/2/3/4/5/64** standardized in `_common.py`; DESIGN §21.2 footnote codified.
4. **`--set` scalar allowlist** preserved; `--set-json` is the new nested-field verb, with its own whitelist.
5. **Absolute-path grants in `allowed-tools`** (§8.7 probe PASSED).
6. **Symlink dev layout** live at `~/.claude/commands/_shared`.
7. **Commit cadence:** one per natural breakpoint; never batched; `Co-Authored-By: Claude Opus 4.7 (1M context)` trailer.

---

## 13. Exit criteria — Stage 2 Done

- [ ] All 8 phase fragments in place at `~/.claude/commands/_shared/NN-*.md`.
- [ ] Two lens reference files at `~/.claude/commands/_shared/lens-*.md` with §22.1 / §22.2 content verbatim.
- [ ] `external-scrape.sh` implements §21.8 and exits cleanly on rate-limit.
- [ ] `artifact-publish.sh` supports optional `--md-path` with `latest.txt` fallback (§13.4); existing smoke stays green.
- [ ] `artifact-patch.py` supports `--delete-finding` (Phase 2) and `--set-json` (Phases 4-6) with scoped whitelists.
- [ ] `adams-review.md` is in place at `~/.claude/commands/adams-review.md` with full `allowed-tools` block + §25.1 working-set preamble + fragment includes.
- [ ] `test/smoke.sh` still passes (20-21 assertions after Stage 2 additions).
- [ ] A real `/adams-review` run on the throwaway branch produces a schema-valid artifact + rendered .md matching §7.
- [ ] PR-mode run posts a comment; re-run edits (not duplicates).
- [ ] Ensemble-mode run exercises `external-scrape.sh` happy path (even if zero bots).
- [ ] Trivial-mode run produces the reduced pipeline per §13.9; reflected in `phases.jsonl`.
- [ ] BUILD.md Stage 2 section filled in (Files landed / Verification evidence / Open issues / Cross-stage notes).
- [ ] All commits on `main`.

---

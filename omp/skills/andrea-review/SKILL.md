---
name: andrea-review
description: Run the Andrea Review Playbook as a 12-sector agent swarm over a PR diff. Each sector agent applies its paradigms (idempotency, concurrency, shutdown, rate-limiting, billing, storage, schema, wire, multi-repo, security, testing, code-smell), grounded in <Provider> infra anchors and the 6 codebase-intelligence backends, then the orchestrator dedups, validates, and adversarially triages. Use when the user types /andrea-review, or wants Andrea-depth multi-lens PR review rather than a single-pass read. Fixes are suggested only — never auto-committed.
argument-hint: "[<PR-number> | <diff-ref>] [--prd <path|issue|url>] [--no-fix-suggest]"
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Task, todowrite
compatibility: omp
metadata:
  author: "mateo.delriolanse"
  version: "1.0.0"
  domain: quality
  triggers: andrea-review, /andrea-review, andrea review, pr review, code review
  role: specialist
  scope: review
---

# andrea-review — 12-sector agent-swarm PR review

Runs the **Andrea Review Playbook v2** as a parallel 12-sector agent swarm.
Each sector is an independent review lens (idempotency, concurrency,
shutdown, rate-limiting, billing, storage, schema, wire, multi-repo,
security, testing, code-smell); the orchestrator dispatches them in one
`tasks[]` batch, then dedups, validates, and adversarially triages.

**The playbook is the source of truth.** Read it before dispatch:
`playbook/andrea-review-playbook.md` (bundled in this skill) — 12 sectors,
77 paradigms, 6 cross-cutting rules, 8 stale-anchor corrections, 6
codebase-intelligence backend bindings, never-auto-commit policy. The
editable source of record lives at
`~/<provider>/docs/andrea-review-playbook.md`; the bundled copy is a
snapshot (see README.md for the refresh procedure).

**This skill is the dispatch contract.** It does not restate the playbook;
it runs it.

## Invoke

```
/andrea-review                          # review the current branch's diff vs main
/andrea-review 1234                     # review PR #1234 (gh pr diff 1234)
/andrea-review feat/batch-api           # review a branch vs its base
/andrea-review --prd docs/spec.md       # + check each sector against the PRD
/andrea-review 1234 --prd 412           # review PR #1234 against issue #412 as PRD
/andrea-review --prd 412 --no-fix-suggest  # PRD-conformance, no suggested-fix field
```

## Hard constraints (non-negotiable)

1. **Fixes are suggested, never auto-committed.** Sector agents do NOT
   `edit`/`write` source files, do NOT run `git add`/`commit`/`push`, do
   NOT dispatch fix sub-agents. Every finding carries a `suggested_fix`
   (the patch *shape*, not the patch) and `anchor_verified: true|false`.
   The PR author owns every fix. This is playbook CR-6.
2. **Re-ground before citing any playbook anchor.** The playbook has 8
   known-stale anchors (see its Drift table). Before citing any `file:line`
   from v1, re-ground via `semble_search` → Serena `find_symbol` (with
   `relative_path`) → `read`. This is playbook CR-1.
3. **Worktree-aware anchoring.** The batch module lives in
   `~/<provider>/worktrees/batch-api/feat-batch-api-gateway/`, not the
   main `~/<provider>/gateway/` checkout. CodeGraph on `~/<provider>/gateway`
   is main-branch (no batch module); codebase-memory has NO gateway project.
   For gateway symbols, use `read` or `semble_search repo=<worktree>`. This
   is playbook CR-3.
4. **Read-only workers.** Sector agents are read-only extraction/detection
   workers. The only file a sector agent writes is its finding-list output
   (returned to the orchestrator, not written to disk).

## Pipeline

### Step 1: Resolve the diff

Resolve the review target to a concrete diff. **Always operate inside the
repo/worktree whose working tree holds the code to review** — `cd` there
first (or confirm `git rev-parse --show-toplevel` points at it). The diff
must reflect *that* working tree, not some other branch's committed state.

- No arg → in the current repo, compute `mb=$(git merge-base HEAD main)`
  then emit **`git diff $mb`** (no `...HEAD`). The bare two-operand form
  includes **both committed and uncommitted working-tree changes** vs the
  merge-base. Do NOT use `git diff $mb...HEAD` — the three-dot form stops at
  HEAD and silently drops staged + unstaged WIP (review-only checkpoints
  soft-reset to keep the tree dirty, uncommitted feature branches, stashes
  applied to the working tree). A review that ignores the working tree
  reviews the wrong code.
- PR number → `gh pr diff <N>` (use `gh`, never `git fetch`).
- Branch arg → `cd` into the branch's worktree (or checkout), then use the
  same two-operand form as the no-arg case: `git diff $(git merge-base HEAD
  main)` (no `...`, no `HEAD` endpoint) so staged + unstaged WIP is
  included. Never pass a worktree path as a git ref — `cd` into it so the
  working tree is the diff endpoint.

Record `comparison_ref` (the merge-base SHA), `reviewed_files_all` (from
`git diff --name-only $mb`), and the repo root the diff was resolved in.

**If the diff is empty, STOP. Do not fall back to reviewing `main`'s
surface, another branch, or any "existing files" shape.** Say plainly:
"No diff in <repo> at <branch> vs <merge-base>. Working tree is clean and
HEAD == merge-base. Nothing to review." A report that reviews code that is
NOT the code under review is worse than no report — it manufactures
findings against the wrong baseline (see the 164037 incident: a soft-reset
WIP produced an empty committed diff, the orchestrator fell back to
`main`, and emitted 9 BLOCKERs against pre-implementation code). The
stop-and-say-so rule is load-bearing; falling back is a bug.

**Empty-diff diagnostics before stopping.** If `git diff $mb` is empty,
run in order and report which fires:
1. `git status --short` — are there staged/unstaged changes the diff
   should have caught? (If yes, the diff command is wrong; you are not in
   the repo you think you are.)
2. `git log --oneline $mb..HEAD` — any committed work the three-dot form
   would have missed? (Indicates a stray reset; the work may live in
   `git reflog`.)
3. `git reflog -5` — show recent `reset:`/`commit:` entries so the user can
   recover a dropped checkpoint (`git reset --hard <sha>`).
Only after reporting these may you stop.

### Step 1.5: Resolve the PRD, if `--prd` given

A PRD is the document the build is supposed to satisfy. Resolve `--prd` to
a file at `<run-dir>/PRD.md`:
- **Path** (`docs/spec.md`) → `read` it.
- **Issue number** (`412`) → `gh issue view 412 --json title,body,comments`.
- **URL** → `gh api` the issue or `read` the URL.

If it resolves to nothing, **stop and say so.** Do not review against a PRD
you could not read; silently skipping it is worse than not asking.

With a PRD resolved, the review gains one question per sector: **does the
code satisfy the PRD requirement in this sector's lens?** (Sector 05 checks
the PRD's billing requirements; Sector 08 checks the wire-shape requirements;
etc.) A finding that contradicts the PRD is in-scope even when the
contradiction is in untouched code, because the PRD defines what "correct"
means for this change. This is `deep-review` track C's model, distributed
across the 12 sectors instead of a separate track — no new agent, just a
new input to the existing sector prompts.

### Step 2: Read the playbook

`read playbook/andrea-review-playbook.md` (bundled in this skill) — the
orchestrator MUST read the full playbook before dispatch. It contains the
12 sector definitions, the 6 cross-cutting rules (CR-1..CR-6), the 8
stale-anchor corrections (Drift table), and the per-paradigm backend
bindings. The sector agents do NOT each re-read the whole playbook; the
orchestrator passes each agent its sector section, sourced from the
bundled copy (or from `sectors/sector-NN-*.md` for the full extract).

### Step 3: Fan out 12 sector agents in ONE `tasks[]` batch

Build a `tasks[]` array of 12 items, one per sector. Each task:
- `agent: "task"` (read-only detection + finding emission)
- `name: "SectorNN<Slug>"` (e.g. `Sector01Idempotency`)
- `task:` a self-contained prompt containing:
  - The PR diff + comparison_ref + reviewed_files_all
  - [if --prd] `<run-dir>/PRD.md` content + the instruction: "Findings that
    contradict this PRD are in-scope even in untouched code; flag them with
    `prd_contradiction: true` and boost severity one band (NIT→MINOR,
    MINOR→MAJOR, MAJOR→BLOCKER) for PRD violations. Also emit one
    `prd_conformance` entry per PRD requirement you can identify in your
    sector's lens (met/partial/missing/contradicted + evidence)."
  - The sector's paradigm list (copied from the playbook section — paradigms
    P-NN-K with anchors, backends, guardrails, fix-suggestion policy)
  - The 6 cross-cutting rules (CR-1..CR-6, verbatim from the playbook)
  - The output contract (below)
  - The hard constraints (read-only, never auto-commit, re-ground, worktree-aware)

**Parallelism is the point.** A single-pass review misses the lenses; the
12-agent fan-out reproduces Andrea's depth. Token budget is not the
binding constraint — thoroughness is. Dispatch all 12 in one batch; do not
serialize.

### Step 4: Join — wait for all 12

`hub wait` (or wait on the task batch). Do NOT report until every launched
sector has returned. If a sector fails or returns nothing, say which and
report the surviving sectors' findings labeled single-sector.

### Step 5: Dedup across sectors

Apply the playbook's 15 merge groups (M-1..M-15). Same file + overlapping
line range + same underlying claim → one finding. Do NOT merge on wording
alone; two different bugs on one line stay two findings. Dispositions:
- **MERGE** (3 groups: M-2 claim-fairness→S04, M-6 BOM→S08, M-7
  det_failures index→S07) — fold the duplicate into the owning sector.
- **KEEP-ASPECTS** (4 groups) — extract non-overlapping parts, merge the
  overlapping core.
- **KEEP-SEPARATE** (8 groups) — genuinely distinct lenses on shared
  evidence; both stay, cross-referenced.

The merge groups are defined in
`sectors/_synthesis-dedup.md` (bundled) — read it for the exact member
lists.

### Step 6: Validate anchors

Re-ground every finding's cited anchor. Use the playbook's Drift table
(8 stale anchors) and the validation synthesis
(`sectors/_synthesis-validation.md`, bundled — 27 paradigms re-verified)
as starting points, NOT as truth — re-verify against the live code:
- `semble_search "<symbol> <feature>"` to relocate moved symbols.
- Serena `find_symbol` with `relative_path` to confirm a symbol exists
  (unscoped `find_symbol` on the large `app/` tree times out at 30s).
- `read` the resolved `file:line` to byte-confirm.
- For gateway batch symbols: `read` the worktree path directly; do NOT
  trust `codegraph explore -p ~/<provider>/gateway` (main-branch index,
  no batch module) or codebase-memory (no gateway project).

Mark each finding `anchor_verified: true|false|stale`. A finding with a
stale anchor is a false-positive risk — either re-ground or drop.

### Step 7: Adversarial triage

Apply the playbook's 6 cross-cutting guardrails (CR-1..CR-6) and the
adversarial synthesis's per-paradigm scores
(`sectors/_synthesis-adversarial.md`, bundled — 77 paradigms scored on 4
axes: false-positive risk, over-application risk, grounding fragility,
sector confusion). Bucket every finding:

- **FIX** — a real defect worth addressing now. One line on what breaks.
- **SKIP-NOW** — real but not worth fixing now (YAGNI, cosmetic,
  speculative edge). One line naming when it *would* be worth revisiting.
- **FALSE-POSITIVE** — not actually a bug; the reviewer misread the code.
  One line on why it's wrong.

**Hard rule from the adversarial pass**: a finding on a security,
data-loss, input-validation, or money path is **never** SKIP-NOW or
FALSE-POSITIVE unless you can show concretely it doesn't apply. When
unsure, FIX.

**CR-4 reminder**: a deferral with a recorded rationale (e.g. MINOR-4
clock injection — DECIDED-NOT-ACTIONED) is a decision, not a finding. Do
not re-raise unless the rationale no longer holds.

### Step 8: Report

Lead with the **FIX** bucket, then SKIP-NOW, then FALSE-POSITIVES. Within
each bucket keep the sector rank order. State plainly which sectors ran
and which did not.

Report shape per finding:
```
[SECTOR NN] P-NN-K: <paradigm name>
  file:line (anchor_verified: yes/no/stale)
  claim: <what breaks, one line>
  severity: BLOCKER | MAJOR | MINOR | NIT  (boosted one band if prd_contradiction)
  suggested_fix: <patch shape, not the patch>  (omitted if --no-fix-suggest)
  backend: <which of the 6 backends confirmed this, with query>
  sibling: <canonical code that does it right, for pattern-matching>
  prd_contradiction: true | false  (only present if --prd given)
```

If `--prd` was given, add a **PRD conformance** section after the FALSE-POSITIVES
bucket, one entry per PRD requirement the sectors could identify, aggregated
across sectors:
```
PRD CONFORMANCE
  [REQ-1] <requirement>: met | partial | missing | contradicted
    evidence: <file:line that implements it, or null if missing>
    sector: <which sector's lens found this>
  [REQ-2] ...
```
- `met` — point at the file:line that implements it.
- `partial` — say exactly which part is absent.
- `missing` — no implementation exists. `evidence` is null. This is expected
  and is the most valuable thing the PRD track finds.
- `contradicted` — the code does something the PRD forbids. Cross-reference
  the FIX-bucket finding that flags it.

Severity bar (from Andrea's #94 audit):
- **BLOCKER** leaks money/data or breaks the contract.
- **MAJOR** is a real defect on a load-bearing path.
- **MINOR** is a real defect on a non-load-bearing path.
- **NIT** is naming, a missing index, or a cosmetic correctness detail.

### Step 9: Persist the full report to disk

`~/<provider>/docs/andrea-review-reports/<title>-<timestamp>.md`,
relative to the reviewed repo. `mkdir -p` first.

- `<title>` — three/four lowercase hyphenated words describing the review.
- `<timestamp>` — `date +%Y-%m-%d-%H%M%S`.

The file is **not** brief — write every finding in full: file:line, the
complete rationale, which sectors found it and any disagreement, the
verified-correct notes, the PRD-conformance section if a PRD was given,
and the bottom line. Nothing from the merge (Step 5) or triage (Step 7)
is lost when the chat scrolls away.

Last line of the in-chat report must be the exact relative path:
```
→ ./docs/andrea-review-reports/<title>-<timestamp>.md
```

## Output contract for each sector agent

Each sector agent returns a JSON-shaped finding list (one entry per
paradigm that fires on the diff):

```json
{
  "sector": "NN — <name>",
  "findings": [
    {
      "paradigm_id": "P-NN-K",
      "paradigm_name": "<imperative title>",
      "file": "<path>",
      "line": "<line or range>",
      "claim": "<what breaks, one line>",
      "severity": "BLOCKER|MAJOR|MINOR|NIT",
      "suggested_fix": "<patch shape>",
      "backend_used": "<codegraph|semble|serena|codebase-memory|graphify|agentmemory> + query",
      "anchor_verified": "yes|no|stale",
      "anchor_evidence": "<the byte-confirmed text at file:line>",
      "prd_contradiction": "true|false",
      "cross_sector_links": ["P-MM-J", ...]
    }
  ],
  "prd_conformance": [
    {"requirement": "<REQ>", "status": "met|partial|missing|contradicted", "evidence": "<file:line|null>", "where": "<file:line|null>"}
  ],
  "sectors_cross_referenced": ["MM", ...],
  "read_only_compliance": true,
  "source_files_modified": []
}

The orchestrator merges these across sectors (Step 5), validates (Step 6),
triages (Step 7), and reports (Step 8).

## Codebase-intelligence backend binding (summary — see playbook for per-paradigm detail)

| Backend | When | Canonical query | Worktree caveat |
|---|---|---|---|
| **CodeGraph** (CLI) | Verbatim source + call paths | `codegraph explore -p ~/<provider>/<repo> "<q>"` | `~/<provider>/gateway/.codegraph` is main-branch (no batch); use `read`/`semble` for batch symbols (CR-3) |
| **Semble** (MCP) | Vague natural-language lookup | `semble_search "<desc>"` or `semble_find_related` | For worktree code, `semble_search repo=<worktree>` |
| **Serena** (MCP) | Symbol confirm, references, rename | `find_symbol` (scope with `relative_path`), `find_referencing_symbols` | Unscoped `find_symbol` on `app/` times out |
| **codebase-memory** (MCP) | Multi-hop chains, cross-service HTTP, Cypher, complexity | `search_graph`, `trace_path` (calls/data_flow/**cross_service**), `query_graph` | **gateway NOT indexed** — only app/app-backend/app-client/helm/operator/python/e2e. `cross_service` is the ONLY real cross-repo edge source |
| **graphify** (CLI) | Communities, god nodes, broad map | `graphify query "<q>"` (merged) or `--graph ./<repo>/graphify-out/graph.json` | Union-only, no inferred cross-repo edges |
| **agentmemory** (MCP) | Past-session decisions, deferral rationales | `memory_smart_search` (preferred), `memory_recall` | Search before re-deriving; canonical for CR-4 deferral checks |

**Re-grounding order (CR-1):** `semble_search` → Serena `find_symbol` (scoped) → `read`.

## What this skill does NOT do

- **No auto-fix.** Fixes are suggested only (CR-6). The PR author owns
  every fix. This skill never `edit`/`write` source, never `git commit`.
- **No re-derivation of the playbook.** The playbook is the source of
  truth; this skill runs it. If the playbook is stale, update the
  source-of-record playbook (re-run the extraction pipeline; see
  README.md), then re-snapshot into this skill — not this SKILL.md.
- **No review of closed/merged PRs.** Live diff only.
- **No light-lane auto-fix without consent.** SKIP-NOW is a label, not an
  action.
- **No ensemble/Codex external review.** (Not ported; `deep-review`'s
  `--ensemble` is not available here.)

## Relationship to other skills

- **`adamsreview`** — a multi-stage review pipeline with 6 detection lenses,
  scoring gates, validation lanes, and an automated fix loop. `andrea-review`
  is the sector-partitioned, infra-grounded, never-auto-commit complement:
  where `adamsreview` fixes, `andrea-review` suggests. They can be run
  together (run `andrea-review` first for the sector findings, then
  `adamsreview fix` on the FIX bucket).
- **`deep-review`** — orchestrates adamsreview + code-reviewer + PRD
  conformance in parallel. `andrea-review` is a single-track 12-sector
  swarm; `deep-review` is a multi-track ensemble. Composable: a
  `deep-review` track could be `andrea-review`.
- **`code-reviewer`** — single-pass diff read. `andrea-review` is the
  deep, sector-partitioned, infra-grounded version.

## Maintenance

The playbook and its pipeline artifacts are bundled in this skill at
`playbook/` and `sectors/`. The editable source of record lives at
`~/<provider>/docs/andrea-review-playbook.md` and
`~/<provider>/docs/andrea-review-sectors/`; the bundled copies are
snapshots. See `README.md` for the refresh procedure (copy the docs back
into the skill after editing).

The dispatch contract (this SKILL.md) is maintained separately from the
playbook content — a playbook refresh does not require editing this file.

To rebuild the playbook from new source reviews (edits the source of
record, not this skill):
1. Update `~/<provider>/docs/andrea-review-sectors/_CONTEXT.md` with new
   source documents.
2. Re-run the 12-worker extraction (see `_CONTEXT.md` for the dispatch
   contract).
3. Re-run the 3 synthesis passes (dedup/validation/adversarial).
4. Re-assemble the playbook from the synthesis output.
5. Re-snapshot into this skill: `cp ~/<provider>/docs/andrea-review-playbook.md playbook/` and `cp ~/<provider>/docs/andrea-review-sectors/{_CONTEXT,_synthesis-*,sector-*}.md sectors/`.

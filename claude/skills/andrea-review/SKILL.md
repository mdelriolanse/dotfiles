---
name: andrea-review
description: Run a 12-sector agent swarm over a PR diff. Each sector agent applies its lens (idempotency, concurrency, shutdown, rate-limiting, billing, storage, schema, wire, multi-repo, security, testing, code-smell), grounding every finding in the codebase-intelligence backends available on the machine, then the orchestrator dedups, validates, and adversarially triages. Use when the user types /andrea-review, or wants deep multi-lens PR review rather than a single-pass read. Fixes are suggested only — never auto-committed.
argument-hint: "[<PR-number> | <diff-ref>] [--prd <path|issue|url>] [--no-fix-suggest]"
compatibility: claude
metadata:
  author: "<your-handle>"
  version: "2.0.0"
  domain: quality
  triggers: andrea-review, /andrea-review, andrea review, pr review, code review
  role: specialist
  scope: review
---

# andrea-review — 12-sector agent-swarm PR review

Runs a **12-sector review playbook** as a parallel agent swarm. Each sector
is an independent review lens (idempotency, concurrency, shutdown,
rate-limiting, billing, storage, schema, wire, multi-repo, security,
testing, code-smell); the orchestrator dispatches them in one `tasks[]`
batch, then dedups, validates, and adversarially triages.

**The playbook is the source of truth.** Read it before dispatch:
`playbook/andrea-review-playbook.md` (bundled in this skill) — 12 sectors,
their core questions and paradigms, cross-cutting rules, and the
codebase-intelligence backend bindings. Every finding must be grounded
against live code via the backends; fixes are suggested only, never
auto-committed.

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
   The PR author owns every fix. This is cross-cutting rule CR-6.
2. **Re-ground before citing any anchor.** Before citing any `file:line`,
   re-ground via `semble_search` → Serena `find_symbol` (with
   `relative_path`) → `read`. A cited anchor that no longer exists is a
   false-positive risk. This is CR-1.
3. **Be worktree-aware.** A feature branch may live in a worktree whose
   code is absent from the main checkout's code-intelligence index. Verify
   anchors against the *actual working tree under review*, not a
   main-branch index that may predate the feature. Use `read` or
   `semble_search repo=<worktree>` for symbols the main index lacks. This
   is CR-3.
4. **Read-only workers.** Sector agents are read-only detection/extraction
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

**If the diff is empty, STOP.** Do not fall back to reviewing `main`'s
surface, another branch, or any "existing files" shape. Say plainly:
"No diff in <repo> at <branch> vs <merge-base>. Nothing to review." A
report that reviews code that is NOT the code under review manufactures
findings against the wrong baseline — the stop-and-say-so rule is
load-bearing; falling back is a bug.

**Empty-diff diagnostics before stopping.** If `git diff $mb` is empty,
run in order and report which fires:
1. `git status --short` — staged/unstaged changes the diff should have caught?
2. `git log --oneline $mb..HEAD` — committed work the three-dot form missed?
3. `git reflog -5` — recent `reset:`/`commit:` entries for recovery.
Only after reporting these may you stop.

### Step 1.5: Resolve the PRD, if `--prd` given

A PRD is the document the build is supposed to satisfy. Resolve `--prd` to
a file at `<run-dir>/PRD.md`:
- **Path** (`docs/spec.md`) → `read` it.
- **Issue number** (`412`) → `gh issue view 412 --json title,body,comments`.
- **URL** → `gh api` the issue or `read` the URL.

If it resolves to nothing, **stop and say so.** Do not review against a PRD
you could not read.

With a PRD resolved, the review gains one question per sector: **does the
code satisfy the PRD requirement in this sector's lens?** A finding that
contradicts the PRD is in-scope even when the contradiction is in untouched
code, because the PRD defines what "correct" means for this change.

### Step 2: Read the playbook

`read playbook/andrea-review-playbook.md` (bundled in this skill) — the
orchestrator MUST read the full playbook before dispatch. It contains the
12 sector definitions, the cross-cutting rules, and the per-sector
backend-grounding guidance. The sector agents do NOT each re-read the whole
playbook; the orchestrator passes each agent its sector section.

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
  - The sector's definition (copied from the playbook — core question,
    paradigms, backend-grounding guidance, failure modes)
  - The cross-cutting rules (CR-1..CR-7, verbatim from the playbook). CR-7
    is the scope gate: every finding must carry `origin`
    (`introduced_by_pr`|`pre_existing`|`unknown`) and `origin_confidence`
    (`high`|`medium`|`low`). Default `introduced_by_pr`/`high` only when the
    cited file is in `reviewed_files_all`; if the cited file is NOT modified
    by this diff, mark `pre_existing` unless the PR's new code in another file
    made the old code wrong (then `introduced_by_pr` — the PR is the cause).
    Apply the paradigm only to code the diff touches; do not surface issues
    on code this PR never touched.
  - The output contract (below)
  - The hard constraints (read-only, never auto-commit, re-ground, worktree-aware)

**Parallelism is the point.** A single-pass review misses the lenses; the
12-agent fan-out reproduces deep multi-lens review. Token budget is not the
binding constraint — thoroughness is. Dispatch all 12 in one batch; do not
serialize.

### Step 4: Join — wait for all 12

`hub wait` (or wait on the task batch). Do NOT report until every launched
sector has returned. If a sector fails or returns nothing, say which and
report the surviving sectors' findings labeled single-sector.

### Step 5: Dedup across sectors

Same file + overlapping line range + same underlying claim → one finding.
Do NOT merge on wording alone; two different bugs on one line stay two
findings. Dispositions:
- **MERGE** — fold the duplicate into the owning sector.
- **KEEP-ASPECTS** — extract non-overlapping parts, merge the overlapping core.
- **KEEP-SEPARATE** — genuinely distinct lenses on shared evidence; both
  stay, cross-referenced.

### Step 6: Validate anchors

Re-ground every finding's cited anchor against the live code:
- `semble_search "<symbol> <feature>"` to relocate moved symbols.
- Serena `find_symbol` with `relative_path` to confirm a symbol exists.
- `read` the resolved `file:line` to byte-confirm.
- If a code-intelligence index lacks the feature (worktree code, un-indexed
  repo), fall back to `read` or `semble_search repo=<worktree>` — do NOT
  trust a main-branch index for worktree-only code.

Mark each finding `anchor_verified: true|false|stale`. A finding with a
stale anchor is a false-positive risk — either re-ground or drop.

### Step 7: Adversarial triage

Apply the cross-cutting guardrails (CR-1..CR-7) and bucket every finding:

- **PRE-EXISTING** (CR-7, highest priority) — `origin: pre_existing` with
  `origin_confidence: high`: the implicated code is unchanged by this diff
  and the bug exists independently of the PR. Route here **before** any
  severity triage. Override: a finding that contradicts the PRD
  (`prd_contradiction: true`) stays in scope regardless of origin. Override:
  pre-existing-looking code that became wrong because of new code this PR
  adds elsewhere stays `introduced_by_pr`. **File-membership check:** if a
  finding's `file` is NOT in `reviewed_files_all` and the agent marked it
  `introduced_by_pr`, downgrade to `pre_existing` unless you can name the
  PR-added code that made it wrong.
- **FIX** — a real defect worth addressing now. One line on what breaks.
- **SKIP-NOW** — real but not worth fixing now (YAGNI, cosmetic,
  speculative edge). One line naming when it *would* be worth revisiting.
- **FALSE-POSITIVE** — not actually a bug; the reviewer misread the code.
  One line on why it's wrong.

**Hard rule**: a finding on a security, data-loss, input-validation, or
money path is **never** SKIP-NOW or FALSE-POSITIVE unless you can show
concretely it doesn't apply. When unsure, FIX.

**CR-4 reminder**: a deferral with a recorded rationale is a decision, not
a finding. Do not re-raise unless the rationale no longer holds.

### Step 8: Report

Lead with the **FIX** bucket, then SKIP-NOW, then PRE-EXISTING, then
FALSE-POSITIVES. Within each bucket keep the sector rank order. State
plainly which sectors ran and which did not. The PRE-EXISTING bucket is
informational — real issues, but not this PR's job to fix.

Report shape per finding:
```
[SECTOR NN] P-NN-K: <paradigm name>
  file:line (anchor_verified: yes/no/stale)
  origin: introduced_by_pr | pre_existing | unknown  (confidence: high|medium|low)
  claim: <what breaks, one line>
  severity: BLOCKER | MAJOR | MINOR | NIT  (boosted one band if prd_contradiction)
  suggested_fix: <patch shape, not the patch>  (omitted if --no-fix-suggest)
  backend: <which backend confirmed this, with query>
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
- `missing` — no implementation exists. `evidence` is null. This is the most
  valuable thing the PRD track finds.
- `contradicted` — the code does something the PRD forbids. Cross-reference
  the FIX-bucket finding that flags it.

Severity bar:
- **BLOCKER** leaks money/data or breaks the contract.
- **MAJOR** is a real defect on a load-bearing path.
- **MINOR** is a real defect on a non-load-bearing path.
- **NIT** is naming, a missing index, or a cosmetic correctness detail.

### Step 9: Persist the full report to disk

`<reviewed-repo>/docs/andrea-review-reports/<title>-<timestamp>.md`, where
`<reviewed-repo>` is the root of the git repo whose diff was reviewed —
resolved via `git -C <reviewed-subdir> rev-parse --show-toplevel` from the
dir whose diff you actually reviewed. Never write to an umbrella/parent
repo that merely *contains* the reviewed repo as a nested checkout. If the
review spans multiple repos, pick the repo holding the bulk of the code
under review as the report's home.

- `<title>` — three/four lowercase hyphenated words describing the review.
- `<timestamp>` — `date +%Y-%m-%d-%H%M%S`.

The file is **not** brief — write every finding in full: file:line, the
complete rationale, which sectors found it and any disagreement, the
verified-correct notes, the PRD-conformance section if a PRD was given,
and the bottom line.

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
      "origin": "introduced_by_pr|pre_existing|unknown",
      "origin_confidence": "high|medium|low",
      "claim": "<what breaks, one line>",
      "severity": "BLOCKER|MAJOR|MINOR|NIT",
      "suggested_fix": "<patch shape>",
      "backend_used": "<semble|serena|codebase-memory|graphify|agentmemory> + query",
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
```

The orchestrator merges these across sectors (Step 5), validates (Step 6),
triages (Step 7), and reports (Step 8).

## Codebase-intelligence backend binding

Every finding MUST be grounded against live code via the backends
available on the machine. NEVER cite an anchor without re-verifying it.
Name the backend and the query used.

| Backend | When | Canonical query | Worktree caveat |
|---|---|---|---|
| **Semble** (MCP) | Vague natural-language lookup | `semble_search "<desc>"` or `semble_find_related` | For worktree code, `semble_search repo=<worktree>` |
| **Serena** (MCP) | Symbol confirm, references, rename | `find_symbol` (scope with `relative_path`), `find_referencing_symbols` | Unscoped `find_symbol` on a large tree may time out |
| **codebase-memory** (MCP) | Multi-hop chains, cross-service HTTP, Cypher, complexity | `search_graph`, `trace_path` (calls/data_flow/**cross_service**), `query_graph` | Not every repo is indexed; check `list_projects`. `cross_service` is the only real cross-repo edge source |
| **graphify** (CLI) | Communities, god nodes, broad map | `graphify query "<q>"` (merged) or `--graph ./<repo>/graphify-out/graph.json` | Union-only, no inferred cross-repo edges |
| **agentmemory** (MCP) | Past-session decisions, deferral rationales | `memory_smart_search` (preferred), `memory_recall` | Search before re-deriving; canonical for CR-4 deferral checks |

**Re-grounding order (CR-1):** `semble_search` → Serena `find_symbol` (scoped) → `read`.

Not all backends may be installed on a given machine. Use what's
available; if a backend is absent, fall back to the next in the
re-grounding order. The requirement is that every cited anchor is
verified against live code — the backend choice is the means, not the end.

## What this skill does NOT do

- **No auto-fix.** Fixes are suggested only (CR-6). The PR author owns
  every fix. This skill never `edit`/`write` source, never `git commit`.
- **No review of closed/merged PRs.** Live diff only.
- **No light-lane auto-fix without consent.** SKIP-NOW is a label, not an
  action.

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

The playbook is bundled in this skill at `playbook/andrea-review-playbook.md`.
The dispatch contract (this SKILL.md) is maintained separately from the
playbook content — a playbook refresh does not require editing this file.

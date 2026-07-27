---
description: Evaluate N library/framework candidates by building the same proof-of-concept with each on separate worktrees, then score and recommend.
argument-hint: <use case or problem> --candidates "<lib1>, <lib2>, <lib3>" [--n <count if auto-discovering>]
---

**Input:** $ARGUMENTS
**Timestamp:** !date +%Y-%m-%d_%H-%M-%S
**Context:** @CLAUDE.md

Parse from $ARGUMENTS:
- `--candidates "<lib1>, <lib2>, ..."` — explicit list of candidates to evaluate
- `--n <count>` — if no candidates specified, researcher will find the top N candidates (default: 3)
- Everything else is the use case / problem statement

## Phase 1 — Discover Candidates (skip if --candidates provided)

Use the Task tool to launch the `researcher` agent. Pass it:
- The use case from $ARGUMENTS
- Instruction: find the top N libraries/frameworks for this use case; compare by GitHub stars, last release date, bundle size, license, and community health. Save to `agent/research/`.

Wait for the research file and extract the candidate names.

## Phase 2 — Define the POC Spec

Use the Task tool to launch `plan-architect` with:
- The use case description
- The candidate list
- Instruction: define a standardized proof-of-concept task that ALL candidates must implement (same inputs, same expected outputs, same interface). The POC should be meaningful enough to exercise the library's core API but small enough to be buildable in a single session. Save to `agent/plans/`.

Wait for the spec file.

## Phase 3 — Parallel POC Builds

Create one worktree per candidate:
```bash
git worktree add -b spike-<candidate-slug> ./worktrees/spike-<candidate-slug>
```

Launch all `ralph-executor` agents simultaneously via the Task tool. Pass each executor:
- The POC spec
- Its assigned candidate library/framework (install it and use it exclusively)
- Its worktree path
- Instruction: implement only what the spec requires; record install size (`du -sh node_modules` or equivalent), build time, and any notable DX observations in a file at `agent/spike-notes/<candidate-slug>.md`

Wait for ALL executors to complete.

## Phase 4 — Evaluate

Use the Task tool to launch the `evaluator` agent. Pass it:
- All worktree paths
- The POC spec as the rubric source
- The research file from Phase 1 (for ecosystem/maturity context)
- The spike notes files from each executor
- Criteria: convention fit with existing codebase, ecosystem maturity, bundle/install size, DX observations, spec adherence, code simplicity

Wait for the evaluation report.

## Phase 5 — Report

Present to the user:
- The evaluator's ranked recommendation with rationale
- Key trade-offs for the top 2 candidates
- The spike notes files for detailed per-candidate observations

Ask whether to:
1. Keep all worktrees for manual inspection
2. Clean up non-recommended worktrees
3. Proceed to a full implementation with the recommended candidate (launch `/research-build` with the recommendation as context)

**MCPs used:** Firecrawl and WebSearch (candidate discovery and research via researcher agent)

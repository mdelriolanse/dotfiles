---
description: Run N full TDD pipelines in parallel on separate worktrees, each building the same spec independently, then evaluate to pick the best implementation.
argument-hint: <task description> [--n <count>]
---

**Input:** $ARGUMENTS
**Timestamp:** !date +%Y-%m-%d_%H-%M-%S
**Context:** @CLAUDE.md

Parse `--n <count>` from $ARGUMENTS (default: 3). Everything else is the task description.

## Phase 1 — Shared Plan & Tests (sequential)

Use the Task tool to launch `plan-architect` with the task description. Wait for the plan file path.

Use the Task tool to launch `test-architect` with the plan file. Wait for the test file path. These acceptance tests are the shared benchmark — every implementation must pass them.

## Phase 2 — Parallel Implementations

Create N worktrees, one per implementation:
```bash
git worktree add -b impl-race-N ./worktrees/impl-race-N
```

Launch all N `ralph-executor` agents simultaneously via the Task tool. Each executor receives:
- The full plan file
- The shared test file path
- Its own worktree path (`./worktrees/impl-race-N`)
- Instruction: implement the plan independently in the worktree; iterate until all shared tests pass; write any additional tests it deems appropriate; do NOT look at other worktrees

Wait for ALL executors to complete.

## Phase 3 — Commit Each (parallel)

Simultaneously launch `commit-architect` agents for each completed worktree, passing each its worktree path.

Wait for all commits.

## Phase 4 — Evaluate

Use the Task tool to launch the `evaluator` agent. Pass it:
- All N worktree paths and branch names
- The plan file as the spec source
- The shared test file path
- Instruction: compare on spec adherence, test pass rate, code quality (simplicity, readability, convention fit), and completeness

Wait for the evaluation report and recommendation.

## Phase 5 — Report & Merge

Present the evaluator's ranked report to the user and ask for confirmation of the winning implementation.

On confirmation, launch `merge-orchestrator` with:
- Only the winning worktree path and branch
- Target: main

After the winning branch is merged and worktree cleaned up, also clean up non-winning worktrees:
```bash
git worktree remove ./worktrees/impl-race-N
git branch -d impl-race-N
```

---
description: Full TDD pipeline — plan, write tests first, parallel execution per worktree, merge to main.
argument-hint: <task description>
---

**Input:** $ARGUMENTS
**Timestamp:** !date +%Y-%m-%d_%H-%M-%S
**Context:** @CLAUDE.md

## Phase 1 — Plan (sequential)

Use the Task tool to launch the `plan-architect` agent with the task description from $ARGUMENTS. Wait for it to complete and note the saved plan file path in `agent/plans/`.

## Phase 2 — Test Suite (sequential, depends on Phase 1)

Use the Task tool to launch the `test-architect` agent. Pass it:
- The plan file path from Phase 1
- Instruction: write acceptance tests covering the plan's success criteria to `agent/tests/`. Tests should be runnable but expected to fail until implementation is complete. Do not implement anything — tests only.

Wait for the test file path.

## Phase 3 — Decompose Tasks

Read the plan file. Identify discrete subtasks (each major phase or step becomes one subtask). For each subtask N (starting at 1):

1. Create a worktree:
   ```bash
   git worktree add -b worktree-task-N ./worktrees/task-N
   ```
2. Copy or symlink the test file into the worktree so the executor can run it.

## Phase 4 — Execute (parallel)

Launch one `ralph-executor` agent per subtask via the Task tool simultaneously (all in the same response). Pass each executor:
- Its specific subtask description (extracted from the plan)
- The path to the test file
- Its worktree path: `./worktrees/task-N`
- Instruction: cd into the worktree path before executing; iterate until all tests pass

Wait for ALL executors to complete before proceeding.

## Phase 5 — Commit (parallel)

For each completed worktree, simultaneously launch a `commit-architect` agent via the Task tool. Pass each one its worktree path and branch name (`worktree-task-N`).

Wait for all commits to complete.

## Phase 6 — Merge

Use the Task tool to launch the `merge-orchestrator` agent. Pass it:
- The list of all worktree paths and branch names from Phase 3
- Target branch: main (or the default branch)

The merge-orchestrator will resolve conflicts, merge all branches to main, and clean up worktrees.

## Completion

Report to the user:
- All subtasks completed and merged
- Final test suite status
- Branch/commit summary from merge-orchestrator

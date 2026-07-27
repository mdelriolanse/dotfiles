---
description: Research best practices and tech context first, then plan and build with findings informing the approach.
argument-hint: <goal or feature description> [--topic <research focus>]
---

**Input:** $ARGUMENTS
**Timestamp:** !date +%Y-%m-%d_%H-%M-%S
**Context:** @CLAUDE.md

Parse `--topic <value>` from $ARGUMENTS if present (overrides the inferred research topic). Everything else is the build goal.

## Phase 1 — Research (sequential)

Use the Task tool to launch the `researcher` agent. Pass it:
- Research topic: the `--topic` value if provided, otherwise infer from the build goal (e.g., "best practices for X", "available libraries for Y", "migration guide for Z")
- Instruction: save findings to `agent/research/`

Wait for the research report file path.

## Phase 2 — Plan (sequential, depends on Phase 1)

Use the Task tool to launch the `plan-architect` agent. Pass it:
- The build goal from $ARGUMENTS
- The research report file path from Phase 1
- Instruction: let the research findings inform technology choices, library versions, patterns, and known pitfalls in the plan

Wait for the plan file path in `agent/plans/`.

## Phase 3 — Execute

Use the Task tool to launch the `test-architect` agent with the plan file. Wait for the test file.

Then decompose the plan into subtasks. For each subtask N:
```bash
git worktree add -b worktree-research-build-N ./worktrees/research-build-N
```

Launch all `ralph-executor` agents simultaneously via the Task tool (one per subtask), each in their own worktree. Pass each executor the research report path as additional context so it can reference the findings during implementation.

Wait for all executors to complete.

## Phase 4 — Commit & Merge

For each completed worktree, simultaneously launch `commit-architect` agents. Then launch `merge-orchestrator` with all worktree paths to merge back to main and clean up.

## Completion

Report to the user:
- Research file location
- Plan file location
- Implementation summary
- Merge result

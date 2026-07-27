---
description: Spin up N parallel frontend implementations of the same spec on separate worktrees and ports, screenshot each with Browserbase, then evaluate to pick the best.
argument-hint: <UI spec or feature description> [--n <count>] [--figma <url>] [--base-port <port>]
---

**Input:** $ARGUMENTS
**Timestamp:** !date +%Y-%m-%d_%H-%M-%S
**Context:** @CLAUDE.md

Parse flags from $ARGUMENTS:
- `--n <count>` — number of parallel implementations (default: 3)
- `--figma <url>` — Figma file URL to use as the design reference
- `--base-port <port>` — starting port for dev servers (default: 3001)
Everything else is the UI spec/description.

## Phase 1 — Plan

Use the Task tool to launch the `plan-architect` agent. Pass it:
- The UI spec from $ARGUMENTS
- The Figma URL if provided (instruct the agent to reference it for component breakdown)
- Instruction: produce a UI spec plan describing required components, interactions, layout, and acceptance criteria. Save to `agent/plans/`.

Wait for the plan file path.

## Phase 2 — Assign Ports

Pre-assign ports for all N implementations. Port for implementation I (1-indexed) = base-port + (I - 1).
Example with N=3 and base-port=3001: ports are 3001, 3002, 3003.

Record the port assignments — pass each to its executor.

## Phase 3 — Parallel Implementations

Create N worktrees:
```bash
git worktree add -b frontend-race-N ./worktrees/frontend-race-N
```

Launch all N `ralph-executor` agents simultaneously via the Task tool. Pass each executor:
- The plan file path
- Its assigned port: `PORT=300X`
- Its worktree path
- The Figma URL if provided (use as visual reference)
- Instruction: build its own interpretation of the spec, start the dev server on the assigned port, and use `mcp__browserbase__screenshot` (or equivalent Browserbase tool) to take screenshots of key views (at minimum: initial state, main interaction, any modal/overlay). Save screenshots to `agent/screenshots/race-N/`. Keep the dev server running after screenshots.

Wait for ALL executors to complete.

## Phase 4 — Evaluate

Use the Task tool to launch the `evaluator` agent. Pass it:
- All N worktree paths
- All N port assignments and their screenshot directories
- The plan file as the rubric source
- The Figma URL if provided (use as the visual ground truth)
- Instruction: evaluate against visual spec adherence, functional completeness, code quality, and accessibility

Wait for the evaluation report.

## Phase 5 — Report to User

Present:
- The evaluator's ranked recommendation
- Live URLs: `http://localhost:PORT` for each implementation still running
- Screenshot paths for each
- Prompt the user to pick a winner or accept the evaluator's recommendation

Once the user selects a winner, offer to:
1. Merge the winning branch to main (launch `merge-orchestrator` with winning worktree only)
2. Clean up the other worktrees: `git worktree remove ./worktrees/frontend-race-N && git branch -d frontend-race-N` for each non-winner

**MCPs used:** Browserbase (screenshots), Figma (optional, design reference)

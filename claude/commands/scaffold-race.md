---
description: Scaffold the same project spec using N different tech stacks in parallel worktrees, benchmark each, and evaluate to recommend the best foundation.
argument-hint: <project type and spec> --stacks "<stack1>, <stack2>, <stack3>" [--n <count if auto-discovering>]
---

**Input:** $ARGUMENTS
**Timestamp:** !date +%Y-%m-%d_%H-%M-%S
**Context:** @CLAUDE.md

Parse from $ARGUMENTS:
- `--stacks "<stack1>, <stack2>, ..."` — explicit tech stacks to scaffold (e.g., "Express+Prisma, Fastify+Drizzle, Hono+Kysely")
- `--n <count>` — if no stacks specified, researcher discovers top N candidates (default: 3)
- Everything else is the project type and spec

## Phase 1 — Discover Stacks (skip if --stacks provided)

Use the Task tool to launch the `researcher` agent with:
- Project type and requirements from $ARGUMENTS
- Instruction: identify the top N tech stack options for this project type; compare by ecosystem maturity, convention fit, performance reputation, and community support; save to `agent/research/`

Wait for the research file and extract the stack names.

## Phase 2 — Define the Scaffold Spec

Use the Task tool to launch `plan-architect` with:
- The project spec from $ARGUMENTS
- The stack list
- Instruction: define a standardized scaffold spec that every stack must implement (same feature set: e.g., "a REST API with auth, a user resource CRUD, database connection, and a health check endpoint"). The spec should be concrete enough to meaningfully differentiate stacks but not so large it takes multiple sessions. Save to `agent/plans/`.

Wait for the spec file.

## Phase 3 — Parallel Scaffolds

Create one worktree per stack:
```bash
git worktree add -b scaffold-<stack-slug> ./worktrees/scaffold-<stack-slug>
```

Launch all `ralph-executor` agents simultaneously via the Task tool. Each executor receives:
- The scaffold spec
- Its assigned tech stack (use this stack exclusively)
- Its worktree path
- Instruction: scaffold the project, implement the spec, run any built-in tests or type checks, then record the following to `agent/scaffold-notes/<stack-slug>.md`:
  - Install size (`du -sh node_modules` or equivalent)
  - Cold start time
  - Lines of code for the spec implementation
  - Any rough edges or DX observations

Wait for ALL executors to complete.

## Phase 4 — Evaluate

Use the Task tool to launch the `evaluator` agent with:
- All worktree paths
- The scaffold spec as the rubric
- The research file (ecosystem context)
- The scaffold notes from each executor
- Criteria: convention fit with project requirements, ecosystem maturity, code clarity, install footprint, DX observations, spec completeness

Wait for the evaluation report.

## Phase 5 — Report & Decision

Present to the user:
- Ranked recommendation with rationale
- Side-by-side scaffold notes (lines of code, install size, DX notes) for the top 2
- Full evaluation report path

Ask the user to:
1. Pick a winner (or accept the recommendation)
2. Whether to use the winning scaffold as the project foundation (merge to main)
3. Whether to clean up non-winning worktrees

On user confirmation of winner:
- Launch `merge-orchestrator` with only the winning worktree
- Clean up all other worktrees

**MCPs used:** Firecrawl and WebSearch (stack discovery via researcher agent)

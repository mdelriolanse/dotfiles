---
description: Fast-path hotfix — diagnose the root cause, produce a minimal fix plan, implement, validate, and open a PR. No parallelism overhead.
argument-hint: <error description, stack trace, or log snippet>
---

**Input:** $ARGUMENTS
**Timestamp:** !date +%Y-%m-%d_%H-%M-%S
**Context:** @CLAUDE.md

## Phase 1 — Diagnose

Analyze the error/issue from $ARGUMENTS directly:
- Identify the affected files and functions from the stack trace or description
- Grep the codebase for the relevant code paths
- Form a hypothesis about the root cause before any changes

If a GitHub issue or PR number is referenced in $ARGUMENTS, use the `mcp__github__get_issue` or `mcp__github__get_pull_request` tool to fetch full context.

## Phase 2 — Plan

Use the Task tool to launch the `plan-architect` agent. Pass it:
- The root cause diagnosis from Phase 1
- The affected file list
- Instruction: produce a **minimal-scope** fix plan (single phase, no architecture changes, no refactoring). The plan should describe exactly what to change and why, not a phased roadmap. Save to `agent/plans/`.

Wait for the plan file.

## Phase 3 — Branch & Fix

Create a hotfix branch (do NOT use a worktree — hotfixes stay in the main working directory):
```bash
git checkout -b hotfix/{{slug-from-diagnosis}}
```

Use the Task tool to launch a single `ralph-executor` agent. Pass it:
- The plan file
- Instruction: implement the fix, run the full existing test suite to validate, iterate if tests fail. Do not add new features. Do not refactor beyond the fix scope.

Wait for the executor to complete.

## Phase 4 — Commit

Use the Task tool to launch `commit-architect` with the current branch. The commit message should clearly describe the bug and fix.

## Phase 5 — Open PR

Use `mcp__github__create_pull_request` to open a PR:
- Title: `fix: <concise description>`
- Body: include the root cause, what was changed, and how it was validated
- Mark as ready for review (not draft)

**If GitHub MCP is not available**, report the branch name and instruct the user to open the PR manually.

## Completion

Report:
- Root cause identified
- Files changed
- Test results
- PR URL (or branch name if MCP unavailable)

**MCPs used:** GitHub (optional — PR creation)

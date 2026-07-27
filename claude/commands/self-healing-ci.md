---
description: Fetch a CI failure, diagnose the root cause, attempt an automated fix, and open a PR. Escalates to the user if confidence is low.
argument-hint: <CI run URL or run ID> [--repo <owner/repo>] [--confidence-threshold <0-10>]
---

**Input:** $ARGUMENTS
**Timestamp:** !date +%Y-%m-%d_%H-%M-%S
**Context:** @CLAUDE.md

Parse from $ARGUMENTS:
- `--repo <owner/repo>` — GitHub repo if not inferable from the current directory
- `--confidence-threshold <N>` — minimum confidence (0-10) required to attempt automated fix (default: 7)
- Everything else is the CI run URL or run ID

## Phase 1 — Fetch CI Failure

Use `mcp__github__list_check_runs_for_ref` or `mcp__github__get_check_run` to fetch the failed CI run. Extract:
- Failed job names and steps
- Full log output of the failing steps
- The commit SHA that triggered the failure
- Which branch/PR this is on

If the GitHub MCP is unavailable, ask the user to paste the CI failure log directly.

## Phase 2 — Diagnose

Analyze the CI logs and the relevant source code:
- Identify the exact error message and line numbers
- Grep the codebase for the relevant code
- Determine whether the failure is: a flaky test, a code bug, a missing dependency, a config issue, or an environment issue
- Assign a confidence score (0-10) on how certain you are of the root cause and fix

## Phase 3 — Gate on Confidence

**If confidence >= threshold:**
Proceed to Phase 4 (automated fix attempt).

**If confidence < threshold:**
Stop here. Report to the user:
- The CI failure summary
- Your best hypothesis about the root cause
- Specific questions that would help narrow it down
- Suggested manual investigation steps

Do not attempt a fix when uncertain — a wrong automated fix creates more noise than it resolves.

## Phase 4 — Plan & Fix

Check out the failing branch:
```bash
git fetch origin
git checkout <branch-name>
```

Use the Task tool to launch `plan-architect` with:
- The root cause diagnosis
- Instruction: minimal-scope fix only; no refactoring

Use the Task tool to launch a `ralph-executor` agent with the fix plan. After completion, run the full test suite locally to validate.

## Phase 5 — Commit & PR

Use the Task tool to launch `commit-architect`.

Use `mcp__github__create_pull_request` (if this is a standalone branch) or `mcp__github__create_review` (if this is an existing PR that needs a fix pushed):
- PR/comment body must include: root cause, what was changed, confidence score, and local test results
- Label the PR with `self-healing` if labels are available

## Completion

Report:
- CI failure summary
- Root cause identified
- Fix applied (files changed)
- Local test results
- PR URL or escalation details

**MCPs used:** GitHub (CI log fetch, PR creation)

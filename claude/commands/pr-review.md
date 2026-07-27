---
description: Fetch a PR, review it for correctness, security, and conventions, then optionally implement fixes and post the review.
argument-hint: <PR number or URL>
---

**Input:** $ARGUMENTS
**Timestamp:** !date +%Y-%m-%d_%H-%M-%S
**Context:** @CLAUDE.md

## Phase 1 — Fetch PR

Extract the PR number from $ARGUMENTS. Use `mcp__github__get_pull_request` to fetch:
- PR title, description, and linked issues
- The diff (files changed, additions, deletions)
- Existing review comments if any

Also fetch the PR's base branch content for the changed files to have full context.

**If GitHub MCP is unavailable**, ask the user to paste the diff directly.

## Phase 2 — Review

Analyze the PR against the following checklist:

**Correctness**
- Does the implementation match the PR description/linked issue?
- Are there logic errors, off-by-one errors, or missing edge cases?
- Are new code paths reachable and tested?

**Security**
- Any injection vulnerabilities (SQL, command, template)?
- Sensitive data in logs, responses, or error messages?
- Auth/authorization checks on new endpoints or actions?
- Dependency additions — are they from reputable sources?

**Test Coverage**
- Are there tests for the new behavior?
- Do existing tests still cover the modified code?
- Are there untested branches introduced?

**Conventions**
- Does the code match the patterns in @CLAUDE.md and existing files?
- Naming, file structure, error handling style?
- Any unnecessary complexity introduced?

**Breaking Changes**
- API signature changes, database schema changes, removed exports?
- Any backwards-incompatible behavior for existing consumers?

## Phase 3 — Decide: Suggest or Fix

If issues found are **minor** (style, naming, small edge cases): compile them as review comments.

If issues found are **significant** (logic errors, security issues, missing critical tests): ask the user whether to:
- (A) Post the review with comments for the author to fix
- (B) Implement the fixes directly on the PR branch (proceed to Phase 4)

Default to (A) unless the user has pre-authorized auto-fix.

## Phase 4 — Implement Fixes (optional, if user chose B)

Check out the PR branch:
```bash
git fetch origin
git checkout <pr-branch>
```

Use the Task tool to launch a `ralph-executor` agent with the list of issues to fix. After completion, launch `commit-architect` to create a fixup commit.

## Phase 5 — Post Review

Use `mcp__github__create_review` to post the review:
- If approving (no issues or all fixed): `event: APPROVE`
- If requesting changes: `event: REQUEST_CHANGES` with inline comments on specific lines
- If commenting only: `event: COMMENT`

Structure the review body:
```
## Summary
[1-2 sentences on overall assessment]

## Issues
[Bulleted list of issues with file:line references]

## Suggestions (non-blocking)
[Optional improvements]
```

**If GitHub MCP is unavailable**, print the formatted review for the user to post manually.

**MCPs used:** GitHub (PR fetch and review posting)

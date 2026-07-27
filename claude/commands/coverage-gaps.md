---
description: Analyze test coverage gaps, fill the highest-risk ones with new tests, fix any bugs the new tests catch, and commit.
argument-hint: [target directory] [--threshold <percent>] [--high-risk-only]
---

**Input:** $ARGUMENTS
**Timestamp:** !date +%Y-%m-%d_%H-%M-%S
**Context:** @CLAUDE.md

Parse from $ARGUMENTS:
- `--threshold <percent>` — minimum coverage target (default: 80%)
- `--high-risk-only` — only write tests for high-risk gaps, skip medium and low
- Everything else is the target directory (default: entire project)

## Phase 1 — Analyze Coverage

Use the Task tool to launch the `coverage-analyzer` agent with:
- Target directory
- Coverage threshold

Wait for the analysis report at `agent/coverage/` and the list of high-risk gaps.

If coverage is already at or above the threshold and there are no high-risk gaps, report this to the user and stop — no work needed.

## Phase 2 — Write Gap Tests

Use the Task tool to launch `test-architect` with:
- The coverage analysis report
- The list of prioritized gaps (high-risk first, then medium unless `--high-risk-only`)
- Instruction: write tests for the uncovered paths identified in the report; add them to the project's existing test suite (not standalone files); tests should be meaningful — test the actual behavior of the uncovered code, not just line coverage

Wait for the new test files.

Run the new tests immediately:
```bash
# run only the new test files to see what passes and what fails
```

## Phase 3 — Fix Caught Bugs

If any new tests fail (and the test is correct — the code behavior is the bug), those are real bugs uncovered by the coverage work.

For each failing test that represents a real bug:
- Note the file, function, and nature of the bug
- Use the Task tool to launch a `ralph-executor` agent with a description of the bugs to fix
- Instruction: fix the bugs exposed by the new tests; do not modify the tests themselves; run the full test suite after fixes

Wait for the executor to complete.

## Phase 4 — Re-Run Coverage

Run the full test suite with coverage again to confirm:
1. All new tests pass
2. Coverage has improved toward the threshold
3. No existing tests were broken

## Phase 5 — Commit

Use the Task tool to launch `commit-architect`. This should produce up to two commits:
1. `test: add coverage for <module/area> — N uncovered paths addressed`
2. `fix: resolve N bugs caught by coverage expansion` (only if bugs were found in Phase 3)

## Completion

Report:
- Coverage before → after
- New tests written (count and areas covered)
- Bugs caught and fixed (if any)
- Remaining gaps below threshold (if any — with explanation of why they weren't addressed)

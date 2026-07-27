---
description: Capture existing behavior with characterization tests before refactoring, then refactor with a green-test guarantee, and finally replace characterization tests with proper semantic tests.
argument-hint: <refactor description or target file/module>
---

**Input:** $ARGUMENTS
**Timestamp:** !date +%Y-%m-%d_%H-%M-%S
**Context:** @CLAUDE.md

## Phase 1 — Characterization Tests (sequential)

Use the Task tool to launch `test-architect` with:
- The target files/modules from $ARGUMENTS
- Instruction: write **characterization tests** — tests that document exactly what the code CURRENTLY does, not what it ideally should do. These tests must pass against the current implementation. Cover all observable behaviors: return values, side effects, error conditions, and edge cases that the code actually handles. Save to `agent/tests/characterization-{{timestamp}}.test.*`.

Wait for the characterization test file. Run the tests to confirm they all pass against the current code before proceeding:
```bash
# run only the characterization tests to confirm baseline
```

If any characterization tests fail, do not proceed — the tests are wrong (the existing behavior IS the spec at this stage). Fix the tests.

## Phase 2 — Commit the Baseline

Use the Task tool to launch `commit-architect` to commit the characterization tests only:
- Commit message: `test: add characterization tests for <target> before refactor`

This creates a safe rollback point.

## Phase 3 — Plan the Refactor

Use the Task tool to launch `plan-architect` with:
- The refactor description from $ARGUMENTS
- The characterization test file path
- Instruction: plan the refactor with these constraints: (a) all characterization tests must remain green throughout; (b) no behavioral changes, only structural improvements; (c) each step should leave the codebase in a working state

Wait for the refactor plan file.

## Phase 4 — Execute the Refactor

Use the Task tool to launch a `ralph-executor` agent with:
- The refactor plan
- The characterization test file path
- Instruction: refactor incrementally; run characterization tests after each step; if any characterization test fails, stop and fix before continuing; do not modify the characterization tests themselves (modifying them defeats the purpose)

Wait for the executor to complete.

## Phase 5 — Semantic Test Cleanup

Once the refactor is complete and all characterization tests still pass:

Use the Task tool to launch `test-architect` with:
- The refactored code
- The characterization test file
- Instruction: review the characterization tests and replace them with proper semantic unit tests that test intended behavior (not just current behavior); remove characterization tests that are redundant or testing implementation details that no longer exist; add any missing coverage for the new structure. Save as a new test file; the original characterization file will be deleted.

## Phase 6 — Commit Final State

Use the Task tool to launch `commit-architect` to create two commits:
1. The refactored code + final semantic tests
2. Deletion of the characterization test file

## Completion

Report:
- Files refactored
- Characterization tests written / deleted
- Final semantic test count
- All tests passing confirmation

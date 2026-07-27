---
name: test-driven-development
description: Use when implementing any feature or bugfix, before writing implementation code
---

# Test-Driven Development — Agent Swarm

## Overview

A three-agent swarm that enforces the Iron Law structurally: the agent that writes the code has NEVER seen the test being written. Each RED→GREEN cycle is a fresh pair of subagents with zero shared context.

```
Orchestrator (you)
      │
      │  Break task into behaviors
      │
      ▼
┌──────────────────────────────────────────┐
│  CYCLE 1                                 │
│                                          │
│  RED agent     →  GREEN agent            │
│  (write test,   (write code,             │
│   verify fail)   verify pass)            │
│       │               ▲                  │
│       └─── test ──────┘                  │
│            (only shared artifact)        │
│                                          │
│  Orchestrator: refactor, verify green    │
└──────────────────────────────────────────┘
      │
      │  Next behavior
      ▼
┌──────────────────────────────────────────┐
│  CYCLE 2                                 │
│  RED agent → GREEN agent → refactor      │
└──────────────────────────────────────────┘
      │
      ▼
   DONE
```

**The Iron Law is enforced structurally:** GREEN agents receive only the test file and error output. They have no access to the conversation that produced the test. They cannot "know" what the test author intended — they can only make the test pass.

**Violating the letter of the rules is violating the spirit of the rules.**

## When to Use

**Always:**
- New features
- Bug fixes
- Refactoring
- Behavior changes

**Exceptions (ask your human partner):**
- Throwaway prototypes
- Generated code
- Configuration files

## The Iron Law

```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

## Orchestrator Workflow

### Step 0: Discover project conventions

Before spawning any subagent, determine:

```bash
# Test framework + file conventions
ls {__tests__,tests,spec,test} 2>/dev/null
cat package.json | jq '.scripts.test' 2>/dev/null
# Or: pyproject.toml, go.mod, Cargo.toml, etc.
```

Capture:
- **Test command**: e.g., `npm test`, `pytest`, `go test ./...`
- **Test file pattern**: e.g., `src/__tests__/foo.test.ts`, `tests/test_foo.py`
- **Source file pattern**: e.g., `src/foo.ts`, `pkg/foo/foo.go`

### Step 1: Break task into behaviors

From the user's request, identify discrete, testable behaviors. Each behavior = one RED→GREEN cycle.

Example: "Add email validation to the signup form"
```
1. Rejects empty email
2. Rejects invalid email format
3. Accepts valid email
4. Trims whitespace from email
```

Present the behavior list to the user for approval before starting cycles.

### Step 2: For each behavior — RED agent

Dispatch a `general` subagent with the RED agent prompt (`references/red-agent-prompt.md`).

Provide:
- The behavior to test
- The test file path (derived from conventions)
- The test command
- The source file that will be modified (if known)
- Any existing test file content (so the agent appends, not overwrites)

The RED agent MUST:
1. Read the relevant source code to understand existing patterns
2. Write ONE failing test for this behavior
3. Run the test and verify it FAILS (not errors)
4. Report: test file, test name, the failure output

**If test passes:** RED agent failed. Tell it to fix — the test must fail because the feature doesn't exist.

**If test errors:** RED agent must fix the error (typo, import issue) and re-verify failure.

**Parallel optimization (optional):** If multiple behaviors target different source files AND different test files (zero overlap), dispatch those RED agents in the same response. They run concurrently. Never parallel-dispatch agents that would edit the same file.

### Step 3: For each behavior — GREEN agent

Dispatch a `general` subagent with the GREEN agent prompt (`references/green-agent-prompt.md`).

Provide ONLY:
- The test file content (or path to read)
- The test failure output from the RED agent
- The source file path to modify
- The test command
- Project language/framework context

**CRITICAL: Do NOT pass any conversation context, reasoning, or intent.** The GREEN agent must work purely from the test and error output. It must discover what the test wants by reading it.

The GREEN agent MUST:
1. Read the test file to understand what's being asked
2. Read the source file to understand the existing code
3. Write MINIMAL code to make the test pass
4. Run the test and verify it PASSES
5. Run the full test suite and verify no regressions
6. Report: what was changed, test output

**If test still fails:** GREEN agent must fix and re-verify.

**If other tests break:** GREEN agent must fix regressions.

**Parallel optimization (optional):** If the corresponding RED agents ran in parallel and the behaviors touch different source files, dispatch those GREEN agents in the same response. Same constraint: never parallel-edit the same file.

### Step 4: Orchestrator verify

After GREEN agent reports success, independently verify:

1. **Review GREEN agent's report** — check file:line changes match what the test requires
2. **Check for conflicts** — did the GREEN agent modify anything outside the expected source file?
3. **Run full test suite yourself** — do NOT trust the agent's report alone
```bash
{test command}
```
4. **Spot check the code** — read the changed lines. Is it minimal? Does it match existing patterns?
5. **If anything is off** — either fix directly (small) or restart the cycle (large)

### Step 5: Refactor

After the cycle passes:
- Remove duplication between cycles
- Improve names
- Extract helpers

Run full test suite after each refactor step. Stay green.

### Repeat

Next behavior → next RED agent → next GREEN agent → refactor.

### Step 6: Final verification

After all cycles complete and final refactor is done:
- [ ] Every new function/method has a test
- [ ] Full test suite passes
- [ ] Each test failed before its implementation existed
- [ ] No dead code, no premature abstraction
- [ ] Commit or report completion

## Constraints

### MUST DO
- Break task into testable behaviors and get user approval
- Fresh subagent pair per cycle — never reuse RED or GREEN agent
- GREEN agent receives only: test file, failure output, source file path, test command
- Verify full suite passes after each cycle
- Run refactor with full suite verification

### MUST NOT DO
- Pass conversation context from RED to GREEN agent
- Implement code in the orchestrator (that's the GREEN agent's job)
- Skip the RED verification step
- Let a GREEN agent see how the test was designed
- Proceed to next behavior while current cycle has failures
- Reuse a subagent across cycles

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| **Behavior too broad** — "validates email" instead of "rejects empty email" | One assertion per behavior. Split anything with "and" in the name. |
| **Context leak** — GREEN agent received conversation history or intent notes | GREEN agent gets ONLY: test file path, failure output, source file path, test command. Nothing else. |
| **GREEN over-implements** — added options, abstractions, or "future-proofing" | Restart cycle. GREEN must write minimal code. |
| **Skipping full suite verification** — GREEN agent only ran the one test | Restart cycle. Run full suite yourself as orchestrator. |
| **Reusing a subagent** — same RED or GREEN agent across cycles | Fresh subagent every cycle. Zero shared context. |
| **Orchestrator writes code** — you implement instead of dispatching GREEN | Stop. Dispatch GREEN agent. That's its job. |
| **Behaviors touch same code, run in parallel** — two agents edit same file | Sequential only when file conflict. Parallel only for disjoint files. |

## When NOT to Use (ask your human partner)

- Behaviors are deeply coupled — changing one changes all
- Exploring unfamiliar code — need to understand before testing
- All behaviors modify the same single function (sequential is fine, just can't parallelize)

## Files

- `SKILL.md` — this file (orchestrator workflow)
- `references/red-agent-prompt.md` — RED subagent prompt template
- `references/green-agent-prompt.md` — GREEN subagent prompt template

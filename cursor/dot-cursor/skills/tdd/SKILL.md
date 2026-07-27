---
name: test-driven-development
description: Use when implementing any feature or bugfix, before writing implementation code
---

# Test-Driven Development — Agent Swarm

## Cursor harness

This copy runs in Cursor Agent. Map Claude Code terms as follows:

| Claude Code | Cursor |
|---|---|
| `Agent` tool | `Task` tool (`subagent_type: generalPurpose`) |
| `run_in_background: true` | `run_in_background: true` on `Task` |
| `isolation: "worktree"` | `git worktree add` + `--workspace <worktree>` (see Isolation) |
| `model: opus` | Cursor picks the model; drop the override |

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

### Step 1.5: Group behaviors into parallel batches

Two agents editing one working tree corrupt each other. Grouping is what makes
parallelism safe, so do it before dispatching anything.

For each behavior, write down the **file set** it will touch: its test file and
its source file.

- Behaviors whose file sets are **disjoint** → same batch, run concurrently.
- Behaviors whose file sets **overlap** → different batches, run sequentially.
- When in doubt, serialize. A wrong parallel run costs more than a slow one.

Write the batches to `.tdd/state.md` (create it) as a checklist:

```markdown
# Goal: <one line>
Test command: <cmd>

## Batch 1 (parallel)
- [ ] B1: rejects empty email — tests/test_signup.py :: src/signup.py
- [ ] B2: trims whitespace on name — tests/test_profile.py :: src/profile.py

## Batch 2 (sequential — both touch src/signup.py)
- [ ] B3: rejects invalid format — tests/test_signup.py :: src/signup.py
```

This file is the **only durable state**. Every ralph iteration re-reads it.
Update the checkboxes as batches land. If you crash, resume from this file.

**Isolation.** If a batch has more than one behavior, give each behavior's
agents their own git worktree — create one before dispatching:

```bash
git worktree add /tmp/tdd-wt-<slug> HEAD
```

Then pass `--workspace /tmp/tdd-wt-<slug>` to `agent -p --trust -f` for that behavior's
agents. A worktree is a second checkout of the same repo on its own branch, so
concurrent edits cannot collide. Merge the worktrees back yourself, one at a
time, running the full suite after each merge. Single-behavior batches run in
the main tree.

### Executor model

RED and GREEN subagents (and any other per-cycle executor the orchestrator
spawns) inherit the session model. Cursor has no per-call model flag, so state the
intended depth in the executor prompt instead. The
orchestrator itself stays on the session's model. Do not let executors silently
inherit the parent model.

### Ralph loops

Each agent runs in a **ralph loop**: a bounded retry where every attempt is a
*brand-new* subagent given the same prompt plus the current file state. Never
reuse a failed agent's session to "try again" — that preserves the confused
context you are trying to discard. Spawn a fresh one via a new `Task` or
`Task` call.

```
attempt = 1
while attempt <= MAX and not success_condition():
    spawn fresh agent (same prompt, current files)
    attempt += 1
```

| Agent | Success condition | MAX |
|---|---|---|
| RED (validator) | named test exists and **fails for the right reason** | 3 |
| GREEN (builder) | named test passes **and** full suite green **and** no test file touched | 5 |

On exhausting MAX: **stop the batch and report to the user.** Do not lower the
bar, do not skip the behavior, do not mark it done. A ralph loop that cannot
converge is telling you the behavior is mis-specified — that is signal, not a
failure to route around.

Each iteration costs a cold start. That is the price of discarding a poisoned
context, and it is usually worth paying.

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

**Every GREEN prompt must carry this clause verbatim:**

> The test file is read-only. You may not edit, delete, rename, skip, or
> `xfail` any test, and you may not weaken an assertion. If you believe the
> test is wrong, stop immediately and report why — that is a valid and useful
> outcome. Making the test pass by changing the test is a failed run.

Also forbid the other cheat: hardcoding the expected value so the one test
passes while the behavior does not exist. The orchestrator catches this in
Step 4 by reading the diff, so say plainly that it will be caught.

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

**Never trust a GREEN agent's self-report.** The cheapest way to make a failing
test pass is to change the test, and a builder under pressure will find it.
Check mechanically before you read anything the agent wrote.

**Gate 0 — the builder did not touch the test.** Run this first. It is the only
check that cannot be talked around:

```bash
git diff --name-only HEAD -- '<test path glob>'   # MUST be empty
```

Non-empty means the builder edited, deleted, skipped, or `xfail`-ed a test.
That run is void: `git checkout -- <test path>`, discard the agent, and respawn
a fresh one with the violation named in its prompt. Do not "just review" the
change. Do not let it stand because the diff looks reasonable.

Also confirm the test is still *run*, not merely present — a `@skip`, a renamed
test function, or an early `return` all leave the file diff clean in spirit but
neuter the check:

```bash
{test command} -k '<test name>'    # must execute and pass, not report "skipped"
```

Then verify the rest:

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

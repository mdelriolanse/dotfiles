---
name: goal
description: Triage a task and route it — one-shot for trivial changes, the tdd swarm for anything that changes behavior. Use when the user types /goal, or hands over a task without saying how it should be done.
---

# goal

Turn a request into a verifiable goal, then route it down the cheapest path
that actually proves the work. Do not start coding before Step 1 is written.

## Step 1: State the goal as a check

Rewrite the request as a condition that can pass or fail. If you cannot, the
request is underspecified — say what's missing and ask.

| Request | Goal |
|---|---|
| "add validation" | a test for each invalid input fails now, passes after |
| "fix the bug" | a test reproducing the bug fails now, passes after |
| "refactor X" | full suite green before and after; behavior byte-identical |
| "bump the timeout" | config reads 30s; nothing else changed |

Say the goal out loud in one line before doing anything.

## Step 2: Route

Answer one question: **does this change runtime behavior?**

### One-shot — only for these

- Typos, comments, docs, formatting.
- A config value, constant, or dependency version.
- Deleting code you have proven is dead.
- Reverting a known-bad commit.
- A change fully covered by an existing test you can point to by name.

Nothing else qualifies. "It's a one-liner" is not a category — one-line changes
to behavior are where bugs live.

Path: make the change → invoke the `verify` skill to drive the affected flow
end-to-end → report. If `verify` finds nothing to drive (docs, config with no
runtime surface), say so plainly instead of claiming it passed.

### TDD — everything else

Any change to product source that alters what the code *does*. New features,
bug fixes, behavior changes, anything you cannot name an existing test for.

Path: invoke the `tdd` skill and hand it the goal from Step 1. It handles
behavior decomposition, batch grouping, worktree isolation, the RED/GREEN
agents, and the ralph loops. Do not reimplement any of that here.

### Ambiguous — ask

If the request is one word ("optimize", "clean this up") or the goal in Step 1
has more than one plausible reading, stop and ask. One question, not four.

## Step 3: Escalate on failure, never retry blind

A one-shot that fails its `verify` check has told you it was mis-triaged. Do
not patch and re-run. Revert the change, and re-route it through `tdd` with
the failure as the first behavior to test.

Escalating is cheap. A one-shot that "worked" on the third guess is a bug
waiting for production.

## Step 4: Report

One line on what changed, one on how you know it works. Name the check that
proves it — the test, the command, the flow you drove. "Tests pass" is not a
check unless you say which test and that you watched it fail first.

## Rules

- **The route is chosen once, before coding.** Choosing after you've written
  the patch is rationalization, not triage.
- **When the two paths tie, take TDD.** The cost of an unnecessary test is one
  test. The cost of an untested behavior change is unbounded.
- **Never route to one-shot because the user seems in a hurry.** Say the change
  needs a test and why; they can override.

---
name: bg-subagent
description: Launch a subagent in the background (non-blocking) with an optional model override. Use when the user types /bg-subagent, or asks to run work in the background, kick something off in parallel, or dispatch an agent without waiting on it.
disable-model-invocation: true
---

# bg-subagent

Launch one background subagent and **return control immediately**. Never block.

## omp harness

This copy runs in omp (Oh My Pi). Map Claude Code terms as follows:

| Claude Code | omp |
|---|---|
| `Agent` tool | `omp -p` (shell-backgrounded with `&`) |
| `run_in_background: true` | `omp -p --no-session ... &` (then `wait $!`) |
| `model: opus` | `omp -p --model glm-5-2-nvfp4:high` |
| `subagent_type: general-purpose` | (default; omp print mode uses the default agent) |
| `isolation: "worktree"` | `git worktree add` (manual, see below) |
| harness re-invokes you when done | `wait $PID` (blocks until process exits) |

## Invocation

```
/bg-subagent <task prompt>
/bg-subagent <task prompt> --model glm-5-2-nvfp4:high
/bg-subagent <task prompt> --worktree
```

Everything before the first `--flag` is the task prompt. Flags are optional and
may appear in any order.

| Flag | Default | Meaning |
|---|---|---|
| `--model` | `glm-5-2-nvfp4:high` | Model for the subagent (with thinking suffix). |

## What to do

1. **Parse** the task prompt and flags. If the prompt is empty, ask for it — do
   not invent one.

2. **Build the command.** Expand the task prompt into a self-contained brief.
   The subagent starts cold: it sees none of this conversation. Restate the
   repo, the relevant paths, the success criterion, and what to return.

   ```bash
   CMD="omp -p --no-session --cwd \"$PWD\""
   # --model
   CMD="$CMD --model \"$MODEL_ID\""
   # the prompt (quoted)
   CMD="$CMD \"$TASK_BRIEF\""
   ```

   If `--worktree` was given, create one **before** launching:

   ```bash
   WT=$(mktemp -d -p /tmp worktree-bg-XXXXXX)
  git worktree add "$WT" HEAD
  CMD="omp -p --no-session --cwd \"$WT\" ..."
   ```

   The worktree is cleaned up after the task completes — `git worktree remove
   "$WT"` once you've read the result.

3. **Launch and return.** Run the command in the background and capture the PID:

   ```bash
   $CMD > /tmp/bg-subagent-<slug>.out 2>&1 &
   PID=$!
   ```

   Report in one line and stop:

   ```
   Launched: <task, 6 words> on <model> (PID $PID). Running in background.
   ```

4. **Waiting.** Unlike Claude Code's harness callback, you must explicitly `wait`
   on the PID when you need the result. The harness does not auto-notify you.

   - To **fire-and-forget** (the default for this skill): do not `wait`. Continue
     with other work. When the user asks for the result, `wait $PID` and read
     the output file.
   - To **collect the result later**: `wait $PID; cat /tmp/bg-subagent-<slug>.out`.
   - **Never read the output file before `wait` returns** — it may be mid-write.

## Rules

- **One launch, no wait.** If the user wants three agents, they invoke this three
  times, or you make three `omp -p --no-session &` calls in a single block — still all
  background. Parallel calls go in one message.
- **Never spawn a background agent to do something you can do in two tool
  calls.** A cold agent re-derives context you already hold; that is the
  expensive path. Background agents pay off for wide research sweeps, long
  builds, and anything that would otherwise stall the conversation.
- **`--worktree` whenever the agent writes code** and another agent might touch
  the same files. Two agents editing one working tree corrupt each other's
  edits. Read-only research agents don't need it.
- When the agent completes, relay what matters. Its stdout comes back when you
  `wait $PID` and read the output file — the user never sees it unless you relay
  it.

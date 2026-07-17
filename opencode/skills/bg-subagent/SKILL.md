---
name: bg-subagent
description: Launch a subagent in the background (non-blocking) with an optional model override. Use when the user types /bg-subagent, or asks to run work in the background, kick something off in parallel, or dispatch an agent without waiting on it.
disable-model-invocation: true
---

# bg-subagent

Launch one background subagent and **return control immediately**. Never block.

## opencode harness

This copy runs in OpenCode. Map Claude Code terms as follows:

| Claude Code | opencode |
|---|---|
| `Agent` tool | `opencode run` (shell-backgrounded with `&`) |
| `run_in_background: true` | `opencode run --auto ... &` (then `wait $!`) |
| `model: opus` | `opencode run -m anthropic/claude-opus-4-8` |
| `subagent_type: general-purpose` | `opencode run --agent general` |
| `isolation: "worktree"` | `git worktree add` (manual, see below) |
| harness re-invokes you when done | `wait $PID` (blocks until process exits) |

## Invocation

```
/bg-subagent <task prompt>
/bg-subagent <task prompt> --model opus|sonnet|haiku|fable
/bg-subagent <task prompt> --agent <agent-type>
/bg-subagent <task prompt> --worktree
```

Everything before the first `--flag` is the task prompt. Flags are optional and
may appear in any order.

| Flag | Default | Meaning |
|---|---|---|
| `--model` | inherit from parent | Model for the subagent. |
| `--agent` | `general` | Agent type. Must exist in the available-agent list. |
| `--worktree` | off | Give the agent its own git worktree, isolating its edits. |

## What to do

1. **Parse** the task prompt and flags. If the prompt is empty, ask for it — do
   not invent one.

2. **Validate `--agent`** against the available agent types in context. If the
   named type does not exist, say so and list what does. Do not silently
   substitute.

3. **Build the command.** Expand the task prompt into a self-contained brief.
   The subagent starts cold: it sees none of this conversation. Restate the
   repo, the relevant paths, the success criterion, and what to return.

   ```bash
   CMD="opencode run --auto --dir \"$PWD\""
   # --model
   CMD="$CMD -m \"$MODEL_ID\""
   # --agent
   CMD="$CMD --agent \"$AGENT_TYPE\""
   # the prompt (quoted)
   CMD="$CMD \"$TASK_BRIEF\""
   ```

   If `--worktree` was given, create one **before** launching:

   ```bash
   WT=$(mktemp -d -p /tmp worktree-bg-XXXXXX)
   git worktree add "$WT" HEAD
   CMD="opencode run --auto --dir \"$WT\" ..."
   ```

   The worktree is cleaned up after the task completes — `git worktree remove
   "$WT"` once you've read the result.

4. **Launch and return.** Run the command in the background and capture the PID:

   ```bash
   $CMD > /tmp/bg-subagent-<slug>.out 2>&1 &
   PID=$!
   ```

   Report in one line and stop:

   ```
   Launched: <task, 6 words> on <model> (PID $PID). Running in background.
   ```

5. **Waiting.** Unlike Claude Code's harness callback, you must explicitly `wait`
   on the PID when you need the result. The harness does not auto-notify you.

   - To **fire-and-forget** (the default for this skill): do not `wait`. Continue
     with other work. When the user asks for the result, `wait $PID` and read
     the output file.
   - To **collect the result later**: `wait $PID; cat /tmp/bg-subagent-<slug>.out`.
   - **Never read the output file before `wait` returns** — it may be mid-write.

## Rules

- **One launch, no wait.** If the user wants three agents, they invoke this three
  times, or you make three `opencode run &` calls in a single block — still all
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

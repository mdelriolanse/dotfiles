---
name: bg-subagent
description: Launch a subagent in the background (non-blocking) with an optional model override. Use when the user types /bg-subagent, or asks to run work in the background, kick something off in parallel, or dispatch an agent without waiting on it.
---

# bg-subagent

Launch one background subagent and **return control immediately**. Never block.

## Invocation

```
/bg-subagent <task prompt>
/bg-subagent <task prompt> --model opus|sonnet|haiku|fable
/bg-subagent <task prompt> --agent <subagent_type>
/bg-subagent <task prompt> --worktree
```

Everything before the first `--flag` is the task prompt. Flags are optional and
may appear in any order.

| Flag | Default | Meaning |
|---|---|---|
| `--model` | inherit from parent | Model for the subagent. |
| `--agent` | `general-purpose` | Subagent type. Must exist in the available-agent list. |
| `--worktree` | off | Give the agent its own git worktree, isolating its edits. |

## What to do

1. **Parse** the task prompt and flags. If the prompt is empty, ask for it — do
   not invent one.

2. **Validate `--agent`** against the available agent types in context. If the
   named type does not exist, say so and list what does. Do not silently
   substitute.

3. **Call `Agent`** exactly once:

   - `prompt` — the task, expanded into a self-contained brief. The subagent
     starts cold: it sees none of this conversation. Restate the repo, the
     relevant paths, the success criterion, and what to return.
   - `run_in_background: true` — **always**. This is the entire point of the
     skill. Never pass `false`, never omit it.
   - `model` — only if `--model` was given.
   - `subagent_type` — from `--agent`, else `general-purpose`.
   - `isolation: "worktree"` — only if `--worktree` was given.
   - `description` — 3–5 words.

4. **Report in one line and stop.** Name the task and the model. Then continue
   with whatever else is in flight, or hand control back.

   ```
   Launched: <task, 6 words> on <model>. Running in background.
   ```

5. **Do not poll.** The harness re-invokes you when the agent finishes. Never
   `sleep`, never loop, never read the agent's output file — that file is the
   raw JSONL transcript and reading it will overflow your context.

## Rules

- **One call, no wait.** If the user wants three agents, they invoke this three
  times, or you make three `Agent` calls in a single block — still all
  background. Parallel calls go in one message.
- **Never spawn a background agent to do something you can do in two tool
  calls.** A cold agent re-derives context you already hold; that is the
  expensive path. Background agents pay off for wide research sweeps, long
  builds, and anything that would otherwise stall the conversation.
- **`--worktree` whenever the agent writes code** and another agent might touch
  the same files. Two agents editing one working tree corrupt each other's
  edits. Read-only research agents don't need it.
- When the agent completes, relay what matters. Its final message comes back to
  you as a tool result and the user never sees it.

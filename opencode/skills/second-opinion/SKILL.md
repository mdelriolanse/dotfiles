---
name: second-opinion
description: Launch several background research agents to deliberate on what the user and I are currently debating, then return one synthesized second opinion with alternatives, a recommendation, and any preserved dissent. Use when the user types /second-opinion, or asks for outside perspective on a decision in the current conversation.
disable-model-invocation: true
---

# second-opinion

The user is mid-discussion with you and wants outside judgment. Launch N
researchers, let them deliberate on a shared canvas, and return one opinion that
preserves genuine disagreement instead of flattening it.

You are the orchestrator. **You do not vote.** Your position is the thing under
review — do not defend it, do not seed it, do not let it leak into the framing.

## opencode harness

This copy runs in OpenCode. Map Claude Code terms as follows:

| Claude Code | opencode |
|---|---|
| `Agent` tool + `run_in_background: true` | `opencode run --auto &` (then `wait`) |
| `model: opus` | `opencode run -m anthropic/claude-opus-4-8` |
| `subagent_type: general-purpose` | `opencode run --agent general` |
| harness re-invokes you when done | `wait` on all PIDs |
| scratchpad run-dir | `mktemp -d` (canvas) |

## Invocation

```
/second-opinion                # N = 3
/second-opinion --number 5     # N = 5
```

Clamp N to **2..6**. Below 2 there is no second opinion; above 6 the synthesis
degrades and cost climbs for nothing.

Model is **`opus`** (`anthropic/claude-opus-4-8`) for every agent. Effort is
inherited from the session — `opencode run` inherits the session's variant
unless overridden by `--variant`.

## Step 1: Build the canvas

```bash
canvas=$(mktemp -d -p /tmp debate-XXXXXX)
mkdir -p "$canvas/positions" "$canvas/critiques" "$canvas/done"
```

Write `$canvas/CONTEXT.md` yourself. This is the only thing every agent reads
first, and it decides whether the exercise is worth anything. It contains:

- **The question**, stated neutrally. Not "is my approach good?" — "should X be
  done by A or B, given C?"
- **The constraints that are real**: the stack, the deadline, what already
  shipped, what the user has ruled out and why.
- **Both positions so far**, stated fairly. If the user and I disagree, write
  the user's position at its strongest, and mine at its strongest. Steelman
  both. An agent that reads a strawman will demolish it and tell you nothing.
- **What is out of scope.** Decisions already made and not reopening.

Do not write your recommendation into `CONTEXT.md`. Do not hint at one.

Then enumerate the **distinct routes** worth investigating — the genuinely
different answers, not variations on one. Assign one route to each agent as its
**primary** angle. This is the anti-duplication mechanism: without it, N agents
research the same obvious path N times and return one opinion wearing N hats.

An agent may conclude its assigned route is wrong. That is a useful result, and
it must say so rather than defending an assignment.

## Step 2: Phase one — sealed positions

Launch all N agents in **one Bash block**, all backgrounded with `&`. Each gets
its own `opencode run` process:

```bash
for i in $(seq 1 "$N"); do
  opencode run --auto --dir "$PWD" -m anthropic/claude-opus-4-8 --agent general \
    "$(cat "$canvas/phase1-prompt-$i.md")" \
    > "$canvas/phase1-$i.out" 2>"$canvas/phase1-$i.err" &
  PIDS[$i]=$!
done
```

Each prompt contains `CONTEXT.md`, that agent's assigned route, and:

> **Write before you read.** Investigate your assigned route and write your
> opening position to `$canvas/positions/agent-<i>.md`. Until that file exists,
> you may not open any other file in `positions/`. This is not a formality —
> reading first makes you agree with whoever wrote first, and then we have paid
> for one opinion N times.
>
> **Research, don't recall.** Use WebSearch and WebFetch. Look for current
> industry practice, recent releases, benchmarks, postmortems, and what teams
> solving this problem actually chose. Cite what you find with URLs. Distinguish
> what you verified from what you are asserting from memory. If the current
> best practice contradicts what CONTEXT.md assumes, say so plainly.
>
> **Your position must contain:** the route as you now understand it, what it
> costs, what it forecloses, the strongest argument against it, and the
> condition under which you would abandon it.
>
> Then signal completion by creating `$canvas/done/agent-<i>`.

After launching all N, `wait` on every PID:

```bash
for i in $(seq 1 "$N"); do
  wait "${PIDS[$i]}" || echo "agent $i exited non-zero"
done
```

Sealed writing is what buys you diversity. Everything after this step is
refinement; nothing after this step can recover a perspective that was never
written down.

## Step 3: Phase two — open critique

Once every agent has completed, launch N fresh `opencode run` processes — one per
position, each told which position it now owns.

```bash
for i in $(seq 1 "$N"); do
  opencode run --auto --dir "$PWD" -m anthropic/claude-opus-4-8 --agent general \
    "$(cat "$canvas/phase2-prompt-$i.md")" \
    > "$canvas/phase2-$i.out" 2>"$canvas/phase2-$i.err" &
  PIDS2[$i]=$!
done

for i in $(seq 1 "$N"); do
  wait "${PIDS2[$i]}" || echo "critique agent $i exited non-zero"
done
```

Each prompt:

> Read every file in `$canvas/positions/`. Then, for the position you own:
>
> **Steelman before you strike.** For each position you disagree with, first
> write the best version of its argument, in its author's terms, well enough
> that its author would accept your summary. Then say where it fails.
>
> **Civility is a requirement, not a tone.** Attack reasoning, never the
> reasoner. No "obviously," no "clearly," no dismissal without a stated reason.
> A position you cannot restate fairly is one you have not understood.
>
> **You may change your mind. You may not converge to be agreeable.** If you
> still disagree after reading the others, say so and say exactly why. A
> preserved, well-argued dissent is worth more than unanimity. If you converge,
> name the specific argument that moved you.
>
> Write to `$canvas/critiques/agent-<i>.md`.

Fresh agents, not the originals. An agent asked to critique its own prior work
defends it.

## Step 4: Synthesize

Read `positions/` and `critiques/` yourself. Write the answer. Do not delegate
this — a synthesizer agent will pick a winner and bury the minority.

The user never opens the canvas. Everything they need is in your reply.

## The reply

Obey the standing return rules. They are not optional here.

- **≤4 sentences of prose TOTAL**, across the entire reply — not per section.
  Six agents deliberating does not entitle you to six paragraphs. The tables
  carry the detail; prose carries only what a table cannot.
- **Never introduce a term without explaining it in the same sentence**, and
  never explain one term with another undefined term. If the agents came back
  with jargon, translate it. Passing their vocabulary through unexplained is
  the failure mode this skill exists to avoid.
- Say what breaks, not what category it belongs to.
- No preamble, no narration of the deliberation, no "the debate did not go
  where either of us expected." Lead with the recommendation.

Structure:

**Alternatives** — one row per route that survived. Columns: route, what it
costs, what it forecloses, who backed it.

**Recommendation** — one route, with the reason it wins over the runner-up
specifically. Not "it's the best" — "it beats B because B requires X, which you
ruled out."

**Dissent** — every position that survived critique and still disagrees, stated
in its own strongest form and attributed. **Never omit this section.** If the
agents genuinely reached consensus, say "no dissent survived" and say what would
have produced one. Unanimity that appears without explanation is a signal the
canvas herded.

**What would change the answer** — the fact that, if untrue, flips the
recommendation. If you cannot name one, the recommendation is not yet a
recommendation.

**Sources** — URLs the agents actually fetched, marked as verified or asserted.

## Rules

- **Do not poll.** `wait` on all PIDs — do not `sleep` or read output files
  before `wait` returns (they may be mid-write).
- **Never let the canvas into the reply.** The user said they will not read it.
  Do not paste it, summarize it phase by phase, or narrate the deliberation.
- **The agents research; they do not edit.** They read, they search the web,
  they write to `$canvas`. They touch nothing in the repository.
- **If every agent agrees immediately, be suspicious.** Either the question was
  not a real question, or `CONTEXT.md` leaked your answer. Say which.

## Honest limit

A shared canvas is deliberation, and deliberation is not the architecture with
the best measured track record — multi-agent debate does not reliably beat N
independent samples, and its reported gains move with how hard you tune the
agents toward agreement. The sealed first phase exists to recover most of what
independence buys. For a task with one right answer that you want *found* rather
than *argued*, use `/best-of-n` instead: independent attempts, blinded judge.
`/second-opinion` is for decisions where the disagreement is the point.

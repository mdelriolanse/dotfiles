---
name: best-of-n
description: Run a task N times in parallel background agents, then rank the results with a blinded judge agent. Use when the user types /best-of-n, or wants several independent attempts at one task compared against each other.
---

# best-of-n

## Cursor harness

This copy runs in Cursor Agent. Map Claude Code terms as follows:

| Claude Code | Cursor |
|---|---|
| `Agent` tool | `Task` tool |
| `run_in_background: true` | `run_in_background: true` on `Task` |
| `model: opus` | Cursor picks the model; drop the override or set it in the Task prompt |
| `claude -p "/best-of-n …"` fan-out | `agent -p --trust -f "/best-of-n …"` |

Spawn N independent background agents on the **same** task, wait, then have a
blinded judge rank their outputs into a standard table.

This is best-of-N sampling: N independent attempts, one judge. It is the
architecture with the strongest evidence behind it — aggregating independent
passes of one strong model beats splitting a task across role-specialized
agents. Independence is the whole mechanism. Do not let the workers see each
other's output, and do not let them see each other's existence.

## Invocation

```
/best-of-n <task description>
/best-of-n 5 <task description>
/best-of-n 5 --model sonnet <task description>
```

- Leading integer = N. Default **3**. Clamp to **2..8** — refuse above 8 and say
  why (cost scales linearly, judge quality degrades past ~6 candidates).
- `--model` overrides the worker model. Default **`opus`**.
- Everything else is the task. Pass it through *verbatim*; do not paraphrase.

**Effort is not settable per agent.** The `Agent` tool takes `model` but no
effort parameter — workers inherit the session's `effortLevel`. If the user asks
for "high effort," confirm their session is set to it rather than pretending you
applied it.

## Procedure

### 1. Set up

Create a run directory under the session scratchpad:

```
<scratchpad>/best-of-n/<slug>/
```

Write `TASK.md` there containing the task description verbatim. This is the
single source of truth that both workers and judge read.

### 2. Spawn N workers — one message, N `Agent` calls

All N calls go in a **single response block** so they run concurrently.

Each call:
- `subagent_type: "general-purpose"`
- `model`: from `--model`, default `opus`
- `run_in_background: true` — always
- `isolation: "worktree"` **if the task writes code.** N agents editing one
  working tree will corrupt each other. Read-only or prose tasks skip this.
- `description`: 3–5 words
- `prompt`: the **identical** brief for every worker. It must contain:
  - the verbatim task from `TASK.md`
  - the repo path and any files that matter (workers start cold — they see
    none of this conversation)
  - the success criterion
  - `Write your complete answer to <run-dir>/candidate-<i>.md. That file is
    your deliverable. Return a two-sentence summary, nothing more.`
  - `You are working independently. Do not look for, read, or reference any
    other candidate file in this directory.`

Vary **nothing** between workers except `i`. Same prompt, same model, same
context. Any difference makes the comparison meaningless.

### 3. Monitor — do not poll

Say one line: `Launched N workers on <model>. Waiting.` Then stop.

The harness re-invokes you when each agent finishes. Never `sleep`, never loop,
never read the agents' `.output` files — those are raw JSONL transcripts and
reading one will overflow your context.

If a worker fails or returns nothing, note it and proceed with the survivors.
Judge on however many landed; state how many.

### 4. Blind the candidates

Before the judge sees anything:

1. **Shuffle** the candidate files into a random order.
2. **Relabel** them `A`, `B`, `C`, … — stripping the worker index.
3. Keep the mapping (`A → candidate-3`) **only in your own context**. Never
   write it into the judge's prompt or the run directory.

Claude judging Claude has a measured self-preference bias, and judges also
favor longer and more authoritative-sounding answers regardless of correctness.
Blinding and shuffling cost nothing and remove the two easiest confounds
(identity, position). They do not remove verbosity bias — the judge rubric
below has to do that.

### 5. Spawn the judge

**One** `general-purpose` agent, `model: opus`, `run_in_background: true`. The
judge is cold: inject everything.

Judge prompt template:

```
You are ranking N independent attempts at one task. You did not write any of
them. Judge only what is in front of you.

## The task the candidates were given
<verbatim contents of TASK.md>

## Candidates
Read each of these files in full:
<run-dir>/A.md
<run-dir>/B.md
...

## Rubric — score each 1-5, independently

- Correctness — does it actually do the task? Would it work? Weight this
  above everything else combined.
- Completeness — does it cover the whole task, including edge cases?
- Simplicity — is it the least complex thing that works? Penalize speculative
  abstraction, unrequested features, and defensive code for impossible states.
- Evidence — are claims verified (tests run, output shown) or merely asserted?

Ignore length. A short answer that is correct beats a long one that is
correct. Ignore confident tone. Ignore formatting polish. If two candidates are
substantively identical, say so and rank them equal rather than inventing a
difference.

## Required output — this exact table, nothing before it

| Rank | Candidate | Correct | Complete | Simple | Evidence | Total | One-line verdict |
|------|-----------|---------|----------|--------|----------|-------|------------------|
| 1    | X         | 5       | 4        | 5      | 4        | 18    | ...              |

Then, under the table and nothing else:

**Winner:** <letter> — two sentences on why it won.
**Fatal flaws:** one bullet per candidate that has a correctness bug, naming
the specific defect. Write "none" if none.
**Disagreement:** if the top two are within 2 points, say what the real
tradeoff between them is and what would break the tie.
```

### 6. Report

Un-blind and give the user the judge's table with real candidate numbers
restored, the winner's file path, and — if the top two were within 2 points —
the tradeoff the judge named. Do not paste all N candidates.

State the cost honestly: N workers + 1 judge.

## When not to use this

- **The task has one obvious right answer.** N agents will produce N identical
  answers and you will have paid N times for one. Best-of-N pays off on tasks
  with genuine solution diversity: design, naming, prose, tricky refactors,
  ambiguous specs.
- **The task is cheap.** If you could do it in two tool calls, do it in two
  tool calls.
- **You need a *correct* answer, not the *best-looking* one.** A judge ranks
  what it can read. Where a test or a compiler can decide, run it — an
  execution check beats any judge, and the judge should be given its output.

---
name: resolve-review
description: Act on a deep-review report — split its findings into trivial vs human-in-the-loop, dispatch the trivial ones to a background subagent, and surface the rest by priority with a recommended fix approach. Use when the user types /resolve-review, or wants to work through the FIX / SKIP NOW findings a deep-review produced.
disable-model-invocation: true
---

# resolve-review

Consumes the markdown report that `deep-review` Step 7 wrote to
`./docs/deep-review/<title>-<timestamp>.md` and turns its findings into action:
the mechanical ones get fixed by a background agent, the judgment calls get
handed back to the human with a recommendation.

- **HITL** — human-in-the-loop: a finding whose fix needs a human decision
  (semantics, a PRD/product trade-off, a security posture, a "decide and
  document" choice). It matters because dispatching these to an agent guesses at
  a call that is not the agent's to make.
- **trivial** — the opposite: one unambiguous mechanical fix with no decision
  attached (default a missing header, drain a body, bump a counter inside the
  claim). Safe to fix without a human in the loop.

## opencode harness

This copy runs in OpenCode. Map Claude Code terms as follows:

| Claude Code | opencode |
|---|---|
| `bg-subagent` skill (Agent + `run_in_background`) | `opencode run --auto &` (see Step 4) |
| `ponytail:ponytail` plugin skill | `ponytail` skill (ponytail plugin) |
| harness re-invokes you when bg agent finishes | `wait $PID` then read output file |

## Invoke

```
/resolve-review                     # both FIX and SKIP NOW (default)
/resolve-review only fix            # FIX findings only
/resolve-review only skip now       # SKIP NOW findings only
/resolve-review <path-to-report.md> # target a specific report; scope defaults to both
/resolve-review only fix <path>     # scope + explicit report
```

**Scope is not hardcoded.** Read the bucket headings that the report actually
contains (`FIX`, `SKIP NOW`, whatever `deep-review` emitted) and select findings
by them. With no scope words, process **both** FIX and SKIP NOW. `only fix` →
FIX only. `only skip now` → SKIP NOW only. The trivial/HITL split then happens
*only within the selected scope* — never pull in a bucket the user excluded.

## Step 1: Locate and read the report

If a path was given, use it. Otherwise take the newest file in
`./docs/deep-review/`:

```bash
ls -t ./docs/deep-review/*.md | head -1
```

If the directory is empty or missing, stop and say so — there is nothing to act
on. Run `deep-review` first.

Read the whole file. It is the exhaustive archive, so every finding you need is
already spelled out there with file:line and full rationale — you do not
re-review the code.

## Step 2: Select the in-scope findings

Extract the findings under the buckets the scope selected (Step "Invoke"). Keep
each finding's verbatim text — file:line, rationale, track/run agreement — intact;
you will feed it downstream unmodified.

## Step 3: Split each selected finding into trivial vs HITL

Judge every in-scope finding:

- **trivial** if the fix is one mechanical change with no decision — a missing
  `Content-Type`, an undrained socket, moving a counter inside an existing
  transaction, a bounded retry with an obvious bound.
- **HITL** if applying it commits to a choice: which of two PRD requirements
  wins, keep-vs-clear semantics, whether a by-design risk is acceptable, any
  "decide and document". A security / data-loss / money path defaults to HITL
  unless the fix is genuinely mechanical.

## Step 4: Dispatch the trivial findings to a background subagent

Launch **one** `opencode run` process to fix **all** trivial findings in one
pass. **Pull the task prompt directly from the report file** — quote each
trivial finding's own text verbatim (its file:line and rationale) as the agent's
brief, rather than paraphrasing. The report is self-contained; the cold agent
should read the same words the report gives.

The brief must also carry: the repo root, the instruction to make the smallest
correct change per finding and nothing adjacent, and to return a per-finding
summary of what it changed. If nothing is trivial, skip this step and say so.

```bash
# Write the brief to a file, then launch
BRIEF_FILE=$(mktemp -p /tmp resolve-review-brief-XXXXXX.md)
# ... write the brief to $BRIEF_FILE ...

opencode run --auto --dir "$PWD" "$(cat "$BRIEF_FILE")" \
  > /tmp/resolve-review-result.out 2>&1 &
PID=$!
echo "Launched: trivial fix agent (PID $PID) in background"
```

Do **not** `wait` immediately — proceed to Step 5 to surface HITL findings while
the agent works. `wait $PID` and read the result when the user asks or when
you've finished Step 5.

## Step 5: Surface the HITL findings by priority

For the human, list the HITL findings **ordered by priority** (data-loss and
security first, then correctness, then the rest — follow the report's own rank
where it gives one). For each, give more detail than the terse report line:
what breaks, the exact decision the human owns, and the options.

Then attach to each a **recommended solution approach through the ponytail
lens**: invoke the `ponytail` skill and, for each HITL finding, state the
laziest correct fix — the fewest-lines approach that holds, naming any ceiling.
Present it as a plain `Recommended:` line under the finding.

## Step 6: Report

- One line: which report was used, which scope, how many trivial vs HITL.
- "Launched: <trivial fix task> in background" (from Step 4), or "no trivial
  findings".
- The prioritized HITL list from Step 5, each with its `Recommended:` line.

When you `wait $PID` and the background agent has finished, relay what it
changed per finding — read `/tmp/resolve-review-result.out` and summarize the
per-finding changes to the user.

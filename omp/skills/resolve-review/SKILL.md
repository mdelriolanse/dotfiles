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

## omp harness

This copy runs in omp (Oh My Pi). Map Claude Code terms as follows:

| Claude Code | omp |
|---|---|
| `bg-subagent` skill (Agent + `run_in_background`) | `omp -p --no-session &` (see Step 5) |
| `ponytail:ponytail` plugin skill | `ponytail` skill (ponytail extension) |
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
already spelled out there with file:line and full rationale. But the report is a
*snapshot* — the working tree may have moved on. Step 2 verifies each finding
against the live code before you act on it.

## Step 2: Verify each finding against the working tree (staleness gate)

**Do this before the trivial/HITL split or any dispatch.** A report can be
stale even when its mtime is newer than `HEAD`: a fix commit can land *before*
the report is written and still be missed by the reviewer (this has happened).
Timestamp comparison is not a reliable gate; only a content check is.

For every in-scope finding that cites a `file:line` or a symbol, open that
location in the **current working tree at `HEAD`** (not uncommitted edits — a
concurrent resolve-review run may have just touched the file) and confirm the
defect the report describes is still present. Use `read` with offset/limit or
`grep`; do not dump whole files.

Classify each finding into one of three states:

- **OPEN** — the code at the cited location still reads as the report describes
  (the defect is real and unfixed). Carry forward to Step 3.
- **RESOLVED-PRE-DISPATCH** — the cited `file:line` now shows the fix the report
  asked for (e.g. the missing guard exists, the counter moved inside the txn,
  the 2xx-accept now requires 206). Drop from the trivial/HITL split; record it
  in the Step 7 report under a "Resolved before dispatch" line so the human can
  see what the tree already fixed. **Do not dispatch a fix.**
- **DRIFTED** — the file was rewritten, the symbol moved, or the `file:line`
  no longer matches but the defect may still exist elsewhere. Keep the finding
  but re-anchor: search for the symbol/condition the report names; if you cannot
  re-anchor, surface it to the human as `UNVERIFIABLE (code drifted)` rather than
  guessing.

Exceptions where the gate does not apply (the finding is not `file:line`-bound):

- A finding whose fix is a **commit SHA not yet in the local tree** (e.g. a
  remote-only fix commit on a stale worktree). Skip the gate; flag for the human
  in Step 7 so they fetch/verify manually.
- A finding that is purely a **decision** with no code anchor (e.g. a PRD
  trade-off, a "decide and document"). Carry forward to Step 4; the gate is a
  code check, not a judgement check.

If **every** in-scope finding is `RESOLVED-PRE-DISPATCH`, stop — say so, list
them, and do not dispatch or surface anything further.

## Step 3: Select the in-scope findings

Extract the **OPEN** and **DRIFTED** findings (Step 2 dropped the
`RESOLVED-PRE-DISPATCH` ones) under the buckets the scope selected (Step
"Invoke"). Keep each finding's verbatim text — file:line, rationale, track/run
agreement — intact; you will feed it downstream unmodified. For DRIFTED
findings, attach the re-anchored `file:line` you found.

## Step 4: Split each selected finding into trivial vs HITL

Judge every remaining in-scope finding:

- **trivial** if the fix is one mechanical change with no decision — a missing
  `Content-Type`, an undrained socket, moving a counter inside an existing
  transaction, a bounded retry with an obvious bound.
- **HITL** if applying it commits to a choice: which of two PRD requirements
  wins, keep-vs-clear semantics, whether a by-design risk is acceptable, any
  "decide and document". A security / data-loss / money path defaults to HITL
  unless the fix is genuinely mechanical.
- **RESOLVED-PRE-DISPATCH** findings are neither; they were dropped in Step 2.

## Step 5: Dispatch the trivial findings to a background subagent

Launch **one** `omp -p` process to fix **all** trivial findings in one
pass. **Pull the task prompt directly from the report file** — quote each
trivial finding's own text verbatim (its file:line and rationale) as the agent's
brief, rather than paraphrasing. The report is the source of the *claim*; the
Step 2 gate is the source of the *verification that the claim is still open*.
Both go in the brief: the verbatim finding, plus a one-line "verified still
open at <file:line> on HEAD <sha>" note so the cold agent does not re-litigate
the gate.

The brief must also carry: the repo root, the instruction to make the smallest
correct change per finding and nothing adjacent, and to return a per-finding
summary of what it changed. If nothing is trivial, skip this step and say so.

```bash
# Write the brief to a file, then launch
BRIEF_FILE=$(mktemp -p /tmp resolve-review-brief-XXXXXX.md)
# ... write the brief to $BRIEF_FILE ...

omp -p --no-session --cwd "$PWD" --model glm-5-2-nvfp4:high "$(cat "$BRIEF_FILE")" \
  > /tmp/resolve-review-result.out 2>&1 &
PID=$!
echo "Launched: trivial fix agent (PID $PID) in background"
```

Do **not** `wait` immediately — proceed to Step 6 to surface HITL findings while
the agent works. `wait $PID` and read the result when the user asks or when
you've finished Step 6.

## Step 6: Surface the HITL findings by priority

For the human, list the HITL findings **ordered by priority** (data-loss and
security first, then correctness, then the rest — follow the report's own rank
where it gives one). For each, give more detail than the terse report line:
what breaks, the exact decision the human owns, and the options.

Then attach to each a **recommended solution approach through the ponytail
lens**: invoke the `ponytail` skill and, for each HITL finding, state the
laziest correct fix — the fewest-lines approach that holds, naming any ceiling.
Present it as a plain `Recommended:` line under the finding.

## Step 7: Report

- One line: which report was used, which scope, how many trivial vs HITL.
- A "Resolved before dispatch" line listing any `RESOLVED-PRE-DISPATCH`
  findings (file:line + the one-line evidence the tree already fixes them), so
  the human sees what the gate caught.
- An "Unverifiable (code drifted)" line for any DRIFTED findings you could not
  re-anchor, and a "SHA-cited, manual verify needed" line for any commit-SHA
  findings the gate skipped.
- "Launched: <trivial fix task> in background" (from Step 5), or "no trivial
  findings".
- The prioritized HITL list from Step 6, each with its `Recommended:` line.

When you `wait $PID` and the background agent has finished, relay what it
changed per finding — read `/tmp/resolve-review-result.out` and summarize the
per-finding changes to the user.

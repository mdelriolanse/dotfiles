---
name: deep-review
description: Run the adamsreview pipeline, optionally in parallel with a built-in code-review pass and a PRD-conformance check, then merge the findings. Use when the user types /deep-review, or wants a thorough multi-track review rather than a single-pass diff read.
disable-model-invocation: true
---

# deep-review

Orchestrates up to three independent review tracks, waits for all of them, and
merges the results. Findings that two tracks found independently are the ones
worth reading first.

## Cursor harness

This copy runs in Cursor Agent. Map Claude Code terms as follows:

| Claude Code | Cursor |
|---|---|
| `Agent` tool | `Task` tool |
| `subagent_type: general-purpose` | `subagent_type: generalPurpose` |
| `run_in_background: true` | `run_in_background: true` on `Task` |
| `claude -p "/deep-review …"` fan-out | `agent -p --trust -f "/deep-review …"` |
| `/code-review max` skill | `code-reviewer` skill (`~/.cursor/skills/code-reviewer/`) |
| `ponytail:ponytail` plugin skill | `ponytail` skill (`~/.cursor/skills/ponytail/`) |
| `adamsreview` skill | `adamsreview` skill (`~/.cursor/skills/adamsreview/`) |

## Invoke

```
/deep-review                          # adamsreview only
/deep-review --extra                  # + code-reviewer, in parallel
/deep-review --prd docs/spec.md       # + PRD conformance track
/deep-review --prd 412                # PRD from GitHub issue #412
/deep-review 1234 --extra --prd 412   # review PR 1234, all three tracks
/deep-review -n 3 --extra             # run the whole skill 3x, cross-run merge
```

Two flags plus `-n`. `-n <k>` (k ≥ 2) is the ensemble knob: it runs this entire
skill k independent times and merges across the runs. See "Fan-out mode" below.
Without `-n`, everything else on this page is a single run.

**`adamsreview` always runs with `--full`.** Not a flag on this skill. `--full`
forces `trivial_mode=false`, so the pipeline never short-circuits a diff it
judges trivial. If you wanted the fast path you would not have typed
`/deep-review`.

**Never pass `--ensemble`.** It dispatches the Codex CLI plus a GitHub bot-comment
scrape — there is no Cursor path through it. Track B is the Cursor-native way to
get a second independent reviewer.

## The tracks

| Track | Runs where | When |
|---|---|---|
| **A — adamsreview** | main thread | always |
| **B — code-reviewer** | background subagent | `--extra` |
| **C — PRD conformance** | background subagent | `--prd` given |

**`adamsreview` cannot be backgrounded.** It uses interactive gates. It runs on
the main thread and fans out internally. Parallelism comes from putting B and C
in background subagents *first*, then starting A while they run.

## Fan-out mode (`-n <k>`)

`-n <k>` runs the *whole* skill k independent times and merges the results across
runs. A single deep-review is already an ensemble across tracks; `-n` stacks a
second ensemble on top — across full pipelines — because the adamsreview harness
is stochastic and a finding that k separate pipelines all surface is far likelier
real than one a single run raised.

This mode only exists at the top. A nested run must not re-fan-out (fork bomb),
so the guard is the `DEEP_REVIEW_INNER` env var: **if `DEEP_REVIEW_INNER` is set,
ignore `-n` entirely and run as a normal single review.**

### Step F1: Launch the k runs

Each run is a fresh **root** `agent` process (not a subagent — subagents cannot
spawn the pipeline's own agents; a new OS process can). Its final report is its
stdout, so redirect stdout straight into the run's file — no need to tell it to
write one.

Pick a shared absolute output dir the orchestrator owns — **not** the session
scratchpad, because each inner run has its own scratchpad. Use
`OUT=$(mktemp -d)`. Forward every flag *except* `-n`:

```bash
for i in $(seq 1 "$K"); do
  DEEP_REVIEW_INNER=1 agent -p --trust -f \
    "/deep-review $FORWARDED_FLAGS" \
    --workspace "$PWD" \
    > "$OUT/dr-$i.md" 2>"$OUT/dr-$i.err" &
done
wait   # returns only when all k roots have exited
echo "OUT=$OUT"
```

Run that whole block as **one backgrounded Shell call** (`block_until_ms: 0` or
enough headroom for k full pipelines). Process exit is the only reliable "done"
signal — a `dr-$i.md` file can exist mid-write, so gate on the `wait` returning,
never on the files appearing.

### Step F2: Merge across runs

You are notified when the backgrounded block exits. Then, **in this session**,
read `$OUT/dr-1.md … dr-k.md` and merge:

1. A run that produced an empty file or non-empty `dr-$i.err` **failed**. Say how
   many of k succeeded; never present a partial ensemble as full.
2. Deduplicate across runs exactly as Step 5 does across tracks: same file,
   overlapping lines, same underlying claim → one finding. Wording alone does not
   merge; two different bugs on one line stay two.
3. Rank by **run agreement**: a finding k-of-k runs raised outranks k−1, outranks
   a singleton. This is the Step 5 consensus signal, now across whole pipelines.
4. Write the merged list to `$OUT/merged.md`, then run the **Step 5b** ponytail
   triage on it exactly as the single-run path does.
5. Report per Step 6, but also lead with "k of K runs completed" and the
   agreement histogram before the FIX bucket.

## Step 1: Resolve the PRD, if given

A PRD is the document the build is supposed to satisfy. Resolve `--prd` to a
file at `<run-dir>/PRD.md`:

- **Path** (`docs/spec.md`) — read it.
- **Issue number** (`412`) — `gh issue view 412 --json title,body,comments`.
- **URL** — `gh api` the issue or fetch the document.

If it resolves to nothing, **stop and say so.** Do not review against a PRD you
could not read; silently skipping it is worse than not asking for it.

## Step 2: Launch background tracks — before starting adamsreview

Both `Task` calls go in **one response block**, both `run_in_background: true`.
Launch them first so they run while track A works.

**Track B — code-reviewer.** `subagent_type: generalPurpose`.

> Read and follow the `code-reviewer` skill on <target>. Write every finding to
> `<run-dir>/track-b.json` as `[{"file","line","severity","claim","confidence"}]`.
> Return only a count.
>
> If you cannot invoke the `code-reviewer` skill, say so explicitly in your return
> message and instead review the diff directly for correctness bugs at the same
> depth. Label the file `"source": "fallback"` so the orchestrator knows.
>
> [if PRD] The change is supposed to satisfy the requirements in
> `<run-dir>/PRD.md`. Read it. Flag code that contradicts it.

**Track C — PRD conformance.** Only when `--prd` was given. Same settings.

> Read `<run-dir>/PRD.md`, then read the diff under review and the current state
> of the feature branch. Answer one question per requirement: **is it built?**
>
> For each requirement emit one entry to `<run-dir>/track-c.json`:
> `{"requirement", "status": "met|partial|missing|contradicted", "evidence", "where"}`
>
> - `met` — point at the file and line that implements it.
> - `partial` — say exactly which part is absent.
> - `missing` — no implementation exists. `where` is null. This is expected and
>   is the most valuable thing you will find.
> - `contradicted` — the code does something the PRD forbids.
>
> Do not report code quality, style, or bugs. Another track owns those. You own
> one question: does the build match the spec.

Track C findings **have no file or line** when a requirement is missing. That is
correct and must not be treated as a malformed finding.

## Step 3: Run track A

Read and follow the `adamsreview` skill with the target, **always passing `--full`**
and never `--ensemble`. If a PRD was resolved, tell it: findings that contradict `<run-dir>/PRD.md`
are in scope even when the contradiction is in untouched code, because the PRD
defines what "correct" means for this change.

## Step 4: Join — output is contingent on every launched track

**Do not report until every launched track has returned.** You are notified as
each background subagent completes; do not poll output files mid-run.

If a track fails or returns nothing:

- Say which track failed and why.
- Report the surviving tracks' findings, **labelled as single-track**.
- Never present a one-track result as if it were the full review.

## Step 5: Merge and rank

Two tracks finding the same thing independently is the strongest precision
signal available here — it is the same consensus effect that lifts review F1 in
the literature. Rank on it.

1. **Deduplicate across tracks.** Same file and overlapping line range, same
   underlying claim → one finding. Do not merge on wording alone; two different
   bugs on one line stay two findings.
2. **Rank:**
   - **Confirmed by both A and B** — highest. Independent agreement.
   - **PRD violations from C** (`missing` / `contradicted`) — next. A shipped
     feature that doesn't do what the spec says is worse than a code smell,
     and only track C can see it.
   - **Single-track findings** — below, tagged with their origin.
   - **Out of scope / report-only** — last, never deleted.
3. **Disagreement is information.** If A confirmed a finding and B never raised
   it, say so rather than silently promoting it. One track's silence is not
   the other's corroboration.

## Step 5b: Ponytail triage

Write the ranked, deduplicated findings to `<run-dir>/merged.md` (one finding per
entry: file, line, claim, rank tier, which tracks/runs found it). Then dispatch
**one** subagent to bucket them — the merge tells you what was found, this tells
you what to actually do about it.

`subagent_type: generalPurpose`, `run_in_background: false` (you need its answer
to report). Prompt:

> Read and follow the `ponytail` skill, then read `<run-dir>/merged.md`. These are
> code-review findings already deduplicated and ranked. Do **not** add findings or
> re-review the code. Sort every existing finding into exactly one bucket, judged
> by the ponytail ladder:
>
> - **FIX** — a real defect worth addressing now. One line on what breaks.
> - **SKIP NOW** — real but not worth fixing now (YAGNI, cosmetic, speculative
>   edge). One line naming when it *would* be worth revisiting.
> - **FALSE POSITIVE** — not actually a bug; the reviewer misread the code. One
>   line on why it's wrong.
>
> Hard rule from ponytail's own "When NOT to be lazy": a finding on a security,
> data-loss, input-validation, or money path is **never** SKIP NOW or FALSE
> POSITIVE unless you can show concretely it doesn't apply. When unsure, FIX.
>
> Return the three bucketed lists, each finding keeping its original file:line.

The triage is advisory — it never deletes a finding, only labels it. The report
still shows everything; the buckets are how you lead.

## Step 6: Report

Findings are written for someone who did not write the code and did not run the
review.

- **Never introduce a term without explaining it in the same sentence.**
- **The explanation may not lean on another undefined term.** "It's a race on
  the mutex" explains nothing. "Two requests arriving at once can both read the
  old balance, so one write is lost" explains it.
- Say what breaks, not what category it belongs to.
- This binds titles, summaries, rationales, and the PRD section. Not code quoted
  verbatim.

Lead with the **FIX** bucket from Step 5b — those are the ones to act on — then
SKIP NOW, then FALSE POSITIVES. Within each bucket keep the rank order. State
plainly which tracks ran and which did not.

## Honest caveat

`adamsreview` is the most elaborate harness here and the least validated — its
author's own comparison ends *"(Anecdotal, n=me.)"* No published false-positive
rate, no third-party evaluation. The cross-track agreement ranking in Step 5 is
the one part of this skill with real evidence behind it, and it only works when
`--extra` is passed.

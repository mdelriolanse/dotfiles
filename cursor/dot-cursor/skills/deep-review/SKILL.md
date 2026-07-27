---
name: deep-review
description: Run the adamsreview pipeline, optionally in parallel with a built-in code-review pass and a PRD-conformance check, then merge the findings. Use when the user types /deep-review, or wants a thorough multi-track review rather than a single-pass diff read.
---

# deep-review

## Cursor harness

This copy runs in Cursor Agent. Map Claude Code terms as follows:

| Claude Code | Cursor |
|---|---|
| `Agent` tool | `Task` tool |
| `subagent_type: general-purpose` | `subagent_type: generalPurpose` |
| `run_in_background: true` | `run_in_background: true` on `Task` |
| `model: opus` | Cursor picks the model; drop the override or set it in the Task prompt |
| `AskUserQuestion` | Cursor's inline question prompt |
| `/code-review max` skill | `code-reviewer` skill (`~/.cursor/skills/code-reviewer/`) |
| `ponytail:ponytail` plugin skill | `ponytail` skill (`~/.cursor/skills/ponytail/`) |
| `adamsreview` skill | `adamsreview` skill (`~/.cursor/skills/adamsreview/`) |
| `claude -p "/deep-review …"` fan-out | `agent -p --trust -f "/deep-review …"` |

Orchestrates up to three independent review tracks, waits for all of them, and
merges the results. Findings that two tracks found independently are the ones
worth reading first.

## Invoke

```
/deep-review                          # adamsreview only
/deep-review --extra                  # + built-in /code-review max, in parallel
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
scrape — there is no Claude path through it. In this copy it is also broken:
`review-prose.md` points at `fragments/02-ensemble-adapter.md`, which does not
exist, and the smoke suite skips every ensemble assertion with *"external-review
not ported (requires Codex CLI plugin runtime)."* Track B is the Claude-native
way to get a second independent reviewer.

## The tracks

| Track | Runs where | When |
|---|---|---|
| **A — adamsreview** | main thread | always |
| **B — `/code-review max`** | background agent | `--extra` |
| **C — PRD conformance** | background agent | `--prd` given |

**`adamsreview` cannot be backgrounded.** It says so itself, and it uses
`AskUserQuestion`. It runs on the main thread and fans out internally. Parallelism
comes from putting B and C in background agents *first*, then starting A while
they run.

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

Each run is a fresh **root** `claude` process (not a subagent — subagents cannot
spawn the pipeline's own agents; a new OS process can). Its final report is its
stdout, so redirect stdout straight into the run's file — no need to tell it to
write one.

Pick a shared absolute output dir the orchestrator owns — **not** the session
scratchpad, because each inner run has its own scratchpad. Use
`OUT=$(mktemp -d)`. Forward every flag *except* `-n`:

```bash
for i in $(seq 1 "$K"); do
  DEEP_REVIEW_INNER=1 claude --dangerously-skip-permissions -p \
    "/deep-review $FORWARDED_FLAGS" \
    > "$OUT/dr-$i.md" 2>"$OUT/dr-$i.err" &
done
wait   # returns only when all k roots have exited
echo "OUT=$OUT"
```

Run that whole block as **one backgrounded Bash call** (`run_in_background:
true`). Rationale: k full pipelines blow past the 10-min foreground Bash cap, and
backgrounding is the harness's notify-on-exit path. Process exit is the only
reliable "done" signal — a `dr-$i.md` file can exist mid-write, so gate on the
`wait` returning, never on the files appearing.

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

Both `Agent` calls go in **one response block**, both `run_in_background: true`.
Launch them first so they run while track A works.

**Track B — built-in code review.** `subagent_type: general-purpose`, `model: opus`.

> Run the built-in `/code-review max` skill on <target>. Write every finding to
> `<run-dir>/track-b.json` as `[{"file","line","severity","claim","confidence"}]`.
> Return only a count.
>
> If you cannot invoke the `code-review` skill, say so explicitly in your return
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

Invoke the `adamsreview` skill with the target, **always passing `--full`** and
never `--ensemble`. If a PRD was resolved, tell it: findings that contradict `<run-dir>/PRD.md`
are in scope even when the contradiction is in untouched code, because the PRD
defines what "correct" means for this change.

## Step 4: Join — output is contingent on every launched track

**Do not report until every launched track has returned.** You are notified as
each background agent completes; do not poll, do not read their `.output` files.

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

`subagent_type: general-purpose`, `run_in_background: false` (you need its answer
to report). Prompt:

> Invoke the `ponytail:ponytail` skill, then read `<run-dir>/merged.md`. These are
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

## Step 7: Persist the full report to disk

Always — single-run and fan-out both. The terse in-chat report is a distillation;
this file is the archive, and it must lose **nothing**.

**Path.** `<reviewed-repo>/docs/deep-review/<title>-<timestamp>.md`, where
`<reviewed-repo>` is the root of the repo whose diff was reviewed — **not** the
session cwd. This checkout may use umbrella repos (a root dir that contains
`app/`, `gateway/`, etc. as independent nested git repos). When the session cwd is
an umbrella root but the reviewed branch lives in a nested repo (e.g.
`<root>/app`), the report MUST land inside that nested repo
(`<root>/app/docs/deep-review/...`), never at the umbrella level
(`<root>/docs/deep-review/...`). Resolve the reviewed repo's root via
`git -C <review-cwd> rev-parse --show-toplevel` (the `--cwd` passed to the
review), then `mkdir -p <root>/docs/deep-review` (always create the directory
if it does not exist — never skip the write because the path is absent) and
write under `<root>/docs/deep-review/`. The back-reference path below is
relative to that root.

- `<title>` — three or four words describing the review, each word lowercase and
  hyphen-separated (e.g. `training-webhook-outbox` or `webhook-double-delivery-audit`).
- `<timestamp>` — also hyphen-appended, `date +%Y-%m-%d-%H%M%S`.
- Full name example: `webhook-double-delivery-audit-2026-07-16-142530.md`.

**Content.** Unlike the in-chat report, this file is **not** brief. Ponytail
concision does not apply — write out every finding in full: each FIX/SKIP/FALSE-
POSITIVE with its file:line, the complete rationale, which tracks/runs found it and
any disagreement, the verified-correct notes, the PRD-conformance section, and the
bottom line. The goal is that nothing from the merge (Step 5) or triage (Step 5b) is
lost when the chat scrolls away. If a detail is in the raw output, it belongs here in
at least as much depth.

**Back-reference.** After writing the file, the **last line** of the raw in-chat
output must be the exact relative path just written, e.g.:

```
→ ./docs/deep-review/webhook-double-delivery-audit-2026-07-16-142530.md
```

## Cost

Tracks A, B, and C all run on your Claude subscription, not usage credits.
`--extra` roughly doubles wall-clock token spend; it does not touch your usage
credit balance. `/code-review ultra` is the one that bills separately, and this
skill never invokes it.

## Honest caveat

`adamsreview` is the most elaborate harness here and the least validated — its
author's own comparison ends *"(Anecdotal, n=me.)"* No published false-positive
rate, no third-party evaluation. The cross-track agreement ranking in Step 5 is
the one part of this skill with real evidence behind it, and it only works when
`--extra` is passed.

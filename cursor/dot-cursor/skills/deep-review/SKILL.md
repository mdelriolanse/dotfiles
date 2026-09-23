---
name: deep-review
description: Run adamsreview --full and andrea together, with optional open-code-review, a PRD or GitHub spec, and parallel repeats. Use when the user types /deep-review.
---

# deep-review

`/adamsreview` and `/andrea-review` are not commands. Both are routines in this directory. Follow their files. Do not look for a separate skill.

| Routine | Read | When |
|---|---|---|
| Adams | `adamsreview/ROUTINE.md` plus `adamsreview/bin` and `adamsreview/references` | always, `review --full` |
| Andrea | `andrea/ROUTINE.md` plus `andrea/playbook` | always |
| Open code review | the `open-code-review` skill (`ocr review`) | `--ocr` only |
| Spec | resolved `--prd` file | `--prd` only |

Adams' layout section says `~/.cursor/skills/adamsreview/SKILL.md`. That path is this skill's `adamsreview/` directory, and `ROUTINE.md` is that file. Same for Andrea: `andrea/ROUTINE.md` is the file it calls `SKILL.md`.

## Cursor harness

| Claude Code | Cursor |
|---|---|
| `Agent` tool | `Task` tool |
| `subagent_type: general-purpose` | `subagent_type: generalPurpose` |
| `run_in_background: true` | `run_in_background: true` on `Task` |
| `model: opus` | Cursor picks the model |
| `AskUserQuestion` | Cursor's inline question prompt |
| `claude -p "/deep-review …"` | `agent -p --trust -f "/deep-review …"` |

## Invoke

```
/deep-review
/deep-review --prd docs/spec.md
/deep-review --prd 412
/deep-review --ocr
/deep-review -n 3
/deep-review 1234 --prd 412 --ocr -n 2
```

Adams `review --full` always runs. `--full` is not a flag of this skill. It stops Adams from skipping a diff it judges trivial.

Andrea always runs, in parallel with Adams. That second reviewer used to be `--extra`. It is now the default. There is no `--extra` flag.

`--ocr` also runs the `open-code-review` skill. That skill stays its own command. This flag only adds it to the same run.

`--prd` is a path, a GitHub issue number, or an issue URL. Every routine reviews against that spec. A missing requirement is a finding.

`-n <k>` (k ≥ 2) runs this whole skill k times and merges across runs. Without `-n`, one run.

**Never pass `--ensemble` to Adams.**

## Tracks

| Track | Where | When |
|---|---|---|
| **A — Adams `review --full`** | main thread | always |
| **B — Andrea** | background | always |
| **O — `open-code-review`** | background | `--ocr` |
| **P — spec checklist** | background | `--prd` |

Adams stays on the main thread. It asks questions and fans out internally. Start B, and O and P when requested, in one response with `run_in_background: true`, then start A.

## Fan-out (`-n <k>`)

`-n` runs the whole skill, including Andrea and any `--ocr` / `--prd`, k times. If `DEEP_REVIEW_INNER` is set, ignore `-n` and do one run.

### Step F1

Each run is a new `agent` process, not a subagent. Pass the same target and the same `--prd` / `--ocr`, and not `-n`. Set `DEEP_REVIEW_INNER=1`.

```
mkdir -p "$OUT/runs"
for i in $(seq 1 "$N"); do
  agent -p --trust -f --output-format text \
    "/deep-review <target> [--prd …] [--ocr]" \
    > "$OUT/runs/$i.md" &
done
wait
```

The environment of each process must include `DEEP_REVIEW_INNER=1`.

### Step F2

1. Drop a run that produced no findings and say so.
2. Deduplicate across runs the same way Step 5 deduplicates across tracks.
3. Rank by run agreement: k-of-k, then k−1, then a singleton.
4. Write `$OUT/merged.md`, then Step 5b.
5. Report per Step 6, and lead with how many runs finished.

## Step 1: Resolve `--prd`

Skip this step when `--prd` is absent.

Write the spec to `<run-dir>/PRD.md`.

- A path: read that file.
- An issue number: `gh issue view <n> --json title,body,comments`.
- A URL: `gh api` the issue, or fetch the document.

If it does not resolve, stop and say so.

## Step 2: Background tracks

Launch these before Adams, in one response.

**Track B — Andrea.** Always. Prompt the background agent to follow `andrea/ROUTINE.md` and `andrea/playbook/andrea-review-playbook.md` on the target. Fixes stay suggestions. If `<run-dir>/PRD.md` exists, check each sector against it.

**Track O — open-code-review.** Only with `--ocr`. Invoke the `open-code-review` skill so it runs `ocr review` on the target. If a PRD was resolved, pass it as `--background`.

**Track P — spec checklist.** Only with `--prd`.

> Read `<run-dir>/PRD.md` and the diff. For each requirement, one entry in `<run-dir>/track-p.json`: `{"requirement", "status": "met|partial|missing|contradicted", "evidence", "where"}`. `missing` has `where: null`. Do not report style or unrelated bugs.

## Step 3: Track A

Follow `adamsreview/ROUTINE.md`. Run `review --full` only. Never `--ensemble`. Use `adamsreview/bin` and `adamsreview/references` next to that file. If a PRD was resolved, contradictions of `<run-dir>/PRD.md` are in scope even in untouched code.

## Step 4: Join

Do not report until every launched track has returned. If one fails, name it, report the rest as single-track, and do not present that as the full review.

## Step 5: Merge and rank

1. Same file, overlapping lines, same claim → one finding. Two bugs on one line stay two.
2. Rank: `--prd` entries that are `missing` or `contradicted`, then findings raised by more than one of A, B, and O, then a single track, then report-only.
3. If two tracks disagree about the same behavior, say so.

## Step 5b: Ponytail triage

Write `<run-dir>/merged.md` (file, line, claim, rank, which tracks). Then one subagent, `subagent_type: generalPurpose`, `run_in_background: false`:

> Read the ponytail instructions, then `<run-dir>/merged.md`. Do not add findings. Put each finding in exactly one bucket: **FIX** (what breaks), **SKIP NOW** (when it would be worth doing), or **FALSE POSITIVE** (why it is wrong). A security, data-loss, input-validation, or money finding is never SKIP NOW or FALSE POSITIVE unless you can show it does not apply. When unsure, FIX.

The buckets label findings. They do not delete them.

## Step 6: Report

Lead with FIX, then SKIP NOW, then FALSE POSITIVE. Say what breaks in plain language. State which tracks ran.

## Step 7: Persist

Write `<reviewed-repo>/docs/deep-review/<title>-<timestamp>.md`. `<reviewed-repo>` is `git -C <review-cwd> rev-parse --show-toplevel`, not an umbrella root above that repo. `<title>` is three or four lowercase hyphenated words. `<timestamp>` is `date +%Y-%m-%d-%H%M%S`.

The file keeps every finding: file:line, rationale, which tracks and runs, disagreements, and the spec section. The last line of the chat report is the relative path:

```
→ ./docs/deep-review/webhook-double-delivery-audit-2026-07-16-142530.md
```

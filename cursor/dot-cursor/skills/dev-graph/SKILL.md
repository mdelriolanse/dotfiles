---
name: dev-graph
description: Autonomous issue-to-PR pipeline. Given an issue tag, drives worktree setup, PRD, plan, TDD build, dual review, resolve-review, and PR creation with two HITL breakpoints. Use when user types /dev-graph.
disable-model-invocation: true
---

# dev-graph

## Cursor harness

This copy runs in Cursor. Map Claude Code terms as follows:

| Claude Code | Cursor |
|---|---|
| `Agent` tool | `Task` (`subagent_type: generalPurpose`), or `agent -p --trust -f` |
| `run_in_background: true` | `run_in_background: true` on `Task` |
| `--add-dir` / workspace | `--workspace <container>` |
| `model: opus` | Cursor picks the model; state the depth in the prompt |

Autonomous issue-to-PR pipeline. Given `{{ISSUE-TAG}}` (a GitHub issue URL or
`number + repo`), drives a 10-session development graph to produce reviewed PRs
linked to the issue. Two human-in-the-loop breakpoints only: Session 2 (grill)
and Session 6 (resolve-review HITL). Everything else auto-runs.

You (this omp session) ARE the orchestrator. Read this skill top to bottom and
follow it. No subagent dispatch for the orchestration logic itself. Per-session
skills (`issue-to-docs`, `to-prd`, `plan`, TDD build, `resolve-review`) are
invoked either inline (read the skill, follow it) or via
`agent -p --trust -f` sub-sessions for isolated work. All sub-sessions are
non-interactive and never trigger the native plan-mode approval popup.

> Do not enter native plan mode. Do not write to `xd://propose`. Do not call the `ask` tool except at the two scheduled breakpoints (Session 2, Session 6) and any ad-hoc breakpoint explicitly specified in the runbook (e.g. the loop-gate round-3 BLOCKER guard, a new security/data-loss finding in a loop). Execute every session directly. Tool calls are auto-approved (`approvalMode: yolo` in config).

> Every memory saved during this run — across all sessions and all sub-session skills (issue-to-docs, to-prd, plan, TDD build, resolve-review) — must carry a structured facet tag identifying the run. After every `memory_save` call, immediately call `memory_facet_tag` with: `targetType: "memory"`, `targetId: <the memory ID returned by memory_save>`, `dimension: "dev-graph-run"`, `value: "<$DIR_NAME>"`. The `<$DIR_NAME>` is the umbrella container directory name created in Step 2a (e.g. `batch-api-894`). This applies to ALL memories saved in this workflow, including those saved by sub-skills — forward this directive to every sub-session via the `agent -p --trust -f` prompt or inline skill invocation. To recall all memories from a run, query `memory_facet_query matchAll="dev-graph-run:<$DIR_NAME>" targetType="memory"`.

## Constants

- Container root: `~/<org-root>/worktrees/<$DIR_NAME>/`
- Org: `<org>`
- Repos (all N): `<repo-1> <repo-2> ... <repo-N>` — the orchestrator fills these from the org's repo set (e.g. app, gateway, operator, helm, plus any DB/migration repos). Replace the placeholder list below wherever it appears.
- Push authorization: pre-assumed for Session 10 only.

## Session 1 — Worktree setup + issue pull + PRD (kickoff, NOT a pause)

`{{ISSUE-TAG}}` is the argument to `/dev-graph`. Not a pause point — run it
straight through.

### 1a. Create the container directory

```bash
# DIR_NAME = two-to-three-word slug from the issue title + "-" + issue number
# e.g. "batch-api-894" for issue #894 titled "Batch API"
CONTAINER=~/<org-root>/worktrees/${DIR_NAME}
mkdir -p "$CONTAINER/docs"
```

The slug is derived from the issue title (fetched in 1b): lowercase, hyphenate,
take first 2–3 words. If the issue has no title yet (URL with number only), fetch
it first via `gh issue view`.

### 1b. Pull the issue via `/issue-to-docs`

Run the `issue-to-docs` skill (see the skill edit for container docs). It
resolves `{{ISSUE-TAG}}` to `owner/repo#N`, fetches the body via `gh issue view`,
and writes the verbatim spec to the **container** `./docs` directory (the
`docs/` created in 1a, not a per-repo `docs/`). Invoke it inline (read the
skill, follow it) with cwd = `$CONTAINER`. Forward the tagging directive so its
`memory_save` calls are followed by `memory_facet_tag`.

After `issue-to-docs` completes, the container has:
- `docs/<slug>-spec.md` — verbatim issue body
- `docs/<repo>-<N>/` — chunked markdown (container-level, not per-repo)
- agentmemory project `issue-<repo>-<N>` with spec memories — each tagged
  `dev-graph-run:$DIR_NAME`.

### 1c. Create worktrees for all N repos

For each repo in `<repo-1> <repo-2> ... <repo-N>` (see Constants):

```bash
REPO_DIR=~/<org-root>/$REPO
BRANCH=feat/${DIR_NAME}-${REPO}
git -C "$REPO_DIR" fetch origin main
git -C "$REPO_DIR" worktree add "$CONTAINER/feat-${DIR_NAME}-${REPO}" -b "$BRANCH" origin/main
```

Branch is based on `origin/main` (fresh fetch), never local `main` (may be
stale). The worktree path pattern matches the existing convention
(`worktrees/batch-api/feat-batch-api-app/`).

Each worktree is a separate git repo on its own branch. The container
`.gitignore` (created in 1d) ignores all `feat-*` subdirs so the umbrella repo
never tracks them.

**Contingency — worktree creation fails for one repo.** If `git worktree add`
fails (branch name collision, fetch failure), skip that repo, log the error,
and continue with the remaining repos. The PR step only creates PRs for
worktrees with diffs.

### 1d. Create container `.gitignore`

```bash
cat > "$CONTAINER/.gitignore" <<'EOF'
feat-*/
EOF
```

Matches the existing `worktrees/batch-api/.gitignore` convention. The container
`docs/` is NOT gitignored — it's the local development workspace, never
committed to any repo (it lives outside all per-repo worktrees).

### 1e. Run `/to-prd` — write PRD to container `./docs/PRD.md`

Run the `to-prd` skill inline with cwd = `$CONTAINER`. It explores the codebase
(using the code-intelligence tools per AGENTS.md), sketches modules, and writes
`docs/PRD.md` in the **container** `./docs` directory (not a per-repo `docs/`).
The `to-prd` skill already writes to `./docs/PRD.md` relative to cwd — the
orchestrator ensures cwd is the container dir for this step.

The orchestrator does NOT pass `--prd` to an off-device issue tracker. `to-prd`
writes only to local `./docs/PRD.md`. After writing, `to-prd` calls
`memory_save` to store the PRD's module boundaries (type: `architecture`) in
the agentmemory project `issue-<repo>-<N>`. Forward the tagging directive: each
`memory_save` from `to-prd` is followed by `memory_facet_tag` with
`dimension: "dev-graph-run"`, `value: "$DIR_NAME"`.

End of Session 1. Proceed immediately to Session 2 (the first breakpoint).

## Session 2 — Grill with docs (BREAKPOINT 1)

Run `/grill-with-docs` inline with cwd = `$CONTAINER`. The skill interviews the
user about the PRD against the domain model, sharpens terminology, and updates
`docs/CONTEXT.md` and `docs/adr/` inline as decisions crystallize. All docs
written to the container `./docs/`.

The grill skill calls `memory_save` as decisions crystallize (per its skill
spec). Forward the tagging directive: every `memory_save` the grill issues is
followed by `memory_facet_tag` with `dimension: "dev-graph-run"`,
`value: "$DIR_NAME"`.

**This is HITL breakpoint 1.** The grill skill is inherently interactive — it
asks questions one at a time and waits for the user. The orchestrator does
nothing else while the grill runs. When the user signals the grill is done (the
skill completes its interview loop), the orchestrator proceeds to Session 3.

No `ask` tool needed here — the grill skill itself drives the interaction. The
orchestrator just invokes the skill and waits for it to return.

## Session 3 — Plan + build

### 3a. Run `/plan` with pre-seeded context

The orchestrator reads the `plan` skill and follows its format. The plan input
is: the PRD (`docs/PRD.md`), the ADRs (`docs/adr/`), the `CONTEXT.md`, and the
agentmemory project `issue-<repo>-<N>` (recalled via
`memory_recall "issue-<repo>-<N>"`). The plan skill produces a caveman-format
plan report and writes it to `docs/plans/<slug>.md` in the container (see the
`plan` skill's Persist section).

The plan uses TDD and the agent-swarm approach per the `test-driven-development`
skill. The orchestrator instructs the plan to reference the code-intelligence
tools (Semble, Serena, codebase-memory, graphify, agentmemory — per
AGENTS.md) to ensure changes are cross-cutting and correctly implemented.

**The `/plan` skill is a report-format skill — it writes a markdown file. It
does NOT trigger native plan mode. No `xd://propose` write, no popup.**

### 3b. Build plan

The orchestrator executes the plan from 3a. This is the implementation phase —
the largest single step. The orchestrator follows the
`test-driven-development` skill's agent-swarm pattern:

- Break the plan into behaviors (one assertion per behavior).
- For each behavior: RED agent (write failing test) → GREEN agent (write
  minimal code to pass) → orchestrator verify → refactor.
- RED/GREEN agents run as `agent -p --trust -f`
  sub-sessions (per the TDD skill's executor-model policy). Non-interactive,
  no popup. Launch with `--cwd "$CONTAINER"` (umbrella dir) so the session's
  project context, context-file discovery, and session storage anchor to the
  container; the prompt tells the agent to `cd` into the target worktree
  (`$CONTAINER/feat-${DIR_NAME}-<repo>`) before editing, since each worktree is
  its own git repo. Each launch attaches an `omp-watchdog.sh` instance (same
  pattern as 4b) so a hung agent is killed and surfaced, not left to burn
  `--max-time`.
- Parallel batches only for behaviors with disjoint file sets; serialize when
  file sets overlap.
- The orchestrator (main session) verifies: `git diff --name-only` to confirm
  the GREEN agent didn't touch tests, runs the full test suite, spot-checks the
  diff.

The orchestrator applies changes inside the per-repo worktrees (e.g.
`$CONTAINER/feat-${DIR_NAME}-app/`). Each worktree is its own git repo, so
changes land on the `feat/${DIR_NAME}-<repo>` branch.

> Before writing any code, consult the code-intelligence backends per AGENTS.md: Semble for natural-language search and source discovery, Serena for symbol-safe edits/renames, codebase-memory for complexity/cross-service traces. Use these to ensure changes are cross-cutting and correctly implemented. Never grep for function definitions — use the MCP backends.

**Contingency — TDD build fails to converge.** If a RED→GREEN cycle exhausts
its ralph loop (MAX attempts), the orchestrator stops, reports the failing
behavior, and asks the user (an ad-hoc breakpoint). The user can adjust the
behavior spec or fix the issue, then resume.

### 3c. Update agentmemory

After the build, `memory_save` what was built to the `issue-<repo>-<N>`
project: files touched, modules created/modified, key decisions made during
implementation (type: `workflow`). Search first (`memory_smart_search`) to
avoid dupes. Follow the tagging directive: each `memory_save` is followed by
`memory_facet_tag` with `dimension: "dev-graph-run"`, `value: "$DIR_NAME"`.

End of Session 3. Proceed to Sessions 4 + 5 (parallel).

## Sessions 4 + 5 — Dual review (parallel)

### 4a. Resolve non-empty worktrees

Both reviews operate on a single git repo's diff (`git diff $mb`), so the
orchestrator runs each review **once per non-empty worktree** in parallel, then
merges the findings into one combined report. This achieves the "one merged
review" decision semantically while respecting the per-repo git boundary.

```bash
NONEMPTY_WTS=()
for REPO in <repo-1> <repo-2> ... <repo-N>; do
  WT="$CONTAINER/feat-${DIR_NAME}-${REPO}"
  [ -d "$WT" ] || continue
  # Fresh fetch so merge-base reflects the current origin/main, not the one
  # fetched in Session 1 — main may have advanced during the build.
  git -C "$WT" fetch origin main 2>/dev/null || true
  MB=$(git -C "$WT" merge-base HEAD origin/main)
  git -C "$WT" diff "$MB" --quiet 2>/dev/null && continue   # empty diff — skip
  NONEMPTY_WTS+=("$REPO:$WT:$MB")
done
# Do NOT `exit 0` here — that kills the orchestrator session. Set a flag and
# skip to Session 10 if there is nothing to review.
if [ ${#NONEMPTY_WTS[@]} -eq 0 ]; then
  echo "No diffs in any worktree — skipping review, going straight to Session 10."
  SKIP_REVIEWS=1
fi
```

**Contingency — review finds nothing.** If both reviews return empty FIX
buckets on round 1, skip the loop and go straight to Session 10.

### 4b. Session 4 — deep-review (parallel with Session 5)

If `SKIP_REVIEWS=1` (set in 4a, no non-empty worktrees), skip 4b/4c and go
straight to Session 10.

Run `/deep-review -n 3 --extra --prd "$CONTAINER/docs/PRD.md"` per non-empty
worktree. The `--prd` is an absolute path to the container PRD. `-n 3` runs the
skill 3x and merges across runs; `--extra` adds the code-reviewer track in
parallel.

Each sub-session is a non-interactive `agent -p --trust -f` process (no popup):

```bash
WATCHDOG=~/dotfiles/omp/scripts/omp-watchdog.sh
PIDS=()
for entry in "${NONEMPTY_WTS[@]}"; do
  REPO="${entry%%:*}"; rest="${entry#*:}"; WT="${rest%%:*}"; MB="${rest##*:}"
  LOG="$CONTAINER/docs/deep-review-$REPO.log"
  # --cwd is the container (umbrella dir) so the session's project context,
  #  context-file discovery, and session storage anchor to the container —
  #  not the worktree. The prompt tells the sub-session to cd into $WT for
  #  git operations (deep-review runs `git diff`).
  agent -p --trust -f --workspace "$CONTAINER" \
    "cd $WT && /deep-review -n 3 --extra --prd $CONTAINER/docs/PRD.md" \
    > "$LOG" 2>&1 &
  PID=$!
  STALL_SECS=300 "$WATCHDOG" "$PID" "$LOG" &
  PIDS+=("$PID:$(jobs -p | tail -1):$REPO:$LOG")
done
# wait for sub-sessions, then stop watchdogs
for entry in "${PIDS[@]}"; do
  PID="${entry%%:*}"; rest="${entry#*:}"; WPID="${rest%%:*}"; rest="${rest#*:}"
  REPO="${rest%%:*}"; LOG="${rest#*:}"
  wait "$PID" 2>/dev/null || true
  kill "$WPID" 2>/dev/null || true
  [ -f "${LOG}.stalled" ] && echo "WARN: deep-review $REPO stalled — see ${LOG}.stalled"
done
```

After all finish, the orchestrator collects each worktree's
`docs/deep-review/*.md` and merges them into `$CONTAINER/docs/deep-review-merged.md`.
**Merge rule** (deterministic, not by feel):
- Group findings by `(file, line_range)` — same file and overlapping line
  ranges collapse to one finding.
- Within a group, keep the **highest severity** claim (BLOCKER > MAJOR > MINOR > NIT).
- Concatenate the originating worktree names into a `raised_by:` field
  (e.g. `raised_by: app, gateway`). A finding k-of-k worktrees raised outranks
  a singleton — order groups by `(severity desc, worktree-count desc)`.
- Preserve each finding's verbatim rationale from the first reporter; append
  any divergent rationale from other worktrees as a `also noted:` line.

### 4c. Session 5 — andrea-review (parallel with Session 4)

Run `/andrea-review --prd "$CONTAINER/docs/PRD.md"` per non-empty worktree, in
parallel with Session 4. Same pattern: `agent -p --trust -f --workspace "$CONTAINER"`
sub-sessions (umbrella dir for project context), one per worktree, with `cd
$WT` in the prompt for git ops. Each has an `omp-watchdog.sh` instance
attached (same wiring as 4b). Each writes its report to its own worktree's
`docs/andrea-review-reports/`. The orchestrator merges into
`docs/andrea-review-merged.md` in the container.

Both Sessions 4 and 5 launch their sub-sessions in one batch, then `wait` for
all. No dependency between them.

End of Sessions 4 + 5. Proceed to Session 6 (the second breakpoint).

## Session 6 — Resolve review (BREAKPOINT 2)

Run `/resolve-review` with both merged review outputs. See the resolve-review
skill edits (origin gate + `RR-#.md` output).

### 6a. The orchestrator feeds both merged reports to resolve-review

The resolve-review skill reads the newest report in `./docs/deep-review/`. Since
we have merged reports at the container level, the orchestrator points
resolve-review at `docs/deep-review-merged.md` (and the andrea-review merged
report). The skill processes FIX and SKIP-NOW findings.

### 6b. The skill's origin gate drops pre-existing findings

The resolve-review skill edit adds a checker: for each finding, verify it was
introduced by the current PR's diff (not pre-existing). Findings whose
`origin: pre_existing` with `origin_confidence: high` are dropped — they're
irrelevant to this PR. The gate uses `git diff --name-only $MB` per worktree to
check file membership.

### 6c. The skill writes `RR-#.md`

The resolve-review skill edit writes its full results to
`docs/resolve-review/RR-1.md` in the container (first iteration). The file
contains: what was fixed, what was decided by HITL but not yet implemented, what
was dropped as pre-existing, and the trivial-fix dispatch results.

### 6d. HITL breakpoint 2

The resolve-review skill surfaces HITL findings to the user (data-loss,
security, semantics decisions). The orchestrator pauses here — the user reviews
the HITL list and decides. The `ask` tool is used to present the HITL findings
and collect decisions. When the user finishes, the orchestrator records
decisions in `RR-1.md` and proceeds to Session 7.

## Session 7 — Plan resolve-review decisions

Run `/plan` with the latest `RR-#.md` as input. The plan covers implementing
everything HITL decided in Session 6. The plan skill writes
`docs/plans/<slug>.md` in the container. Then the orchestrator builds the plan
(same TDD agent-swarm pattern as Step 3b), applying changes to the worktrees.

End of Session 7. Proceed to Sessions 8 + 9 (parallel).

## Sessions 8 + 9 — Second dual review (parallel)

Same as Step 5 (4b/4c — including `--cwd "$CONTAINER"` + `cd $WT` in the
prompt, plus `omp-watchdog.sh`), but without `-n 3` (single pass, not 3x
ensemble — the second review pass is lighter):

- Session 8: `/deep-review --extra --prd "$CONTAINER/docs/PRD.md"` per
  non-empty worktree, parallel.
- Session 9: `/andrea-review --prd "$CONTAINER/docs/PRD.md"` per non-empty
  worktree, parallel.

Merge reports into `docs/deep-review-merged.md` and
`docs/andrea-review-merged.md` (overwrite the round-1 versions, or version them
as `*-round-2.md`).

## Loop gate

After Sessions 8 + 9 complete, run the resolve-review ponytail triage on the
merged findings (same as Session 6, but without the HITL pause — auto-triage
only).

**Loop-back condition**: the FIX bucket contains ≥1 BLOCKER or MAJOR finding.
NIT/MINOR never trigger a loop.

**Round-specific behavior**:
- **Round 1** (Sessions 4/5 → 6 → 7): address ALL flagged issues (FIX + SKIP-NOW
  that were promoted).
- **Rounds 2–3** (Sessions 8/9 → loop): address ONLY BLOCKER + MAJOR. NIT/MINOR
  are recorded in `RR-#.md` but not actioned.

**Hard cap**: 3 review rounds total (initial round 1 + 2 loops). After the 3rd
round, force-exit regardless of remaining findings. **If the 3rd round still
has BLOCKER findings, do NOT silently defer them — surface them to the user
via the `ask` tool before proceeding to Session 10.** Shipping known-broken
code is a human decision, not an auto-exit. MAJOR/MINOR/NIT are recorded in
the final `RR-#.md` as deferred.

**Loop counter**: tracked in the container as `docs/.review-round` (a single
integer file). Increment after each round. The orchestrator reads it at the
loop gate to decide whether to loop or exit.

If looping: go back to Sessions 4/5 equivalent (but now it's the next round, so
Sessions 8/9 pattern). Increment `docs/.review-round`. Run resolve-review
(auto-triage, no HITL unless a new security/data-loss finding appears — then
pause). If the HITL pause fires, it's an ad-hoc breakpoint, not a scheduled one.

If not looping (FIX bucket has no BLOCKER/MAJOR, or round ≥ 3): proceed to
Session 10.

## Session 10 — Commit + PR

### 10a. Commit all changes (excluding `docs/`)

For each non-empty worktree:

```bash
# Use git -C so cwd stays at $CONTAINER across iterations.
git -C "$WT" add -A
git -C "$WT" reset -- docs/
# Local-only excludes (not committed) so review/plan docs never get pushed.
echo "docs/deep-review/" >> "$WT/.git/info/exclude"
echo "docs/andrea-review-reports/" >> "$WT/.git/info/exclude"
git -C "$WT" commit -m "$(conventional-commit-message)"
```

The `git reset -- docs/` ensures no `docs/` content is staged, even if a
worktree's `docs/` has review reports. The `.git/info/exclude` is local-only
(not committed) so it doesn't show up in the PR diff.

Commit message style: per `commit-message-style` rule —
`type(scope): imperative description (#PR)`. **Never** include review-skill lingo
("adamsreview", "andrea review", "ponytail:", "per X's request"), per
`commit-hygiene` rule. The commit body explains WHY, not just WHAT, with bullets
for multi-feature changes.

The container `docs/` is never committed — it's outside all per-repo worktrees,
living in the umbrella's working tree. The umbrella repo doesn't track
`worktrees/` content (the container `.gitignore` ignores `feat-*` subdirs, and
the umbrella `.gitignore` ignores `worktrees/`).

### 10b. Create PRs via `gh`

The issue already exists on the Planner board (it was `{{ISSUE-TAG}}` — the
issue we pulled in Session 1). So `/planner-create` is NOT used to create a new
issue. Instead:

For each non-empty worktree, create a PR:

```bash
# Subshell contains cwd; --repo makes gh independent of cwd.
(
  cd "$WT"
  git push -u origin <branch>
  gh pr create \
    --repo "<org>/<pr-repo>-$REPO" \
    --base main \
    --title "<conventional-commit title>" \
    --body "$(cat <<'BODY'
<body derived from commit messages + diff summary>

Closes <org>/<issue-repo>#<issue-number>
BODY
)"
)
```

**Push authorization**: pre-assumed per the user's spec ("You can pre-assume
push authorization for this step"). `git push -u origin <branch>` runs without
asking.

**PR body**: ends with `Closes <org>/<issue-repo>#<issue-number>` — the
fully-qualified cross-repo form per `pr-issue-linkage` rule. Even if the PR is
in a different repo than the issue, the `Closes <org>/<issue-repo>#N` form
creates the timeline linkage. ALWAYS use `Closes`, per the user's convention.

**Move issue to "In review"**: set the Planner board item's Status field to
`In review` via:

```bash
gh project item-edit --project-id <PLANNER_PROJECT_ID> --id <item-id> \
  --field-id <PLANNER_STATUS_FIELD_ID> --single-select-option-id <IN_REVIEW_OPTION_ID>
```

The item ID is found by matching the issue URL in the project item list.
The project/field/option IDs are org-specific — look them up via
`gh project list` and `gh project field-list` (see `planner-create` skill).

**If the issue is NOT on the board**, add it via
`gh project item-add <PLANNER_PROJECT_NUMBER> --owner <org> --url <issue URL>` (same as
`planner-create` Step 3), then set Status to "In review".

### 10c. Do NOT delete branches or worktrees

Per the user's spec: "Do NOT delete the branches or worktrees locally or on
remote. The merge lifecycle will be dealt with later." No `git worktree remove`,
no `git push origin --delete`, no `git branch -D`.

## Assumptions & contingencies

- **`agent -p --trust -f` sub-sessions don't enter plan mode.** `-p` (print
  mode) is non-interactive — no UI to show a popup. Liveness is monitored by
  `omp/scripts/omp-watchdog.sh` — it watches the sub-session's stdout log for
  growth and kills the PID after `STALL_SECS` (default 300s) of no output,
  writing a `*.stalled` marker the orchestrator reads when `wait $PID`
  returns. `--max-time` remains as a wall-clock backstop. Contingency: add
  `--trust` to every `agent -p --trust -f` call (belt and suspenders with the
  global config).
- **All N repos have an `origin/main` branch.** Verified: each repo in
  the org's set has an `origin` remote pointing at
  `github.com/<org>/<repo>.git`. If a repo's `origin/main` fetch fails,
  skip that worktree and report — the others proceed.
- **`gh` is authenticated.** `gh auth status` must pass. If not, the
  orchestrator stops at Session 1 and tells the user to authenticate.
- **The issue already exists on the Planner board.** Session 10 links PRs to
  the existing issue (moves to "In review"), does not create a new one.
- **Contingency — worktree creation fails for one repo.** Skip that repo, log
  the error, continue with the remaining repos.
- **Contingency — review finds nothing.** Skip the loop, go straight to
  Session 10.
- **Contingency — TDD build fails to converge.** Stop, report the failing
  behavior, ask the user (ad-hoc breakpoint). Resume after user adjusts.

# Stage 2.8 — PR comment freshness filter (replace `--since` with code-locality check)

## Context

**Problem.** Phase 1.5's PR-comment scrape (`--ensemble` only) currently passes `--since $review_started_at` to `external-scrape.sh`, which keeps bot comments with `created_at >= review_started_at` and drops the rest. The filter axis is wrong: a three-week-old CodeRabbit/Greptile comment on an unchanged file is still actionable; a comment posted five minutes ago on a file that just got rewritten is stale. Newness doesn't correlate with relevance — code-locality does.

**What prompted this.** User observation during review of PR #199 on `beta-briefing`: Greptile summary comments posted before `review_started_at` were silently dropped even though the code they described hadn't changed since. Intent all along was "nothing has changed in the repo since the comment was posted," not "only comments newer than our review's start time."

**Intended outcome.** Replace the time-based filter with a per-comment code-locality filter. Three record kinds (inline review comments, review submissions, issue comments) get different checks based on what coordinate data the GitHub API returns for each. Greptile-style summary comments posted after the latest commit are included; any comment whose referenced code has changed since posting is excluded.

**Stage sizing.** Fits the Stage 2.5/2.6/2.7 pre-Stage-4 hardening pattern — one helper, one fragment rewire, small DESIGN update, smoke growth. Stage 2.8 in the BUILD.md index.

---

## Scope

### New helper: `commands/_shared/tools/comment-freshness.sh`

Bash. Takes normalized bot-comment array on stdin (same shape `external-scrape.sh` emits today), applies per-record code-freshness algorithm, emits filtered array on stdout + one audit line per record on stderr.

**Interface:**
```
comment-freshness.sh --pr <num> --reviewed-files <csv|@-> [--comments <path|@->] [--fixtures-dir <dir>]
```

- `--pr <num>` — PR number, used to fetch `pulls/$pr/commits` for the issue_comment implicit-commit lookup.
- `--reviewed-files <csv|@->` — list of files in the current PR diff (`$reviewed_files_all` from Phase 0). Intersected with per-record diff results to determine staleness.
- `--comments <path|@->` — where to read the normalized comment array from. Default `@-` (stdin) so the helper pipes cleanly from `external-scrape.sh`.
- `--fixtures-dir <dir>` — offline replay path (mirrors `external-scrape.sh`). Reads `pr_commits.json` from the fixture dir instead of calling `gh api`.

**Only one of `--reviewed-files` / `--comments` may use `@-` in a single invocation.** Helper rejects the conflict with a usage error.

**Algorithm (per record, policy C2):**

| `kind` | `commit_id` | `path` | Check |
|---|---|---|---|
| `review_comment` (inline) | present | present | `git diff --name-only $commit_id..HEAD -- "$path"` empty → include. Non-empty → exclude (`action=stale`). |
| `review` (submission) | present | null | `git diff --name-only $commit_id..HEAD` ∩ `$reviewed_files_all` empty → include. Non-empty → exclude (`action=stale`). |
| `issue_comment` (general) | null | null | Fetch `pulls/$pr/commits` (cached once per helper run); find `latest = max(.committer.date)`. `iso8601($comment.created_at) > iso8601($latest_committer_date)` → include (`action=fresh-summary`). Otherwise exclude (`action=stale-summary`). |

**Reachability edge case:** `commit_id` present but not in local history (force-push, shallow clone). Attempt one `git fetch origin +refs/pull/$pr/head:refs/adams-review/pr-$pr` to pull the PR ref, re-test with `git cat-file -e $commit_id`. Still missing → exclude with `action=unreachable`. Log `comment_freshness: id=$id action=unreachable` to stderr; include the helper's short-fix suggestion in the audit line so a user reading `trace.md` can diagnose.

**API-failure fallback:** if `pulls/$pr/commits` fetch fails (rate limit, auth, network) AND any record is an `issue_comment`, emit a single `comment_freshness_api_failed: <stderr excerpt>` audit line and **include all `issue_comment` records unchanged** (policy A fallback). Records with a real `commit_id` still get their normal check — the API failure only affects the issue_comment path that needed the commits list. Don't abort the whole helper; upstream `external-scrape.sh` already degrades gracefully on gh failures and this preserves the symmetry.

**Audit line grammar** (one line per input record, stderr, matches `origin-crosscheck.sh` convention so `trace.md` readers parse uniformly):
```
comment_freshness: id=<n> kind=<issue|review|review_comment> action=<fresh|stale|stale-summary|fresh-summary|unreachable|api-degraded> [reason=<short>]
```

**Exit codes:** 0 success (empty filtered array is OK); 1 invalid stdin JSON, malformed records, or unresolvable `--reviewed-files`; 64 usage.

**Bash 3.2 portable** (per BUILD.md cross-stage-note convention — no `declare -A`, no `mapfile`). Uses `jq` + `git` + `gh` + a small Bash wrapper.

### Helper changes: `commands/_shared/tools/external-scrape.sh`

Remove `--since` requirement:
- `SINCE` variable and `[[ -n "$SINCE" ]] || die_usage` check dropped.
- `--since` arg parsing dropped (strict — fail-closed on unknown args per existing `die_usage "unknown arg"` branch).
- `jq` pipeline: remove the `iso_gt_eq($c.created_at; $since)` clause from the top `map(. as $c | select(...))` filter; every other filter (bot-login, deny-list, allow-list, self-author) stays unchanged.
- Usage text and header comment updated to remove `--since` references.
- Exit-code table unchanged.

**This IS a breaking change** for any direct caller of `external-scrape.sh`; the only caller in the repo is `02-ensemble-adapter.md:123`. User-level `.claude/review-config.json` is unaffected (no `since` config key today).

**Fixture replay path** (`--fixtures-dir`) — unchanged. Same three fixture files (`issue_comments.json`, `reviews.json`, `review_comments.json`) feed the same normalization path; only the time filter is gone.

### Fragment changes: `commands/_shared/02-ensemble-adapter.md`

Rewrite step 1.5.3's scrape block to pipe scrape output through the new helper:

```bash
if [[ "$mode" == "pr" ]]; then
    ~/.claude/commands/_shared/tools/external-scrape.sh \
        --pr "$pr_number" \
        > "$scratch_dir/pr-scrape.raw.json" \
        2> "$scratch_dir/pr-scrape.err" \
        || scrape_exit=$?
    scrape_exit=${scrape_exit:-0}

    if [[ $scrape_exit -eq 0 ]]; then
        reviewed_files_csv=$(printf '%s\n' "$reviewed_files_all" \
            | awk 'NF' | paste -sd, -)

        if ! ~/.claude/commands/_shared/tools/comment-freshness.sh \
                --pr "$pr_number" \
                --reviewed-files "$reviewed_files_csv" \
                --comments "$scratch_dir/pr-scrape.raw.json" \
                > "$scratch_dir/pr-scrape.json" \
                2> >(tee -a "$trace_log_path" >&2); then
            # Freshness helper itself failed — include raw scrape, log tag.
            printf 'phase_1_5_freshness_helper_failed: using raw scrape\n' \
                >> "$trace_log_path"
            cp "$scratch_dir/pr-scrape.raw.json" "$scratch_dir/pr-scrape.json"
        fi
    fi
else
    echo "[]" > "$scratch_dir/pr-scrape.json"
    scrape_exit=0
fi
```

Rationale for the `tee -a` pattern: matches `origin-crosscheck.sh`'s dispatch at `01-detection.md` step 1.4 step 2a — per-record audit lines land in `trace.md` inline, preserving the artifact's audit trail without the orchestrator having to re-parse stderr.

Rationale for the helper-failure fallback (fall back to raw scrape): consistent with Phase 1.5's broader "degrade gracefully, never abort the pipeline" posture (§24.2). A freshness helper bug should not block the entire ensemble phase.

Step 1.5.3 prose before the code block rewritten to describe the two-stage pipe (scrape then freshness-filter); remove the `--since $review_started_at` reference.

### Fragment changes: `commands/_shared/00-preflight.md`

Step 0.5 (`Capture review_started_at`) — relax the "before any push" invariant note. `review_started_at` still captured; Phase 6 metrics still consumes it for `time_elapsed_seconds`. Remove the sentence *"Per §4 Phase 0 step 4, this timestamp anchors the Phase 1.5 scrape window, and missing it by even a second of push-gap can silently hide bot comments that landed during the gap."* Replace with a one-liner: *"Captured as the review's start time; consumed by Phase 6 `metrics.time_elapsed_seconds`."*

No other fragment changes in 00-preflight. Step 0.13/0.14 prior-artifact detection and step 0.16 latest.txt write unaffected.

### DESIGN updates (clarification-level — no rev bump)

- **§21.8 `external-scrape.sh`** — remove `--since` from signature + narrative. Update the output-schema paragraph to match (no behavioral change to the normalized shape itself).
- **§21.10 new — `comment-freshness.sh`** — full spec mirroring §21.9 (`origin-crosscheck.sh`) shape: interface, per-record algorithm table (C2 policy explicit), reachability/API-failure fallback cases, audit-line grammar, fixture-replay behavior, exit codes. Include a short rationale paragraph: "Replaces the Stage-2 `--since` time filter; the time axis doesn't correlate with relevance — code locality does."
- **§4 Phase 0 step 4 narrative** — remove the "anchors the Phase 1.5 scrape window" sentence; `review_started_at` survives only as the metrics anchor.
- **§4 Phase 1.5 narrative** — add one sentence to the comment-scrape description: *"Scraped bot comments are post-filtered by `comment-freshness.sh` (§21.10) so comments referring to code that has changed since they were posted are excluded."*
- **Section number table of contents / cross-references** — only §21.10 gains a row; existing refs to §21.8 from §4 stay.

### Smoke coverage: `test/smoke.sh`

New block `Stage 2.8 — Comment freshness` with CF-1..CF-7 assertions against a scratch two-commit repo (same setup pattern as Stage 2.6's FR-1..FR-7 / OC-1..OC-7 blocks):

- **CF-1 review_comment, path unchanged between commit_id and HEAD** → included; `action=fresh`.
- **CF-2 review_comment, path touched between commit_id and HEAD** → excluded; `action=stale`.
- **CF-3 review submission, commit_id present, no PR-diff file touched since** → included; `action=fresh`.
- **CF-4 review submission, commit_id present, some PR-diff file touched since** → excluded; `action=stale`.
- **CF-5 issue_comment, `created_at` newer than latest commit's `committer.date`** → included; `action=fresh-summary`. (Uses `--fixtures-dir` with a hand-crafted `pr_commits.json`.)
- **CF-6 issue_comment, `created_at` older than latest commit's `committer.date`** → excluded; `action=stale-summary`.
- **CF-7 unreachable commit_id (force-push simulation — synthesize a commit_id that doesn't exist in the scratch repo and fails the fetch fallback)** → excluded; `action=unreachable`.

Plus two tangential checks to guard the `external-scrape.sh` change:

- **CF-ES-1** `external-scrape.sh` without `--since` succeeds against the fixture dir (was previously a usage error).
- **CF-ES-2** `external-scrape.sh --since <iso>` is rejected with a usage error (ensures we actually removed the arg — not just ignored it).

Existing `G` scrape assertion from Stage 2 stays green with the same fixtures — the scraper's output shape is unchanged; only the filter got simpler.

Target total after this stage: **~96 + 9 = ~105 assertions** (tracking BUILD.md's "grew from N to M assertions" narrative).

### BUILD.md update

- Flip Stage 2.8 row from N/A to `done` in the stage index; add link to this section.
- New "Stage 2.8 — PR comment freshness" section with Files landed / Verification evidence / Open issues, matching Stage 2.5/2.6/2.7 shape.
- Append a cross-stage note dated 2026-04-18: "Replaced time-based PR comment filter with code-locality filter (policy C2). `review_started_at` demoted from scrape-anchor to metrics-only role. `--since` removed from `external-scrape.sh`."
- Current state sentence updated to "Stage 2.8 COMPLETE."

Copy this plan file into `plans/stage-2.8-comment-freshness.md` at close-out (matches Stage 2.5/2.6/2.7 convention per BUILD.md).

---

## Explicitly out of scope

- **Non-ensemble runs.** They don't scrape; Phase 1.5 skip gate untouched.
- **Policy A (always include)** or **policy B (always exclude)** for issue_comments. C2 is decided.
- **Per-comment timeline lookup** for issue_comments (full policy C). C2 is the simpler equivalent for the common case; upgrade only if a future run surfaces a case C2 misclassifies.
- **Changes to allow/deny bot config** (`review-config.json`). Untouched.
- **Re-introducing time-based filters.** If a future "only comments from last N days" need emerges, add a separate flag; don't conflate with freshness.
- **Schema change.** `review_started_at` stays required in schema-v1.json (still consumed by Phase 6 metrics). No schema version bump.
- **Renderer changes.** The filter runs before normalization → artifact `findings[]`, so the rendered `artifact.md` already benefits from better candidate input with no renderer-side work.
- **Retroactive re-run of C13 / PR #199.** User can choose to re-run `/adams-review --ensemble` on any prior PR after this stage ships; no automated backfill.

---

## Done when

1. `comment-freshness.sh` exists, is executable, passes CF-1..CF-7 + CF-ES-1/2.
2. `external-scrape.sh` no longer accepts `--since`; `02-ensemble-adapter.md` step 1.5.3 pipes through the new helper.
3. `test/smoke.sh` passes all assertions (existing + CF-*). Final count recorded in BUILD.md Stage 2.8 section.
4. `DESIGN.md` gains §21.10; §21.8, §4 Phase 0 step 4, §4 Phase 1.5 narratives updated.
5. `00-preflight.md` step 0.5 prose updated (no behavior change).
6. `BUILD.md` stage index + Stage 2.8 section filled in; cross-stage note appended.
7. Real-repo `/adams-review --ensemble` re-run deferred (same pattern as 2.6/2.7/3) — integration signal budgeted for the next ensemble-mode invocation on a real PR with pre-existing bot comments.

---

## Commit cadence (estimated)

1. **2.8.A** — `comment-freshness.sh` + DESIGN §21.10 + smoke CF-1..CF-7 — 1 commit.
2. **2.8.B** — `external-scrape.sh` `--since` removal + DESIGN §21.8 update + smoke CF-ES-1/2 — 1 commit.
3. **2.8.C** — Fragment rewire (`02-ensemble-adapter.md` + `00-preflight.md`) + DESIGN §4 narrative updates — 1 commit.
4. **2.8.D** — BUILD.md close-out (stage index + Stage 2.8 section + cross-stage note) + copy plan to `plans/stage-2.8-comment-freshness.md` — 1 commit.

~4 commits. No mid-stage plan-approval round-trips expected — scope is small and decisions are pinned above. If a blast-radius surprise turns up (e.g., a hidden second caller of `external-scrape.sh --since`), surface and decide.

---

## Critical files to modify

- `commands/_shared/tools/comment-freshness.sh` — **new**.
- `commands/_shared/tools/external-scrape.sh` — drop `--since`.
- `commands/_shared/02-ensemble-adapter.md` — step 1.5.3 rewrite.
- `commands/_shared/00-preflight.md` — step 0.5 prose trim.
- `DESIGN.md` — new §21.10; §21.8, §4 Phase 0 step 4, §4 Phase 1.5 updates.
- `test/smoke.sh` — CF-* block.
- `BUILD.md` — stage index row + new Stage 2.8 section + cross-stage note.
- `plans/stage-2.8-comment-freshness.md` — copied from this plan file at close-out.

Reusable patterns to lean on (no new abstractions):

- `origin-crosscheck.sh` (§21.9) for stderr-audit-with-`tee -a` and per-record `action=<verb>` grammar.
- `staleness.sh` (§21.4) for scratch-repo `git diff --name-only` + intersection check.
- `_common.py` exit codes are Python-only; for Bash helpers the convention is 0/1/64 per BUILD.md cross-stage notes.
- `external-scrape.sh` `--fixtures-dir` pattern for offline replay — mirror for `pr_commits.json`.

---

## Verification

### Per-commit

- After 2.8.A: `bash test/smoke.sh` — CF-1..CF-7 new assertions green; existing 96 unchanged.
- After 2.8.B: `bash test/smoke.sh` — CF-ES-1/2 green; CF-1..CF-7 green; existing 96 unchanged.
- After 2.8.C: `bash test/smoke.sh` — all green. Manual `grep -rn "review_started_at" commands/_shared/` confirms Phase 0 capture + Phase 6 consumer are the only remaining references.
- After 2.8.D: `bash test/smoke.sh` — all green. `git log --oneline` shows the four commits. BUILD.md "Current state" reflects Stage 2.8 complete.

### End-to-end (deferred)

Real-repo integration smoke: user runs `/adams-review --ensemble` on a PR with at least one pre-existing bot comment (e.g., CodeRabbit, Greptile). Verify in `trace.md`:

- `comment_freshness:` audit lines appear, one per scraped record.
- Comments on unchanged files get `action=fresh` and appear in `external_candidates`.
- Comments on files touched since posting get `action=stale` and do NOT appear in `external_candidates`.
- Final `artifact.md` reflects the filtered set in its Pre-existing and ensemble-sourced sections.

Record outcome in BUILD.md's Stage 2.8 Open issues or the next cross-stage note, whichever closes the integration gap first.

### Helper-level manual smoke (during development, not committed)

Pre-CF-* — exercise the helper against scratch fixtures by hand:

- Empty input array → empty output, exit 0, no audit lines.
- Mixed-kind input with one of each kind + one unreachable commit_id + one pre-commits-fetch issue_comment → audit lines match expected action verbs in stderr-captured order.
- `--reviewed-files @-` with empty stdin + review submission → should still process (empty intersection = fresh).
- Malformed JSON stdin → exit 1 + error-as-prompt matching the `_common` Bash convention (ERROR / Context / Action trio).

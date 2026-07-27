# Stage 1 — Foundation plan

**Status:** drafted 2026-04-17, awaiting user review.
**Preceded by:** Stage 0 bootstrap (commit `bd6b610`). DESIGN.md rev 8 is normative.
**Followed by:** Stage 2 (`/adams-review` end-to-end).

---

## 1. Goal

Build the data layer + shared helper infrastructure that Stages 2 and 3 consume. By the end of Stage 1:

1. A hand-authored synthetic `artifact.json` validates against `schema-v1.json`.
2. `artifact-patch.py` applies `--init`, `--add-finding`, `--set`, `--append-fix-attempt`, and `--dry-run` correctly, enforcing the state-transition whitelist (§5.3) and disposition/is_actionable coupling (§21.2).
3. `artifact-render.py` renders that artifact to Markdown matching §7 (filtered views over `findings[]` keyed on `disposition`, with the stable HTML-comment marker as line 1).
4. Schema-invalid inputs are rejected with error-as-prompt messages per §8.6.
5. All supporting Bash helpers (validate, read, publish, log, claude-md-paths, staleness) are in place and callable.

No slash-command wiring yet — Stage 2 does that.

---

## 2. Layout decision: symlink dev-repo into the live commands dir

**Pre-flight check (already done as of drafting):** `~/.claude/commands/_shared/` does not exist. Existing Adam commands (`adams-code-review.md`, `adams-super-code-review.md`, etc.) live at `~/.claude/commands/` but none uses a `_shared/` directory. Safe to create.

**Plan:** first task of execution is `ln -s ~/Projects/adams-review/commands/_shared ~/.claude/commands/_shared`. The dev repo grows `commands/_shared/{tools/,}` to mirror production. From that point on, every edit in the repo is live at the canonical `~/.claude/commands/_shared/tools/...` path with zero copy step.

**Close-out:** nothing to do at stage end. Symlink is already live. Stage close-out commits `BUILD.md` only.

**Alternatives considered:**
- Copy-at-stage-close install script: adds "forgot to sync" bugs between edits and tests. Rejected.
- Dev-in-place at `~/.claude/commands/_shared/` directly (no repo): loses git history, violates the stated repo layout. Rejected.

**Risks / mitigations:**
- Mid-stage symlink lives in the live environment before the scripts are complete. Mitigation: `allowed-tools` grants aren't issued yet (no top-level command file), so unsolicited invocations can't happen. Ad-hoc testing is scoped to a throwaway review_id.

---

## 3. Python dependency strategy — uv inline-script (PEP 723)

**Decision (updated 2026-04-17, behavioral deviation from initial draft — user approved):**
Every Python helper uses a `uv`-powered inline-script shebang:

```python
#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["jsonschema"]
# ///
```

`uv` resolves and caches `jsonschema` on first invocation. No venv, no `pip install`, no activation.

**Why the change.** Plain `pip install jsonschema` (the initial draft) is blocked by PEP 668 on Homebrew Python — `pip`, even with `--user`, refuses to install into an externally-managed site-packages. `uv` (already present at `/opt/homebrew/bin/uv 0.7.15`) sidesteps this cleanly; each script is self-contained and its dep list lives next to the code that imports it. Probe verified: `jsonschema 4.26.0` pulled in 10ms from cache; 6 packages on cold install.

**Tradeoff.** Machines running these commands need `uv`. For a personal tool this is fine; `README.md` deps table makes it explicit.

**Alternatives rejected:**
- `pip install --break-system-packages`: overrides PEP 668 warning; "least correct" path.
- Repo-local `.venv`: works, but couples shebangs to an absolute path in `~/Projects/adams-review/.venv/bin/python3`. Awkward if the repo ever moves.
- `pipx`: wrong tool — `jsonschema` is a library, not a CLI app.

**Cross-stage impact:** Stage 2 and Stage 3 will add more Python helpers (`group-fixes.py`). They inherit the same shebang. No further deviation expected.

---

## 4. Scope — files this stage creates

### Data layer (core)

| File | Purpose |
|---|---|
| `commands/_shared/schema-v1.json` | JSON Schema codifying §5–§6. Strict `additionalProperties: false` at every object level. |
| `commands/_shared/tools/_common.py` | Shared Python helpers: schema-validate, error-as-prompt formatter, atomic write (`tmp + rename`), path resolver via `latest.txt`, exit-code constants. |
| `commands/_shared/tools/artifact-patch.py` | Full §21.2 implementation: `--init`, `--add-finding`, `--set <field=value>` (repeatable), `--append-fix-attempt <json>`, `--dry-run`, state-transition whitelist, disposition/is_actionable coupling, append-only guards on `fix_attempts` + `score_history`. |
| `commands/_shared/tools/artifact-render.py` | §7 template: marker line, header block, section selectors keyed on `disposition`, fix-runs section when `fix_attempts` present. |

### Bash glue

| File | Purpose |
|---|---|
| `commands/_shared/tools/artifact-validate.sh` | Thin wrapper calling Python validator; exits non-zero with human-readable errors per §21.3. |
| `commands/_shared/tools/artifact-read.sh` | jq wrapper: `--filter`, `--finding-id`, `--summary`. Default path via `latest.txt`. |
| `commands/_shared/tools/artifact-publish.sh` | Full §21.6 implementation: PR-mode comment discovery (comment_id → marker fallback), PATCH/POST, `{"comment_id": N}` stdout emit, local-mode no-op. |
| `commands/_shared/tools/claude-md-paths.sh` | §21.7: walk up from each file, collect `CLAUDE.md`, dedupe, root-first sort. |
| `commands/_shared/tools/staleness.sh` | §21.4: git-diff intersection, safe/warn/unsafe stdout. |
| `commands/_shared/tools/log-phase.sh` | §21.6: `--summary` mode appends to `trace.md`; `--record` mode appends to `phases.jsonl`. |
| `commands/_shared/tools/log-tokens.sh` | New helper (DESIGN §11 specifies the record shape but not the helper). Appends one JSONL line to `tokens.jsonl`. Parse-failure fallback: accept `--tokens null` literal. |

### Test fixtures and smoke harness

| File | Purpose |
|---|---|
| `test/fixtures/artifact-seed.json` | Valid seed doc for `--init`. Minimal: one finding per disposition. |
| `test/fixtures/expected.md` | Eyeballed reference output of `artifact-render.py` run against the full exercised artifact. |
| `test/smoke.sh` | Single Bash script exercising the full Stage 1 done-when walk-through (see §7 below). |
| `test/fixtures/invalid/` | A small set of schema-invalid / transition-invalid artifacts for negative tests. |

### Intentionally NOT in Stage 1

- All `_shared/*.md` phase fragments (`00-preflight.md`, `01-detection.md`, …, `10-post-fix-and-commit.md`) — Stage 2 & 3 draft these as they assemble the phases.
- Lens reference files (`lens-ux-reference.md`, `lens-security-reference.md`) — Stage 2.
- `external-scrape.sh` — Phase 1.5 only, Stage 2.
- `group-fixes.py` — Phase 8 only, Stage 3.
- Top-level `adams-review.md` + `adams-review-fix.md` — Stages 2 & 3.
- Runtime directories under `~/.claude/reviews/<slug>/<branch>/...` — created by orchestrator at Phase 0 in Stage 2, not at build time.

---

## 5. Task order and commit breakdown

Each bullet = one commit (approximate; collapse adjacent ones if diffs are tiny):

1. **Scaffold + symlink.** Create `commands/_shared/tools/` in the repo; symlink `~/.claude/commands/_shared` → repo path; short `commands/_shared/README.md` pointing at DESIGN.md.
2. **`schema-v1.json`.** Full §5–§6 shape with strict enums and `additionalProperties: false`. Includes the top-level `schema_version`, `review_id`, `findings[]`, `cross_cutting_groups[]`, `subagent_tokens`, `metrics` sub-shapes.
3. **`_common.py`.** Shared helpers: schema-validate, error-as-prompt formatter, atomic write, path resolver, exit-code constants (`1=validation`, `2=invalid transition`, `3=dry-run-invalid`, `4=unexpected/crash`; see §8 below).
4. **`artifact-patch.py --init`.** Create fresh artifact from seed; validate; atomic write.
5. **`artifact-patch.py --add-finding`.** Append with full re-validation, rejects duplicate IDs.
6. **`artifact-patch.py --set` with transition whitelist + disposition/is_actionable coupling.** §5.3 + §21.2. Error-as-prompt messages list valid values + suggested corrections.
7. **`artifact-patch.py --append-fix-attempt`.** Append-only guard for `fix_attempts`; also append-only for `score_history` when `score_phase3`/`score_phase4` is set.
8. **`artifact-patch.py --dry-run`.** Validates, prints diff (unified), exits 0 without writing; non-zero if the patched artifact would be invalid.
9. **`artifact-render.py`.** §7 template: marker, header, four disposition-filtered sections (deep auto / deep manual / deep uncertain / light / pre-existing), optional fix-runs section when any finding has `fix_attempts[]`. Manual eyeball diff against `expected.md`.
10. **`artifact-validate.sh`.** Thin Bash wrapper around `_common.py` validation.
11. **`artifact-read.sh`.** jq wrapper + canned `--summary` jq.
12. **`log-phase.sh` + `log-tokens.sh`.** Two small Bash appenders. `trace.md` append is plain cat; `phases.jsonl` / `tokens.jsonl` appends run through `jq -c` for shape check.
13. **`claude-md-paths.sh`.** Pure Bash walk per §21.7.
14. **`staleness.sh`.** `git diff --name-only` intersection per §21.4.
15. **`artifact-publish.sh`.** `gh api` comment discovery (comment_id arg → PR issue-comments list filtered by current gh user + marker → take most recent), PATCH/POST branches, `{"comment_id": N}` stdout emit. Local-mode no-op.
16. **Smoke harness.** `test/smoke.sh` walks the full done-when flow. Negative-test fixtures exercise invalid transitions and schema violations.
17. **BUILD.md close-out.** Flip Stage 1 status to done. Fill `Files landed` / `Verification evidence` / `Open issues` / `Cross-stage notes`.

Commits 4–9 all touch `artifact-patch.py`/`artifact-render.py` — they stay separate so the journal is readable. Commits 10–15 are small; can be collapsed 2-at-a-time if sensible.

---

## 6. Error-as-prompt house style

Every script on non-zero exit emits to stderr, in this order (§8.6 shows examples but not the exact phrasing; picking a house style now and documenting here):

```
ERROR: <specific thing that went wrong, naming the field/value>
<context line 1: what the valid values / allowed states are>
<context line 2: optional "Did you mean X?" suggestion>
<action line: what to do next>
```

Example (state transition):
```
ERROR: invalid transition from 'open' to 'resolved' for finding F001
Valid transitions from 'open': attempted
A finding must be attempted (Phase 8) before it can be resolved.
Action: set current_state=attempted first, then --append-fix-attempt, then set resolved.
```

Example (missing Python dep):
```
ERROR: missing Python dependency 'jsonschema'
This package provides Draft 2020-12 JSON Schema validation.
Install: pip install jsonschema  (or pip3 install jsonschema)
Action: install, then re-run.
```

No stack traces on expected errors. Wrap unexpected errors (schema load failure, disk full) in a catch-all that prints the traceback once to stderr with a leading `UNEXPECTED ERROR:` prefix so it's distinguishable from error-as-prompt.

---

## 7. Stage 1 smoke harness — the Done-when walk-through

`test/smoke.sh` performs, against a throwaway dir:

```bash
# 1. --init from seed
artifact-patch.py --init "$(cat fixtures/artifact-seed.json)" --path /tmp/art.json
# 2. --add-finding
artifact-patch.py --path /tmp/art.json --add-finding '{"id":"F099",...}'
# 3. validate success
artifact-validate.sh --path /tmp/art.json
# 4. invalid transition — MUST fail non-zero with error-as-prompt
artifact-patch.py --path /tmp/art.json --finding-id F001 --set current_state=resolved
# 5. valid transition
artifact-patch.py --path /tmp/art.json --finding-id F001 --set current_state=attempted
# 6. resolved requires disposition=resolved — MUST fail alone
artifact-patch.py --path /tmp/art.json --finding-id F001 --set current_state=resolved
# 7. resolved + disposition=resolved — succeeds
artifact-patch.py --path /tmp/art.json --finding-id F001 --set current_state=resolved --set disposition=resolved
# 8. append-fix-attempt
artifact-patch.py --path /tmp/art.json --finding-id F001 --append-fix-attempt '{"run_id":"fixrun_X","timestamp":"2026-04-17T21:00:00Z","fix_group_id":"FG-1","input_sha":"a1","output_sha":"b2","phase_9_outcome":"verified"}'
# 9. render
artifact-render.py --input /tmp/art.json --output /tmp/art.md
diff /tmp/art.md fixtures/expected.md
# 10. negative: bad disposition
! artifact-patch.py --path /tmp/art.json --finding-id F001 --set disposition=bogus
# 11. negative: is_actionable disagrees with disposition
! artifact-patch.py --path /tmp/art.json --finding-id F001 --set is_actionable=true --set disposition=below_gate
# 12. --dry-run on invalid
! artifact-patch.py --path /tmp/art.json --finding-id F001 --set current_state=bogus --dry-run
```

Pass = every assertion matches. Not a pytest suite; a shell walk-through is enough for Stage 1's done-when.

---

## 8. Exit codes (clarification; §21.2 says "non-zero")

Since DESIGN §21.2 doesn't specify, standardizing now:

| Code | Meaning |
|---|---|
| 0 | success (or `--dry-run` valid) |
| 1 | schema / field validation error |
| 2 | invalid state transition |
| 3 | `--dry-run` would produce invalid artifact |
| 4 | unexpected error (uncaught exception) |
| 5 | missing dependency (`jsonschema` not installed) |
| 64 | usage / argparse error (conventional) |

Logged into DESIGN.md as a §21.2 footnote at execution time (clarification-level update per BUILD.md protocol).

---

## 9. Design adjustments likely to surface (flagged early)

Per BUILD.md "Adjusting the design as we build" — clarifications get inline DESIGN updates + a Cross-stage notes entry; behavioral changes stop and ask.

**Clarification-level (expected):**
- Exit codes for `artifact-patch.py` (covered in §8 above).
- Error-as-prompt message phrasing (house style in §6 above).
- Atomic-write temp filename convention: I'll use `<target>.tmp.<pid>` in the same dir (so `rename` is atomic on the same filesystem).
- Behavior when `artifact-patch.py --set` receives a field not in the schema: reject with error-as-prompt listing valid fields (not silently ignored).

**Behavioral (will stop and ask if they surface):**
- Any schema field add / rename / type change beyond DESIGN §6.
- `artifact-render.py` needing sections not covered by §7.
- Symlink strategy proving unworkable (e.g. `allowed-tools` grants don't resolve through the symlink — unlikely per §8.7 research but possible).
- `artifact-publish.sh` behaviors not covered by §21.6 (e.g. multi-account `gh` auth ambiguity).

---

## 10. Decisions (confirmed by user 2026-04-17)

1. **Symlink timing:** created immediately as step 1 of execution (already live at time of this edit). Scripts don't become active until a top-level command with matching `allowed-tools` exists in Stage 2.
2. **Python deps:** `uv` inline-script shebang (see §3; revised from plain pip after PEP 668 blocker surfaced).
3. **`artifact-publish.sh` real PR-mode test:** deferred to Stage 2. Stage 1 verifies shell path + local-mode no-op only.
4. **`allowed-tools` grant probe (§8.7):** done in Stage 1 as throwaway validation. Artifacts set up in-session; user triggers the probe in a separate `default`-mode Claude Code session; findings recorded in BUILD.md cross-stage notes before teardown.

---

## 11. Exit criteria — Stage 1 Done

- [ ] `schema-v1.json` validates the hand-authored synthetic artifact.
- [ ] `artifact-patch.py --init`, `--add-finding`, `--set`, `--append-fix-attempt`, `--dry-run` all work.
- [ ] State-transition whitelist rejects invalid transitions with error-as-prompt.
- [ ] Disposition/is_actionable coupling enforced; resolved-state coupling enforced.
- [ ] `artifact-render.py` output matches `fixtures/expected.md` exactly.
- [ ] All Bash helpers work: `artifact-validate.sh`, `artifact-read.sh`, `artifact-publish.sh` (dry / local mode), `claude-md-paths.sh`, `staleness.sh`, `log-phase.sh`, `log-tokens.sh`.
- [ ] `test/smoke.sh` passes end-to-end (all 12 steps).
- [ ] Symlink live; ad-hoc invocation through `~/.claude/commands/_shared/tools/...` works.
- [ ] BUILD.md close-out section filled in.
- [ ] All commits on `main` (no feature branches needed for Stage 1; it's all new files).

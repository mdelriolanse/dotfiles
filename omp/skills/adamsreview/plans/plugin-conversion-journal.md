# Plugin conversion build journal

Progress log for executing `plans/plugin-conversion-execution.md`. The
orchestrator appends one entry per phase as it goes. Brief summaries only —
no sub-agent output dumps. Link to commit shas.

Phases with "(interactive)" in the status column have user-testable
acceptance criteria the orchestrator cannot verify (require a live Claude
Code session with the plugin loaded). The orchestrator still does the file
work, but flags those phases' commit messages accordingly.

---

## Status summary

| Phase | Status | Commit | Iterations | Notes |
|---|---|---|---|---|
| Pre-flight | pending | — | — | record N (smoke baseline) below |
| 0 Repo scaffolding | done | 3345960 | 1 | license set proprietary (LICENSE on disk, not MIT) |
| 1a Helpers + fragments migration | done | fefcd2c | 1 | smoke 203/203 — fragments still reference `~/.claude/commands`, cleaned in 2.2 |
| 1b.1 Promote command port | done | 174583e | 1 | file work only — commit tagged (interactive tests deferred) |
| 1b.3–1b.4 (interactive) | deferred | — | — | user tests plugin-loaded session |
| 1b.5 commit | done | 174583e | 1 | bundled with 1b.1 per plan |
| 2.1–2.2 Remaining 4 commands | done | c1608e3 | 1 | 4 renames + 12 fragments audited; smoke 203/203 |
| 2.3 per-command sanity (interactive) | deferred | — | — | user tests each command |
| 2.4 commit | done | c1608e3 | 1 | bundled with 2.1–2.2 |
| 3 Install scripts + smoke | done | e058af4 | 1 | new smoke baseline **204** (was 203) |
| 4 SessionStart hook | done | 107706c | 1 | file work only; live-fire test is user-side |
| 5 Docs rewrite | done | fb3876c | 1 | CLAUDE.md + README.md fully re-anchored on plugin layout |
| 6.1 Mechanical verification | done | (no commit) | 1 | all checks green |
| 6.2–6.3 (interactive) | deferred | — | — | user tests real review + AskUserQuestion |
| 6.4 commit | skipped | — | — | plan says "commit if touch-ups" — none needed |
| 7 Plugin cold-boot + doc-drift follow-up | done | 060ced6 | 1 | unplanned: caught post-Phase-5 slash-command-ref drift |

---

## Pre-flight findings

- worktree confirmed: yes — `/Users/adammiller/Projects/adams-review/.claude/worktrees/plugin-conversion`
- deps verified: uv, jq, gh, git, claude CLI all resolve. Only `/bin/bash` 3.2 available (no homebrew bash 4+); smoke and `claude plugin validate .` both run successfully under 3.2, so the "bash 4 for validation gate" concern didn't materialize.
- baseline smoke assertion count (**N**): **203**
- `claude --version`: 2.1.117
- working tree: clean except for untracked `plans/plugin-conversion-*.md` plan docs (expected)
- candidate artifact for 1b.3 test: `/Users/adammiller/.adams-reviews/github.com-cdinnison-ray-finance/feat/import-apple-review-3/rev_01KPP38V0VZ5TDZ1WQN84HPNRW` (user to pick a specific finding_id at test time)
- `claude plugin validate .` pre-Phase-0: reports "No manifest found" as expected (Phase 0 creates it)

---

## Phase entries

Append one section per phase, following this template. Keep each entry
under ~20 lines.

```
### Phase N (title)

Started: <UTC ISO>
Completed: <UTC ISO>
Build iterations: N
Commit: <sha> (short message)

**Summary**: 2–3 sentences of what changed.

**Files touched**: bulleted list (paths, short reason per).

**Verification**:
- `claude plugin validate .`: pass/fail
- `bash test/smoke.sh`: pass/fail (assertion count: N)
- Other: phase-specific checks from acceptance criteria

**Interactive items deferred**: list if applicable, empty if none.

**Notes**: anything non-obvious or worth flagging to the user.
```

---

### Phase 0 Repo scaffolding

Completed: 2026-04-22
Build iterations: 1
Commit: 3345960 (Plugin scaffolding: manifest, marketplace, layout dirs, LF gitattributes)

**Summary**: Created `.claude-plugin/{plugin,marketplace}.json`, empty `bin/`/`fragments/`/`hooks/` with `.gitkeep`, and LF-enforcing `.gitattributes`. `claude plugin validate .` passes with one benign warning (marketplace metadata.description).

**Files touched**:
- `.claude-plugin/plugin.json` — plugin manifest (name adams-review, v0.1.0, repository URL to adamjgmiller/adams-review)
- `.claude-plugin/marketplace.json` — single-plugin marketplace with `source: "./"`
- `.gitattributes` — LF for .sh/.py/.json/.md (D17a)
- `bin/.gitkeep`, `fragments/.gitkeep`, `hooks/.gitkeep` — layout placeholders

**Verification**:
- `claude plugin validate .`: pass (1 marketplace description warning, acceptable)
- `bash test/smoke.sh`: n/a for this phase (no code changes)
- Directory tree: matches acceptance criteria

**Notes**: The plan's step 0.1 specified `"license": "MIT"` but the on-disk `LICENSE` is `LicenseRef-Proprietary` ("All rights reserved"). Wrote the SPDX value that matches reality. If you intended the plugin to be MIT-distributable, that requires an independent LICENSE change.

### Phase 1a Helpers + fragments migration

Completed: 2026-04-22
Build iterations: 1
Commit: fefcd2c (Phase 1a: migrate all helpers + fragments to plugin layout, add include wrapper, update smoke)

**Summary**: Moved 20 helpers + `schema-v1.json` into `bin/`, 14 fragments into `fragments/`, added `bin/include` wrapper, retargeted smoke paths, and updated `_common.py`'s SCHEMA_PATH to script-local.

**Files touched** (grouped):
- `commands/_shared/tools/* → bin/*` — 20 helpers
- `commands/_shared/schema-v1.json → bin/schema-v1.json`
- `commands/_shared/{00–10,lens-*,promote-core}.md → fragments/*.md` — 14 fragments
- `bin/include` — new 5-line wrapper
- `bin/_common.py` — line 32 parent.parent → parent, line 89 guidance rewrite, docstring bin/
- `test/smoke.sh` — TOOLS var, fragment vars, plus 5 inline literal fragment paths at 2971–3065
- `commands/_shared/README.md`, `bin/.gitkeep`, `fragments/.gitkeep` deleted

**Verification**:
- `bash test/smoke.sh`: PASS (203 assertions — same as baseline)
- `grep _shared/ test/smoke.sh`: 0 hits
- `commands/_shared/`: absent
- `bin/include`: executable

**Notes**: The 4 unported command files (`adams-review.md` etc.) still reference `~/.claude/commands/_shared/tools/...` and `!cat ~/.claude/commands/_shared/<fragment>.md` — intentionally broken until Phase 2 ports them. Fragments retain 4 internal cross-refs (`fragments/{00,01,05,07}`) that Phase 2.2 will fix.

### Phase 1b Promote command port

Completed: 2026-04-22
Build iterations: 1
Commit: 174583e (Phase 1b: port promote command to plugin layout (POC))

**Summary**: Renamed `adams-review-promote.md` → `promote.md` (history preserved), rewrote frontmatter (6 abs-path grants → bare-name + `include:*`) and body (5 helper refs + 1 `!cat`→`!include`), updated smoke's `PROMOTE_MD` var.

**Files touched**:
- `commands/adams-review-promote.md → commands/promote.md` — rename + rewrite
- `test/smoke.sh` — PROMOTE_MD path update

**Verification**:
- `bash test/smoke.sh`: PASS (203/203)
- `grep ~/.claude/commands commands/promote.md`: 0 hits
- `git log --follow commands/promote.md`: rename detected, history preserved

**Interactive items deferred**:
- 1b.3: user runs `/adams-review:promote <F-id> --defer-publish --reason "POC"` against an existing artifact.
- 1b.4: user runs full-publish against a throwaway test PR.

**Notes**: `fragments/promote-core.md` still references `~/.claude/commands/_shared/tools/...` in its body — correctly deferred to Phase 2.2 (fragment audit).

### Phase 2 Remaining 4 commands + fragment audit

Completed: 2026-04-22
Build iterations: 1
Commit: c1608e3 (Phase 2: port remaining 4 commands to plugin layout)

**Summary**: Renamed and rewrote review/fix/walkthrough/add. Audited all 12 non-promote-core fragments; replaced 101 helper refs and 3 fragment cross-references with bare-name / `!include` forms.

**Files touched**:
- `commands/{adams-review,-fix,-walkthrough,-add}.md → commands/{review,fix,walkthrough,add}.md`
- All 13 fragments under `fragments/` (every fragment except `promote-core.md` already touched in 1b, which was also re-audited here)
- `test/smoke.sh` — WALK_MD + ADD_MD retargeted

**Verification**:
- `bash test/smoke.sh`: PASS (203/203)
- `grep -rnE '~/.claude/commands|/_shared/' commands/ fragments/`: 0 hits
- Every command file has `Bash(include:*)` grant
- No abs-path `Bash(/Users...)` grants remain

**Interactive items deferred**:
- 2.3: user runs each of 4 commands once against a real target (trivial-mode review, fix on confirmed_mechanical artifact, walkthrough on walkable artifact, add in structured mode).

**Notes**: Build agent flagged a pre-existing gap — `review.md`'s `allowed-tools` doesn't list `line-range-check.sh`, which `01-detection.md` invokes. Not a Phase 2 regression (the helper wasn't granted previously either, just with a different path). May surface at runtime; will want fixing in a follow-up.

### Phase 3 Install scripts + smoke

Completed: 2026-04-22
Build iterations: 1
Commit: e058af4

**Summary**: Deleted install.sh/uninstall.sh (D13), added 5-line `scripts/dev-run.sh` wrapper for plugin-author iteration, replaced smoke's RA-9 (install-script symlink assertion) with PL-1 (dev-run exists+exec) and PL-2 (plugin.json valid JSON).

**Files touched**:
- `scripts/install.sh`, `scripts/uninstall.sh`: deleted
- `scripts/dev-run.sh`: new (exec claude --plugin-dir "$REPO_ROOT" "$@")
- `test/smoke.sh`: RA-9 → PL-1/PL-2

**Verification**:
- `bash test/smoke.sh`: PASS (**204 assertions** — new baseline)
- `bash scripts/dev-run.sh --version`: prints `2.1.117 (Claude Code)` (arg forwarding works)
- `scripts/` contains only `dev-run.sh`

**Notes**: Assertion label family `PL-*` is new; CLAUDE.md conventions list FR/RH/OC/FX/MP/WT but don't prohibit new families. Phase 5's CLAUDE.md rewrite can optionally mention it.

### Phase 4 SessionStart hook

Completed: 2026-04-22
Build iterations: 1
Commit: 107706c

**Summary**: Added `hooks/dep-check.sh` (soft-warn on missing uv/jq/gh/git, OS-specific install hints, always exit 0) and `hooks/hooks.json` registering it on SessionStart.

**Files touched**:
- `hooks/dep-check.sh` — new (executable)
- `hooks/hooks.json` — new (top-level "hooks" wrapper per D18)
- `hooks/.gitkeep`: deleted

**Verification**:
- `claude plugin validate .`: pass (only pre-existing marketplace description warning)
- `jq . hooks/hooks.json`: parses cleanly
- `bash hooks/dep-check.sh`: empty output, exit 0 on this machine

**Notes**: Live-fire test (4.3 — start a fresh session, temporarily stash `jq` to confirm the warning and install-hint) is user-side. The plan treats this as acceptable since the mechanical artifact is verifiable.

### Phase 5 Docs rewrite

Completed: 2026-04-22
Build iterations: 1
Commit: fb3876c

**Summary**: Rewrote CLAUDE.md and README.md for the plugin layout — namespacing (`/adams-review:*`), layout tree swap, operational rule 10 inversion (bare-name grants), helper index bin/ paths + `prior-fix-diff.sh` addition, assertion count 129→204, Dependencies Windows row, README install flow + Troubleshooting section.

**Files touched**:
- `CLAUDE.md` — ~25 edits across command refs, layout tree, rule 7, rule 10, helper index, assertion count, deps table
- `README.md` — install section rewrite, command-ref namespacing, new Troubleshooting section

**Verification**:
- `grep -rE '~/.claude/commands|/_shared/' CLAUDE.md README.md`: 0 hits
- `bash test/smoke.sh`: PASS (204 — docs-only changes, no impact)

**Notes**: Build agent summarized `prior-fix-diff.sh` purpose from its script header as a Phase 1 L2 deterministic prior-fix suspect scan. Verify the phrasing fits your intended surface; easy tweak in a follow-up if not.

---

### Phase 7 (unplanned follow-up) Plugin cold-boot + doc-drift cleanup

Completed: 2026-04-22
Build iterations: 1
Commit: 060ced6

**Context**: During post-6.1 cold-boot validation (`claude --plugin-dir "$PWD" -p "list plugin commands"`), the plugin loaded cleanly with all 5 `/adams-review:*` commands discovered. `bin/include` verified end-to-end (happy path + exit-64 error path). But the cold-boot surfaced a scope gap in the original plan: the D18 rename covered file names, frontmatter, body helper calls, and CLAUDE.md/README.md — but NOT slash-command name references inside fragment/command PROSE, nor inside the PR-comment renderer's output strings.

**Summary**: Rewrote ~150 stale `/adams-review-{fix,add,walkthrough,promote}` references to `/adams-review:*` across 20 files, including the renderer output (`bin/artifact-render.py`) + its fixture in lockstep.

**Files touched**:
- 5 command files (add, fix, promote, review, walkthrough)
- 7 fragments (00, 05, 07, 08, 09, 10, promote-core)
- 6 bin/ helpers with user-visible output (artifact-render.py, schema-v1.json, artifact-publish.sh, tally-subagent-tokens.sh, assign-finding-ids.sh, artifact-patch.py)
- `test/fixtures/expected.md` — kept in lockstep with renderer
- `test/smoke.sh` — cosmetic message-string updates

**Deliberately preserved**:
- `/tmp/adams-review-*` scratch-file prefixes
- `~/.adams-reviews/` state directory
- `<!-- adams-review-v1 -->` / `<!-- adams-review-walkthrough-v1 -->` HTML discovery markers (renaming would orphan existing PR comments)

**Verification**:
- `bash test/smoke.sh`: PASS (204) — render fixture still matches
- Plugin cold-boot via `claude --plugin-dir "$PWD" -p …`: 5 commands discovered
- `CLAUDE_PLUGIN_ROOT=$PWD bin/include promote-core.md`: works; missing fragment → exit 64 with plan-spec message

**Notes**: This was not in the execution plan. Caught by running the plugin end-to-end after phase completion, which is why the plan's acceptance grep (`~/.claude/commands`) missed it — that pattern doesn't match bare slash-command names.

---

### Phase 6.1 Mechanical verification

Completed: 2026-04-22
Build iterations: 1 (verification-only; no code changes)
Commit: none (plan conditions the 6.4 commit on final touch-ups; none were needed)

**Summary**: All five mechanical checks + the acceptance grep pass clean. Plugin is structurally ready for the interactive 6.2/6.3 gates.

**Verification**:
- `bash test/smoke.sh`: PASS (204 assertions)
- `claude plugin validate .`: passes with one pre-existing warning (`metadata.description` on marketplace manifest — optional to silence)
- `jq -r '.version' .claude-plugin/plugin.json`: `0.1.0`
- `git ls-files --eol bin/`: every entry `i/lf w/lf` — no CRLF
- `grep -rE '~/.claude/commands' . --exclude-dir=.git --exclude-dir=docs/archive --exclude-dir=plans`: 0 hits
- `git log --oneline plugin-conversion ^main`: 7 commits, Phase 0→5 in order

**Interactive items deferred to user**:
- 6.2: one non-trivial `/adams-review:review` run exercising the 6-way Phase 1 lens fan-out.
- 6.3: AskUserQuestion check in default + `acceptEdits` permission modes.

---

## End-of-run summary

All seven non-interactive phases committed. Ready for the three user-side interactive gates.

**Commits (oldest → newest)**:
```
3345960 Plugin scaffolding: manifest, marketplace, layout dirs, LF gitattributes
fefcd2c Phase 1a: migrate all helpers + fragments to plugin layout, add include wrapper, update smoke
174583e Phase 1b: port promote command to plugin layout (POC)
c1608e3 Phase 2: port remaining 4 commands to plugin layout
e058af4 Phase 3: delete install scripts, add dev-run.sh wrapper, rewrite smoke install-script assertions
107706c Phase 4: SessionStart dep-check hook
fb3876c Phase 5: docs — rewrite CLAUDE.md and README.md for plugin layout
060ced6 Phase 7 (follow-up): scrub stale /adams-review-* slash-command refs in prose + renderer output
```

**Interactive tests pending** (pulled from plan):
- **1b.3**: in a Claude Code session loaded with the plugin, invoke
  `/adams-review:promote <F-id> --defer-publish --reason "POC smoke test"`
  against any existing artifact under `~/.adams-reviews/`.
  Pick a finding currently `disposition: confirmed_manual` or `confirmed_report`.
- **1b.4**: full-publish test — `/adams-review:promote <id> --reason "full-publish POC"` (no --defer-publish) against a throwaway test PR.
- **2.3**: in a fresh session, invoke each of the remaining four commands once:
  - `/adams-review:review` against a docs-only PR (trivial_mode auto-detects).
  - `/adams-review:fix` against an artifact with ≥1 `confirmed_mechanical`.
  - `/adams-review:walkthrough` against an artifact with ≥1 walkable finding.
  - `/adams-review:add` in structured mode: `--file <path> --line <N> --claim "..."`.
- **6.2**: one non-trivial `/adams-review:review` run (code PR, not docs-only) to exercise the 6-way Phase 1 fan-out. Verify tokens.jsonl shows exactly 6 phase-1 entries (7 with --ensemble).
- **6.3**: AskUserQuestion check — invoke `/adams-review:promote` without `--reason` to trigger AUQ. Verify in default AND `acceptEdits` permission modes.

**Known gap (non-blocking, pre-existing)**: `commands/review.md`'s `allowed-tools` does not grant `Bash(line-range-check.sh:*)`, which `fragments/01-detection.md` invokes. The old pre-conversion review command had the same gap (under its abs-path form). Surface this at runtime if review invocation pauses for permission; fix in a follow-up.

**License note**: the plan's scaffolding step assumed MIT but the on-disk `LICENSE` is proprietary (`LicenseRef-Proprietary`). `.claude-plugin/plugin.json` was populated to match the actual file. If public distribution is intended, relicense the LICENSE file first and update `plugin.json`.

**Next command for the user**:
```
claude --plugin-dir "$PWD"
```

Sample POC invocation inside that session (1b.3):
```
/adams-review:promote <F-id> --defer-publish --reason "POC"
```

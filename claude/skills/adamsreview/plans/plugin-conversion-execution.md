# Plugin Conversion — Executable Checklist

Convert the `adams-review` slash-command suite into a Claude Code plugin distributable via `/plugin marketplace add`. Five top-level commands, 20 helper scripts, 14 fragments (11 phase + 2 lens-reference + promote-core). Target: native cross-platform support (macOS/Linux/Windows-via-Git-Bash) with no behavior change to the review pipeline itself.

## Context for the reviewer

`adams-review` is a 5-command slash-command suite for multi-agent code review of GitHub PRs, currently in production use as a personal tool installed via symlinks. This plan converts it to a Claude Code plugin distributable via `/plugin marketplace add`. No behavior change to the review pipeline itself — purely a packaging migration.

### Required reading (read in this order)

1. **This plan** (`plugin-conversion-execution.md`) — what we're going to do.
2. **`plugin-conversion.md`** — the decisions doc. Every D-ID citation in this plan (D1, D5, D17, etc.) resolves here. Without it, you can't tell *why* one strategy was picked over alternatives.
3. **`plugin-conversion-checklist.md`** — the original third-party audit input. Tells you what universe of considerations was on the table, so you can spot what was dropped.
4. **`CLAUDE.md`** — the codebase guide. Defines the vocabulary this plan uses without explaining (`disposition`, `human_confirmation`, `confirmed_mechanical`, `fix_groups`, `trivial_mode`, deep/light lanes, helper index, operational rules).

### Helpful for deep critique

5. `README.md` — user-facing install + workflow. Helps judge whether Phase 5's docs rewrite covers the right surface.
6. `commands/adams-review-promote.md` (sample command) — see the *current* frontmatter and `!cat` patterns being migrated.
7. `commands/_shared/tools/_common.py` — line numbers 32 and 89 are referenced for edits.
8. `test/smoke.sh` — judge whether wholesale path replacement is reasonable.

### Reference URLs

- Anthropic plugin docs: <https://code.claude.com/docs/en/setup> — Windows shell model, plugin install, manifest schemas.

### What to scrutinize (v2 — post external review)

This is the second round of the plan. A previous external reviewer caught schema mismatches, a command-namespacing miss, and testing gaps; those are folded in and called out inline with "D18" citations (see §16 of `plugin-conversion.md`). For a fresh review:

1. **Schema correctness**, re-verified. Schemas for `plugin.json`, `marketplace.json`, and `hooks/hooks.json` were corrected in the v2 pass. Flag any remaining mismatch against current docs.
2. **Sequencing**. Phase 1a does a wholesale helper+fragment migration in one pass; Phase 1b ports and renames one command (POC); Phase 2 ports the remaining 4 with renames; Phase 3 rewrites smoke's install-script assertions before deleting those scripts. Confirm no broken intermediate state.
3. **Namespacing consequences** (D18). Plugin commands are `/adams-review:review`, `/adams-review:promote`, etc. Command files renamed from `adams-review-<stem>.md` to `<stem>.md`. Flag any invocation-name contexts the plan still has in the old form.
4. **Acceptance criteria**. Each phase has a "this is done when" gate anchored on `claude plugin validate .` (for structural gates) and real invocation (for behavioral gates). Confirm those are testable.
5. **Anything missed**. The "Out of scope" section near the end lists what was consciously deferred — flag anything you'd have included.

## Pre-flight

- [ ] Confirm working in `plugin-conversion` worktree (not main): `git rev-parse --show-toplevel` should end in `.claude/worktrees/plugin-conversion`.
- [ ] Working tree clean: `git status` reports nothing.
- [ ] All deps present: `command -v uv jq gh git bash` all resolve.
- [ ] Bash version ≥ 4: `bash --version | head -1` (macOS default 3.2 is OK for shipped scripts but not for the validation gate).
- [ ] Baseline smoke passes: `bash test/smoke.sh` reports `smoke: PASS (N assertions)`. Record `N` here: __________ (used in Phase 6 to confirm no regression in count).
- [ ] `claude` CLI available: `claude --version` resolves. Needed for `claude plugin validate` gates in Phases 0, 4, and 6.
- [ ] At least one existing artifact available for Phase 1b: `ls ~/.adams-reviews/*/*/` should show at least one `<review_id>/artifact.json`. Pick one and record its full path: __________ (used in Phase 1b for `--defer-publish` test).
- [ ] At least one throwaway test PR available (or willing to create one) for Phase 1b publish-mode test.

---

## Phase 0 — Repo scaffolding

Create the plugin's required structural files at repo root. Per D1 (repo IS the plugin), D2 (single-plugin marketplace), D3 (schema in `bin/`), D17a (LF gitattributes), D15 (start at `0.1.0`).

### 0.1 Create `.claude-plugin/plugin.json`

```json
{
  "name": "adams-review",
  "version": "0.1.0",
  "description": "Multi-lens code review pipeline: deep review, automated fix loop, interactive walkthrough, manual promote, external-finding injection.",
  "author": { "name": "Adam Miller" },
  "license": "MIT",
  "keywords": ["code-review", "pr-review", "review"],
  "repository": "https://github.com/<OWNER>/adams-review"
}
```

- [ ] Replace `<OWNER>` with actual GitHub owner.
- [ ] Verify `license` matches the repo's `LICENSE` file (currently MIT per `LICENSE` content; confirm).

Schema notes (per D18 corrections): `repository` is a **string URL**, not an npm-style `{type, url}` object. `name` is the only strictly-required field; everything else above is best-practice. `claude plugin validate .` in the acceptance step is the authoritative check.

### 0.2 Create `.claude-plugin/marketplace.json`

```json
{
  "name": "adams-review",
  "owner": { "name": "Adam Miller" },
  "plugins": [
    {
      "name": "adams-review",
      "source": "./",
      "description": "Multi-lens code review pipeline for Claude Code."
    }
  ]
}
```

Schema notes (per D18 corrections): `source: "./"` is the documented form for same-repo relative paths (resolved relative to the marketplace root, i.e., the directory containing `.claude-plugin/`). Each plugin entry requires both `name` and `source` — there is no "omit source" case.

### 0.3 Create empty target directories

- [ ] `mkdir -p bin fragments hooks`
- [ ] Add a `.gitkeep` in each so they're trackable empty (delete `.gitkeep` once content lands).

### 0.4 Create `.gitattributes`

```
*.sh   text eol=lf
*.py   text eol=lf
*.json text eol=lf
*.md   text eol=lf
```

- [ ] Write file at repo root.
- [ ] Run `git add --renormalize .` after committing to enforce LF on existing tracked files.

### 0.5 Phase 0 commit

- [ ] `git add .claude-plugin/ .gitattributes bin/.gitkeep fragments/.gitkeep hooks/.gitkeep`
- [ ] Commit: "Plugin scaffolding: manifest, marketplace, layout dirs, LF gitattributes"

**Acceptance**: `tree -L 2 -I node_modules` shows `.claude-plugin/{plugin,marketplace}.json`, `bin/`, `fragments/`, `hooks/`, `.gitattributes`. `claude plugin validate .` reports no errors. (Manifest and marketplace files are skeletal at this point; the validator still catches schema-level issues early.)

---

## Phase 1 — POC: `/adams-review:promote` end-to-end

Validate the plugin runtime model on the smallest meaningful command (D16). Post-conversion invocation is `/adams-review:promote` (renamed from `/adams-review-promote` per D18). Exercises bin/ scripts, the `!include` wrapper, AskUserQuestion, artifact patching, and PR comment publish — but not agent dispatch or fix-commit loops.

### Phase 1a — Migrate ALL helpers and fragments + smoke

Move every helper and every fragment in one pass. **Why all-at-once**: smoke tests all 20 helpers AND reaches into `_shared/` fragments for assertions; a partial migration would break smoke or require dual-path test logic. The 4 commands we haven't ported yet will be temporarily broken because their `!cat ~/.claude/commands/_shared/...` paths point to nowhere — that's fine, we don't invoke them between Phase 1a and Phase 2 (D6, D7 cover the helper layout; D4/D5 cover the fragment layout).

- [ ] Move all 20 files from `commands/_shared/tools/` to `bin/`:
      ```
      git mv commands/_shared/tools/* bin/
      ```

- [ ] Move `schema-v1.json` to `bin/`:
      ```
      git mv commands/_shared/schema-v1.json bin/
      ```

- [ ] Move all 14 fragments to `fragments/`:
      ```
      git mv commands/_shared/00-preflight.md          fragments/
      git mv commands/_shared/01-detection.md          fragments/
      git mv commands/_shared/02-ensemble-adapter.md   fragments/
      git mv commands/_shared/03-dedup.md              fragments/
      git mv commands/_shared/04-scoring-gate.md       fragments/
      git mv commands/_shared/05-validation.md         fragments/
      git mv commands/_shared/06-cross-cutting.md      fragments/
      git mv commands/_shared/07-finalize.md           fragments/
      git mv commands/_shared/08-fix-loader.md         fragments/
      git mv commands/_shared/09-fix-execution.md      fragments/
      git mv commands/_shared/10-post-fix-and-commit.md fragments/
      git mv commands/_shared/lens-security-reference.md fragments/
      git mv commands/_shared/lens-ux-reference.md     fragments/
      git mv commands/_shared/promote-core.md          fragments/
      ```

- [ ] Delete the now-vestigial `commands/_shared/README.md` (contents become plugin-level docs in Phase 5):
      ```
      git rm commands/_shared/README.md
      ```

- [ ] Verify `commands/_shared/` is now empty: `ls commands/_shared/` returns nothing (only `tools/` should remain as an empty dir; remove it too: `rmdir commands/_shared/tools commands/_shared`).

- [ ] Update `bin/_common.py` line 32:
      `SCHEMA_PATH = Path(__file__).parent.parent / "schema-v1.json"` → `SCHEMA_PATH = Path(__file__).parent / "schema-v1.json"`

- [ ] Update `bin/_common.py` line 89's stale guidance. Old text: `"verify ~/.claude/commands/_shared is symlinked to the repo's commands/_shared directory."` Replace with: `"verify schema-v1.json is shipped alongside this script in the plugin's bin/ directory."`

- [ ] Update `bin/_common.py` module docstring (lines 3–7). Current text mentions "sibling scripts in the same `tools/` directory" — replace with "sibling scripts in the same `bin/` directory". Lines 9–10 reference `docs/archive/DESIGN.md §21.2` paths — those archive references stay valid (archive is frozen).

### 1a.2 Write `bin/include` wrapper (D5)

```bash
#!/usr/bin/env bash
# include — print a shared fragment from $CLAUDE_PLUGIN_ROOT/fragments/
# Used by command-markdown `!`include <name>`` preprocessor lines to
# inline shared phase fragments into top-level command files.
set -euo pipefail
[ $# -eq 1 ] || { echo "Usage: include <fragment-name>" >&2; exit 64; }
fragments_dir="${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}/fragments"
target="$fragments_dir/$1"
[ -f "$target" ] || { echo "ERROR: fragment '$1' not found at $target" >&2; exit 64; }
cat "$target"
```

Exit-code note: both failure modes use `64` (usage), matching the project's exit-code convention (CLAUDE.md operational rule 3 — `64` for usage/config errors). Missing fragment is a configuration error (fragment name doesn't match any shipped file), not a validation error.

- [ ] Write to `bin/include`.
- [ ] `chmod +x bin/include`.

### 1a.3 Update `test/smoke.sh` paths

Smoke is a 173KB file with ~129 assertions reaching into helpers, fragments, and schema. All three source-path families need rewriting here. Install-script assertions are handled separately in Phase 3 (before those scripts are deleted). Command-file variable renames (PROMOTE_MD, WALK_MD, ADD_MD) are handled in Phases 1b.1 and 2.1 at rename time.

- [ ] Update the `TOOLS` variable at smoke.sh line 21: `TOOLS="$REPO/commands/_shared/tools"` → `TOOLS="$REPO/bin"`. Variable name stays; pattern-match for any remaining `commands/_shared/tools/` literal and replace with `bin/`.
- [ ] Find every `commands/_shared/schema-v1.json` reference and replace with `bin/schema-v1.json`.
- [ ] Update every fragment-MD variable assignment. Confirmed set (from grep): `FRAG` (line 1558), `PROMOTE_CORE_MD` (line 2083), `VALIDATION_MD` (line 2515), `POSTFIX_MD` (line 2557), `DETECTION_MD` (line 3074). All point at `$REPO/commands/_shared/<fragment>.md` — change to `$REPO/fragments/<fragment>.md`.
- [ ] Sanity sweep: `grep -nE '_shared/' test/smoke.sh` — should return zero hits after the three edits above. Any remaining hit is a stale reference the plan didn't anticipate.
- [ ] Run smoke: `bash test/smoke.sh`. Expect `smoke: PASS` with the same assertion count as the pre-flight baseline. If it drops, find the broken assertion before continuing.

### 1a.4 Phase 1a commit

- [ ] Commit: "Phase 1a: migrate all helpers + fragments to plugin layout, add include wrapper, update smoke"

**Acceptance**: `bash test/smoke.sh` reports `smoke: PASS` with same assertion count as baseline. `ls bin/` shows 21 files (20 helpers + `schema-v1.json`) plus `include`. `ls fragments/` shows 14 files. `commands/_shared/` no longer exists.

### Phase 1b — Port promote command and integration test

`promote-core.md` already moved to `fragments/` in Phase 1a — don't re-move.

### 1b.1 Rename command file (D18), edit frontmatter/body, update smoke

- [ ] Rename the command file to drop the redundant `adams-review-` prefix:
      ```
      git mv commands/adams-review-promote.md commands/promote.md
      ```
      Post-rename invocation will be `/adams-review:promote`.

- [ ] Update `test/smoke.sh`'s `PROMOTE_MD` variable to point at the new path:
      `PROMOTE_MD="$REPO/commands/adams-review-promote.md"` → `PROMOTE_MD="$REPO/commands/promote.md"`.
      Without this, every RA-* assertion referencing `$PROMOTE_MD` fails on the next smoke run.

- [ ] Edit `commands/promote.md` frontmatter `allowed-tools`:
  - Replace each `Bash(/Users/adammiller/.claude/commands/_shared/tools/<script>:*)` with `Bash(<script>:*)` (bare name).
  - Add `Bash(include:*)` for the `!include` wrapper.
  - Drop any vestigial `Bash(uv:*)` if the body doesn't use `uv` directly (verify with grep).

- [ ] Edit `commands/promote.md` body:
  - Find every `~/.claude/commands/_shared/tools/<script>` invocation. Replace with bare name.
  - Replace `!`cat ~/.claude/commands/_shared/promote-core.md`` with `!`include promote-core.md``.
  - Verify with: `grep -nE '~/.claude/commands|/_shared/' commands/promote.md` should return nothing.

- [ ] Run smoke: `bash test/smoke.sh`. Must still PASS — if it drops, the smoke variable update above is the likely cause.

### 1b.2 Install plugin locally for testing

Two documented local-dev paths, each used in a specific sub-phase below:

- **Fast iteration** (`claude --plugin-dir "$(pwd)"`): loads the working tree as a plugin for the session. **Phase 1b.3 runs under this** — `--defer-publish` has no PR side-effects, so fast iteration is fine.
- **Install-path simulation** (`/plugin marketplace add .` + `/plugin install adams-review@adams-review` from a fresh session): exercises the real install flow. **Phase 1b.4 runs under this** — publish-mode touches a real PR, so we want to validate under the production install path.

- [ ] Confirm both paths work before proceeding. If either fails, stop and debug.

### 1b.3 Test `--defer-publish` against existing artifact (no PR side-effects)

- [ ] In a Claude Code session whose cwd is the repo containing the artifact you recorded in pre-flight:
  - Invoke `/adams-review:promote <some-finding-id> --defer-publish --reason "POC smoke test"`.
  - Pick a finding that's currently `disposition: confirmed_manual` or `confirmed_report` (safe to promote).
- [ ] Verify:
  - [ ] Command resolved (no "command not found"; if it fails, the D18 rename or plugin install didn't take — debug before proceeding).
  - [ ] `bin/` scripts resolved (no "command not found" from helper invocations).
  - [ ] `!include promote-core.md` expanded (the body of promote-core ran).
  - [ ] AskUserQuestion fired (or was correctly skipped because `--reason` was passed).
  - [ ] `artifact.json` was patched: re-read the finding and confirm `human_confirmation` is populated, `disposition: confirmed_mechanical`.
  - [ ] No `gh api` call was made (defer-publish honored — `promote_publish_failed` absent from trace.md).

### 1b.4 Test full publish against throwaway test PR

- [ ] Create or pick a throwaway test PR with a recent `/adams-review` artifact (pre-conversion artifacts are compatible — see D16a).
- [ ] Invoke `/adams-review:promote <id> --reason "full-publish POC"` (no `--defer-publish`).
- [ ] Verify:
  - [ ] `gh api PATCH` succeeded — PR comment updated.
  - [ ] `artifact.json` patched.
  - [ ] `trace.md` has the promote entry.
  - [ ] User-visible summary block printed correctly.

### 1b.5 Phase 1b commit

- [ ] Commit: "Phase 1b: port promote command to plugin layout (POC) — renames adams-review-promote.md → promote.md, invocation becomes /adams-review:promote"

**Acceptance**: All checks in 1b.3 AND 1b.4 green. Smoke still PASS.

**If anything fails here, STOP** and revisit the architecture before proceeding to Phase 2 — the failure mode in promote will recur in every other command.

---

## Phase 2 — Port the remaining four commands

Same recipe as Phase 1b (rename file per D18, then edit frontmatter + body), applied to the four remaining commands. Helpers and fragments are already at their final paths from Phase 1a — this phase is file renames + command-content edits only.

### 2.1 Rename + port each command (4× iterations)

Rename command files per D18, then edit frontmatter/body of the renamed files:

- [ ] Rename all four:
      ```
      git mv commands/adams-review.md             commands/review.md
      git mv commands/adams-review-fix.md         commands/fix.md
      git mv commands/adams-review-walkthrough.md commands/walkthrough.md
      git mv commands/adams-review-add.md         commands/add.md
      ```

- [ ] Update `test/smoke.sh`'s command-file variables to match the renames:
      `WALK_MD="$REPO/commands/adams-review-walkthrough.md"` → `WALK_MD="$REPO/commands/walkthrough.md"`
      `ADD_MD="$REPO/commands/adams-review-add.md"` → `ADD_MD="$REPO/commands/add.md"`
      (No `REVIEW_MD` or `FIX_MD` variables exist in smoke — grep confirms — so the rename of `adams-review.md`/`adams-review-fix.md` has no smoke-variable impact.)

- [ ] For each of `commands/review.md`, `commands/fix.md`, `commands/walkthrough.md`, `commands/add.md`:
  - Frontmatter: replace abs-path Bash grants with bare-name grants. Add `Bash(include:*)`. Drop vestigial `Bash(uv:*)` if unused in body (`grep -E '\buv\b' <file>` to check).
  - Body: replace every `~/.claude/commands/_shared/tools/<script>` with bare-name `<script>`.
  - Body: replace every `!`cat ~/.claude/commands/_shared/<fragment>.md`` with `!`include <fragment>.md``.
  - Verification: `grep -nE '~/.claude/commands|/_shared/' commands/<file>` returns nothing.
  - Verification: `grep -nE 'cat ~/' commands/<file>` returns nothing.

### 2.2 Audit fragments for the same patterns

Fragments reference helpers by absolute path AND reference each other by `!cat`. Known site: `fragments/01-detection.md` has literal `!`cat ~/.claude/commands/_shared/lens-ux-reference.md`` and `!`cat ~/.claude/commands/_shared/lens-security-reference.md`` blocks that need rewriting to the `!`include`` form. Other fragments may have similar cross-references — the greps below catch them.

- [ ] `grep -rnE '~/.claude/commands|/_shared/' fragments/` — fix every hit. Replace helper-path references with bare names, replace fragment-to-fragment `!`cat`` with `!`include <fragment>.md``.
- [ ] `grep -rnE 'cat ~/' fragments/` — fix every hit.
- [ ] Verify `Bash(include:*)` grant is already in the `allowed-tools` of every top-level command that transcludes a fragment containing `!`include`` (Phase 1b and 2.1 added it; this is a belt-and-suspenders check).

### 2.3 Smoke + per-command sanity

- [ ] Run `bash test/smoke.sh` after porting all four. Same assertion count as baseline. (Phase 3's install-script assertion fix hasn't happened yet — but Phase 1a already scrubbed fragment paths, so smoke should still pass if install.sh/uninstall.sh still exist.)
- [ ] In a fresh Claude Code session, invoke each command at least once against a real target:
  - [ ] `/adams-review:review` against a docs-only PR so `trivial_mode` auto-detects and the run skips Phases 1–5 (cheapest smoke). **Note**: this does NOT exercise the 6-way fan-out — the non-trivial exercise lives in Phase 6.
  - [ ] `/adams-review:fix` against an artifact with at least one `confirmed_mechanical` finding.
  - [ ] `/adams-review:walkthrough` against an artifact with at least one walkable finding.
  - [ ] `/adams-review:add` in structured mode (`--file path --line N --claim "..."`) against an existing artifact.

### 2.4 Phase 2 commit

- [ ] Commit per command if you prefer granular history, or one combined "Phase 2: port remaining 4 commands to plugin layout (D18 renames + frontmatter/body)" commit.

**Acceptance**: all four commands invoke without "command not found" or "fragment not found" errors. Smoke still PASS. All command files live at bare-name paths (`commands/review.md` etc.).

---

## Phase 3 — Replace install scripts and fix smoke's install-script assertions

Per D13 (delete user-facing install scripts; keep a dev-run wrapper for plugin-author iteration). `commands/_shared/` was already removed in Phase 1a. Smoke references `install.sh`/`uninstall.sh` in ~several assertions, so those must be rewritten or removed in the same phase — otherwise smoke breaks on the delete.

### 3.1 Rewrite smoke assertions referencing install scripts

- [ ] `grep -nE 'install\.sh|uninstall\.sh' test/smoke.sh` — list every assertion involving the install scripts.
- [ ] For each hit: either delete the assertion (if it tests behavior that's now the plugin runtime's job) or rewrite to test the new equivalent (e.g., assert `scripts/dev-run.sh` exists and is executable; assert `.claude-plugin/plugin.json` validates).
- [ ] Run smoke: `bash test/smoke.sh`. Should PASS. **Note**: the total assertion count may legitimately change here (RA-9 was one assertion; its replacement may be one, two, or zero). Record the new `smoke: PASS (N assertions)` count as the updated baseline for Phase 6's count-check.

### 3.2 Delete install scripts and write dev-run wrapper

- [ ] `git rm scripts/install.sh scripts/uninstall.sh`.
- [ ] Write `scripts/dev-run.sh` as a thin wrapper around `claude --plugin-dir`:

  ```bash
  #!/usr/bin/env bash
  # dev-run.sh — launch Claude Code with the working tree loaded as a plugin.
  # For plugin-author iteration. For install-path simulation, use
  # `/plugin marketplace add .` inside a Claude Code session instead.
  set -euo pipefail
  REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
  exec claude --plugin-dir "$REPO_ROOT" "$@"
  ```

- [ ] `chmod +x scripts/dev-run.sh`.

### 3.3 Phase 3 commit

- [ ] Commit: "Phase 3: delete install scripts, add dev-run.sh wrapper, rewrite smoke install-script assertions"

**Acceptance**: `scripts/` contains only `dev-run.sh`. Smoke PASS with the rewritten assertions. `bash scripts/dev-run.sh --version` resolves (confirms the wrapper at least executes — actual plugin-load happens when you use it).

---

## Phase 4 — `SessionStart` hook for dependency check (D12)

### 4.1 Write `hooks/dep-check.sh`

**Design note (per D18 corrections)**: `SessionStart` hook stdout is injected into Claude's conversation context every session. Output only what's useful for the model to know. Hard-requirement warnings stay; the old "ensemble mode requires codex/coderabbit (optional)" note moves out of the hook (into README troubleshooting + `/adams-review:review --ensemble` preflight).

```bash
#!/usr/bin/env bash
# dep-check.sh — SessionStart hook: warn if required CLI tools are missing.
# Soft warning only — never fails the session. Output is injected into
# Claude's session context, so keep it focused on hard requirements.

missing=()
for tool in uv jq gh git; do
  command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done

if [ "${#missing[@]}" -gt 0 ]; then
  echo "[adams-review] WARNING: missing required tool(s): ${missing[*]}"
  case "$(uname -s)" in
    Darwin)
      echo "[adams-review]   macOS:   brew install ${missing[*]}" ;;
    Linux)
      echo "[adams-review]   Linux:   apt install ${missing[*]}  # or distro equivalent" ;;
    MINGW*|MSYS*|CYGWIN*)
      echo "[adams-review]   Windows: choco install ${missing[*]}  # or scoop install ${missing[*]}" ;;
  esac
fi

exit 0
```

- [ ] Write file at `hooks/dep-check.sh` and `chmod +x`.

### 4.2 Write `hooks/hooks.json`

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/dep-check.sh"
          }
        ]
      }
    ]
  }
}
```

Schema notes (per D18 corrections): the top-level `"hooks"` wrapper is required — `SessionStart` is NOT at the root. `matcher: "*"` is a documented-supported match-all. `${CLAUDE_PLUGIN_ROOT}` IS substituted in hook `command` fields per the hooks reference — no further verification needed.

### 4.3 Test hook

- [ ] Start a fresh Claude Code session — confirm the hook fires once and prints the expected message (or nothing, if all deps present).
- [ ] Temporarily rename `jq` (e.g., `mv $(which jq) $(which jq).bak`) and restart session — confirm the warning appears with correct OS-specific install hint. Restore `jq` after.

### 4.4 Phase 4 commit

- [ ] Commit: "Phase 4: SessionStart dep-check hook"

**Acceptance**: hook fires on session start, warns on missing deps with OS-correct install hint, never fails. `claude plugin validate .` reports no errors (hook schema is validated).

---

## Phase 5 — Documentation rewrite

### 5.1 Rewrite `CLAUDE.md`

The following sections need updates:

- [ ] **Command references throughout**: replace every `/adams-review`, `/adams-review-promote`, `/adams-review-fix`, `/adams-review-walkthrough`, `/adams-review-add` with the namespaced form (`/adams-review:review`, `/adams-review:promote`, etc.) per D18. Robust grep: `grep -nE '/adams-review' CLAUDE.md | grep -v '/adams-review:'` surfaces every pre-rename reference while excluding the post-rename form.
- [ ] **Layout section**: replace the `_shared/` tree with the plugin tree (`bin/`, `fragments/`, `hooks/`, `.claude-plugin/`).
- [ ] **Operational rule 7**: re-anchor to bin/ paths.
- [ ] **Operational rule 10**: rewrite. Old: "Absolute paths in `allowed-tools` grants." New: "Bare-name grants in `allowed-tools` — bin/ is on $PATH automatically."
- [ ] **Helper index**: rewrite paths from `commands/_shared/tools/` → `bin/`.
- [ ] **Helper index**: add the missing `prior-fix-diff.sh` entry (pre-existing doc drift).
- [ ] **Pipeline shape**: update fragment paths from `_shared/NN-name.md` to `fragments/NN-name.md`.
- [ ] **How to test**: smoke command unchanged.
- [ ] **Dependencies** section: add a Windows row noting Git for Windows + Git Bash auto-routing.

### 5.2 Rewrite `README.md` install section (D17b)

- [ ] Replace the current install section with a plugin-install flow. Restore `bash 4+` and `git` from the current README's dependency list (I dropped them in an earlier draft — external review caught):

  ```markdown
  ## Installation

  ### macOS / Linux
  1. Install deps: `brew install uv jq gh bash git` (macOS) or distro equivalent. Bash 4+ is required; macOS's default `/bin/bash` is 3.2.
  2. In Claude Code: `/plugin marketplace add <OWNER>/adams-review`
  3. `/plugin install adams-review@adams-review`

  ### Windows (native)
  1. Install [Git for Windows](https://git-scm.com/downloads/win) — provides Git Bash (bash 5+) and git, which Claude Code uses internally.
  2. Install [uv](https://docs.astral.sh/uv/), [jq](https://jqlang.github.io/jq/download/), and [GitHub CLI](https://cli.github.com/).
  3. In Claude Code: `/plugin marketplace add <OWNER>/adams-review` and `/plugin install adams-review@adams-review`.

  ### Commands (post-install)

  All invocations are plugin-namespaced (per D18):

  - `/adams-review:review [--ensemble] [--full]`
  - `/adams-review:promote <finding_id> [--reason "..."] [--fix-hint "..."]`
  - `/adams-review:fix [threshold]`
  - `/adams-review:walkthrough [threshold]`
  - `/adams-review:add [<paste...>] [--file ...]`
  ```

- [ ] Update every user-facing reference to `/adams-review-*` (or bare `/adams-review`) elsewhere in README.md to the `/adams-review:*` form.
- [ ] Fix the existing pseudocode bash-loop snippet (`for id in F003 F037 F039; do /adams-review-promote $id; done`) — slash commands aren't bash-invocable. Either remove or relabel as "conceptual loop, not literal bash."

### 5.3 Add troubleshooting section to `README.md`

- [ ] **First run is slow (uv resolves Python deps)**: one-line explanation that first-invocation on a fresh machine pauses while `uv` resolves the Python interpreter + `jsonschema` dep; subsequent runs hit cache.
- [ ] **`--ensemble` mode requirements**: note that `--ensemble` additionally requires the `codex` and `coderabbit` CLI plugins; without them the mode errors at runtime. (Per D18 correction, moved out of SessionStart hook to avoid polluting every session's context.)
- [ ] **Windows: Git Bash not found**: point to `CLAUDE_CODE_GIT_BASH_PATH` env var override for explicit Git Bash location.
- [ ] (Deferred per D10) **AskUserQuestion not appearing**: skip for now; add a `--prose` mode subsection only if the regression bites.

### 5.4 Phase 5 commit

- [ ] Commit: "Phase 5: docs — rewrite CLAUDE.md and README.md for plugin layout"

**Acceptance**: `grep -rE '~/.claude/commands|/_shared/' CLAUDE.md README.md` returns nothing. README's install section reads as plugin-only.

---

## Phase 6 — Final smoke, release prep, and fan-out verification

### 6.1 Mechanical verification

- [ ] `bash test/smoke.sh` — PASS, baseline assertion count.
- [ ] `claude plugin validate .` — no errors. (Replaces the earlier `jq . .claude-plugin/*.json` checks, per D18 corrections — jq only proves the JSON parses.)
- [ ] Plugin version shows correctly: `jq -r '.version' .claude-plugin/plugin.json` → `0.1.0`.
- [ ] `git log --oneline plugin-conversion ^main` shows the phase commits in order.
- [ ] Manually verify `.gitattributes` LF enforcement: `git ls-files --eol bin/ | head` should show `lf` for every entry.

### 6.2 Non-trivial `/adams-review:review` run (added post-external-review)

The Phase 2.3 sanity test uses trivial_mode, which bypasses Phases 1–5 and never exercises the 6-way lens fan-out — the heaviest plugin-risk surface. At least one non-trivial run is required before release.

- [ ] Pick a real non-trivial PR (code changes, not docs-only). Any PR where `trivial_mode` auto-detection will land `false`.
- [ ] Invoke `/adams-review:review` against it. Do not abort the run.
- [ ] Verify:
  - [ ] Phase 1 dispatches 6 parallel lens agents in a single orchestrator turn (7 under `--ensemble`). Look for the single-turn multi-agent fan-out in the trace.
  - [ ] Each lens agent's output is parsed and its tokens logged. `tokens.jsonl` shows **exactly 6 entries tagged `phase: 1`** for a default run, or **7+ entries** (L1–L7 plus ensemble sub-agents) with `--ensemble`.
  - [ ] Phase 3 and Phase 4 per-candidate agents also dispatch in batches.
  - [ ] Phase 6 finalize publishes a PR comment successfully.
- [ ] **Optional**: if `codex` and `coderabbit` CLIs are installed, run once with `--ensemble` to exercise Phase 1.5.

### 6.3 Manual `AskUserQuestion` check (D10 deferred but gate-covered)

D10 deferred building prose-fallback wrappers. The manual check before release covers the known regression class without pre-engineering.

- [ ] Default permission mode: invoke a command that uses `AskUserQuestion` (e.g., `/adams-review:promote` without `--reason` triggers the AUQ at step 1). Confirm the question renders and response handling works.
- [ ] `acceptEdits` permission mode: repeat the same invocation. Confirm AUQ still works (this is the mode that's historically had the most regressions).
- [ ] If either fails: document the failure in trace notes and surface in release notes. Do NOT block release unless you can't advance past the AUQ gate.

### 6.4 Phase 6 commit

- [ ] Phase 6 commit if any final touch-ups: "Phase 6: final smoke, validate, fan-out and AUQ verification"

**Acceptance**: smoke PASS, `claude plugin validate .` clean, all five commands work end-to-end, one non-trivial `/adams-review:review` run complete with lens fan-out confirmed, AUQ manually verified in default + acceptEdits modes, no `~/.claude/commands` references anywhere in the repo (`grep -rE '~/.claude/commands' . --exclude-dir=.git --exclude-dir=docs/archive --exclude-dir=plans` returns nothing — exclusions allowed for the historical archive and these planning docs).

---

## Out of scope / explicitly deferred

These were considered and consciously NOT included. Document for the reviewer's situational awareness.

- **`AskUserQuestion` prose-fallback wrappers** (D10). AUQ works in plugins today. Add `--prose` flag if a regression bites; not pre-engineering.
- **CI matrix across Claude Code versions** (D14). Personal-use plugin; smoke on local dev is sufficient. Revisit when external users depend on it.
- **CHANGELOG.md** (D14). Skipped for v0.1.0; add when there's a v0.2.0 to compare against.
- **Cross-cutting refactor of helper scripts**. Strictly path-mechanical migration; no behavior changes to `artifact-patch.py`, `external-scrape.sh`, etc.
- **`mktemp -t` BSD/GNU divergence** (fresh-eyes review finding). Multiple helpers use `mktemp -t <prefix>.XXXXXX`. BSD `mktemp` (macOS default) and GNU `mktemp` (Linux, Git Bash/mingw on Windows) treat the `-t` flag slightly differently: BSD appends random chars after the prefix, GNU's `-t` is deprecated but still works by treating the next arg as a template in `$TMPDIR`. Current usage happens to function on both because the argument includes `.XXXXXX`, but strict Windows portability would prefer normalizing to `mktemp "${TMPDIR:-/tmp}/<prefix>.XXXXXX"`. Pre-existing, not plugin-introduced. Out of scope for v0.1.0 per "no behavior change to the review pipeline itself" — revisit if a Windows user hits an actual failure. Note softens the D17 "Git Bash handles everything" claim: it handles everything the plan explicitly tests, but `mktemp -t` portability is an unverified corner.
- **Alternative state directory** (D9). `~/.adams-reviews/` and `$ADAMS_REVIEW_REVIEWS_ROOT` unchanged.
- **Plugin-shipped agents/** (D11). Lens prompts stay inline.
- **Stage-4 fragment shrink** (per `plans/stage-4-fragment-shrink.md`). Unrelated to plugin packaging.

## Rollback notes

If Phase 1 (POC) fails in a way that suggests the plugin model itself is wrong:

- The `plugin-conversion` worktree is isolated; abandon by not merging.
- All `git mv`s preserve history, so `git checkout main -- commands/_shared/tools/` restores the original layout.
- Pre-conversion scripts/install.sh symlink-based install still works on `main`.

If Phase 1 succeeds but a later phase breaks one specific command:

- Revert just the offending phase's commit (each phase is a separate commit per the checklist).
- Smoke + per-command sanity tells you which command regressed.

If `.gitattributes` LF enforcement causes mass-rewrite churn after `git add --renormalize`:

- Confirm the renormalize commit is its own commit (clean diff).
- Verify on a Linux/macOS box that scripts still execute (line endings are a write-side concern; checkout-side is the issue).

## Review questions (v2)

Most v1 reviewer questions are resolved (schema shape, hook-root wrapper, local-install command, plugin-name@marketplace-name form, namespacing). Remaining open questions for a v2 reviewer:

1. **Cross-repo command uniqueness**: with `plugin-name == marketplace-name == "adams-review"`, is `/plugin install adams-review@adams-review` the cleanest form, or is there a shorter variant documented?
2. **Windows-portability spot-check** in the bash helpers: `mktemp -t`, `git rev-parse --show-toplevel` returning mixed-style paths on Git Bash, jq installation assumptions. Anything missed?
3. **Sequencing**: Phase 1a breaks the other 4 commands' `!cat` paths until Phase 2 ports them. Intentional (not invoked in between) but worth confirming no smoke assertion reaches into command bodies.
4. **Phase 3 smoke rewrite scope**: is `grep -nE 'install\.sh|uninstall\.sh' test/smoke.sh` sufficient to surface all the install-script assertions, or are there indirect references (via function helpers etc.)?
5. **Hook-output context injection**: the revised dep-check.sh only emits output when required deps are missing. On a fully-set-up machine, zero bytes are injected. Confirm that's the goal.

For Adam's review:

1. Phase 1b's "throwaway test PR" — do you have one ready, or do we need to create one?
2. Phase 6.2 non-trivial `/adams-review:review` run — which PR are you going to run it against? Self-review of this conversion branch once merged is a candidate.
3. Anything in "Out of scope" you want pulled into scope for v0.1.0?

# adams-review → Claude Code Plugin: Decisions Walkthrough

Companion to `adams-review-plugin-readiness-checklist.md`. Walks through every decision the checklist surfaces, with a recommendation, the tradeoff, and what the checklist undersells or misses. Once these decisions are confirmed, this becomes the input for a final executable checklist.

## Methodology

Read the checklist plus the actual current state of the codebase:

- Five command files (`adams-review.md`, `-add.md`, `-fix.md`, `-promote.md`, `-walkthrough.md`).
- 20 helpers under `_shared/tools/` (checklist says 21 — off by one).
- `_shared/promote-core.md` is a 7th fragment used by promote/walkthrough.
- `schema-v1.json` already located via script-relative path in `_common.py:32`.
- `AskUserQuestion` in 4 of 5 commands plus 6 fragments.
- No hooks today.
- All frontmatter using absolute `/Users/adammiller/...` Bash grants.

Good news: the codebase is structurally well-prepared. Almost every "real" decision is in §1, §3, §4 — the rest are mostly "do the obvious thing."

---

## §1 — Repo layout (4 decisions)

### D1. Repo-IS-the-plugin vs. repo-as-marketplace-with-subdir

**Recommend: repo IS the plugin** — manifest at `.claude-plugin/plugin.json` at repo root. You ship one plugin; nesting it inside a `plugins/adams-review/` subdir buys nothing.

### D2. Ship `marketplace.json` so users can install via `/plugin marketplace add owner/repo`?

**Recommend: yes**, single-plugin marketplace at `.claude-plugin/marketplace.json` listing only `adams-review`. Without it, you'd depend on a third-party marketplace listing you. Cost is one ~10-line JSON file.

### D3. Where does `schema-v1.json` live?

The checklist suggests a `data/` or `resources/` directory. **Recommend: just put it in `bin/` alongside the helpers** (and change `_common.py:32` from `parent.parent / "schema-v1.json"` to `parent / "schema-v1.json"`). The "bin/ should be only executables" purism doesn't pay off here — it forces `_common.py` to do `os.environ["CLAUDE_PLUGIN_ROOT"]` lookups and you trade a one-line constant for a runtime env-var dependency.

### D4. What happens to `_shared/`?

Tied to D5 below — defer.

```
★ Insight ─────────────────────────────────────
- The Claude Code plugin runtime sets $CLAUDE_PLUGIN_ROOT in subprocess
  env, so it's available to bin/ scripts at runtime — but it's NOT
  substituted in `allowed-tools` patterns or in command-body !`...`
  preprocessor lines. That asymmetry is what makes §3 hard.
- _common.py already uses Path(__file__).parent.parent / "schema-v1.json"
  — script-relative, no hardcoded path. That's actually plugin-ready
  today; only the parent.parent becomes parent if both files end up in
  bin/.
─────────────────────────────────────────────────
```

---

## §2 — Frontmatter (mostly mechanical)

No real decisions; this is search-and-replace work across all 5 command files. One thing the checklist doesn't quite spell out:

### D2a (hidden). Tool-grant string format for bare names

You'll change `Bash(/Users/adammiller/.claude/commands/_shared/tools/artifact-patch.py:*)` → `Bash(artifact-patch.py:*)`. **But the command body must also be edited** to call helpers by bare name (currently they call `~/.claude/commands/_shared/tools/artifact-patch.py`). Allowed-tools match is on the literal Bash command string — `Bash(artifact-patch.py:*)` does NOT match `~/.claude/.../artifact-patch.py`. Easy to forget; both ends need to move together.

**Vestigial scrub.** `Bash(uv:*)` appears in some grants but you may not actually invoke `uv` directly in any command body (the shebang handles uv internally). Audit and drop unused grants while you're in there.

---

## §3 — The `!cat` preprocessor (THE big decision)

This is the one decision where the choice materially shapes the work. Counts confirmed:

- 4 of 5 commands use `!`cat`` — `adams-review.md` (7 includes), `adams-review-fix.md` (3), `adams-review-promote.md` (1), `adams-review-walkthrough.md` (1).
- `adams-review-add.md` already inlines (line 956 even comments on it: "Inline copies, not `!`cat`` includes").
- Total: 12 include sites across 4 files.

### D5. Which strategy?

**Recommend: Strategy C (wrapper binary)**, called something like `bin/include`:

```bash
#!/usr/bin/env bash
set -euo pipefail
[ $# -eq 1 ] || { echo "Usage: include <fragment-name>" >&2; exit 64; }
fragments_dir="${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}/fragments"
target="$fragments_dir/$1"
[ -f "$target" ] || { echo "ERROR: fragment '$1' not found at $target" >&2; exit 1; }
cat "$target"
```

Then `!`cat ~/.claude/commands/_shared/00-preflight.md`` becomes `!`include 00-preflight.md``. Move all 13 fragments (11 phase + 2 lens-reference + promote-core, minus the one already-inlined) under `fragments/` at plugin root.

Why C over A and B:

- **A (inline at build time)**: largest files in git, every fragment edit needs a build step before testing. The build artifact must be committed because plugins don't run install steps. Slowest dev loop.
- **B (commands → skills)**: Skills load context unconditionally, which changes invocation semantics. The architecture churn (commands wrapping skills) doesn't pay back what it costs. Also unsure if `${CLAUDE_PLUGIN_ROOT}` interpolation in SKILL.md `!`...`` lines actually works — would need to verify, and "would need to verify" is itself a yellow flag.
- **C (wrapper binary)**: 5-line bash script, preserves source-of-truth, no build step, fragment edits land directly. Negligible risk surface. Adds one allowed-tool grant (`Bash(include:*)`).

The fallback `${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}` in the wrapper means it works under direct testing too (e.g. from `smoke.sh` running outside the plugin runtime).

```
★ Insight ─────────────────────────────────────
- Why this works and why the checklist's framing makes it sound harder
  than it is: plugin command-markdown DOES expand !`...` preprocessor
  lines into Bash subprocess executions — that's the whole mechanism.
  What it doesn't do is substitute ${CLAUDE_PLUGIN_ROOT} *inside* the
  markdown text of those `!` lines. But the resulting Bash subprocess
  HAS $CLAUDE_PLUGIN_ROOT in its env, so a wrapper binary that reads the
  env var sidesteps the substitution gap entirely.
- Strategy A's "commit the expanded files" approach has a subtle
  versioning problem: every plugin version bump now requires re-running
  the build even when only a fragment changed. With C, you bump version,
  edit fragment, ship — no separate build artifact to keep in sync.
─────────────────────────────────────────────────
```

---

## §4 — Helper scripts (3 decisions)

### D6. Where does `_common.py` live?

**Recommend: stays in `bin/` alongside the Python helpers.** No `sys.path` work needed — Python prepends the script directory automatically when `uv run --script` executes the shebang. Moving it to `lib/python/` would require every Python helper to add `sys.path.insert(...)` boilerplate.

### D7. Cross-script invocations

The audit shows helpers reference each other only in comments/doc strings, not in code (the README mentions `assign-finding-ids.sh --start-from` in `/adams-review-add` flow but that's invoked from the orchestrator, not script-to-script). So this is a **non-decision** — there's no script-to-script absolute-path call to fix.

### D8. macOS/Linux/Windows `env -S` portability for the uv shebang

**Recommend: works on all three platforms; no defer needed.** macOS has `env -S` since 10.15 (Catalina, 2019); GNU coreutils since 8.30; Git Bash on Windows uses mingw env which supports `-S`. (See §15 below for the Windows verification context.)

### Cleanup

The one **real cleanup** in §4: `_common.py:89` has stale guidance saying "verify `~/.claude/commands/_shared` is symlinked." That message becomes wrong post-conversion. Update to point at the plugin install path, or just rewrite it to "verify schema-v1.json is shipped with the plugin."

---

## §5 — State directory (1 decision)

### D9. Add `$CLAUDE_PLUGIN_DATA` as alternate root?

**Recommend: no, keep `~/.adams-reviews/` and `$ADAMS_REVIEW_REVIEWS_ROOT` exactly as-is.** Reasons:

- `~/.adams-reviews/` is OUTSIDE `~/.claude/`, so plugin upgrades won't touch it (plugins live under `~/.claude/plugins/cache/`).
- The existing override env var already covers any need to relocate state. `$CLAUDE_PLUGIN_DATA` adds a third location concept users have to learn.
- Per CLAUDE.md operational rule 6: writes under `~/.claude/` trigger the sensitive-file permission prompt. You explicitly chose `~/.adams-reviews/` for this reason.

---

## §6 — Token accounting

No real decisions. The cwd-slug derivation in `orchestrator-tokens.sh` (`tr '/.' '-'`) reads transcripts based on the user's working directory, not the plugin install path — so plugin packaging is invisible to it. Verify with one real session post-conversion.

```
★ Insight ─────────────────────────────────────
- ~/.claude/projects/<cwd-slug>/ transcripts are Claude Code's own
  persistence; <cwd-slug> is computed from where the user invoked the
  command, not from where the plugin lives. That's why plugin install
  location doesn't affect token tallying — it's user-cwd-keyed all the
  way down.
─────────────────────────────────────────────────
```

---

## §7 — `AskUserQuestion` resilience (1 decision, with nuance)

### D10. Pre-engineer prose fallbacks now, or wait?

The checklist recommends wrapping every AUQ call site. **Recommend: don't pre-engineer. Defer.** Reasoning:

- AUQ works in plugins today; the checklist's "had repeated regressions" wording suggests historical pain, not current-state breakage.
- Wrapping 11 call sites adds significant code surface (and a fallback path you can't easily test until AUQ actually breaks).
- The right time to add a `--prose` flag is when (or if) the regression bites you — which will be obvious when it happens.

**Compromise option** if you want a safety net: ship a single `--prose` flag on `/adams-review-walkthrough` only (the heaviest interactive flow) and do nothing for the other four. That gets you a usable escape hatch without modifying every command.

---

## §8 — Sub-agent dispatch (1 decision)

### D11. Ship lens prompts as plugin `agents/` or keep inline?

**Recommend: keep inline.** The checklist already flags that plugin-shipped agents lose `hooks`/`mcpServers`/`permissionMode` keys. The current architecture prompts each lens inline via the Agent tool with `subagent_type: general-purpose` and a per-fragment prompt. That works identically from a plugin. No reason to introduce an `agents/` directory.

The only verification step: confirm the 6-way Phase-1 fan-out (or 7-way under `--ensemble`) still dispatches in a single orchestrator turn. This is a smoke test, not a design decision.

---

## §9 — Dependency preflight (1 decision)

### D12. `SessionStart` hook for dep check?

**Recommend: yes, ship a `SessionStart` hook in `hooks/hooks.json`.** It runs once per session (cheap), warns loudly on missing tools (`uv`, `jq`, `gh`, `git`), and replaces the install-script preflight cleanly. **Warn, don't fail** — failing a `SessionStart` hook blocks all of Claude Code, which is way too aggressive for a missing optional dep.

**Windows priority (added during walkthrough):** `jq` is the likely missing dep on Windows — Git for Windows bundles git/bash/awk/sed but NOT jq. Hook should emit an OS-appropriate install hint when it detects missing jq (`brew install jq` / `apt install jq` / `choco install jq` / `scoop install jq`).

Worth ALSO checking for the optional ensemble deps (`codex` and `coderabbit` plugins/CLIs) but only emitting a softer "ensemble mode unavailable" notice — they're not required for the default flow.

---

## §10 — Install scripts (1 decision)

### D13. Delete `scripts/install.sh` and `scripts/uninstall.sh`?

**Recommend: yes, delete both.** Plugin marketplace install replaces them entirely. Keeping them creates a confusing "two ways to install" situation.

**Caveat**: keep ONE small dev-loop script — something like `scripts/dev-link.sh` — that lets you install the working tree directly without going through the marketplace flow. (Plugin systems usually support installing from a local directory; verify the exact incantation and document it.) This is for plugin-author iteration, not user installation.

---

## §11 — Testing (1 decision)

### D14. Build a CI matrix against multiple Claude Code versions?

**Recommend: defer.** Smoke.sh on local dev is enough for a personal-use plugin. CI matrix is significant overhead (GitHub Actions setup + maintenance). If/when others depend on the plugin, build it then.

The minimal change: update `test/smoke.sh` to point at the new `bin/` paths. Already mentioned in the checklist; trivial.

---

## §12 — Versioning

### D15. Starting version?

**Recommend: `0.1.0`** for first plugin release. Bump to `1.0.0` when you've used the plugin against ≥3 real PRs without conversion-related regressions. CHANGELOG.md is fine to add later (don't pre-engineer it for v0.1.0).

---

## §13 — Docs

No decisions, just work. CLAUDE.md rewrite is significant — operational rule 7, 10, the entire helper index, and the layout section all need updating. README install section becomes a 2-line `/plugin marketplace add` + `/plugin install`.

---

## §14 — Proof-of-concept first

### D16. Which command for the proof-of-concept?

**Recommend: `/adams-review-promote`** as the checklist suggests. It exercises:

- `!`cat`` include (1 site)
- AskUserQuestion (1 site)
- 6 helper scripts
- `~/.adams-reviews/` state read
- PR comment publish

But NOT: agent dispatch, Phase 8/9 commit loops, or fragment fan-out. So if it works end-to-end, you've validated `bin/`, the wrapper binary, frontmatter conversion, `AskUserQuestion`, and `~/.adams-reviews/` interop in one shot. Then porting the remaining 4 is "more of the same."

### D16a. Testing the POC without a fresh `/adams-review` run

**Concern raised during walkthrough**: `/adams-review-promote` requires an existing artifact (`~/.adams-reviews/<slug>/<branch>/<review_id>/artifact.json`). If we haven't ported `/adams-review` first, what do we promote against?

**Resolution**: the artifact format is stable (schema-v1.json), so any artifact written by the pre-conversion slash command is fully promote-compatible by the post-conversion plugin. You have plenty available — `/adams-review` has been in production use since 2026-04-19. Pick any branch with a recent artifact under `~/.adams-reviews/`, run promote against it.

**Three-layer POC validation order:**

1. **`test/smoke.sh` against new `bin/` layout** — catches helper-level path/import bugs cheaply. Doesn't exercise orchestrator-side concerns.
2. **`/adams-review-promote <id> --defer-publish` against existing artifact** — exercises bin/ scripts via bare-name, the `!`include`` wrapper, AskUserQuestion, and the artifact patch path. `--defer-publish` skips the `gh api PATCH` so a half-tested run doesn't smear a real PR comment.
3. **`/adams-review-promote <id>` (no `--defer-publish`) against a throwaway test PR** — exercises the publish path.

This validates the entire plumbing without requiring `/adams-review` itself to be ported first. Promote remains the right POC choice.

```
★ Insight ─────────────────────────────────────
- The artifact format being a stable, on-disk JSON file is what makes
  this POC strategy work. Each command in the suite is independent at
  the artifact level — coupling is via shared file format, not shared
  in-memory state. This is also why /adams-review-add could be retro-
  fitted on its own without rebuilding the rest. Same property pays off
  for the plugin conversion.
- --defer-publish exists for /adams-review-walkthrough's batched per-
  finding flow (so render+publish runs once at the end rather than per
  promote). It happens to also be the perfect dry-run flag for testing
  the plugin conversion. Pre-existing capability, no new code needed.
─────────────────────────────────────────────────
```

---

## §15 — Windows support (added during walkthrough)

Out-of-checklist concern. The checklist doesn't address cross-platform support; came up during the decisions discussion.

### D17. Support Windows in addition to macOS/Linux?

**Recommend: yes — the marginal cost is small and the platform model is favorable.**

Per [Anthropic's setup docs](https://code.claude.com/docs/en/setup), Claude Code on Windows uses Git Bash internally for `Bash(...)` tool grants, regardless of where the user launched it. Quote: *"Claude Code uses Git Bash internally to execute commands regardless of where you launched it."* User burden is installing [Git for Windows](https://git-scm.com/downloads/win) (most devs have it) and any missing CLI tools (mainly `jq`).

This means your bash helpers run unchanged on Windows under mingw bash 5.x. No PowerShell port, no WSL requirement (though WSL is supported as an alternative).

**What changes from the original walkthrough:**

- **D8** flips from "defer Linux/Windows" to "works on all three" — Git Bash's mingw env supports `-S`.
- **D12 SessionStart hook** gains real teeth — `jq` is the likely missing dep on Windows.
- **NEW**: ship `.gitattributes` enforcing LF endings (see D17a below).

### D17a. `.gitattributes` enforcing LF endings

**Recommend: yes, as a load-bearing requirement.** Git for Windows defaults to CRLF on checkout. CRLF in `.sh` and `.py` files breaks shebang parsing on every Unix-like system including Git Bash itself: `bash: bad interpreter: /usr/bin/env^M`.

Minimal `.gitattributes` at repo root:

```
*.sh   text eol=lf
*.py   text eol=lf
*.json text eol=lf
*.md   text eol=lf
```

Cheap, prevents the most common Windows-newcomer footgun, also protects macOS/Linux users from accidentally committing CRLF via misconfigured editors.

### D17b. README install section

**Recommend: split install instructions by platform, document Git Bash as the Windows path.** Three lines instead of one — small docs cost, big "does this work?" clarity for prospective users.

```
★ Insight ─────────────────────────────────────
- The "Claude Code uses Git Bash internally" design choice is what
  makes this work — Anthropic absorbs the cross-platform shell problem
  inside Claude Code, so plugin authors get a uniform bash environment
  on every OS. You write Unix-style helpers; Claude Code finds the
  right bash. Remaining cross-platform concerns are about the toolchain
  bash invokes (jq, gh, git itself), not the shell language itself.
- The .gitattributes LF rule is the one thing the platform CAN'T fix
  for you. Git's CRLF translation happens at checkout, before any shell
  runs — so Claude Code never sees the broken file in a state it could
  repair. That's why this single line matters across the whole project.
─────────────────────────────────────────────────
```

---

## What the checklist misses (or undersells)

1. **Command-body bare-name edits.** Every `~/.claude/commands/_shared/tools/<script>` invocation in the body of every command and every fragment must change to bare name. The frontmatter change alone won't help — the orchestrator literally invokes whatever string the body says. Quick `grep -r '~/.claude/commands' commands/` will surface them.

2. **Subshell invocation pattern in README.** Snippets like `for id in F003 F037 F039; do /adams-review-promote $id; done` aren't actually executable from bash (slash commands run from chat input). Pre-existing issue, not plugin-conversion, but worth fixing while you're already in the docs.

3. **Helper count is off.** Checklist says "21 helper scripts"; actual count is 20. Trivial, but worth fixing the checklist before it becomes the official reference.

4. **`prior-fix-diff.sh` missing from CLAUDE.md helper index.** Doc drift unrelated to plugin work, but you'll touch CLAUDE.md anyway.

5. **uv first-run latency.** First plugin invocation on a fresh machine pauses while `uv` resolves Python interpreter + jsonschema dep. Not a bug, but worth a one-line note in the troubleshooting section so users don't think the command hung.

6. **Ensemble-mode optional deps.** `--ensemble` requires `codex` and `coderabbit` (separate plugins/CLIs). The dep-preflight hook should mention these as soft-optional.

---

## Proposed final-checklist sequence (SUPERSEDED)

> **Superseded by `plugin-conversion-execution.md`.** This section was a pre-plan draft sketched during the walkthrough. It does not reflect the v2 post-external-review structure (6 phases vs. the 7 projected here; helper/fragment migration consolidated into Phase 1a; D18 command renames folded in). Retained for audit trail only. See the execution plan for authoritative sequencing.

1. **Phase 0 — Setup**: create `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `bin/`, `fragments/`, `hooks/`, `.gitattributes` (LF rules per D17a). Decide `0.1.0`.
2. **Phase 1 — POC (`/adams-review-promote`)**:
   - **1a — Smoke first**: move helpers it needs to `bin/`, write `bin/include`, run `test/smoke.sh` against the new layout to catch helper-level path bugs cheaply.
   - **1b — Integration**: port the one command + its frontmatter + body bare-name edits. Test with `--defer-publish` against an existing artifact (per D16a). Then publish-mode against a throwaway test PR.
3. **Phase 2 — Port the other 4 commands**: same recipe, more sites.
4. **Phase 3 — Fragments + helpers final move**: complete `_shared/` → `fragments/` + `bin/` migration; delete `_shared/` and update `_common.py`.
5. **Phase 4 — `SessionStart` hook**: ship the dep preflight.
6. **Phase 5 — Docs**: rewrite CLAUDE.md, README install section.
7. **Phase 6 — Cleanup**: delete `scripts/install.sh` + `uninstall.sh`; keep `scripts/dev-link.sh`.
8. **Phase 7 — Smoke**: update `test/smoke.sh` to new paths; run.

Total: roughly 7 phases, mostly mechanical after Phase 1 validates the architecture.

---

## §16 — Post-external-review additions

Decisions and corrections added after an external reviewer's pass on the executable checklist surfaced gaps in the original walkthrough. Kept separate so the audit trail stays clear: these were not in the initial round.

### D18. Command namespacing (RESOLVED: option B)

Per the Claude Code plugins-reference docs, plugin commands are invoked as `/<plugin-name>:<command-name>`, where `plugin-name` comes from `plugin.json` and `command-name` is the filename stem under `commands/`. With `plugin.json` name `adams-review` and current command files (`adams-review-promote.md` etc.), users would invoke `/adams-review:adams-review-promote` — poor UX.

**Options considered**:

- **(a) Accept namespaced UX as-is**. Zero plan churn. Awful invocation names.
- **(b) Rename command stems** to drop the redundant `adams-review-` prefix. **SELECTED.**
- **(c) Shorten the plugin namespace** (e.g., `ar`). Loses name recognition; plugin identity change.

**Invocation mapping**:

| Before (slash command) | After (plugin command) |
|---|---|
| `/adams-review` | `/adams-review:review` |
| `/adams-review-promote` | `/adams-review:promote` |
| `/adams-review-fix` | `/adams-review:fix` |
| `/adams-review-walkthrough` | `/adams-review:walkthrough` |
| `/adams-review-add` | `/adams-review:add` |

**Cascade**: Phase 1b renames `commands/adams-review-promote.md` → `commands/promote.md`. Phase 2.1 renames the remaining four. Phase 5 docs pass updates every user-facing invocation reference. When describing pre-conversion history, use the old names; when describing post-conversion behavior, use the new ones.

### Schema / hook refinements (mechanical corrections, not decisions)

Four places where the external reviewer caught doc-mismatches in the original drafts. Corrections, not decisions; recorded here so the updated state is traceable:

- **`plugin.json#repository`**: string URL (`"https://..."`), not an npm-style object.
- **`marketplace.json#source`**: `"./"` for same-repo relative, not `"."`. Each plugin entry requires `name` + `source` — no "may be omitted" case.
- **`hooks/hooks.json` shape**: wrap `SessionStart` in a top-level `"hooks"` object. `matcher: "*"` and `${CLAUDE_PLUGIN_ROOT}` in hook commands are documented-supported (not open questions).
- **SessionStart hook output injects into model context.** Hard-requirement warnings stay in the hook. Ensemble-dep notice moves out: into README troubleshooting + `/adams-review:review --ensemble` preflight. Avoids polluting every session's context on machines without codex/coderabbit.

### Dev loop (settles D13 sub-question)

The execution plan originally placeholder'd `scripts/dev-link.sh`. Real docs-supported paths are:

- `claude --plugin-dir "$(pwd)"` — session-local, fast iteration. **Chosen for `scripts/dev-run.sh`.**
- `/plugin marketplace add .` + `/plugin install adams-review@adams-review` — install-path simulation. **Documented in README; no wrapper script.**

### `claude plugin validate` gates

The plan originally leaned on `jq . <file>` as a validation step — which only proves JSON parses, not that the plugin loads. Correct tool per docs is `claude plugin validate .`, which checks manifest, command/skill frontmatter, and hook schema. Added to Phase 0 acceptance, Phase 4 acceptance, and Phase 6 final acceptance.

### Testing scope additions

- **Non-trivial `/adams-review:review` run** added to Phase 6. The original plan's sanity test used a docs-only PR (trivial_mode bypasses Phases 1–5), which never exercises the 6-way parallel fan-out — the heaviest plugin-risk surface. Phase 6 now requires one non-trivial run before release; optional `--ensemble` run if external plugins are installed.
- **Manual `AskUserQuestion` check** in default + `acceptEdits` permission modes added to Phase 6. Keeps D10 deferred (no wrapper pre-engineering) while still covering the known regression class.

---

## All decisions resolved

D1–D18 closed as of 2026-04-21. No open questions remain; execution plan is ready to apply.

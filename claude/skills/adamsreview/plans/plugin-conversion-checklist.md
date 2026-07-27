# adams-review → Claude Code Plugin Readiness Checklist

General changes required. Your AI coder should figure out the specifics against the actual codebase.

## 1. Repo layout

- [ ] Add a `.claude-plugin/` directory at the repo root with a `plugin.json` manifest (name, version, description, author, keywords, license field, optional `homepage`/`repository`/`strict` flags).
- [ ] Decide top-level shape: either the repo IS the plugin (manifest at repo root) or the repo is a marketplace that contains one plugin (manifest in a subdirectory with its own `.claude-plugin/plugin.json`). Pick one and commit.
- [ ] Add a `.claude-plugin/marketplace.json` if you want users to install directly from your GitHub repo via `/plugin marketplace add owner/repo`. Otherwise users need a third-party marketplace to list you.
- [ ] Move the five top-level `commands/adams-review*.md` files into the plugin's `commands/` directory at the plugin root.
- [ ] Move all 21 helper scripts from `commands/_shared/tools/` into the plugin's `bin/` directory. The `bin/` directory is auto-added to `$PATH` at plugin load time, which is the whole point — scripts become bare-name callable.
- [ ] Decide what happens to `commands/_shared/` fragments (see §3).
- [ ] Decide what happens to `commands/_shared/schema-v1.json` — it's data, not executable, so it belongs in a `data/` or `resources/` directory referenced by scripts via their own location.

## 2. Frontmatter in command files

- [ ] Strip every absolute `/Users/adammiller/...` path from `allowed-tools` in all five command files. These will not resolve once the plugin is installed to `~/.claude/plugins/cache/`.
- [ ] Replace absolute-path Bash grants with bare-name grants that match what's in `bin/` — e.g., `Bash(artifact-patch.py:*)` instead of `Bash(/Users/.../artifact-patch.py:*)`.
- [ ] Keep `Bash(git:*)`, `Bash(gh:*)`, `Bash(jq:*)`, `Bash(uv:*)`, `Bash(codex:*)`, `Bash(coderabbit:*)` as-is — those are system binaries on user `$PATH`.
- [ ] Keep `Agent`, `AskUserQuestion`, `Read`, `Edit`, `Write`, `BashOutput`, `KillShell` as-is — these all pass through plugin frontmatter unmodified.
- [ ] Keep `argument-hint`, `description`, `disable-model-invocation` as-is.
- [ ] Do NOT rely on `${CLAUDE_PLUGIN_ROOT}` expanding inside `allowed-tools` patterns. It doesn't.

## 3. The `!cat` preprocessor problem

This is the biggest mechanical change. Your top-level command files currently inline shared fragments via `` !`cat /Users/.../commands/_shared/NN-name.md` ``. This pattern breaks in plugins because `${CLAUDE_PLUGIN_ROOT}` is not substituted inside command-markdown `!` preprocessor lines.

Pick ONE of these three strategies and apply it consistently:

- [ ] **Strategy A — Inline everything.** Run the preprocessor once at build time, commit the fully-expanded command files, and delete `_shared/`. Simplest for the plugin; largest files in git; fragment edits now require a build step.
- [ ] **Strategy B — Convert top-level commands to skills.** Move each of the five entry points to `skills/<name>/SKILL.md` where body substitution DOES work. Commands become thin wrappers that invoke the skill. More moving parts; preserves `_shared/` fragment reuse.
- [ ] **Strategy C — Wrapper binary.** Add a `bin/include` script that reads a fragment path relative to its own location (via `$0` / `BASH_SOURCE`) and prints it. Replace `!cat ...` with `!include 00-preflight.md`. Preserves current architecture most faithfully but requires the wrapper script to be robust.

- [ ] Whichever you pick, update `CLAUDE.md`'s "rule 10" guidance to match the new reality.

## 4. Helper scripts (the 21 in `bin/`)

- [ ] Audit every helper for hardcoded `/Users/adammiller/` or `~/.claude/commands/_shared/` paths. Replace with either `$CLAUDE_PLUGIN_ROOT` (works in Bash tool subprocesses from hooks and MCP contexts) or script-relative lookup via `$(dirname "$0")`.
- [ ] Audit every helper for cross-script references. If script A shells out to script B by absolute path, switch to bare-name invocation now that both are on `$PATH`.
- [ ] Confirm the Python helpers' `#!/usr/bin/env -S uv run --script` shebangs still work when invoked as bare names from `bin/`. Test on macOS and Linux — `env -S` behavior differs.
- [ ] Confirm `_common.py` import still resolves. It's imported by the four Python helpers; either keep it alongside them in `bin/` with `sys.path` adjustment, or move it to a `lib/python/` directory that the Python helpers prepend to `sys.path` via their own location.
- [ ] Preserve the atomic tmp-file-then-rename writer pattern — nothing about plugin packaging changes this.
- [ ] Preserve the exit code contract (0/1/2/3/4/5/64) — nothing about plugin packaging changes this either.

## 5. State directory

- [ ] Confirm `~/.adams-reviews/<repo-slug>/<branch>/<review_id>/` still works. It should — the plugin runtime doesn't sandbox home-directory writes outside `~/.claude/`.
- [ ] Consider offering `$CLAUDE_PLUGIN_DATA` as an alternate root when the plugin is installed, so state survives plugin upgrades predictably. Keep `~/.adams-reviews/` as the default and `$ADAMS_REVIEW_REVIEWS_ROOT` as the override.
- [ ] Do NOT move state under `~/.claude/` — the sensitive-file permission prompt there still applies.

## 6. Token accounting

- [ ] Confirm `orchestrator-tokens.sh` can still read `~/.claude/projects/<cwd-slug>/`. The path remains reachable from plugin code; only the plugin's own files live under the cache directory.
- [ ] If the cwd-slug algorithm has changed in recent Claude Code versions, update the `tr '/.' '-'` logic accordingly. Worth spot-checking against a real session transcript.

## 7. Robust interactive prompts

`AskUserQuestion` has had repeated regressions inside plugin contexts. Design for it failing silently rather than trying to pin versions.

- [ ] Wrap every `AskUserQuestion` invocation so an empty or sentinel response triggers a prose-elicitation fallback (ask the question as plain text, end the turn, let the user reply naturally).
- [ ] Add a `--prose` or `--no-interactive` flag to `/adams-review-walkthrough` and `/adams-review-promote` that uses turn-taking elicitation throughout, as a permanent safety net.
- [ ] Test interactive flows under both default and `acceptEdits` permission modes.

## 8. Sub-agent dispatch

- [ ] Confirm the single-turn multi-Agent-block dispatch pattern still works from plugin-shipped commands. It should — plugin-shipped agents fan out identically — but verify on your heaviest fan-out command (`/adams-review` Phase 1 with 6–7 parallel lenses).
- [ ] If you ship any of the lens prompts as plugin `agents/`, note that plugin-shipped agent frontmatter loses `hooks`, `mcpServers`, and `permissionMode` keys. If you rely on those, keep lenses as inline prompts instead.

## 9. Dependency preflight

- [ ] Replace `scripts/install.sh`'s dependency check with a `SessionStart` hook in `hooks/hooks.json` that runs `command -v uv jq gh git` on plugin load and warns loudly on missing tools.
- [ ] There is no install-time lifecycle hook; `SessionStart` is the closest substitute. Keep the hook fast.
- [ ] Consider a separate minimum-version check for Claude Code itself (read version, warn if below your floor). Warning, not failing.

## 10. Install scripts

- [ ] Delete `scripts/install.sh` and `scripts/uninstall.sh`. The plugin system replaces both.
- [ ] Delete the `sed`-rewrite-of-`/Users/adammiller/` step. It's obsolete once paths are bare-name or plugin-relative.
- [ ] Delete the symlink-into-`~/.claude/commands/` step. The plugin cache handles this.
- [ ] Document the new install path in `README.md`: `/plugin marketplace add <your-repo>` then `/plugin install adams-review@<marketplace-name>`.

## 11. Testing

- [ ] Keep `test/smoke.sh`; update any absolute paths inside it to match the new `bin/` layout.
- [ ] Add a CI matrix that installs `@anthropic-ai/claude-code@latest` plus the last 2–3 published versions and runs the smoke tests against each. This tells you about Claude Code regressions before users hit them.
- [ ] Add an end-to-end install test: fresh machine, `/plugin marketplace add`, `/plugin install`, run each of the five commands against a throwaway repo.

## 12. Versioning

- [ ] Put a real semver in `plugin.json`'s `version` field from day one.
- [ ] Bump the version on every release — cached plugin files don't refresh without a version change.
- [ ] Keep a `CHANGELOG.md` so users can see what's in each version.

## 13. Documentation updates

- [ ] Rewrite `CLAUDE.md` to reflect plugin reality — no more symlinks, no more `sed`, no more absolute paths, `bin/` replaces `_shared/tools/`.
- [ ] Rewrite `README.md` install section around `/plugin marketplace add` + `/plugin install`.
- [ ] Add a "troubleshooting" section covering the `AskUserQuestion` prose-fallback mode and the dep-check warnings.

## 14. Proof-of-concept first

- [ ] Before committing to the full port, convert ONE command (`/adams-review-promote` is the simplest — metadata-only) end-to-end. Verify: (a) `bin/` scripts are callable by bare name, (b) `AskUserQuestion` behaves, (c) sub-agent dispatch works, (d) install UX is clean. If any of those fail, you want to know before porting the other four.

---

**Rough sequence:** §14 proof-of-concept first → §1-4 layout and path migration → §3 pick a fragment strategy → §7 prose fallbacks → §8 fan-out verification → §9 SessionStart hook → §10-13 cleanup and docs → §11 CI matrix.

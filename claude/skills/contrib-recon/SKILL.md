---
name: contrib-recon
description: Research an open source project's contribution policies - PR and commit conventions, code style, CI gates, issue templates, where discussion happens, security reporting - and record them as project memory files. Use when starting work on an unfamiliar OSS repo, before opening a first PR or issue upstream, or when the user asks what the contributing rules, house style, or review process for this project are.
---

# contrib-recon

Run from the root of the target repo. Produces durable memory files, not chat prose.

## 1. Gather (one pass)

```bash
bash ~/.claude/skills/contrib-recon/scripts/recon.sh .
```

Dumps: root + `.github` + `docs` trees, policy/governance file paths, lint & task config names, 40 commit titles, commit-prefix histogram, repo settings (license, discussions on/off, merge modes), labels, 8 merged PR bodies, `good first issue` list.

Then **Read** what the dump surfaced — typically `CONTRIBUTING`, `CODE_OF_CONDUCT`, `SECURITY`, issue/PR templates, the lint config, the task runner file, and any `docs/dev/` development guide. Read the linter config properly: the enabled rule set is what actually rejects a PR.

## 2. Infer from practice, not just docs

Docs state intent; merged PRs show the real bar. Extract:

- **PR body shape** — does the body open with `Fixes #N`? Root cause before fix? Named files/functions? Sections? Config snippets for user-visible changes?
- **Commit title shape** — conventional commits? scope list actually in use? Is a `(#N)` appended by squash merge (so branch commits must omit it)?
- **Review/merge flow** — who reviews, squash vs merge commit, DCO sign-off or CLA.
- **CI gates** — the exact jobs a PR must pass, with pinned tool versions.
- **Style** — test location and idiom (mocks vs temp fixtures), doc pages to update alongside code, generated files that need a regen command.
- **Comms** — Discussions on or off, where questions actually go, private security channel.
- **Anything unusual** — AI-generated-code rules, files contributors must not touch, allowlists (spellcheck dictionaries), claim-an-issue mechanics.

## 3. Write memory

Split into ~3 files under the project memory dir (`~/.claude/projects/<slug>/memory/`), one concern each:

- `<project>-pr-and-commit-conventions.md`
- `<project>-code-style-and-ci-gates.md`
- `<project>-issue-and-comms-policy.md`

Each uses the memory frontmatter (`name`, `description`, `metadata.type: project`), cites concrete paths and pinned versions, links siblings with `[[name]]`, and ends with `**Why:**` and `**How to apply:**`. Add one index line per file to `MEMORY.md`. Update an existing file rather than duplicating it.

## 4. Report

Few sentences max: where the memories landed, plus the non-obvious findings — the rules that differ from generic OSS defaults or from the user's own global conventions. Skip anything a reader could guess.

## Notes

- `gh` for anything on github.com; `git` is local-only.
- No upstream GitHub remote (or `gh` missing) → the script still yields docs + commit history; say which signals were unavailable.
- Only write the repo's own tree if the user asks for a committed in-tree doc; default target is project memory.

---
description: Scan for outdated or vulnerable dependencies, research breaking changes, sequence upgrades safely, and implement with test validation.
argument-hint: [package names to upgrade] [--all] [--security-only]
---

**Input:** $ARGUMENTS
**Timestamp:** !date +%Y-%m-%d_%H-%M-%S
**Context:** @CLAUDE.md

Parse flags from $ARGUMENTS:
- `--all` — upgrade all outdated packages
- `--security-only` — only upgrade packages with known CVEs
- Remaining arguments are specific package names to upgrade (if no flags given)

## Phase 1 — Scan

Detect the package manager and run the appropriate outdated check:

```bash
# Node.js
npm outdated --json 2>/dev/null || yarn outdated --json 2>/dev/null

# Python
pip list --outdated --format=json 2>/dev/null

# Go
go list -u -m all 2>/dev/null
```

Also run a vulnerability scan:
```bash
npm audit --json 2>/dev/null || pip-audit --format=json 2>/dev/null
```

Build a list of packages to upgrade based on flags and scan results.

## Phase 2 — Research Breaking Changes

For each package to upgrade, use the Task tool to launch the `researcher` agent. Pass it:
- The package name, current version, and target version
- Instruction: find the changelog/release notes for all versions between current and latest; identify breaking changes, deprecations, migration steps, and any known issues with the target version. Save to `agent/research/dep-{{package-name}}.md`.

If upgrading many packages, launch multiple researcher agents simultaneously (parallel Task calls) to speed up the research phase.

Wait for all research files.

## Phase 3 — Plan Upgrade Sequence

Use the Task tool to launch `plan-architect` with:
- The list of packages and their research files
- Instruction: sequence the upgrades to minimize breakage (upgrade peer dependencies before dependents; group patch/minor changes together; isolate major version upgrades into individual steps). Flag any upgrades that require code changes (API changes, removed exports, config format changes).

Wait for the upgrade plan file.

## Phase 4 — Implement

Use the Task tool to launch a `ralph-executor` agent with:
- The upgrade plan
- Instruction: upgrade packages one logical group at a time; after each group, run the full test suite and fix any failures before proceeding to the next group; document any code changes required by breaking changes in the commit messages

Wait for executor completion.

## Phase 5 — Commit

Use the Task tool to launch `commit-architect`. Each logical upgrade group should be a separate commit (e.g., "chore(deps): upgrade express 4→5 with route handler migration").

## Completion

Report:
- Packages upgraded (old version → new version)
- Test results after final upgrade
- Any packages that could not be upgraded (pinned by peer deps, etc.) with explanation

**MCPs used:** Firecrawl (changelog/release notes research via researcher agent)

---
name: gh-cli-preference
description: Use gh CLI for remote GitHub operations, git CLI for local git operations. Always active.
disable-model-invocation: true
---

# GitHub CLI Preference

The GitHub MCP tools are unauthenticated — they cannot push, create PRs, or perform any operation requiring authentication.

Always use `gh` CLI for remote repository interactions — issues, PRs, repo listing, pushing, etc.

For git operations (commit, clone, branch, etc.), continue using `git` CLI directly.

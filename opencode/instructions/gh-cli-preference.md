# BOUNDARY: gh = GITHUB.COM, git = LOCAL ONLY

This system's `git` CLI is NOT authenticated to GitHub.com. Any command that hits the network (`fetch`, `pull`, `push`, `ls-remote`, etc.) will fail.

## REMOTE — USE gh (DO NOT USE git)

- PRs / PR comments / PR reviews / PR status → `gh pr ...`
- Issues / labels / milestones → `gh issue ...`
- CI / status checks / releases → `gh run ...`, `gh release ...`, `gh api ...`
- Repo info / branch list from remote / commits on remote → `gh repo ...`, `gh api ...`
- Reading files from a remote branch → `gh api repos/{owner}/{repo}/contents/...`
- Fetch from or sync with remote → `gh repo sync` or `gh api ...`
- ANY operation that reads from or writes to github.com → `gh`

## LOCAL — USE git (NO NETWORK)

- status, add, commit, reset, stash
- rebase, merge (local-only, no fetch), cherry-pick
- branch, checkout (local branch), switch
- log, diff, blame, show (local commits)
- ANY operation that does not contact the remote

## DO NOT

- `git fetch`, `git pull`, `git push`, `git ls-remote` — unauthenticated, will fail.
- GitHub MCP tools for read-only lookups — `gh` is faster and already authenticated.
- Use `git` as a substitute for `gh` when reading PRs, issues, or remote state.

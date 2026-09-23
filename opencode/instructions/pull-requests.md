
# Pull requests

Use `gh` for GitHub: issues, pull requests, checks, and releases. If given a GitHub URL, use `gh` to read it. GitHub operations use `gh api`, not an MCP.

When asked to create a pull request:

1. In parallel: git status, git diff, whether the branch tracks a remote, and `git log` plus `git diff [base]...HEAD` for every commit that will be in the PR.
2. Draft the summary from all of those commits, not only the latest.
3. Create a branch if needed, push with `-u` if needed, then `gh pr create`. Pass the body with a HEREDOC.

```
gh pr create --title "the pr title" --body "$(cat <<'EOF'
## Summary
- ...

## Test plan
- [ ] ...

EOF
)"
```

Return the PR URL. Do not update git config.

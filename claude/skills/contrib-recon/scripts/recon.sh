#!/usr/bin/env bash
# contrib-recon: dump an open source repo's contribution-policy surface in one pass.
# usage: recon.sh [repo-dir]   (defaults to cwd; needs git, gh optional)
set -u
cd "${1:-.}" 2>/dev/null || { echo "no such dir: ${1:-.}"; exit 1; }

sec() { printf '\n===== %s =====\n' "$1"; }

sec "ROOT LISTING"
ls -A | grep -v '^\.git$'

sec "POLICY / GOVERNANCE FILES"
find . -maxdepth 3 \( -name .git -o -name node_modules -o -name vendor -o -name target \) -prune -o \
  -type f -iregex '.*\(contributing\|code_of_conduct\|code-of-conduct\|security\|governance\|maintainers\|codeowners\|styleguide\|style_guide\|dco\|cla\|pull_request_template\|issue_template.*\|agents\|claude\)\(\.[a-z]*\)?$' \
  -print 2>/dev/null | sed 's|^\./||'

sec ".github TREE"
ls -R .github 2>/dev/null || echo "(none)"

sec "DOCS TREE"
ls -R docs doc DOCS 2>/dev/null | head -60 || echo "(none)"

sec "TOOLING / LINT / TASK CONFIG"
ls -A | grep -iE '^(\.golangci|\.eslint|\.prettier|biome|ruff|pyproject|setup\.cfg|tox|\.editorconfig|justfile|Justfile|Makefile|Taskfile|\.pre-commit-config|_typos|typos|rustfmt|clippy|\.rubocop|\.clang-format|\.swiftlint|package\.json|go\.mod|Cargo\.toml)'

sec "RECENT COMMIT TITLES (40)"
git log --oneline -40 2>/dev/null

sec "COMMIT SUBJECT SHAPE (top prefixes)"
git log --pretty=%s -200 2>/dev/null | sed -E 's/(\([^)]*\))?:.*/:/' | sort | uniq -c | sort -rn | head -15

sec "REMOTE"
git remote -v 2>/dev/null

command -v gh >/dev/null || { echo; echo "(gh not installed - skipping GitHub queries)"; exit 0; }
SLUG=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)
[ -n "${SLUG:-}" ] || { echo; echo "(no GitHub remote resolved - skipping GitHub queries)"; exit 0; }

sec "REPO SETTINGS ($SLUG)"
gh api "repos/$SLUG" --jq '{default_branch,license:.license.spdx_id,has_issues,has_discussions,has_wiki,allow_squash_merge,allow_merge_commit,allow_rebase_merge,delete_branch_on_merge}' 2>&1

sec "LABELS"
gh label list -R "$SLUG" -L 40 2>&1

sec "MERGED PR BODIES (8)"
gh pr list -R "$SLUG" --state merged --limit 8 --json number,title,author,labels,body 2>&1 | head -c 8000

sec "OPEN CONTRIBUTOR-FACING ISSUES"
gh issue list -R "$SLUG" --label "good first issue" --limit 10 2>&1

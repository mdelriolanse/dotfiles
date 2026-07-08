---
name: submit-for-review
description: Submit a completed feature branch for review. Creates an issue on the <Provider> Planner board, moves it to In review, pushes the branch, and opens a PR that links the issue. Use when the user says they're done with a feature, wants to put something up for review, or says "submit this," "open a PR," "create an issue and PR for this."
---

# Submit for Review

End-of-feature workflow: infer the branch, create a tracking issue, move it to `In review`, push, and open a PR.

## Step 1: Infer context from git

- Current branch: `git branch --show-current`
- Base branch: repo default (`gh repo view --json defaultBranchRef`)
- Remote repo: infer from `git remote get-url origin` or `gh repo view --json owner,name`
- Commits since base: `git log <base>..HEAD --oneline`

Parse branch name for title prefix:
- `feat/scope` → `feat(scope):` prefix
- `fix/scope` or `fix/issue-N` → `fix(scope):` prefix
- `chore/scope` → `chore(scope):` prefix
- `mcm/scope` → `chore(scope):` or `feat(scope):` prefix (multi-change merge)

Generate a 1-sentence summary from the commit messages.

## Step 2: Create the tracking issue

Target repo for the issue is **always** `<org>/<provider>-app` (the Planner board lives there).

Use `gh issue create --repo <org>/<provider>-app`.

**Title**: follow [Planner Board Conventions](file://$HOME/<provider>/docs/planner-board-conventions.md) but with conventional-commit format.  
Bad: `[Users] Hide member enumeration...`  
Good: `feat(users): hide member enumeration when org sharing is off`

Examples:
- `feat/org-hide-members` → `feat(users): hide member enumeration when org sharing is off`
- `fix/issue-838` → `fix(api-keys): editable model access + stale-aware display`

**Body — technical template**:
```markdown
## Context
<!-- One paragraph: what the branch does and why. Derived from commit summary. -->

## Scope
<!-- Bullet list of changes. File paths where known. -->

## Where
<!-- Explicit file paths changed in this branch. -->
```

**Policies (non-negotiable, copied from create-ticket):**
- NEVER add labels (`--label`, `--add-label`). Leave empty.
- ALWAYS assign to `mateo-delriolanse_options`.
- NEVER set Priority or Size.

Capture the issue URL from stdout.

## Step 3: Add to board and set status

```bash
gh project item-add 6 --owner <org> --url "<issue URL>"
```

Get the item ID. If `gh project item-add` does not print the item ID, query it:
```bash
gh project item-list 6 --owner <org> --format json | python3 -c "
import sys, json
data = json.load(sys.stdin)
for item in data.get('items', []):
    content = item.get('content', {})
    if content.get('url', '').endswith('/<issue number>'):
        print(item['id'])
        break
"
```

Set status to **In review**:
```bash
gh project item-edit --project-id PVT_kwDOD20yV84BUEJ6 --id <item-id> \
  --field-id PVTSSF_lADOD20yV84BUEJ6zhBO0dw --single-select-option-id df73e18b
```

## Step 4: Push the branch

Ask the user for explicit approval per the `never-push` instruction, then:
```bash
git push -u origin <branch-name>
```

## Step 5: Merge conflict gate

After pushing, check whether the branch merges cleanly into `<base-branch>`:

```bash
git fetch origin <base-branch>
git branch _opencode-conflict-test HEAD
git checkout _opencode-conflict-test

set +e
git merge --no-commit --no-ff origin/<base-branch> > /dev/null 2>&1
merge_rc=$?
set -e

if [[ "$merge_rc" -ne 0 ]]; then
    conflict_files=$(git diff --name-only --diff-filter=U)
    conflict_count=$(echo "$conflict_files" | awk 'NF' | wc -l | tr -d ' ')

    # Resolve minimally: accept base branch versions
    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        git checkout --theirs -- "$f"
        git add -- "$f"
    done < <(git diff --name-only --diff-filter=U)

    git commit -m "chore: resolve merge conflicts with <base-branch>"

    # Bring resolution back to original branch
    resolved_sha=$(git rev-parse HEAD)
    git checkout <branch-name>
    git merge "$resolved_sha" --ff-only
    git branch -D _opencode-conflict-test
    git push origin <branch-name>

    conflict_list=$(echo "$conflict_files" | awk 'NF' | paste -sd', ' -)
    echo "Conflicts with origin/<base-branch> in $conflict_count file(s): $conflict_list. Resolved by keeping base versions, branch re-pushed."
else
    git reset --hard HEAD
    git checkout <branch-name>
    git branch -D _opencode-conflict-test
fi
```

**Aborts.** If the gate fails for any reason (fetch fails, checkout blocked, etc.), clean up the test branch and return to the original branch. Do NOT proceed to PR creation with an unresolved merge state.

## Step 6: Open the PR on the current repo

PR target is the repo the user is currently working in (inferred from git remote), **not** necessarily `<provider>-app`.

```bash
gh pr create \
  --base <base-branch> \
  --title "<conventional-commit-style title>" \
  --body "$(cat <<'BODY'
Closes #<issue-number>

## What
<1–3 paragraphs derived from commit messages and diff summary>

BODY
)"
```

**Policies:**
- NEVER add labels on the PR.
- Title matches the issue title but in conventional-commit style (`type(scope): description`) or `type: description`.
- Body always starts with `Closes #N`.

## Step 7: Report

With conflict note (if applicable):
```
Issue #N — <title> — In review — <issue URL>
PR #M — <title> — <PR URL>
Branch <branch> pushed to origin.
```

If conflicts were encountered in Step 5, append the conflict summary to the report:

```
Merge conflicts — <count> file(s) with origin/<base-branch>: <file1>, <file2>.
Resolved by keeping base branch versions in all conflicting files.
```

If a conflict resolution commit was created, it is included in the pushed branch.

## Abort conditions

- Stop if you're not in a git repo.
- Stop if the current branch is `main`/`master`.
- Stop if there are no commits ahead of base (nothing to review).
- Stop if `gh` CLI is not authenticated (`gh auth status`).
- Stop if push fails — ask user for permission or suggest fork-and-PR.

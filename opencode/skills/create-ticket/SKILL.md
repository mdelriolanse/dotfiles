---
name: planner-create
description: Create an issue on the <Provider> Planner board with correct conventions, fields, and assignment. Use when user wants to create a task, ticket, issue, or backlog item on the Planner board, or mentions "planner", "add to planner", "create task", "create issue for planner".
---

# Planner Create

Create well-structured issues on the [<Provider> - Planner](https://github.com/orgs/<org>/projects/6) board via `gh` CLI.

## Quick reference

| Thing | Value |
|---|---|
| Board | `<org>/<provider>-app` project #6 |
| Project ID | `PVT_kwDOD20yV84BUEJ6` |
| Repo | `<org>/<provider>-app` |
| Assignee (always) | `mateo-delriolanse_options` |

## Policies (non-negotiable)

1. **NEVER add labels/tags.** No `--label`, no `--add-label`. No `bug`, `enhancement`, `frontend`, nothing. The field says "Labels" but we leave it empty — always.
2. **ALWAYS assign to mateo-delriolanse_options.** `--add-assignee mateo-delriolanse_options` on every issue.
3. **ALWAYS add to the board.** Every issue gets `gh project item-add 6 --owner <org> --url <url>`.

## Field IDs (for `gh project item-edit`)

| Field | Field ID | Option ID → Name |
|---|---|---|
| Status | `PVTSSF_lADOD20yV84BUEJ6zhBO0dw` | `f75ad846` → Backlog, `75a337ac` → Future, `7add7ae9` → UI Handover, `47fc9ee4` → In progress, `df73e18b` → In review, `98236657` → Done |
| Priority | `PVTSSF_lADOD20yV84BUEJ6zhBO0pI` | `ALWAYS LEAVE EMPTY` |
| Size | `PVTSSF_lADOD20yV84BUEJ6zhBO0pM` | `ALWAYS LEAVE EMPTY` |

## Step-by-step workflow


### 1. Write the issue

Follow the [Planner Board Conventions](file://$HOME/<provider>/docs/planner-board-conventions.md) for title and body:

**Title shape — pick one:**

Technical: `[Component]: active-voice action — what and why`

Feature/UI: `[Feature area] - brief noun phrase`

Avoid "Fix X", "Add Y", "Update Z" prefixes.

**Body structure (technical):**

```
## Context
<!-- Current state and what's wrong or missing. One paragraph. -->

## Fix / Scope
<!-- What changes, where, and in what order. File paths and line references. -->

## Impact (if relevant)
<!-- Why this matters: user-facing symptom, security, reliability. -->

## Where
<!-- Explicit file paths. -->
```

**Body structure (feature/UI):**

```
<!-- Description line stating the goal. -->

1. Requirement 1
2. Requirement 2
3. Requirement 3

<!-- Reference links to designs, specs. -->
```

Never leave the body empty.

### 2. Create the issue

```bash
gh issue create \
  --repo <org>/<provider>-app \
  --title "<title>" \
  --body "$(cat <<'BODY'
<body content>
BODY
)"
```

**Never pass `--label` or `--add-label`.** Capture the issue URL from stdout.

### 3. Add to board

```bash
gh project item-add 6 --owner <org> --url "<issue URL>"
```

Capture the item ID. If stdout is empty, query it:

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

### 4. Assign to mateo-delriolanse_options

```bash
gh issue edit <number> --repo <org>/<provider>-app --add-assignee mateo-delriolanse_options
```

### 5. Set fields on the project item

```bash
gh project item-edit --project-id PVT_kwDOD20yV84BUEJ6 --id <item-id> \
  --field-id PVTSSF_lADOD20yV84BUEJ6zhBO0dw --single-select-option-id <status-option-id>
gh project item-edit --project-id PVT_kwDOD20yV84BUEJ6 --id <item-id> \
  --field-id PVTSSF_lADOD20yV84BUEJ6zhBO0pI --single-select-option-id <priority-option-id>
gh project item-edit --project-id PVT_kwDOD20yV84BUEJ6 --id <item-id> \
  --field-id PVTSSF_lADOD20yV84BUEJ6zhBO0pM --single-select-option-id <size-option-id>
```

### 6. Report

Return the issue URL to the user with a one-line summary of what was created (number, title, status, priority, size, assignee).

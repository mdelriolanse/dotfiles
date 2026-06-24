# Planner Issue / Ticket Creation

## GitHub Username Mapping

When creating issues or PRs on the <Provider> GitHub repo, the correct username for self-assignment is:

- **Primary GitHub login:** `mateo-delriolanse`
- **Enterprise / Org alias:** `mateo-delriolanse_options`
- **Git config name:** `Mateo Del Rio Lanse`

> Always use `mateo-delriolanse_options` when assigning issues to self via `gh issue edit --add-assignee` or the GitHub GraphQL API. The plain `mateo-delriolanse` login resolves to the personal account but the org-specific handle is what the <Provider> repository expects for assignment operations.

## Usage Pattern

```bash
# Create issue and assign to self
gh issue create --title "..." --body "..."
gh issue edit <number> --add-assignee mateo-delriolanse_options
```

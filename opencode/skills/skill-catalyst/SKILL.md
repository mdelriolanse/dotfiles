---
name: skill-catalyst
description: Use ONLY at the end of a long-running or recurring task when the agent detects a durable, repeatable workflow that could be captured as a skill. Triggers on patterns like multi-step deployment, environment setup, review pipelines, or any sequence the user is likely to run again.
---

# Skill Catalyst

## Purpose

Your job is to notice when a completed task represents a recurring workflow that would benefit from being saved as a reusable opencode skill. If so, suggest creating a `SKILL.md` — but only at the right time and in the right way.

## When to suggest a skill

A workflow is a good candidate **only** if ALL of the following are true:

1. **It is recurring** — the user has done this before, or will clearly need to do it again (e.g., "deploy to staging", "run lint + test + commit", "set up a new uv project").
2. **It is substantial** — it spans multiple steps, tools, or decisions, not a one-liner.
3. **It is stable** — the sequence is unlikely to change drastically each time.
4. **The task is actually complete** — do NOT suggest a skill mid-task or while work is in progress.

Do NOT suggest a skill for:
- One-off debugging or data analysis
- Tasks that are inherently unique (e.g., "fix this specific bug")
- Ad-hoc Q&A or explanations
- Anything the user explicitly marked as temporary or experimental

## When to make the suggestion

**Only at the very end of your response.**

- Never interrupt a long-running task to suggest a skill.
- If you notice a pattern while working, finish the task first, then raise the suggestion in your closing remarks.
- The suggestion must be the **last** thing in your message.

## Format of the suggestion

Use exactly this format:

```
**New Skill** — One-sentence summary of what the skill would do and why it is reusable.
  - Scope: `project` or `global` — explain your reasoning in one line
  - Permission: Ask the user whether you should write the `SKILL.md` file. Wait for a yes before creating it.
```

### Choosing scope

| If the workflow is... | Suggest scope |
|---|---|
| Specific to a repo or tech stack (e.g., Django migrate + seed, this project's CI rules) | `project` (`.opencode/skills/...`) |
| Generic and reusable across projects (e.g., GitHub PR review, uv setup, Docker build pattern) | `global` (`~/.config/opencode/skills/...`) |

Be conservative: when uncertain, prefer `project` scope.

## What to do after permission is granted

If the user says yes, create the `SKILL.md` with:

1. Frontmatter:
   - `name`: lowercase-hyphen, up to 64 chars, matching the folder name
   - `description`: One sentence covering what the skill does AND when to trigger it. Front-load literal keywords or filenames.
2. Body:
   - A `#` heading with the skill name
   - Step-by-step instructions the next agent can follow without rediscovery
   - Any relevant file paths, commands, or conventions
   - Keep it concise but complete — the goal is to eliminate the discovery phase

After writing it, remind the user to quit and restart opencode so the new skill is loaded.

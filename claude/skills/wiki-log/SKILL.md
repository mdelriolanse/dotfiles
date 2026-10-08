---
name: wiki-log
description: Record knowledge in the repo wiki (plain markdown committed with the code). Use right after an architectural decision or rejected alternative, a bug fix whose root cause was non-obvious, a gotcha learned the hard way, a new or redefined domain term, or when a user overrides an existing ADR. Also use when a Stop hook says the wiki wasn't updated.
---

# wiki-log

Write one entry, keep `docs/INDEX.md` in sync, then tell the user in one line: `Logged to wiki: <path>`. Don't ask permission first.

First check `docs/INDEX.md` (and `qmd search` if unsure): if a page already covers this, **update it** instead of making a new one. If an entry turns out wrong, delete or correct it.

## Where it goes

| What happened | Where |
|---|---|
| Decision that's hard to reverse, a rejected path, an accepted tradeoff | new `docs/adr/NNNN-<slug>.md` (next number) |
| User overrides an existing ADR | new ADR that supersedes it; add `Status: superseded by NNNN` to the old one |
| Non-obvious bug fixed | repo `CLAUDE.md` section; `docs/incidents/YYYY-MM-DD-<slug>.md` if it needs more than ~10 lines |
| Gotcha / constraint learned the hard way | repo `CLAUDE.md` |
| New or changed domain term | `CONTEXT.md` (match its existing format, including `_Avoid_:` lines) |
| How something works changed | the closest existing file in `docs/` |

## Templates

ADR (match the repo's existing ADRs if they differ):
```markdown
# <Decision as a sentence>

Status: accepted.

<Context: what forced the choice, 1–3 sentences.>

<Decision and why. Name the alternatives rejected and why they lost.>
```

Incident:
```markdown
# <Symptom in plain words> (YYYY-MM-DD)

- **Symptom:** what was seen.
- **Root cause:** why it happened.
- **Fix:** what changed (commit or file).
- **Spot it next time:** the tell, and the first thing to check.
```

## Rules
- One topic per file. Write for a future session with zero context: include the *why*.
- Use the vocabulary in `CONTEXT.md`.
- Add, rename or delete a page → update `docs/INDEX.md` in the same change (one line: link + summary).
- Put the entry in the same commit as the code it explains when committing.
- Skip trivia: typos, renames, routine refactors.

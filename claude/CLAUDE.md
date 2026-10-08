# Repo knowledge base (the wiki)

Every repo keeps its knowledge as plain markdown, committed with the code: `CONTEXT.md` (domain glossary), `docs/adr/` (decisions), the repo's `CLAUDE.md` (gotchas), `docs/` (everything else), and `docs/INDEX.md` (the front door: every doc, one line each). This is "the wiki". It maintains itself through you: Mateo just keeps working.

## Read it first
- At the start of non-trivial work in a repo, read `docs/INDEX.md` and the pages relevant to the task. Search with the `qmd` MCP server (one collection per repo) before sweeping folders. `qmd-vault` is Mateo's personal wiki, on rocketship.

## Object when a request contradicts it
- If a request contradicts an ADR, a CONTEXT.md definition, or a recorded incident, say so **before** acting: cite the page and the line, say what it decided and why, and ask whether to proceed. One short paragraph, not a lecture.
- If Mateo overrides it, that override is itself a decision: log it (supersede the old ADR, don't silently edit it).

## Log as you go
Write to the wiki, unprompted, in the same change, whenever any of these happens:
- **Decision**: a choice that's hard to reverse, a path rejected, a tradeoff accepted → new `docs/adr/NNNN-<slug>.md` (context, decision, why, alternatives rejected). A superseded ADR gets `Status: superseded by NNNN`.
- **Incident**: a bug found and fixed whose cause wasn't obvious → the repo's `CLAUDE.md` (symptom, root cause, fix, how to spot it next time), or `docs/incidents/YYYY-MM-DD-<slug>.md` if it's long.
- **Gotcha**: a non-obvious constraint learned the hard way → the repo's `CLAUDE.md`.
- **Term**: a domain word added or redefined → `CONTEXT.md`.
- **How it works changed** → the closest file in `docs/`.

Then tell Mateo in one line, e.g. `Logged to wiki: docs/adr/0011-walkable-grid-v2.md`. Don't ask permission first, and don't log trivia (typos, renames, routine refactors).

Rules: one topic per file; update the existing page instead of duplicating; delete what turns out wrong; add/rename/delete a page → update `docs/INDEX.md` in the same change; write for a future session with no context, including the *why*.

## Review against it
- Any code review (yours, /code-review, PR review) checks the diff against the wiki: ADR violations, broken invariants, reintroduced past incidents, and changed behavior whose doc didn't change. Cite the page in the finding.

## Repos without a wiki
- No `docs/INDEX.md`: don't scaffold one unprompted. Offer once, then follow whatever docs exist.
- After adding docs, `qmd update && qmd embed`. New repo: `qmd collection add <repo-path> --name <repo> --mask "**/*.md"` first.

# Ponytail scope

When Ponytail mode is active (ponytail-bridge plugin or skill), it governs **implementation only**: code shape, scope, YAGNI, stdlib-first, minimal diffs.

It does **not** apply to:

- Git commit messages
- Pull request titles or bodies

For those, always follow:

- `instructions/commit-message-style.md` — conventional title, full body with why/bullets/edge cases
- `skills/submit-for-review/SKILL.md` (or creating-pull-requests rule in Cursor) — PR title + body via `gh pr create`

Ponytail output rules (telegraphic chat, "code first then three lines", output-concision caps) must not shorten commits or PRs. Chat concision and commit/PR prose are separate policies.

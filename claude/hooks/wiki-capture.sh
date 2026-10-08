#!/usr/bin/env bash
# Stop: if this turn changed code but not the wiki, ask haiku whether it produced a decision,
# non-obvious fix, gotcha or new term worth logging. If yes, block once and send Claude to wiki-log.
in=$(cat)
[ -n "$WIKI_HOOK" ] && exit 0
[ "$(jq -r '.stop_hook_active // false' <<<"$in")" = true ] && exit 0

cwd=$(jq -r '.cwd // empty' <<<"$in")
root=$(git -C "${cwd:-${CLAUDE_PROJECT_DIR:-.}}" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -f "$root/docs/INDEX.md" ] || exit 0

# ponytail: looks at the whole uncommitted diff, not just this turn's; per-turn snapshots if it nags
changed=$( (git -C "$root" diff HEAD --name-only; git -C "$root" ls-files --others --exclude-standard) 2>/dev/null | sort -u)
[ -z "$changed" ] && exit 0
grep -qiE '^(docs/|context\.md$|claude\.md$|.*/claude\.md$)' <<<"$changed" && exit 0

msg=$(jq -r '.last_assistant_message // empty' <<<"$in" | head -c 6000)
[ -z "$msg" ] && exit 0

verdict=$(WIKI_HOOK=1 HERMES_TASK=1 VAULT_MINE=1 timeout 40 claude -p --model haiku --tools "" <<EOF 2>/dev/null | tr -d '[:space:]' | head -c 3
An AI coding agent just finished a turn. Changed files (none are docs):
$(head -30 <<<"$changed")

Its final message:
---
$msg
---
Did this turn produce something a teammate would need written down: an architectural decision or rejected alternative, a bug fixed whose root cause was non-obvious, a gotcha learned the hard way, or a new domain term? Routine edits, refactors, typo fixes, and work still in progress do NOT count.
Answer with exactly YES or NO.
EOF
)
[ "$verdict" = YES ] || exit 0

jq -n '{decision:"block", reason:"This turn produced a decision, non-obvious fix, gotcha or term but the repo wiki was not updated. Use the wiki-log skill to record it (ADR, incident, CLAUDE.md gotcha, or CONTEXT.md term), update docs/INDEX.md, then tell the user in one line: `Logged to wiki: <path>`. If on reflection nothing is worth logging, say so in one line and stop."}'

#!/usr/bin/env bash
# Inject the repo wiki (docs/INDEX.md, live ADRs, incidents, CONTEXT.md) into any code review.
# Wired to UserPromptExpansion (user typed /code-review etc.) and PreToolUse[Skill] (model invoked it).
# No-op unless the command is a review and the repo has docs/INDEX.md.
in=$(cat)
event=$(jq -r '.hook_event_name // empty' <<<"$in")
name=$(jq -r '.command_name // .tool_input.skill // empty' <<<"$in")
name=${name##*:} # strip plugin prefix (open-code-review:review → review)
name=${name#/}
case "$name" in
  code-review|review|review-graph|dev-graph|deep-review|resolve-review) ;;
  *) exit 0 ;;
esac

cwd=$(jq -r '.cwd // empty' <<<"$in")
root=$(git -C "${cwd:-${CLAUDE_PROJECT_DIR:-.}}" rev-parse --show-toplevel 2>/dev/null) || root=${CLAUDE_PROJECT_DIR:-}
[ -f "$root/docs/INDEX.md" ] || exit 0

ctx="# Repo wiki: review the diff against it
Check the diff against these pages. ADR violations, reintroduced past incidents, broken CONTEXT.md definitions, and behavior changes whose doc wasn't updated are IMPORTANT findings, not nits. Cite the page path in each finding.

## docs/INDEX.md
$(cat "$root/docs/INDEX.md")
"
body=""
for f in "$root"/docs/adr/*.md "$root"/docs/incidents/*.md "$root/CONTEXT.md"; do
  [ -f "$f" ] || continue
  grep -qiE '^status:.*superseded' "$f" && continue
  body+="
## ${f#$root/}
$(cat "$f")
"
done
# ponytail: 40 KB cap, then titles only; switch to qmd retrieval on the diff if wikis outgrow it
if [ ${#body} -gt 40000 ]; then
  body="
## Pages (too large to inline; read the ones the diff touches)
$(for f in "$root"/docs/adr/*.md "$root"/docs/incidents/*.md; do [ -f "$f" ] && echo "- ${f#$root/}: $(head -1 "$f" | sed 's/^# //')"; done)
"
fi

jq -n --arg e "$event" --arg c "$ctx$body" '{hookSpecificOutput:{hookEventName:$e, additionalContext:$c}}'

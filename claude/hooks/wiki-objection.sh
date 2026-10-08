#!/usr/bin/env bash
# UserPromptSubmit: surface wiki pages (ADRs, incidents, glossary, gotchas) related to the prompt,
# so the model objects before acting on something the wiki already decided against.
in=$(cat)
[ -n "$WIKI_HOOK" ] && exit 0
prompt=$(jq -r '.prompt // empty' <<<"$in")
[ ${#prompt} -lt 20 ] && exit 0
[[ $prompt == /* ]] && exit 0

cwd=$(jq -r '.cwd // empty' <<<"$in")
root=$(git -C "${cwd:-${CLAUDE_PROJECT_DIR:-.}}" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -f "$root/docs/INDEX.md" ] || exit 0
db=${QMD_INDEX:-$HOME/.cache/qmd/index.sqlite}
[ -f "$db" ] || exit 0

# `qmd search` ANDs every term, which misses on natural prompts; query qmd's FTS5 table with OR instead.
hits=$(timeout 3 python3 -I - "$db" "$(basename "$root")" "$prompt" <<'EOF'
import re, sqlite3, sys
db, col, prompt = sys.argv[1:4]
# ponytail: tiny stopword list; words of 3 chars or fewer are dropped too
stop = set("that this with from have what when where which would could should there their about into just like "
           "make want also then than them they your some does dont lets going need back please here only more these "
           "those will been were being still very really maybe think change switch update code file".split())
words = [w for w in dict.fromkeys(re.findall(r"[a-z0-9_]+", prompt.lower())) if len(w) > 3 and w not in stop][:10]
if not words: sys.exit()
q = " OR ".join(f'"{w}"*' for w in words)
c = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
rows = c.execute("select filepath, bm25(documents_fts) s from documents_fts where documents_fts match ? "
                 "and filepath like ? order by s limit 25", (q, col + "/%")).fetchall()
keep = re.compile(r"^[^/]+/(docs/adr/|docs/incidents/|context\.md$|(.*/)?claude\.md$)")
for path, s in [r for r in rows if keep.match(r[0]) and r[1] < -3][:3]:
    print(path.split("/", 1)[1])
EOF
)
[ -z "$hits" ] && exit 0

# the index lowercases paths; map back to real filenames
list=$(while read -r h; do
  real=$(git -C "$root" ls-files | grep -ixF "$h" | head -1)
  echo "- ${real:-$h}"
done <<<"$hits")

jq -n --arg c "Possibly relevant wiki pages for this request:
$list
If the request contradicts one of them, say so before acting: cite the page, say what it decided and why, and ask whether to proceed (an override then gets logged as a superseding ADR)." \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit", additionalContext:$c}}'

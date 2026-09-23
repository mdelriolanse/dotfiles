#!/usr/bin/env bash
set -euo pipefail

# Links all skills in the opencode config to ~/.cursor/skills, so that
# they are available as global Cursor Agent Skills.
#
# Two passes. The opencode tree is the base, then cursor/dot-cursor/skills is
# overlaid on top: a skill present in both wins from the Cursor tree. Skills
# that name harness-specific machinery (the Agent/Task tool, subagent types,
# background dispatch) ship a per-harness copy, and the opencode copy tells the
# agent it is running in OpenCode and to shell out to `opencode run` — wrong,
# and actively misleading, inside Cursor.
#
# NOTE: the destination is ~/.cursor/skills, Cursor's *personal* skills dir.
# Do not target ~/.cursor/skills-cursor: Cursor reserves that for its own
# built-in skills and prunes anything it did not put there.

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CURSOR_SKILLS="$(cd "$REPO/.." && pwd)/cursor/dot-cursor/skills"
DEST="$HOME/.cursor/skills"

mkdir -p "$DEST"

# Prune stale links: drop any symlink in DEST whose target no longer exists
# (e.g. a skill that was deleted/renamed in the source tree).
find "$DEST" -maxdepth 1 -type l ! -exec test -e {} \; -print0 2>/dev/null |
while IFS= read -r -d '' dangling; do
  rm -f "$dangling"
  echo "pruned stale link $(basename "$dangling")"
done

link_tree() {
  local root="$1" label="$2" skip="${3:-}"
  [ -d "$root" ] || return 0
  find "$root" -name SKILL.md -not -path '*/node_modules/*' -not -path '*/deprecated/*' -print0 |
  while IFS= read -r -d '' skill_md; do
    src="$(dirname "$skill_md")"
    name="$(basename "$src")"
    # The session hook already injects skills/ponytail/SKILL.md. Linking it
    # again would put the same text in the skill catalog.
    if [ -n "$skip" ] && [ "$name" = "$skip" ]; then
      if [ -L "$DEST/$name" ]; then rm -f "$DEST/$name"; fi
      continue
    fi
    target="$DEST/$name"

    if [ -e "$target" ] && [ ! -L "$target" ]; then
      rm -rf "$target"
    fi

    ln -sfn "$src" "$target"
    echo "linked $name -> $src${label:+  ($label)}"
  done
}

link_tree "$REPO/skills" ""
link_tree "$REPO/ponytail/skills" "ponytail" "ponytail"
link_tree "$CURSOR_SKILLS" "cursor override"

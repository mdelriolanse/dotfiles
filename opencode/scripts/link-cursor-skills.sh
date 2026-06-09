#!/usr/bin/env bash
set -euo pipefail

# Links all skills in the opencode config to ~/.cursor/skills, so that
# they are available as global Cursor Agent Skills.

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$HOME/.cursor/skills"

mkdir -p "$DEST"

# Prune stale links: drop any symlink in DEST whose target no longer exists
# (e.g. a skill that was deleted/renamed in the source tree).
find "$DEST" -maxdepth 1 -type l ! -exec test -e {} \; -print0 2>/dev/null |
while IFS= read -r -d '' dangling; do
  rm -f "$dangling"
  echo "pruned stale link $(basename "$dangling")"
done

find "$REPO/skills" -name SKILL.md -not -path '*/node_modules/*' -not -path '*/deprecated/*' -print0 |
while IFS= read -r -d '' skill_md; do
  src="$(dirname "$skill_md")"
  name="$(basename "$src")"
  target="$DEST/$name"

  if [ -e "$target" ] && [ ! -L "$target" ]; then
    rm -rf "$target"
  fi

  ln -sfn "$src" "$target"
  echo "linked $name -> $src"
done

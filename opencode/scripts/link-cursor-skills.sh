#!/usr/bin/env bash
set -euo pipefail

# Links all skills in the opencode config to ~/.cursor/skills, so that
# they are available as global Cursor Agent Skills.

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$HOME/.cursor/skills"

mkdir -p "$DEST"

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

#!/usr/bin/env bash
#
# Build IRIS (shell auto-completion) from source with the gruvbox palette.
#
# Upstream ships no theme option -- only the "modern"/"classic" layouts -- and
# its colours are hardcoded Go literals, so the only way to get gruvbox is to
# rewrite them (iris/gruvbox.sed) before compiling. Re-run this to update IRIS;
# it refetches main, re-applies the palette, and reinstalls the binary.
#
# Usage:
#     ./iris/build.sh          # clone/update, patch, build -> ~/.local/bin/iris
#
# ponytail: sed over the one file that holds the palette, not a maintained fork.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${IRIS_SRC:-$HOME/.local/src/iris}"
OVERLAY="$SRC/integration/overlay.go"

if [ -d "$SRC/.git" ]; then
  git -C "$SRC" fetch --depth 1 origin main
  git -C "$SRC" reset --hard FETCH_HEAD
else
  mkdir -p "$(dirname "$SRC")"
  git clone --depth 1 https://github.com/versenilvis/iris.git "$SRC"
fi

sed -i -f "$DIR/gruvbox.sed" "$OVERLAY"

# The palette moved or was renamed upstream if any Aura hex survives.
if grep -qiE '#(a277ff|61ffca|edecee|9692a8)' "$OVERLAY"; then
  echo "iris/gruvbox.sed is stale: unmapped upstream colours remain in $OVERLAY" >&2
  grep -niE '#[0-9a-f]{6}' "$OVERLAY" >&2
  exit 1
fi

mkdir -p "$HOME/.local/bin"
cd "$SRC"
GOTOOLCHAIN=auto go build -o "$HOME/.local/bin/iris" ./cmd/iris
echo "built $("$HOME/.local/bin/iris" --version 2>/dev/null || echo iris) -> ~/.local/bin/iris"

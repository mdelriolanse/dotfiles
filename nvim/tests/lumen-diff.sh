#!/usr/bin/env bash
set -euo pipefail

repo="$(mktemp -d)"
trap 'rm -rf "$repo"' EXIT

mkdir -p "$repo/src" "$repo/bin"
git -C "$repo" init -q
printf 'fn main() {}\n' > "$repo/src/anagrams.rs"
printf '#!/bin/sh\npwd > "$LUMEN_TEST_OUT"\n' > "$repo/bin/lumen"
chmod +x "$repo/bin/lumen"

nvim_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="$repo/lumen-cwd"
PATH="$repo/bin:$PATH" LUMEN_TEST_OUT="$out" nvim --headless -u NONE \
  --cmd "set runtimepath^=$nvim_root" \
  "+edit $repo/src/anagrams.rs" \
  "+lua require('core.lumen-diff').open('worktree'); vim.wait(1000, function() return vim.fn.filereadable('$out') == 1 end)" \
  +qa!

actual="$(<"$out")"
if [[ "$actual" != "$repo" ]]; then
  printf 'lumen cwd: expected %s, got %s\n' "$repo" "$actual" >&2
  exit 1
fi

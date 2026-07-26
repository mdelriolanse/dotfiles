#!/usr/bin/env bash
# ponytail: popup script invoked by herdr keybind prefix+shift+r
# Renames the currently focused agent pane.
set -euo pipefail

pane_id=$(herdr api snapshot 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d['result']['snapshot'].get('focused_pane_id', ''))
" 2>/dev/null)

if [ -z "$pane_id" ]; then
  echo "No focused pane found."
  read -r _
  exit 1
fi

if ! herdr agent get "$pane_id" >/dev/null 2>&1; then
  echo "Focused pane $pane_id is not an agent."
  read -r _
  exit 1
fi

echo "Rename agent $pane_id"
echo "(empty to cancel, --clear to reset):"
read -r name

[ -z "$name" ] && exit 0
herdr agent rename "$pane_id" "$name" >/dev/null 2>&1 && echo "Done." || echo "Rename failed."
read -r _

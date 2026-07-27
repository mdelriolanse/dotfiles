#!/usr/bin/env bash
# ponytail: keep temp pane open briefly after send so omp processes PageUp
# while focused, then closes.
set -uo pipefail

HERDR="${HERDR_BIN_PATH:-$(command -v herdr 2>/dev/null || echo "$HOME/.local/bin/herdr")}"
PANE="${HERDR_ACTIVE_PANE_ID:-}"
[ -n "$PANE" ] || PANE=$("$HERDR" pane current --current 2>/dev/null | jq -r '.result.pane.pane_id // empty')
[ -n "$PANE" ] || exit 0

seq=$([ "${1:-}" = down ] && printf '\x1b[6~' || printf '\x1b[5~')

"$HERDR" pane send-text "$PANE" "$seq" 2>/dev/null

# Keep pane open briefly so the key gets processed; then exit closes it.
sleep 0.3

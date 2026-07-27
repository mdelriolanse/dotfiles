#!/usr/bin/env bash
# omp-watchdog.sh — liveness monitor for an `omp -p --no-session` sub-session.
#
# A stalled sub-session (model hung, provider 502, infinite tool loop with no
# output) burns wall-clock until --max-time fires. This watches the log file
# the orchestrator redirects sub-session stdout to; if no bytes are appended
# for STALL_SECS, it kills the PID and writes a stall marker the orchestrator
# reads when its `wait $PID` returns.
#
# Why log growth, not tokens: `omp -p --no-session` is ephemeral
# (MemorySessionStorage, no JSONL on disk per omp session.md). The stdout log
# is the only progress observable. Bytes-appended == progress.
#
# Usage (orchestrator launches this right after backgrounding the sub-session):
#   omp -p --no-session ... > "$LOG" 2>&1 &
#   PID=$!
#   omp-watchdog.sh "$PID" "$LOG" &
#   WPID=$!
#   wait $PID; RC=$?
#   kill "$WPID" 2>/dev/null   # stop the watchdog once the run ended normally
#   [ -f "${LOG}.stalled" ] && { echo "sub-session $PID stalled — inspect $LOG"; <recover> }
#
# Env knobs:
#   STALL_SECS  — no-output grace period before kill (default 300, i.e. 5 min)
#   CHECK_SECS  — poll interval (default 30)
#   KILL_GRACE  — seconds between SIGTERM and SIGKILL (default 10)

set -euo pipefail

PID="${1:?usage: omp-watchdog.sh <pid> <logfile>}"
LOG="${2:?usage: omp-watchdog.sh <pid> <logfile>}"

STALL_SECS="${STALL_SECS:-300}"
CHECK_SECS="${CHECK_SECS:-30}"
KILL_GRACE="${KILL_GRACE:-10}"

# ponytail: poll mtime, not content hashing — mtime updates on any append,
# cheapest correct liveness signal. Switch to inotifywait if sub-second
# detection matters and the host has it.

[ -e "/proc/$PID" ] || { echo "watchdog: PID $PID not running at start"; exit 0; }

last_size=$(stat -c %s "$LOG" 2>/dev/null || echo 0)
last_change=$(date +%s)
stalled=0

while true; do
  if [ ! -e "/proc/$PID" ]; then
    # ponytail: process exited on its own — normal completion or --max-time.
    # No marker; orchestrator's `wait $PID` returns and proceeds normally.
    exit 0
  fi

  sleep "$CHECK_SECS"

  cur_size=$(stat -c %s "$LOG" 2>/dev/null || echo 0)
  now=$(date +%s)

  if [ "$cur_size" != "$last_size" ]; then
    last_size=$cur_size
    last_change=$now
    continue
  fi

  if [ $(( now - last_change )) -ge "$STALL_SECS" ]; then
    stalled=1
    break
  fi
done

[ "$stalled" -eq 1 ] || exit 0

# Stall confirmed. Write the marker the orchestrator checks after `wait`.
: > "${LOG}.stalled"
echo "watchdog: no output to $LOG for ${STALL_SECS}s; killing PID $PID" >> "${LOG}.stalled"

kill -TERM "$PID" 2>/dev/null || true
for _ in $(seq 1 "$KILL_GRACE"); do
  [ -e "/proc/$PID" ] || break
  sleep 1
done
[ -e "/proc/$PID" ] && kill -KILL "$PID" 2>/dev/null || true

exit 0

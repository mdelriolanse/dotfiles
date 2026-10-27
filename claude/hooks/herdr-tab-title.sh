#!/bin/sh
# Name the herdr tab after the newest Claude chat started in it.
#   SessionStart (new, /clear, -c, --resume): this chat becomes the tab's owner.
#   Stop: if this chat owns the tab, set the label to its title.
# A label you typed yourself is never overwritten: the hook renames only a numbered
# label (herdr's default) or the label it set itself last time.
[ "${HERDR_ENV:-}" = "1" ] && [ -n "${HERDR_TAB_ID:-}" ] || exit 0
command -v herdr >/dev/null 2>&1 || exit 0

HOOK_ACTION="${1:-stop}" HOOK_INPUT="$(cat)" python3 - <<'PY' || true
import json, os, subprocess

try:
    hook = json.loads(os.environ.get("HOOK_INPUT") or "{}")
except Exception:
    raise SystemExit(0)
if hook.get("agent_id"):  # subagent
    raise SystemExit(0)
sid = hook.get("session_id") or ""
path = hook.get("transcript_path") or ""
tab = os.environ["HERDR_TAB_ID"]

state_dir = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "herdr-tab-title")
state_file = os.path.join(state_dir, f"{os.environ.get('HERDR_SESSION', 'default')}_{tab}.json".replace(":", "-"))
try:
    with open(state_file) as f:
        state = json.load(f)
except Exception:
    state = {}

def save():
    os.makedirs(state_dir, exist_ok=True)
    with open(state_file, "w") as f:
        json.dump(state, f)

if os.environ["HOOK_ACTION"] == "session":
    state["owner"] = sid
    save()
elif state.get("owner") and state["owner"] != sid:
    raise SystemExit(0)  # an older chat in this tab; the newest one owns the label

custom = ai = None
try:
    with open(path, encoding="utf-8") as f:
        for line in f:
            if '"custom-title"' not in line and '"ai-title"' not in line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            if r.get("type") == "custom-title":
                custom = r.get("customTitle") or custom
            elif r.get("type") == "ai-title":
                ai = r.get("aiTitle") or ai
except OSError:
    pass
title = (custom or ai or "").strip()
if not title:
    raise SystemExit(0)  # new chat, no title yet; the next Stop tries again

try:
    out = subprocess.run(["herdr", "tab", "get", tab], capture_output=True, text=True, timeout=2).stdout
    label = str(json.loads(out)["result"]["tab"]["label"])
except Exception:
    raise SystemExit(0)
if label == title or not (label.isdigit() or label == state.get("set")):
    raise SystemExit(0)
if subprocess.run(["herdr", "tab", "rename", tab, title], capture_output=True, timeout=2).returncode == 0:
    state["set"] = title
    save()
PY
exit 0

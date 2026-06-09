#!/usr/bin/env bash
#
# Dotfiles bootstrap — safe to re-run (idempotent).
#
# On a fresh Linux machine:
#     git clone <repo> ~/dotfiles && cd ~/dotfiles && ./install.sh
#
# It symlinks the standard config locations into this repo, scaffolds the
# (gitignored) secrets file, regenerates derived state, and checks prereqs.
# Existing files are backed up under ~/.dotfiles-backup-<timestamp>/ before
# being replaced — nothing is destroyed.
#
# Usage:
#     ./install.sh              # links + scaffolding
#     ./install.sh --extensions # also reinstall Cursor extensions from snapshot
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/.dotfiles-backup-$TS"

c_info='\033[0;36m'; c_ok='\033[0;32m'; c_warn='\033[0;33m'; c_off='\033[0m'
info() { printf "${c_info}[*]${c_off} %s\n" "$*"; }
ok()   { printf "${c_ok}[ok]${c_off} %s\n" "$*"; }
warn() { printf "${c_warn}[!]${c_off} %s\n" "$*"; }

# link <target> <source-in-repo>
link() {
  local target="$1" src="$2"
  if [ ! -e "$src" ]; then warn "source missing, skip: $src"; return 0; fi
  if [ -L "$target" ] && [ "$(readlink -f "$target")" = "$(readlink -f "$src")" ]; then
    ok "already linked: ${target/#$HOME/\~}"; return 0
  fi
  mkdir -p "$(dirname "$target")"
  if [ -e "$target" ] || [ -L "$target" ]; then
    mkdir -p "$BACKUP_DIR$(dirname "$target")"
    mv "$target" "$BACKUP_DIR$target"
    warn "backed up ${target/#$HOME/\~} -> ${BACKUP_DIR/#$HOME/\~}$target"
  fi
  ln -s "$src" "$target"
  ok "linked ${target/#$HOME/\~} -> ${src/#$HOME/\~}"
}

info "Dotfiles repo: $REPO_DIR"

# ---------------------------------------------------------------------------
# 1. Symlinks  (whole dirs for nvim/opencode; individual items for Cursor)
# ---------------------------------------------------------------------------
link "$HOME/.config/nvim"                          "$REPO_DIR/nvim"
link "$HOME/.config/opencode"                      "$REPO_DIR/opencode"
link "$HOME/.config/Cursor/User/settings.json"     "$REPO_DIR/cursor/User/settings.json"
link "$HOME/.config/Cursor/User/keybindings.json"  "$REPO_DIR/cursor/User/keybindings.json"
link "$HOME/.config/Cursor/User/snippets"          "$REPO_DIR/cursor/User/snippets"
link "$HOME/.cursor/argv.json"                     "$REPO_DIR/cursor/dot-cursor/argv.json"
link "$HOME/.cursor/cli-config.json"               "$REPO_DIR/cursor/dot-cursor/cli-config.json"
link "$HOME/.cursor/USER_RULES.md"                 "$REPO_DIR/cursor/dot-cursor/USER_RULES.md"
link "$HOME/.cursor/commands"                      "$REPO_DIR/cursor/dot-cursor/commands"
link "$HOME/.cursor/skills-cursor"                 "$REPO_DIR/cursor/dot-cursor/skills-cursor"
# NOTE: ~/.cursor/plans/ is intentionally NOT centralized — it holds
# project-specific agent plans and stays local-only.

# ---------------------------------------------------------------------------
# 2. Secrets scaffold (real values live ONLY here, gitignored)
# ---------------------------------------------------------------------------
SECRETS="$REPO_DIR/secrets/secrets.env"
if [ ! -f "$SECRETS" ]; then
  cp "$REPO_DIR/secrets/secrets.env.example" "$SECRETS"
  warn "created secrets/secrets.env from example — EDIT IT and add real keys."
else
  ok "secrets/secrets.env present"
fi

# ---------------------------------------------------------------------------
# 3. Source secrets from ~/.bashrc (idempotent)
# ---------------------------------------------------------------------------
BASHRC="$HOME/.bashrc"
if [ -f "$BASHRC" ] && ! grep -qF 'dotfiles/secrets/secrets.env' "$BASHRC"; then
  {
    printf '\n# Load dotfiles secrets (gitignored)\n'
    printf '[ -f "%s" ] && set -a && . "%s" && set +a\n' "$SECRETS" "$SECRETS"
  } >> "$BASHRC"
  ok "added secrets sourcing to ~/.bashrc"
else
  ok "~/.bashrc already sources secrets (or no ~/.bashrc)"
fi

# ---------------------------------------------------------------------------
# 4. Cursor real mcp.json (gitignored) — generate from example + secrets.
#    Cursor's ${VAR} expansion is unreliable, so we materialize real values.
#    Missing/empty keys are fine: we still write a stub so the rest of the
#    bootstrap is uninterrupted — those MCP servers just fail at runtime.
#    Never overwrites an existing mcp.json.
# ---------------------------------------------------------------------------
MCP_REAL="$REPO_DIR/cursor/dot-cursor/mcp.json"
MCP_EX="$REPO_DIR/cursor/dot-cursor/mcp.json.example"

# Load secrets defensively — a missing var or sourcing hiccup must NOT abort.
if [ -f "$SECRETS" ]; then
  set +e +u
  set -a; . "$SECRETS" 2>/dev/null; set +a
  set -e -u
fi

# Inform (don't fail) when MCP keys are absent — those servers will be stubs.
mcp_missing=""
for v in FIRECRAWL_API_KEY BROWSERBASE_API_KEY BROWSERBASE_PROJECT_ID \
         GEMINI_API_KEY AGENTMEMORY_SECRET GITHUB_TOKEN; do
  [ -z "${!v:-}" ] && mcp_missing="$mcp_missing $v"
done
[ -n "$mcp_missing" ] && warn "MCP keys empty/unset:$mcp_missing — those Cursor MCP servers will be stubbed and fail until you fill secrets.env (bootstrap continues)."

if [ ! -e "$MCP_REAL" ]; then
  : "${NODE_BIN_PATH:=$(dirname "$(command -v node 2>/dev/null || echo /usr/bin/node)")}"
  export NODE_BIN_PATH
  if command -v envsubst >/dev/null 2>&1 \
     && envsubst '$NODE_BIN_PATH $FIRECRAWL_API_KEY $AGENTMEMORY_SECRET $BROWSERBASE_API_KEY $BROWSERBASE_PROJECT_ID $GEMINI_API_KEY $GITHUB_TOKEN' \
          < "$MCP_EX" > "$MCP_REAL" 2>/dev/null; then
    ok "generated cursor/dot-cursor/mcp.json (any empty keys are written as stubs)"
  else
    cp "$MCP_EX" "$MCP_REAL" 2>/dev/null || true
    warn "wrote mcp.json stub from example (no envsubst, or substitution failed) — fill secrets.env + re-run."
  fi
fi
link "$HOME/.cursor/mcp.json" "$MCP_REAL"

# ---------------------------------------------------------------------------
# 5. Regenerate derived Cursor skills (symlinks into opencode/skills)
# ---------------------------------------------------------------------------
if [ -x "$REPO_DIR/opencode/scripts/link-cursor-skills.sh" ]; then
  info "Linking opencode skills into ~/.cursor/skills ..."
  "$REPO_DIR/opencode/scripts/link-cursor-skills.sh" >/dev/null 2>&1 && ok "cursor skills linked" \
    || warn "skill linking failed (non-fatal)"
fi

# ---------------------------------------------------------------------------
# 6. Optional: reinstall Cursor extensions from snapshot
# ---------------------------------------------------------------------------
if [ "${1:-}" = "--extensions" ]; then
  if command -v cursor >/dev/null 2>&1; then
    info "Installing Cursor extensions from snapshot ..."
    while IFS= read -r ext; do
      [ -n "$ext" ] && { cursor --install-extension "$ext" || warn "could not install $ext"; }
    done < "$REPO_DIR/cursor/dot-cursor/extensions-list.txt"
  else
    warn "cursor CLI not found; cannot install extensions."
  fi
fi

# ---------------------------------------------------------------------------
# 7. Prerequisite check (warn-only; we do not auto-install system packages)
# ---------------------------------------------------------------------------
info "Checking prerequisites ..."
for c in git nvim node npx envsubst; do
  command -v "$c" >/dev/null 2>&1 && ok "found $c" || warn "MISSING: $c"
done
command -v opencode >/dev/null 2>&1 && ok "found opencode" || warn "opencode not on PATH — see https://opencode.ai"
command -v cursor   >/dev/null 2>&1 && ok "found cursor CLI" || warn "cursor CLI not on PATH"

# ---------------------------------------------------------------------------
# 8. Summary / next steps
# ---------------------------------------------------------------------------
cat <<EOF

$(printf "${c_ok}Bootstrap complete.${c_off}")

Next steps:
  1) Fill in real keys:   \$EDITOR $SECRETS    (gitignored, never pushed)
  2) Re-run ./install.sh  (regenerates Cursor mcp.json with real values)
  3) Open a new shell so secrets.env is sourced (opencode reads {env:...})
  4) Cursor extensions:   ./install.sh --extensions
  5) Cursor will re-fetch the plugins in cursor/dot-cursor/plugins-list.txt on demand.

Backups of anything replaced (if any) are under: $BACKUP_DIR
EOF

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
link "$HOME/.tmux.conf"                           "$REPO_DIR/tmux/tmux.conf"
link "$HOME/.config/nvim"                          "$REPO_DIR/nvim"
link "$HOME/.config/opencode"                      "$REPO_DIR/opencode"
link "$HOME/.config/starship.toml"                 "$REPO_DIR/starship/starship.toml"
link "$HOME/.config/kitty/kitty.conf"              "$REPO_DIR/kitty/kitty.conf"
# Ghostty: items only — ~/.config/ghostty can hold runtime files.
link "$HOME/.config/ghostty/config.ghostty"        "$REPO_DIR/ghostty/config.ghostty"
link "$HOME/.config/ghostty/tabs.css"              "$REPO_DIR/ghostty/tabs.css"
link "$HOME/.config/iris/config.toml"              "$REPO_DIR/iris/config.toml"
link "$HOME/.config/iris/theme.toml"               "$REPO_DIR/iris/theme.toml"
link "$HOME/.bashrc"                               "$REPO_DIR/bash/bashrc"
link "$HOME/.blerc"                                "$REPO_DIR/bash/blerc"
link "$HOME/.config/Cursor/User/settings.json"     "$REPO_DIR/cursor/User/settings.json"
link "$HOME/.config/Cursor/User/keybindings.json"  "$REPO_DIR/cursor/User/keybindings.json"
link "$HOME/.config/Cursor/User/snippets"          "$REPO_DIR/cursor/User/snippets"
link "$HOME/.cursor/argv.json"                     "$REPO_DIR/cursor/dot-cursor/argv.json"
link "$HOME/.cursor/cli-config.json"               "$REPO_DIR/cursor/dot-cursor/cli-config.json"
link "$HOME/.cursor/hooks.json"                    "$REPO_DIR/cursor/dot-cursor/hooks.json"
link "$HOME/.cursor/hooks"                         "$REPO_DIR/cursor/dot-cursor/hooks"
# Not linked: never-push, gh-cli-preference, commit-message-style.
# The user-prompt copies of push/gh/commit style live in git-commit and pull-requests.
mkdir -p "$HOME/.cursor/rules"
for rule in shared-machine chinese-model-english codebase-discovery \
  commit-hygiene karpathy-guidelines ponytail-scope \
  context-efficiency output-concision telegraphic concision-scope \
  affirmative browser-verify git-commit pull-requests; do
  link "$HOME/.cursor/rules/$rule.mdc" "$REPO_DIR/cursor/dot-cursor/rules/$rule.mdc"
done
link "$HOME/.cursor/USER_RULES.md"                 "$REPO_DIR/cursor/dot-cursor/USER_RULES.md"
link "$HOME/.cursor/skills-cursor"                 "$REPO_DIR/cursor/dot-cursor/skills-cursor"
# Claude Code: symlink individual items only — ~/.claude is a real dir holding
# runtime state, so we must never replace the whole directory. Claude Code has its
# OWN committed config under claude/ (skills copied from opencode, CLAUDE.md, and
# mcp.json.example). settings.json, skills/, agents/, and CLAUDE.md are
# pure symlinks here;
# MCP registration + the ponytail plugin need the claude CLI and live in section 6.
link "$HOME/.claude/settings.json"                 "$REPO_DIR/claude/settings.json"
link "$HOME/.claude/skills"                        "$REPO_DIR/claude/skills"
link "$HOME/.claude/CLAUDE.md"                      "$REPO_DIR/claude/CLAUDE.md"
link "$HOME/.claude/agents"                        "$REPO_DIR/claude/agents"
if [ -L "$HOME/.claude/commands" ]; then
  rm -f "$HOME/.claude/commands"
  ok "removed stale ~/.claude/commands symlink"
fi
# NOTE: herdr is wired in section 6c, not here.
# NOTE: ~/.cursor/commands is NOT centralized. opencode/skills is the single
# source of truth; those skills are deployed to ~/.cursor/skills by
# link-cursor-skills.sh (step 5). A skill behaves as a /slash command in Cursor
# when its frontmatter sets `disable-model-invocation: true`; otherwise it
# auto-invokes. Remove any stale ~/.cursor/commands symlink from older installs.
if [ -L "$HOME/.cursor/commands" ]; then
  rm -f "$HOME/.cursor/commands"
  ok "removed stale ~/.cursor/commands symlink (skills now cover commands)"
fi
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
# 5b. Hermes agent (~/.hermes)
#     Pure-preference files are symlinked (edit-here == edit-live). config.yaml
#     and .env mix preferences with secrets AND are rewritten by Hermes at
#     runtime, so they are NOT symlinked: we materialize them from the tracked
#     *.example templates + secrets.env, ONCE, only if absent (never clobber a
#     live config). Secrets already sourced into the env in step 4.
# ---------------------------------------------------------------------------
HERMES_HOME="$HOME/.hermes"
if [ -d "$REPO_DIR/hermes" ]; then
  # Symlinked preferences (persona, digest topics).
  link "$HERMES_HOME/SOUL.md"         "$REPO_DIR/hermes/SOUL.md"
  link "$HERMES_HOME/news-topics.txt" "$REPO_DIR/hermes/news-topics.txt"
  # hermes/scripts is gitignored (machine-local). Link only if present.
  if [ -d "$REPO_DIR/hermes/scripts" ]; then
    link "$HERMES_HOME/scripts" "$REPO_DIR/hermes/scripts"
  fi
  # User skills only. Each hermes/skills/<category>/<skill> is linked into the
  # live tree. The rest of ~/.hermes/skills stays Hermes-managed (bundled sync).
  if [ -d "$REPO_DIR/hermes/skills" ]; then
    while IFS= read -r src; do
      rel="${src#"$REPO_DIR/hermes/skills/"}"
      dest="$HERMES_HOME/skills/$rel"
      # A category dir that is itself a symlink (skills/research -> ~/.agents)
      # would drop the skill back onto a Cursor load path. Link it at the
      # top of ~/.hermes/skills/ instead.
      if [ -L "$(dirname "$dest")" ]; then
        dest="$HERMES_HOME/skills/$(basename "$src")"
      fi
      link "$dest" "$src"
    done < <(find "$REPO_DIR/hermes/skills" -mindepth 2 -maxdepth 2 -type d | sort)
  fi

  # Scaffold secret-bearing, runtime-mutated files from templates (if absent).
  # hermes_scaffold <target> <template> <var-list-for-envsubst>
  hermes_scaffold() {
    local target="$1" tmpl="$2" vars="$3"
    [ -f "$tmpl" ] || { warn "hermes template missing, skip: ${tmpl/#$HOME/\~}"; return 0; }
    if [ -e "$target" ]; then ok "hermes: ${target/#$HOME/\~} already present (left as-is)"; return 0; fi
    mkdir -p "$(dirname "$target")"
    if command -v envsubst >/dev/null 2>&1 \
       && envsubst "$vars" < "$tmpl" > "$target" 2>/dev/null; then
      ok "hermes: materialized ${target/#$HOME/\~} from $(basename "$tmpl") (empty keys written as blanks)"
    else
      cp "$tmpl" "$target" 2>/dev/null || true
      warn "hermes: wrote ${target/#$HOME/\~} stub from template (no envsubst) — fill secrets.env + re-run."
    fi
  }
  hermes_scaffold "$HERMES_HOME/config.yaml" "$REPO_DIR/hermes/config.yaml.example" \
    '$HERMES_MODEL_API_KEY $AGENTMEMORY_SECRET'
  hermes_scaffold "$HERMES_HOME/.env"        "$REPO_DIR/hermes/.env.example" \
    '$TELEGRAM_BOT_TOKEN $TELEGRAM_ALLOWED_USERS $TELEGRAM_HOME_CHANNEL $TELEGRAM_HOME_CHANNEL_NAME'

  hermes_missing=""
  for v in HERMES_MODEL_API_KEY AGENTMEMORY_SECRET TELEGRAM_BOT_TOKEN; do
    [ -z "${!v:-}" ] && hermes_missing="$hermes_missing $v"
  done
  [ -n "$hermes_missing" ] && warn "Hermes keys empty/unset:$hermes_missing — fill secrets.env; existing ~/.hermes files (if any) were left untouched."
fi

# ---------------------------------------------------------------------------
# 6. Claude Code — its own committed config lives under claude/ (skills copied
#    from opencode, CLAUDE.md, mcp.json.example). skills/ + CLAUDE.md + settings
#    are already symlinked in section 1. This section handles the two things that
#    need the `claude` CLI: MCP registration (user scope can't be symlinked) and
#    the ponytail plugin. Idempotent; no-ops cleanly when the CLI is absent.
# ---------------------------------------------------------------------------
if command -v claude >/dev/null 2>&1; then
  info "Configuring Claude Code ..."

  # 6.1 MCP: materialize claude/mcp.json from mcp.json.example (real secret values
  #     substituted, gitignored — same pattern as Cursor in step 4), then register
  #     each server into Claude's user scope. Claude keeps user-scope MCP inside
  #     ~/.claude.json (heavy runtime state), so this is registered via the CLI
  #     rather than symlinked. remove-then-add keeps it idempotent; a "command"
  #     key -> stdio add-json, a bare {url} -> http transport.
  CLAUDE_MCP_REAL="$REPO_DIR/claude/mcp.json"
  CLAUDE_MCP_EX="$REPO_DIR/claude/mcp.json.example"
  if [ ! -e "$CLAUDE_MCP_REAL" ] && [ -f "$CLAUDE_MCP_EX" ]; then
    if command -v envsubst >/dev/null 2>&1 \
       && envsubst '$GITHUB_TOKEN' < "$CLAUDE_MCP_EX" > "$CLAUDE_MCP_REAL" 2>/dev/null; then
      ok "generated claude/mcp.json (empty secrets written as stubs)"
    else
      cp "$CLAUDE_MCP_EX" "$CLAUDE_MCP_REAL" 2>/dev/null || true
      warn "wrote claude/mcp.json stub from example (no envsubst) — fill secrets.env + re-run."
    fi
  fi
  if command -v jq >/dev/null 2>&1 && [ -f "$CLAUDE_MCP_REAL" ]; then
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      srv="$(jq -c --arg n "$name" '.mcpServers[$n]' "$CLAUDE_MCP_REAL")"
      claude mcp remove "$name" -s user >/dev/null 2>&1 || true
      if printf '%s' "$srv" | jq -e 'has("command")' >/dev/null 2>&1; then
        claude mcp add-json "$name" "$srv" -s user >/dev/null 2>&1 \
          && ok "claude MCP: $name" || warn "claude MCP: failed to add $name"
      else
        url="$(printf '%s' "$srv" | jq -r '.url // empty')"
        [ -n "$url" ] && { claude mcp add --transport http "$name" "$url" -s user >/dev/null 2>&1 \
          && ok "claude MCP: $name (http)" || warn "claude MCP: failed to add $name"; }
      fi
    done < <(jq -r '.mcpServers | keys[]' "$CLAUDE_MCP_REAL" 2>/dev/null)
  else
    warn "claude MCP skipped (need jq + claude/mcp.json)"
  fi

  # 6.2 ponytail: install its native Claude Code plugin (commands, hooks, modes).
  #     `marketplace add` wants the dir CONTAINING .claude-plugin/marketplace.json
  #     (the repo root), not the .claude-plugin dir itself.
  PONY_ROOT="$REPO_DIR/opencode/ponytail"
  if [ -f "$PONY_ROOT/.claude-plugin/marketplace.json" ]; then
    claude plugin marketplace add "$PONY_ROOT" >/dev/null 2>&1 || true
    if claude plugin list 2>/dev/null | grep -qi "ponytail"; then
      ok "ponytail Claude Code plugin present"
    else
      claude plugin install ponytail@ponytail >/dev/null 2>&1 \
        && ok "installed ponytail Claude Code plugin" \
        || warn "ponytail plugin install failed (non-fatal)"
    fi
  else
    warn "ponytail plugin skipped — $PONY_ROOT/.claude-plugin/marketplace.json missing (init the git submodule?)"
  fi
else
  info "claude CLI not on PATH — skipping Claude Code config (see https://claude.com/claude-code)"
fi

# ---------------------------------------------------------------------------
# 6b. omp agent (~/.omp/agent)
#     omp discovers this tree natively via its .omp provider (priority 100).
#     Link individual items ONLY — ~/.omp/agent also holds live runtime state
#     (agent.db, sessions/, history.db) that must stay real files.
#     mcp.json is a plain symlink (NOT materialized like claude/mcp.json): omp
#     resolves credentials by bare env-var name, so no secret is ever written
#     into the tracked file.
# ---------------------------------------------------------------------------
OMP_AGENT="$HOME/.omp/agent"
if [ -d "$REPO_DIR/omp" ]; then
  link "$OMP_AGENT/AGENTS.md"   "$REPO_DIR/omp/AGENTS.md"
  link "$OMP_AGENT/config.yml"  "$REPO_DIR/omp/config.yml"
  link "$OMP_AGENT/models.yml"  "$REPO_DIR/omp/models.yml"
  link "$OMP_AGENT/mcp.json"    "$REPO_DIR/omp/mcp.json"
  link "$OMP_AGENT/lsp.json"    "$REPO_DIR/omp/lsp.json"
  link "$OMP_AGENT/extensions"  "$REPO_DIR/omp/extensions"
  link "$OMP_AGENT/skills"      "$REPO_DIR/omp/skills"
fi

# ---------------------------------------------------------------------------
# 6c. herdr terminal multiplexer (~/.config/herdr)
#     Link items, not the dir — herdr may write runtime state alongside config.
#     Note: herdr/config.toml hardcodes ~/dotfiles/herdr/scripts/rename-agent.sh
#     for its rename popup, so the repo must live at ~/dotfiles for that keybind
#     to resolve. The scripts symlink below is what makes it reachable.
#     The omp/opencode agent-state plugins are deliberately NOT linked here.
#     herdr owns them via `herdr integration install <omp|opencode>`, which
#     version-stamps each one, so symlinking would fight its updater.
# ---------------------------------------------------------------------------
if [ -d "$REPO_DIR/herdr" ]; then
  link "$HOME/.config/herdr/config.toml" "$REPO_DIR/herdr/config.toml"
  link "$HOME/.config/herdr/scripts"     "$REPO_DIR/herdr/scripts"
fi

# ---------------------------------------------------------------------------
# 6d. Codex CLI harness (~/.codex)
#     AGENTS.md is the global user-instruction file Codex reads from CODEX_HOME
#     (AGENTS.override.md wins if present). Symlink that file. Do NOT set
#     model_instructions_file — that replaces Codex's built-in base instructions.
#     Upsert approval/sandbox keys from the tracked snippet. Do NOT symlink
#     ~/.codex or the live config.toml — Codex rewrites that file (hooks.state,
#     plugins, desktop) and it holds secrets. No persistent `codex config set`;
#     -c is session-only. Line replace/insert only; never rewrite from a parse.
# ---------------------------------------------------------------------------
link "$HOME/.codex/AGENTS.md" "$REPO_DIR/codex/AGENTS.md"
CODEX_HARNESS="$REPO_DIR/codex/harness.toml"
CODEX_CFG="$HOME/.codex/config.toml"
if [ -f "$CODEX_HARNESS" ]; then
  mkdir -p "$HOME/.codex"
  if [ -f "$CODEX_CFG" ] && grep -qE '^default_permissions[[:space:]]*=' "$CODEX_CFG"; then
    warn "Codex: live config has default_permissions — do not mix with sandbox_mode (Permissions docs). Leaving it; harness still upserts classic keys."
  fi
  # upsert_toml_top_level <file> <key> <value>
  upsert_toml_top_level() {
    local file="$1" key="$2" value="$3" tmp
    tmp="$(mktemp)"
    if [ ! -f "$file" ]; then
      printf '%s = %s\n' "$key" "$value" > "$file"
      rm -f "$tmp"
      return 0
    fi
    if grep -qE "^${key}[[:space:]]*=" "$file"; then
      awk -v k="$key" -v v="$value" '
        BEGIN { done=0 }
        $0 ~ "^" k "[[:space:]]*=" && !done { print k " = " v; done=1; next }
        { print }
      ' "$file" > "$tmp"
    else
      printf '%s = %s\n' "$key" "$value" > "$tmp"
      cat "$file" >> "$tmp"
    fi
    mv "$tmp" "$file"
  }
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|\#*) continue ;;
      \[*) break ;;
    esac
    key="${line%%=*}"
    key="${key%"${key##*[![:space:]]}"}"
    value="${line#*=}"
    value="${value#"${value%%[![:space:]]*}"}"
    [ -n "$key" ] && [ -n "$value" ] || continue
    upsert_toml_top_level "$CODEX_CFG" "$key" "$value"
  done < "$CODEX_HARNESS"
  ok "Codex harness upserted into ~/.codex/config.toml"
else
  warn "codex/harness.toml missing — skip Codex harness"
fi
command -v codex >/dev/null 2>&1 || warn "codex CLI not on PATH — harness keys are written but Codex is not installed"

# ---------------------------------------------------------------------------
# 7. Optional: reinstall Cursor extensions from snapshot
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
# 8. Prerequisite check (warn-only; we do not auto-install system packages)
# ---------------------------------------------------------------------------
info "Checking prerequisites ..."
for c in git nvim node npx envsubst jq; do
  command -v "$c" >/dev/null 2>&1 && ok "found $c" || warn "MISSING: $c"
done
command -v opencode >/dev/null 2>&1 && ok "found opencode" || warn "opencode not on PATH — see https://opencode.ai"
command -v cursor   >/dev/null 2>&1 && ok "found cursor CLI" || warn "cursor CLI not on PATH"
command -v claude   >/dev/null 2>&1 && ok "found claude CLI" || warn "claude CLI not on PATH — see https://claude.com/claude-code"
command -v omp      >/dev/null 2>&1 && ok "found omp" || warn "omp not on PATH — install with: curl -fsSL https://omp.sh/install | sh"
command -v herdr    >/dev/null 2>&1 && ok "found herdr" || warn "herdr not on PATH — install with: curl -fsSL https://herdr.dev/install.sh | sh"
command -v iris     >/dev/null 2>&1 && ok "found iris" || warn "iris not on PATH — build the gruvbox one with: ./iris/build.sh"
command -v codex    >/dev/null 2>&1 && ok "found codex" || warn "codex CLI not on PATH"

# ---------------------------------------------------------------------------
# 9. Summary / next steps
# ---------------------------------------------------------------------------
cat <<EOF

$(printf "${c_ok}Bootstrap complete.${c_off}")

Next steps:
  1) Fill in real keys:   \$EDITOR $SECRETS    (gitignored, never pushed)
  2) Re-run ./install.sh  (regenerates Cursor mcp.json with real values)
  3) Open a new shell so secrets.env is sourced (opencode reads {env:...})
  4) Cursor extensions:   ./install.sh --extensions
  5) Cursor will re-fetch the plugins in cursor/dot-cursor/plugins-list.txt on demand.
  6) Claude Code: verify with 'claude mcp list' and 'claude plugin list'
     (~/.claude/{skills,CLAUDE.md} are symlinks into claude/; MCP is registered
     from claude/mcp.json into user scope on each ./install.sh run).
  7) Hermes: ~/.hermes/{SOUL.md,news-topics.txt,scripts} are symlinks, and each
     hermes/skills/<category>/<skill> dir is linked into ~/.hermes/skills/.
     config.yaml and .env were materialized from templates only if absent.
  8) omp: ~/.omp/agent/* are symlinks into omp/ (runtime state stays real).
     Provider is DeepInfra; put your key in DEEPINFRA_API_KEY in secrets.env.
     Install omp itself with: curl -fsSL https://omp.sh/install | sh
  9) herdr: ~/.config/herdr/{config.toml,scripts} are symlinks into herdr/.
     Install herdr with: curl -fsSL https://herdr.dev/install.sh | sh
 10) Codex: ~/.codex/AGENTS.md is a symlink into codex/AGENTS.md. Approval/sandbox
     keys from codex/harness.toml are upserted into ~/.codex/config.toml (the
     live config file is never symlinked).

Backups of anything replaced (if any) are under: $BACKUP_DIR
EOF

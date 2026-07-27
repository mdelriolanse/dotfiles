#!/usr/bin/env bash
#
# verify-offload-merge.sh — read-only assertions for the
# origin/feat/dotfiles-offload -> master merge.
#
# Idempotent and non-mutating: safe to run repeatedly, after Phase 3 and
# again after Phase 5. Group G8 only runs once install.sh has been executed
# (detected via the ~/.omp/agent symlinks); it is skipped otherwise.
#
#     ./agent/tests/verify-offload-merge.sh
#
# Exits non-zero if any assertion fails.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_DIR"

TAG="pre-offload-merge-2026-07-26"

pass=0; fail=0; skip=0
c_ok='\033[0;32m'; c_no='\033[0;31m'; c_sk='\033[0;33m'; c_hd='\033[1;36m'; c_off='\033[0m'

group() { printf "\n${c_hd}%s${c_off}\n" "$*"; }
ok()   { pass=$((pass+1)); printf "  ${c_ok}PASS${c_off} %s\n" "$*"; }
no()   { fail=$((fail+1)); printf "  ${c_no}FAIL${c_off} %s\n" "$*"; }
sk()   { skip=$((skip+1)); printf "  ${c_sk}SKIP${c_off} %s\n" "$*"; }

# check <description> <command...>
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else no "$d"; fi; }
# refute <description> <command...>  — passes when the command FAILS
refute() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then no "$d"; else ok "$d"; fi; }
# count_is <description> <expected> <actual>
count_is() {
  if [ "$2" = "$3" ]; then ok "$1 ($3)"; else no "$1 (expected $2, got $3)"; fi
}

# ---------------------------------------------------------------------------
group "G1. MERGE INTEGRITY"
# ---------------------------------------------------------------------------
check "pre-merge tag $TAG exists" git rev-parse --verify "$TAG"

merge_sha="$(git log --merges --format=%H --grep='dotfiles-offload' -1 2>/dev/null)"
if [ -n "$merge_sha" ]; then
  count_is "merge commit has exactly 2 parents" 3 "$(git rev-list --parents -1 "$merge_sha" | wc -w)"
else
  no "merge commit not found"
fi

refute "no conflict markers in tree" git grep -qE '^(<<<<<<<|>>>>>>>)' -- . ':(exclude)agent/'
count_is "no unmerged paths" 0 "$(git diff --name-only --diff-filter=U | wc -l)"

# ---------------------------------------------------------------------------
group "G2. MASTER WORK PRESERVED (byte-identical vs $TAG)"
# ---------------------------------------------------------------------------
if git rev-parse --verify "$TAG" >/dev/null 2>&1; then
  count_is "kitty/ starship/ bash/ hermes/ unchanged" 0 \
    "$(git diff --name-only "$TAG" -- kitty/ starship/ bash/ hermes/ | wc -l)"
  count_is "master-only nvim files unchanged" 0 \
    "$(git diff --name-only "$TAG" -- \
        nvim/lua/core/theme-toggle.lua nvim/lua/core/autosave.lua \
        nvim/lua/core/lumen-diff.lua nvim/lua/core/keylog.lua \
        nvim/lua/core/buffer-refresh.lua nvim/lua/plugins/drop.lua \
        nvim/lua/plugins/rust.lua nvim/lua/plugins/gruvbox.lua \
        nvim/lua/plugins/autopairs.lua nvim/lua/plugins/snacks.lua | wc -l)"
else
  sk "G2 needs tag $TAG"
fi

check "kitty.conf keeps JetBrainsMono Nerd Font" grep -q 'JetBrainsMono Nerd Font' kitty/kitty.conf
check "kitty.conf keeps background_opacity 0.90" grep -qE '^background_opacity[[:space:]]+0\.90' kitty/kitty.conf

# ---------------------------------------------------------------------------
group "G3. REMOTE WORK ACQUIRED"
# ---------------------------------------------------------------------------
for d in omp claude tmux .serena herdr; do
  check "dir exists: $d/" test -d "$d"
done
for f in .gitmodules opencode/opencode.json opencode/AGENTS.md \
         nvim/lua/plugins/pretty-ts-errors.lua tmux/tmux.conf \
         cursor/dot-cursor/hooks.json; do
  check "file exists: $f" test -f "$f"
done
refute "opencode/opencode.jsonc removed" test -e opencode/opencode.jsonc
refute "nvim/nvim/ nested duplicate removed" test -e nvim/nvim

count_is "claude/skills count"   39 "$(ls -A claude/skills | wc -l)"
count_is "omp/skills count"      39 "$(ls -A omp/skills | wc -l)"
count_is "opencode/skills count" 39 "$(ls -A opencode/skills | wc -l)"
# claude, omp and opencode carry the same skill family; drift means a skill was
# added to one harness and never ported to the others.
for h in claude opencode; do
  if diff -q <(ls omp/skills | sort) <(ls "$h/skills" | sort) >/dev/null 2>&1; then
    ok "skill set parity: omp == $h"
  else
    no "skill set parity: omp != $h ($(diff <(ls omp/skills|sort) <(ls "$h/skills"|sort) | grep -cE '^[<>]') differing)"
  fi
done
# Cursor-specific skills only. deep-review and issue-to-docs were removed from
# here: Cursor reserves ~/.cursor/skills-cursor for its own built-ins and prunes
# the rest, and both are served from ~/.cursor/skills instead.
count_is "skills-cursor count"   20 "$(ls -A cursor/dot-cursor/skills-cursor | wc -l)"
for s in deep-review issue-to-docs best-of-n bg-subagent resolve-review second-opinion; do
  refute "family skill not in Cursor's reserved dir: $s" test -e "cursor/dot-cursor/skills-cursor/$s"
done

# Cursor override layer: skills whose instructions name harness machinery ship a
# Cursor copy that beats the opencode one, which would otherwise tell the agent
# it is running in OpenCode.
for s in adamsreview best-of-n bg-subagent deep-review resolve-review second-opinion skill-catalyst tdd; do
  check "cursor override exists: $s" test -f "cursor/dot-cursor/skills/$s/SKILL.md"
  check "cursor override maps the harness: $s" grep -q '^## Cursor harness' "cursor/dot-cursor/skills/$s/SKILL.md"
  refute "cursor override drops opencode wording: $s" grep -q 'runs in OpenCode' "cursor/dot-cursor/skills/$s/SKILL.md"
done
for s in adamsreview tdd skill-catalyst; do
  check "opencode harness section: $s" grep -q '^## opencode harness' "opencode/skills/$s/SKILL.md"
  check "omp harness section: $s"      grep -q '^## omp harness'      "omp/skills/$s/SKILL.md"
  refute "claude copy is the baseline: $s" grep -q '^## .* harness'   "claude/skills/$s/SKILL.md"
  refute "claude copy free of opencode leakage: $s" grep -qi 'opencode' "claude/skills/$s/SKILL.md"
done
check "link script overlays the cursor tree" grep -q 'link_tree "\$CURSOR_SKILLS"' opencode/scripts/link-cursor-skills.sh
refute "link script never targets the reserved dir" grep -q 'DEST=.*skills-cursor' opencode/scripts/link-cursor-skills.sh
count_is "cursor rules/*.mdc"    15 "$(ls cursor/dot-cursor/rules/*.mdc 2>/dev/null | wc -l)"
count_is "omp ponytail commands"  5 "$(ls omp/commands/ponytail*.md 2>/dev/null | wc -l)"

for s in best-of-n bg-subagent goal inspect issue-to-docs resolve-review second-opinion; do
  check "claude skill from ac61bd2: $s" test -d "claude/skills/$s"
done

# ---------------------------------------------------------------------------
group "G4. HARNESS PRECEDENCE (remote content won)"
# ---------------------------------------------------------------------------
for s in serena codebase-memory semble; do
  check "cursor mcp.json.example has $s" grep -q "$s" cursor/dot-cursor/mcp.json.example
done
for s in composio firecrawl browserbase excalidraw quiverai; do
  refute "cursor mcp.json.example dropped $s" grep -q "$s" cursor/dot-cursor/mcp.json.example
done
if command -v jq >/dev/null 2>&1; then
  # Cursor/VS Code ship JSONC (full-line // comments) for some configs, so
  # strip those before validating. Anything still unparseable is real breakage.
  bad=0
  while IFS= read -r f; do
    sed 's|^[[:space:]]*//.*||' "$f" | jq -e . >/dev/null 2>&1 \
      || { bad=$((bad+1)); printf "       invalid JSON: %s\n" "$f"; }
  done < <(git ls-files '*.json' '*.json.example')
  count_is "all tracked JSON parses" 0 "$bad"
else
  sk "jq not installed — JSON validation"
fi

# ---------------------------------------------------------------------------
group "G5. UNION-MERGE CORRECTNESS"
# ---------------------------------------------------------------------------
for e in 'hermes/config.yaml' 'hermes/.env' 'claude/mcp.json' '__pycache__/' 'excalidraw.log'; do
  check ".gitignore has $e" grep -qxF "$e" .gitignore
done
count_is ".gitignore has exactly one .claude/worktrees/" 1 \
  "$(grep -cxF '.claude/worktrees/' .gitignore)"

for l in '$HOME/.tmux.conf' '$HOME/.claude/settings.json' '$HOME/.claude/skills' \
         '$HOME/.claude/CLAUDE.md' '$HOME/.config/starship.toml' \
         '$HOME/.config/kitty/kitty.conf' '$HOME/.bashrc' '$HOME/.blerc'; do
  check "install.sh links $l" grep -qF "link \"$l\"" install.sh
done
check "install.sh defines hermes_scaffold()" grep -q 'hermes_scaffold()' install.sh
check "install.sh registers claude MCP"      grep -q 'claude mcp add-json' install.sh

# section headers strictly ascending, no duplicates
secs="$(grep -oE '^# [0-9]+[a-c]?\.' install.sh | tr -d '#. ' || true)"
if [ "$secs" = "$(printf '%s\n' "$secs" | sort -V -u)" ]; then
  ok "install.sh sections ascending, no duplicates"
else
  no "install.sh section numbering broken"
fi

for v in DEEPINFRA_API_KEY HERMES_MODEL_API_KEY TELEGRAM_BOT_TOKEN; do
  check "secrets.env.example exports $v" grep -q "export $v=" secrets/secrets.env.example
done
for v in FIRECRAWL_API_KEY LINEAR_API_KEY; do
  refute "secrets.env.example dropped $v" grep -q "$v" secrets/secrets.env.example
done

# ---------------------------------------------------------------------------
group "G5b. OMP WIRING (install.sh section 6b)"
# ---------------------------------------------------------------------------
for i in AGENTS.md config.yml models.yml mcp.json lsp.json extensions skills; do
  check "install.sh links ~/.omp/agent/$i" grep -qF "\$OMP_AGENT/$i" install.sh
done
refute "install.sh does NOT whole-dir link ~/.omp" grep -qE 'link "\$HOME/\.omp"|link "\$OMP_AGENT"' install.sh
refute "omp/mcp.json NOT gitignored" grep -q 'omp/mcp.json' .gitignore
check  "omp/mcp.json is tracked" git ls-files --error-unmatch omp/mcp.json
check  "omp/mcp.json uses bare GITHUB_TOKEN name" grep -q '"GITHUB_TOKEN": *"GITHUB_TOKEN"' omp/mcp.json
# omp resolves credentials by env-var NAME; a real key must never land here.
check  "omp/models.yml references the key by name only" grep -q '^ *apiKey: DEEPINFRA_API_KEY$' omp/models.yml
refute "omp/models.yml holds no literal secret" grep -qE 'apiKey: *[A-Za-z0-9]{24,}' omp/models.yml
check  "omp default model is set and concrete" grep -q '^  default: deepinfra/' omp/config.yml
refute "omp config has no leftover <provider> placeholders" grep -q '<provider' omp/config.yml omp/models.yml

# ---------------------------------------------------------------------------
group "G5c. CLAUDE SKILLS PRECEDENCE (remote-only)"
# ---------------------------------------------------------------------------
for s in architect debugger explainer ponderer surveyor tdd-pipeline-orchestrator; do
  refute "local-only skill NOT committed: $s" git ls-files --error-unmatch "claude/skills/$s"
done

# ---------------------------------------------------------------------------
group "G5d. KIMI REMOVED (Phase 3g)"
# ---------------------------------------------------------------------------
refute "kimi/ directory absent" test -e kimi
count_is "no kimi/ files tracked" 0 "$(git ls-files kimi/ | wc -l)"
refute ".gitignore has no kimi/config.toml" grep -q 'kimi/config.toml' .gitignore
refute "install.sh has no KIMI block" grep -qi 'KIMI' install.sh
refute "secrets.env.example header drops kimi" grep -qi 'kimi' secrets/secrets.env.example
# omp was since repointed at DeepInfra, so its credential slot is the concrete
# DEEPINFRA_API_KEY rather than the scrub's generic PROVIDER_API_KEY.
check  "secrets.env.example exports DEEPINFRA_API_KEY" grep -q 'export DEEPINFRA_API_KEY=' secrets/secrets.env.example
# KEEP bucket — the model and the prose must survive the CLI deletion
check "opencode.json keeps Kimi-K2.6 model" grep -q 'nvidia-kimi-k2-6-nvfp4' opencode/opencode.json
check "omp/models.yml still defines a Kimi model" grep -qi 'Kimi-K2' omp/models.yml
for f in claude/CLAUDE.md cursor/dot-cursor/USER_RULES.md omp/AGENTS.md \
         cursor/dot-cursor/rules/chinese-model-english.mdc \
         opencode/instructions/chinese-model-english.md; do
  check "chinese-model-english prose intact: $f" grep -qi 'kimi' "$f"
done

# ---------------------------------------------------------------------------
group "G5e. HERDR WIRING (install.sh section 6c)"
# ---------------------------------------------------------------------------
for f in herdr/config.toml herdr/scroll.sh herdr/scripts/rename-agent.sh; do
  check "tracked: $f" git ls-files --error-unmatch "$f"
done
check "install.sh links ~/.config/herdr/config.toml" grep -qF 'link "$HOME/.config/herdr/config.toml"' install.sh
check "install.sh links ~/.config/herdr/scripts"     grep -qF 'link "$HOME/.config/herdr/scripts"' install.sh
refute "install.sh does NOT whole-dir link ~/.config/herdr" grep -qE 'link "\$HOME/\.config/herdr"' install.sh
refute "agent-state plugins not separately linked" grep -qE 'herdr-omp-agent-state|herdr-agent-state' install.sh
check "tracked: omp/extensions/herdr-omp-agent-state.ts" git ls-files --error-unmatch omp/extensions/herdr-omp-agent-state.ts
check "tracked: opencode/plugins/herdr-agent-state.js"   git ls-files --error-unmatch opencode/plugins/herdr-agent-state.js
check "herdr in prereq check" grep -q 'command -v herdr' install.sh

# ---------------------------------------------------------------------------
group "G5f. MCP ROSTER (graphify is a CLI, never an MCP)"
# ---------------------------------------------------------------------------
for f in cursor/dot-cursor/mcp.json.example claude/mcp.json.example omp/mcp.json opencode/opencode.json; do
  refute "no graphify MCP entry in $f" grep -q 'graphify' "$f"
done
check "omp/AGENTS.md keeps the graphify runbook" grep -q 'GRAPHIFY_START' omp/AGENTS.md
# 592 as the remote shipped it, minus the 32 lines of codegraph guidance purged.
count_is "USER_RULES.md is the rewritten version" 560 "$(wc -l < cursor/dot-cursor/USER_RULES.md)"

# ---------------------------------------------------------------------------
group "G6. NVIM RESOLUTION (C4 hybrid / C5)"
# ---------------------------------------------------------------------------
check "init.lua sets vim.g.have_nerd_font" grep -q 'vim.g.have_nerd_font' nvim/init.lua
nf_line="$(grep -n 'vim.g.have_nerd_font' nvim/init.lua | head -1 | cut -d: -f1)"
lz_line="$(grep -n "require('lazy').setup" nvim/init.lua | head -1 | cut -d: -f1)"
if [ -n "$nf_line" ] && [ -n "$lz_line" ] && [ "$nf_line" -lt "$lz_line" ]; then
  ok "nerd-font detect precedes lazy.setup ($nf_line < $lz_line)"
else
  no "nerd-font detect must precede lazy.setup (got $nf_line vs $lz_line)"
fi
check "init.lua keeps the keylog wiring" grep -q 'NVIM_KEYLOG' nvim/init.lua
refute "options.lua no longer hardcodes have_nerd_font" grep -q 'vim.g.have_nerd_font = true' nvim/lua/core/options.lua
check "lualine gates icons on nerd font" grep -q 'icons_enabled = vim.g.have_nerd_font ~= false' nvim/lua/plugins/lualine.lua
refute "lualine keeps glyphs, not ASCII diff symbols" grep -qE "added = '\+'" nvim/lua/plugins/lualine.lua
check "lualine keeps the theme-toggle hook" grep -q 'active_theme' nvim/lua/plugins/lualine.lua
refute "C5: <C-j>/<C-k> TmuxNavigate removed" grep -qE 'TmuxNavigateDown|TmuxNavigateUp' nvim/lua/core/keymaps.lua
check  "C5: TmuxNavigateLeft/Right kept" grep -q 'TmuxNavigateLeft' nvim/lua/core/keymaps.lua
for t in xclip pretty-ts-errors lumen; do
  check "keymaps.lua has $t" grep -qi -- "$t" nvim/lua/core/keymaps.lua
done
check "cmp-config has the ASCII fallback table" grep -q '\[T\]' nvim/lua/plugins/cmp-config.lua

if command -v nvim >/dev/null 2>&1; then
  bad="$(nvim --headless -c 'lua
    local n = 0
    for _, f in ipairs(vim.fn.split(vim.fn.glob("nvim/**/*.lua"), "\n")) do
      if not loadfile(f) then n = n + 1 end
    end
    io.stderr:write(tostring(n))
  ' -c qa 2>&1 | tail -1)"
  count_is "all nvim lua files parse" 0 "$bad"
else
  sk "nvim not installed — lua parse check"
fi

# ---------------------------------------------------------------------------
group "G7. HYGIENE"
# ---------------------------------------------------------------------------
for s in install.sh opencode/scripts/*.sh herdr/scroll.sh herdr/scripts/*.sh; do
  [ -f "$s" ] || continue
  check "bash -n $s" bash -n "$s"
done
# Placeholder runs (xxxx…, YOUR_…, <…>, ####) are expected inside *.example
# templates, so strip those before deciding a match is a real credential.
cred_hits="$(git grep -nIE '(sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xoxb-[A-Za-z0-9-]{20,}|AIza[A-Za-z0-9_-]{30,})' -- . ':(exclude)agent/' 2>/dev/null \
  | grep -vEi '(x{8,}|y{8,}|0{8,}|1234567890|YOUR_|REPLACE|EXAMPLE|PLACEHOLDER|<[A-Za-z_]+>)' || true)"
if [ -z "$cred_hits" ]; then
  ok "no live-looking credentials tracked"
else
  no "possible live credentials tracked:"
  printf '%s\n' "$cred_hits" | sed 's/^/         /'
fi
for f in kimi/config.toml claude/mcp.json cursor/dot-cursor/mcp.json \
         hermes/config.yaml hermes/.env secrets/secrets.env; do
  refute "not tracked: $f" git ls-files --error-unmatch "$f"
done

# ---------------------------------------------------------------------------
group "G8. POST-INSTALL (skipped until install.sh has run)"
# ---------------------------------------------------------------------------
if [ -L "$HOME/.omp/agent/AGENTS.md" ]; then
  linked_to() { [ "$(readlink -f "$1" 2>/dev/null)" = "$(readlink -f "$2" 2>/dev/null)" ]; }
  check "~/.claude/skills -> repo"           linked_to "$HOME/.claude/skills" "$REPO_DIR/claude/skills"
  check "~/.tmux.conf -> repo"               linked_to "$HOME/.tmux.conf" "$REPO_DIR/tmux/tmux.conf"
  check "~/.config/kitty/kitty.conf -> repo" linked_to "$HOME/.config/kitty/kitty.conf" "$REPO_DIR/kitty/kitty.conf"
  check "~/.config/starship.toml -> repo"    linked_to "$HOME/.config/starship.toml" "$REPO_DIR/starship/starship.toml"
  for i in AGENTS.md config.yml models.yml mcp.json lsp.json extensions skills; do
    check "~/.omp/agent/$i -> repo" linked_to "$HOME/.omp/agent/$i" "$REPO_DIR/omp/$i"
  done
  check  "~/.omp/agent is a real directory" test -d "$HOME/.omp/agent"
  refute "~/.omp/agent is NOT a symlink"    test -L "$HOME/.omp/agent"
  for i in config.toml scripts; do
    check "~/.config/herdr/$i -> repo" linked_to "$HOME/.config/herdr/$i" "$REPO_DIR/herdr/$i"
  done
  refute "~/.config/herdr is NOT a symlink" test -L "$HOME/.config/herdr"
  count_is "no dangling skill symlinks" 0 \
    "$(find -L "$HOME/.claude/skills" "$HOME/.cursor/skills" "$HOME/.cursor/skills-cursor" "$HOME/.omp/agent" -type l 2>/dev/null | wc -l)"
  # Cursor sees the whole skill family, with the 5 adapted ones overridden.
  if diff -q <(ls -A opencode/skills | sort) <(ls -A "$HOME/.cursor/skills" | sort) >/dev/null 2>&1; then
    ok "~/.cursor/skills carries the full skill family"
  else
    no "~/.cursor/skills is missing family skills (run link-cursor-skills.sh)"
  fi
  for s in adamsreview best-of-n bg-subagent deep-review resolve-review second-opinion skill-catalyst tdd; do
    check "~/.cursor/skills/$s resolves to the cursor override" \
      [ "$(readlink -f "$HOME/.cursor/skills/$s")" = "$REPO_DIR/cursor/dot-cursor/skills/$s" ]
  done
  check "ponytail submodule populated" test -f opencode/ponytail/.claude-plugin/marketplace.json
else
  sk "install.sh has not run yet (no ~/.omp/agent symlinks)"
fi

# ---------------------------------------------------------------------------
group "G9. CONFIGURED APPS ARE ACTUALLY INSTALLED"
# ---------------------------------------------------------------------------
# Every app this repo configures should exist on the machine, otherwise the
# symlinks are inert. Checked against PATH plus the two user-local bin dirs
# that omp (bun) and herdr/serena (~/.local/bin) install into.
have() { command -v "$1" >/dev/null 2>&1 || [ -x "$HOME/.local/bin/$1" ] || [ -x "$HOME/.bun/bin/$1" ]; }
for app in nvim tmux kitty starship opencode cursor claude omp herdr jq node envsubst git; do
  check "installed: $app" have "$app"
done
# MCP backends are separate binaries the configs invoke by name.
for b in serena codebase-memory-mcp agentmemory-mcp uvx; do
  check "MCP backend installed: $b" have "$b"
done
# codegraph was purged: no public package provides it, so a registered server
# could never connect. Guard against it creeping back into any config or doc.
for f in claude/mcp.json.example omp/mcp.json cursor/dot-cursor/mcp.json.example opencode/opencode.json; do
  refute "no codegraph server in $f" grep -q 'codegraph' "$f"
done
count_is "no codegraph references anywhere" 0 \
  "$(git grep -lic 'codegraph' -- . ':(exclude)agent/' ':(exclude)README.md' | wc -l)"

# ---------------------------------------------------------------------------
printf "\n${c_hd}RESULT${c_off}  ${c_ok}%d passed${c_off}  ${c_no}%d failed${c_off}  ${c_sk}%d skipped${c_off}\n" \
  "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]

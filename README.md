# dotfiles

Centralized configuration for **Neovim**, **opencode**, **Cursor**, **Claude
Code**, **omp**, **Codex**, **Hermes**, **tmux**, **herdr**, **Ghostty**,
**kitty**, **starship**, **iris**, and **bash**. `install.sh` replaces the
usual paths (`~/.config/nvim`, `~/.bashrc`, …) with symlinks into this
repo — there is no second copy.

## Quickstart

```bash
# 1. Clone
git clone https://github.com/mdelriolanse/dotfiles.git ~/dotfiles
cd ~/dotfiles

# 2. Link everything (idempotent; backs up anything it would overwrite)
./install.sh

# 3. Add your secrets (install.sh created secrets.env from the example)
$EDITOR secrets/secrets.env          # paste real API keys — file is gitignored

# 4. Re-run to materialize Cursor's mcp.json from your keys, then reload shell
./install.sh
exec $SHELL

# 5. (optional) reinstall the same Cursor extensions
./install.sh --extensions
```

That's it — Neovim, opencode, and Cursor now read their config straight from
this repo via symlinks. `secrets/secrets.env.example` lists every key you need.

`install.sh` is idempotent and backs up anything it would overwrite to
`~/.dotfiles-backup-<timestamp>/`. It does **not** install the apps themselves
(nvim, opencode, Cursor, node) — it warns if they're missing.

## Layout

```
nvim/                    -> ~/.config/nvim            (whole dir)
opencode/                -> ~/.config/opencode        (whole dir; node_modules ignored)
bash/bashrc              -> ~/.bashrc
bash/blerc               -> ~/.blerc
starship/starship.toml   -> ~/.config/starship.toml
kitty/kitty.conf         -> ~/.config/kitty/kitty.conf
ghostty/config.ghostty   -> ~/.config/ghostty/config.ghostty
ghostty/tabs.css         -> ~/.config/ghostty/tabs.css
cursor/User/*            -> ~/.config/Cursor/User/*    (settings, keybindings, snippets)
cursor/dot-cursor/*      -> ~/.cursor/*                (argv, cli-config,
                                                        skills-cursor, USER_RULES,
                                                        mcp.json)
cursor/dot-cursor/skills/  overlaid -> ~/.cursor/skills  (Cursor-adapted copies of
                                                        the skills that need one;
                                                        see Derived / excluded)
claude/settings.json     -> ~/.claude/settings.json    (individual items only —
claude/skills/           -> ~/.claude/skills            ~/.claude holds runtime
claude/CLAUDE.md         -> ~/.claude/CLAUDE.md         state, never whole-dir)
claude/agents/           -> ~/.claude/agents
claude/mcp.json.example  materialized -> claude/mcp.json (gitignored), then
                         registered into Claude's user scope by install.sh
omp/*                    -> ~/.omp/agent/*             (7 individual items;
                                                        agent.db, sessions/ and
                                                        history.db stay real)
tmux/tmux.conf           -> ~/.tmux.conf               (ctrl+hjkl pane nav)
iris/config.toml         -> ~/.config/iris/config.toml  (IRIS completion menu;
iris/gruvbox.sed + build.sh  palette patch — upstream has no theme option)
herdr/config.toml        -> ~/.config/herdr/config.toml
herdr/scripts/           -> ~/.config/herdr/scripts
codex/AGENTS.md          -> ~/.codex/AGENTS.md         (global user instructions;
                                                        not model_instructions_file)
codex/harness.toml       upserted -> ~/.codex/config.toml  (approval/sandbox
                                                        keys only; never
                                                        symlink the live
                                                        file — Codex rewrites
                                                        it and it holds
                                                        secrets)
hermes/SOUL.md           -> ~/.hermes/SOUL.md          (persona / system prompt)
hermes/news-topics.txt   -> ~/.hermes/news-topics.txt  (digest topics)
hermes/config.yaml.example  scaffolded -> ~/.hermes/config.yaml  (gitignored real)
hermes/.env.example         scaffolded -> ~/.hermes/.env         (gitignored real)
secrets/secrets.env      (gitignored) real keys; sourced by ~/.bashrc
install.sh               symlink + bootstrap script
```

### Hermes agent (`~/.hermes`)

Only **preferences** are centralized — never memory or runtime state. `SOUL.md`
and `news-topics.txt` are symlinked (edit-here == edit-live). Cron scripts are
machine-local (gitignored; `install.sh` links `~/.hermes/scripts` only if that
directory exists next to the repo).
`config.yaml` and `.env` mix preferences with secrets **and** are rewritten by
Hermes at runtime, so they are not symlinked: `install.sh` materializes them from
`config.yaml.example` / `.env.example` + `secrets.env` (via `envsubst`) **only if
absent** — it never clobbers a live config. Secret values (`HERMES_MODEL_API_KEY`,
`AGENTMEMORY_SECRET`, `TELEGRAM_*`) live in `secrets.env`; the tracked templates
carry `${VAR}` placeholders / blanks. The `agentmemory` MCP entry uses
`agentmemory-mcp` on `PATH`.

Deliberately **excluded** (memory, state, caches, creds, binaries, the app
checkout): `memories/`, `sessions/`, `state.db*`, `kanban*`, `cron/`, `auth.json`,
all `*cache*` / `logs/`, `bin/`, `hermes-agent/`, and the bundled `skills/`
tree (re-provisioned by Hermes itself). User skills are the exception:
`hermes/skills/<category>/<skill>/` is the canonical copy, and `install.sh`
symlinks each skill directory into `~/.hermes/skills/<category>/`. Hermes
discovers them by scanning `~/.hermes/skills/` for `SKILL.md` (category
subdirectory plus `name` / `description` frontmatter).

### Codex CLI (`~/.codex`)

Global user instructions live in `codex/AGENTS.md`, symlinked to
`~/.codex/AGENTS.md`. Codex reads that file (or `AGENTS.override.md` if it
exists and is non-empty) on every run and injects it as user instructions.
Do not point `model_instructions_file` at it — that key replaces Codex's
built-in base instructions.

`codex/harness.toml` holds `approval_policy` + `sandbox_mode` (Cursor
unrestricted / sandbox-off, expressed in Codex keys). `install.sh` upserts
those two top-level keys into the live `~/.codex/config.toml`. The live file
is **never** symlinked: Codex rewrites it (plugins, marketplaces,
`[hooks.state]`, desktop) and it holds MCP secrets. Do not commit
`~/.codex/config.toml`. Do not mix `sandbox_mode` with `default_permissions`
— they do not compose. Codex has no skills tree in this repo.

## Secrets & MCP keys

No API keys are committed. They live only in `secrets/secrets.env` (gitignored)
and are consumed two ways:

- **opencode** resolves `{env:VAR}` from the shell environment at runtime, so
  `secrets.env` (sourced by `~/.bashrc`) is enough — `opencode/opencode.json`
  is committed verbatim with `{env:...}` references.
- **omp** resolves credentials by bare env-var name, so `omp/mcp.json` is
  committed as-is and symlinked — nothing is ever materialized into it.
- **Cursor** does not reliably expand `${VAR}` in `mcp.json`, so the real
  `cursor/dot-cursor/mcp.json` is **gitignored** and `install.sh` regenerates it
  from `mcp.json.example` + `secrets.env` (via `envsubst`). Only the redacted
  `mcp.json.example` is committed.

## Derived / excluded (regenerated, not committed)

- `~/.cursor/skills/` — Cursor's **personal** skills dir, regenerated by
  `opencode/scripts/link-cursor-skills.sh` (run automatically by `install.sh`).
  Two passes: `opencode/skills/` is the base, then `cursor/dot-cursor/skills/`
  is overlaid on top, so a skill in both wins from the Cursor tree.

  Skills are written for Claude Code and carry a `## <harness> harness` mapping
  table for every other harness. Only the five that name harness machinery
  (`best-of-n`, `bg-subagent`, `deep-review`, `resolve-review`,
  `second-opinion`) need a Cursor copy — the opencode copy of those tells the
  agent it is running in OpenCode and to shell out to `opencode run`, which is
  wrong in Cursor. The other 34 are harness-neutral and link straight through.
  Add a Cursor copy only when a skill genuinely diverges; every fork is a file
  that will drift from its Claude original.
- `~/.cursor/plugins/` — ~114M plugin cache; the list is captured in
  `cursor/dot-cursor/plugins-list.txt` and Cursor re-fetches on demand.
- Cursor `extensions/` — captured in `cursor/dot-cursor/extensions-list.txt`;
  reinstall with `./install.sh --extensions`.
- `~/.cursor/plans/` — project-specific agent plans; intentionally **not**
  centralized (stays local-only) to keep work context out of this repo.
- Heavy state (`globalStorage/`, `History/`, `workspaceStorage/`, caches,
  `projects/` transcripts, `worktrees/`) is never centralized.

## Notes

- opencode auth lives in `~/.local/share/opencode/` (not in this repo).
- `opencode/ponytail` is a git submodule — run
  `git submodule update --init --recursive` after cloning, or `install.sh`
  will skip the ponytail Claude Code plugin.
- `install.sh` needs `jq` to register MCP servers into Claude Code's user
  scope; without it that step is skipped with a warning.
- `install.sh` links config but does **not** install the apps. Two of them are
  not in any distro repo:

  ```bash
  curl -fsSL https://omp.sh/install | sh        # omp (oh-my-pi) -> ~/.bun/bin
  curl -fsSL https://herdr.dev/install.sh | sh  # herdr          -> ~/.local/bin
  ```

  omp routes through DeepInfra — set `DEEPINFRA_API_KEY` in `secrets.env`.
  Validate herdr's config with `herdr config check`, and confirm the omp and
  opencode agent-state plugins are recognized with `herdr integration status`.

- The MCP configs invoke backends **by binary name**, so they must be on PATH
  or the server just fails to connect. `context7` is HTTP and `fetch`,
  `github` and `semble` are fetched on demand by `npx`/`uvx`; the rest need
  installing:

  ```bash
  uv tool install -p 3.13 serena-agent      # -> serena
  npm i -g codebase-memory-mcp              # -> codebase-memory-mcp
  npm i -g @agentmemory/mcp                 # -> agentmemory-mcp (the npx shim
                                            #    re-execs this name from PATH)
  ```

  `codebase-memory` is configured at `${HOME}/.local/bin/codebase-memory-mcp`,
  so symlink it there if npm puts it elsewhere. `agentmemory` additionally
  needs its server on `AGENTMEMORY_URL` (default `http://localhost:3111`).

  **`codegraph` has been removed.** It used to be registered in every
  `mcp.json` and documented as the primary code-discovery backend, but no
  public package provides it — the `codegraph` names on npm and PyPI are
  unrelated projects, the npm one being an empty 2024 placeholder with no
  `bin`. Rather than ship a server that could never connect and guidance that
  told agents to reach for it first, both are gone. Semble covers the
  natural-language queries it used to answer. Do not re-add it from npm or
  PyPI; those are not the same tool.

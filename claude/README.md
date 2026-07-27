# Claude Code config

Claude Code (`~/.claude/`) has its **own committed config** in this directory,
migrated from the opencode setup but standalone (edit here; drift from opencode is
expected). `install.sh` symlinks the pure-config pieces into `~/.claude/` and
registers the parts that need the `claude` CLI. `~/.claude/` itself is never
symlinked as a whole — it holds runtime state — so only individual items are linked.

## What lives here (committed)

- `settings.json` → symlinked to `~/.claude/settings.json`. Theme/model plus
  `permissions.defaultMode: bypassPermissions` (parity with opencode
  `permission: "allow"` / Cursor `approvalMode: "unrestricted"`).
- `skills/` → symlinked to `~/.claude/skills`. 31 skills copied from
  `opencode/skills` (each a Claude-native `SKILL.md`). Standalone copies — the
  opencode originals are no longer the source of truth for Claude.
- `CLAUDE.md` → symlinked to `~/.claude/CLAUDE.md`. Concatenation of
  `opencode/AGENTS.md` + `opencode/instructions/*.md` at migration time.
- `mcp.json.example` → template for the 8 MCP servers (context7, agentmemory,
  fetch, github, codebase-memory, serena, semble), converted to
  Claude's schema. Secrets are `${VAR}` placeholders.

## What `install.sh` derives (not committed)

- **`claude/mcp.json`** — materialized from `mcp.json.example` via `envsubst`
  (fills `${GITHUB_TOKEN}` from the sourced `secrets.env`). Gitignored, since it
  holds a live token. Empty keys are written as stubs so bootstrap never blocks.
- **MCP registration** — each server in `claude/mcp.json` is registered into
  Claude's **user scope** via `claude mcp add-json`/`claude mcp add`. User-scope
  MCP lives inside `~/.claude.json` (heavy runtime state), so it is registered
  through the CLI rather than symlinked — this makes the servers available in
  every directory. remove-then-add keeps it idempotent.
- **ponytail** — installed as a native Claude Code plugin from
  `opencode/ponytail/.claude-plugin` (its commands, hooks, and mode skills).
  ponytail is a git submodule, so it stays referenced in place rather than copied.

## Updating

- **Skills / CLAUDE.md**: edit the files under `claude/` directly (they are the
  source of truth for Claude now). To re-pull from opencode, re-copy
  `opencode/skills` → `claude/skills` and re-concatenate the instructions.
- **MCP servers**: edit `mcp.json.example`, delete `claude/mcp.json`, re-run
  `./install.sh` to re-materialize and re-register.

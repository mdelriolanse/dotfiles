# Claude Code config

Claude Code (`~/.claude/`) reuses **opencode as the single source of truth** — the
same skills, rules, and MCP backends that drive opencode and Cursor. `install.sh`
wires everything up; this directory holds only the Claude-specific glue that has no
opencode equivalent.

## What lives here (committed)

- `settings.json` → symlinked to `~/.claude/settings.json`. Theme/model plus
  `permissions.defaultMode: bypassPermissions` (parity with opencode
  `permission: "allow"` / Cursor `approvalMode: "unrestricted"`).

## What `install.sh` derives (not committed)

- **Skills** — `opencode/scripts/link-skills.sh` symlinks every `opencode/skills/*`
  into `~/.claude/skills/` (same set as opencode/Cursor).
- **`~/.claude/CLAUDE.md`** — generated as a manifest of `@`-imports pointing at
  `~/.config/opencode/AGENTS.md` + `~/.config/opencode/instructions/*.md`. Content
  stays in opencode; edits there flow through. Re-run `install.sh` after adding or
  removing instruction files.
- **MCP servers** — registered into Claude's user scope from the same materialized
  server list used for Cursor (`cursor/dot-cursor/mcp.json`), via `claude mcp add`.
- **ponytail** — installed as a native Claude Code plugin from
  `opencode/ponytail/.claude-plugin` (its commands, hooks, and mode skills).

Everything is idempotent and content-agnostic: the derived steps read whatever
instructions / MCP servers / skills exist at install time, so this stays correct as
the opencode source evolves.

---
name: obsidian-vault
description: Search, create, and edit notes in the Obsidian vault with wikilinks and index notes. Use when the user wants to find, create, or organize notes in Obsidian.
version: 1.0.0
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [Obsidian, Notes, Markdown, Vault, Wikilinks]
    category: note-taking
---

# Obsidian Vault

Filesystem-first vault work: read, list, search, create, append, edit, and wikilink notes.

## Vault path

Known vault: `/home/mdelrio/Documents/Obsidian Vault/`.

If that path is missing, use `OBSIDIAN_VAULT_PATH` from `${HERMES_HOME:-~/.hermes}/.env`. If unset, use `~/Documents/Obsidian Vault`.

File tools do not expand shell variables. Do not pass paths containing `$OBSIDIAN_VAULT_PATH` to `read_file`, `write_file`, `patch`, or `search_files`; resolve the vault path first and pass a concrete absolute path. Vault paths may contain spaces, which is another reason to prefer file tools over shell commands.

If the vault path is unknown, `terminal` is acceptable for resolving `OBSIDIAN_VAULT_PATH` or checking whether the fallback path exists. Once the path is known, switch back to file tools.

## Naming conventions

- **Index notes**: aggregate related topics (e.g., `INDEX.md`, `Skills Index.md`)
- **Title case** for all note names
- No folders for organization — use links and index notes instead

## Linking

- Use Obsidian `[[wikilinks]]` syntax: `[[Note Title]]`
- Notes link to dependencies/related notes at the bottom
- Index notes are just lists of `[[wikilinks]]`

## Read a note

Use `read_file` with the resolved absolute path to the note. Prefer this over `cat` because it provides line numbers and pagination.

## List notes

Use `search_files` with `target: "files"` and the resolved vault path. Prefer this over `find` or `ls`.

- To list all markdown notes, use `pattern: "*.md"` under the vault path.
- To list a subfolder, search under that subfolder's absolute path.

## Search

Use `search_files` for both filename and content searches. Prefer this over `grep`, `find`, or `ls`.

- For filenames, use `search_files` with `target: "files"` and a filename `pattern`.
- For note contents, use `search_files` with `target: "content"`, the content regex as `pattern`, and `file_glob: "*.md"` when you want to restrict matches to markdown notes.

Search for `[[Note Title]]` across the vault to find backlinks.

## Create a note

Use `write_file` with the resolved absolute path and the full markdown content. Prefer this over shell heredocs or `echo`.

1. Use **Title Case** for the filename
2. Write content as a unit of learning (per vault rules)
3. Add `[[wikilinks]]` to related notes at the bottom
4. If part of a numbered sequence, use the hierarchical numbering scheme

## Append to a note

Prefer a native file-tool workflow when it is not awkward:

- Read the target note with `read_file`.
- Use `patch` for an anchored append when there is stable context, such as adding a section after an existing heading or appending before a known trailing block.
- Use `write_file` when rewriting the whole note is clearer than constructing a fragile patch.

For an anchored append with `patch`, replace the anchor with the anchor plus the new content.

For a simple append with no stable context, `terminal` is acceptable if it is the clearest safe option.

## Targeted edits

Use `patch` for focused note changes when the current content gives you stable context. Prefer this over shell text rewriting.

## Find index notes

Use `search_files` with `target: "files"`, the resolved vault path, and `pattern: "*Index*"`.

## UI Configuration

### Show Hidden Files (Dotfiles) in File Tree Sidebar

To display hidden files and directories (those prefixed with a dot, like `.git`, `.env`, `.obsidian`) in Obsidian's file tree sidebar:

1. Edit `/home/mdelrio/Documents/Obsidian Vault/.obsidian/workspace.json`
2. Add `"showHiddenFiles": true` to the file-explorer state configuration
3. Example configuration:
```json
{
  "type": "file-explorer",
  "state": {
    "sortOrder": "alphabetical",
    "autoReveal": false,
    "showSearch": false,
    "showHiddenFiles": true,
    "searchQuery": ""
  }
}
```

After restarting Obsidian (or refreshing the sidebar), dotfiles will appear alongside regular files and directories.

**Related:** The global setting can also be set in `/home/mdelrio/Documents/Obsidian Vault/.obsidian/app.json` which already contained `"showHiddenFiles": true`.

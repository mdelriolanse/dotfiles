# MCP-First Hard Rule

## YOU HAVE MCP TOOLS — USE THEM BEFORE GREP

Before any grep/glob/Read for code discovery, you MUST call one of these:

1. **semble_search** — for natural-language code search ("where is auth handled?"), "how does X work", tracing flows
2. **Serena find_symbol / find_referencing_symbols** — for symbol lookup and references
3. **codebase-memory search_graph / trace_path** — for structured graph queries

## RULE

- **code first → grep NEVER** for anything involving functions, classes, imports, call chains, or architecture
- grep/glob are ONLY for: string literals in code, config values, non-code files (Dockerfiles, YAML, markdown)
- If you reach for grep to find a function definition, a class, or an import — STOP. Call an MCP tool instead.
- These tools cost fewer tokens and give better results. There is no reason to grep first.

## WHEN YOU NEED CODE

| Task | Tool |
|---|---|
| "How does X work?" | semble_search |
| "Where is X done?" | semble_search |
| "Find class/function" | Serena find_symbol |
| "Who calls this?" | Serena find_referencing_symbols |
| "Rename/move/delete" | Serena rename_symbol / safe_delete_symbol |
| "Complex graph query" | codebase-memory search_graph |

**DO NOT use grep for any of the above.**

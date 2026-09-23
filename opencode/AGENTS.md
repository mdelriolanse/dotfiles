
# Lookup

Two stores. Use them before grep.

**Agent memory** for anything already decided or discussed. `memory_smart_search`, then `memory_recall`. If a memory is current, answer from it. If it is stale or contradicts the repo, say so and check the code.

**codebase-memory** for the code. `search_graph`, `trace_path`, `get_code_snippet`, `get_architecture`. Read `CONTEXT.md` and `docs/adr/` when they exist. Grep only for literals, config, non-code files, or after both miss.

After a real finding, save one memory if it is an architecture decision, a bug root-cause, a schema or API change, a workflow, or a pattern. Search first and update the existing memory instead of adding a duplicate. Include why and the file path. Do not save transient debugging. Delete a memory when a refactor makes it false.

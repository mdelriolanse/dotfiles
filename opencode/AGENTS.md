<!-- codebase-memory-mcp:start -->
# Codebase Knowledge Graph — Three-Backend Policy

This project has THREE complementary code-intelligence backends. Pick the right one for the task.
**ALWAYS prefer these MCP backends over grep/glob/file-search for code discovery.**
These tools are purpose-built to understand code structure, relationships, and semantics.
Resort to grep/glob ONLY when every backend fails or for non-code files.


## 1. Semble (semantic code search — reach for this for "find where X is done" queries)

When you need to **find code by natural-language description** or **find similar code** to a known location, use Semble. Semantic (embedding + BM25) search retrieves relevant code snippets using ~98% fewer tokens than grep+read. CPU-only, no API keys.

- **Two tools**: `semble_search` (natural-language query → code chunks) and `semble_find_related` (find similar code at a location)
- **Best for**:
  - "Where is authentication handled?", "how do we save models?" — vague natural-language queries where you don't know the exact symbol names
  - Finding related code at a specific line — "find code similar to this error handling pattern"
- **Parser**: Tree-sitter chunking + Model2Vec embeddings + BM25 lexical matching
- **When to use**: Before grep, when the query is descriptive or fuzzy. Also useful for finding patterns across languages or when you only have a partial description.
- **Setup**: None. Indexes on first search, caches automatically, watches for file changes.

## 2. Serena (symbol-level IDE operations — use when editing or refactoring)

When **refactoring code** or needing **language-server precision** (cross-file renames, safe deletes, diagnostics, type navigation), use Serena first.

- **Best for**:
  - `rename_symbol` — safe cross-file renames (language server guarantees references updated)
  - `replace_symbol_body` — replace an entire function/class definition atomically
  - `insert_before_symbol` / `insert_after_symbol` — inject code at semantic boundaries
  - `safe_delete_symbol` — delete a symbol after checking for remaining usages
  - `find_declaration` / `find_implementations` / `find_referencing_symbols` — go-to-definition / find-references
  - `get_diagnostics_for_file` / `get_diagnostics_for_symbol` — type errors, warnings
  - `get_symbols_overview` — get top-level symbols in a file (faster than full read for navigation)
- **Parser**: Language servers (LSP), fully type-aware
- **When to use**: Whenever correctness across files matters. Serena prevents text-level errors that grep-based edits miss.
- **Setup**: `serena init` (done once globally). Auto-activates the project from cwd — no per-repo setup needed.

## 3. codebase-memory (specialised — use when Semble + Serena are insufficient)

Keep this as the **fallback / detail** backend for scenarios none of the others cover.

- **Granular multi-tool**: `search_graph`, `trace_path`, `get_code_snippet`, `query_graph`, `get_architecture`
- **Best for**:
  - Complexity analysis (`query_graph` with `cyclomatic`, `transitive_loop_depth`, `linear_scan_in_loop`)
  - Cypher graph queries (`query_graph`) for complex multi-hop patterns
  - ADR management (`manage_adr`)
  - Runtime trace ingestion (`ingest_traces`) — seeing actual execution paths
  - Cross-repo intelligence mode (`index_repository` with `cross-repo-intelligence`)
  - Engineering metrics (bottleneck detection, dead-code analysis via graph queries)
- **Parser**: LSP-style type-aware resolution
- **When to use**: When Semble and Serena return nothing, or when the task specifically needs complexity props, ADRs, traces, or custom Cypher

## Decision Flow

```
Need to understand code / architecture / call chain, have a vague
natural-language query ("where is auth done?"), or need similar code?
  → Semble first (semble_search / semble_find_related)

Need to refactor, rename, delete, or edit symbols safely?
  → Serena first (rename_symbol, replace_symbol_body, safe_delete_symbol, find_referencing_symbols)

Need type errors / diagnostics / hover info?
  → Serena diagnostics tools

Query is specific enough for symbol names?
  → codebase-memory search_graph / trace_path

Need loop-depth / complexity?
  → codebase-memory query_graph

Need ADR / traces / cross-repo?
  → codebase-memory specific tool

All three backends return nothing?
  → grep / glob fallback (last resort)
```

## When to fall back to grep/glob (LAST RESORT ONLY)

The following are the **only** legitimate reasons to use grep or glob instead of the MCP backends:
- String literals, error messages, config values
- Non-code files (Dockerfiles, shell scripts, configs, markdown, data files)
- All three backends return insufficient results after a genuine attempt

**Rule**: If you are grepping for functions, classes, imports, call chains, or architecture, stop. Use the appropriate MCP backend. Grep is ~10× more token-expensive and produces noisier results.

Plan reports: follow `skills/plan/` format.
<!-- codebase-memory-mcp:end -->


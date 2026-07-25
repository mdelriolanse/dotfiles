<!-- codebase-memory-mcp:start -->
# Codebase Knowledge Graph — Four-Backend Policy

This project has FOUR complementary code-intelligence backends. Pick the right one for the task.
**ALWAYS prefer these MCP backends over grep/glob/file-search for code discovery.**
These tools are purpose-built to understand code structure, relationships, and semantics.
Resort to grep/glob ONLY when every backend fails or for non-code files.

## 1. CodeGraph (default — reach for this first for "How does X work?" questions)

When a `.codegraph/` index exists in a repo, use CodeGraph as the **primary** code-exploration tool.

- **One tool does it all**: `codegraph explore` — ask a natural-language question, get back verbatim line-numbered source + call paths (including dynamic-dispatch: callbacks, React re-renders, JSX children)
- **Best for**: "How does X work?", architecture questions, locating symbols, understanding flows, impact analysis
- **Parser**: Tree-sitter AST (20+ languages)
- **When to use**: ALMOST ALWAYS as the first code-discovery call. Usually zero file reads needed.
- **Availability**: CLI only (`codegraph explore "…"`). The `codegraph_explore` MCP tool exists but is anchored to the umbrella-root index — in this checkout the root has no indexable source (only stray scripts under `scripts/`, `integrations/`), so the MCP tool returns irrelevant results. **Use the CLI.**
- **CRITICAL — per-repo indices, NOT one shared index**: each cloned repo (`app/`, `gateway/`, `operator/`, `helm/`) has its own `.codegraph/` directory and index. Indices are **not** cross-repo. To query a repo's code you MUST target that repo:
  - From inside the repo: `cd ~/<umbrella>/app && codegraph explore "how does createSource enforce CHECK constraints"`
  - From anywhere, with `-p`: `codegraph explore -p ~/<umbrella>/app "how does createSource enforce CHECK constraints"`
  - Never run bare `codegraph explore` from `~/<umbrella>/` (umbrella root) expecting app/gateway results — it queries the root index, which has none of that code.
- **Setup**: Run `codegraph init` once per repo (inside the repo dir) to build the `.codegraph/` index. Auto-syncs after via file watcher.
- **If a repo has no `.codegraph/`**: skip CodeGraph for that repo, pick from the others below. Do NOT fall back to the umbrella-root index.

Examples:
- `cd ~/<umbrella>/app && codegraph explore "how does JWT auth flow work?"`
- `codegraph explore -p ~/<umbrella>/gateway "trace the BATCH worker shutdown drain path"`
- `codegraph explore -p ~/<umbrella>/app createSource sharedUpload.ts` — get sources + paths between them


## 2. Semble (semantic code search — reach for this for "find where X is done" queries)

When you need to **find code by natural-language description** or **find similar code** to a known location, use Semble. Semantic (embedding + BM25) search retrieves relevant code snippets using ~98% fewer tokens than grep+read. CPU-only, no API keys.

- **Two tools**: `semble_search` (natural-language query → code chunks) and `semble_find_related` (find similar code at a location)
- **Best for**:
  - "Where is authentication handled?", "how do we save models?" — vague natural-language queries where you don't know the exact symbol names
  - Finding related code at a specific line — "find code similar to this error handling pattern"
  - Quick semantic lookup when CodeGraph hasn't been indexed yet
- **Parser**: Tree-sitter chunking + Model2Vec embeddings + BM25 lexical matching
- **When to use**: Before grep, when the query is descriptive or fuzzy. Also useful for finding patterns across languages or when you only have a partial description.
- **Setup**: None. Indexes on first search, caches automatically, watches for file changes.

## 3. Serena (symbol-level IDE operations — use when editing or refactoring)

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

## 4. codebase-memory (specialised — use when CodeGraph + Semble + Serena are insufficient)

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
- **When to use**: When CodeGraph returns nothing, or when the task specifically needs complexity props, ADRs, traces, or custom Cypher

## Decision Flow

```
Need to understand code / architecture / call chain?
  → `codegraph explore` (CLI, from inside the repo or with `-p <repo>`) first (if that repo has a .codegraph/ index)

Have a vague natural-language query ("where is auth done?") OR need similar code?
  → Semble first (semble_search / semble_find_related)

Need to refactor, rename, delete, or edit symbols safely?
  → Serena first (rename_symbol, replace_symbol_body, safe_delete_symbol, find_referencing_symbols)

Need type errors / diagnostics / hover info?
  → Serena diagnostics tools

No .codegraph/ index AND query is specific enough for symbol names?
  → codebase-memory search_graph / trace_path

Need loop-depth / complexity?
  → codebase-memory query_graph

Need ADR / traces / cross-repo?
  → codebase-memory specific tool

All four backends return nothing?
  → grep / glob fallback (last resort)
```

## When to fall back to grep/glob (LAST RESORT ONLY)

The following are the **only** legitimate reasons to use grep or glob instead of the MCP backends:
- String literals, error messages, config values
- Non-code files (Dockerfiles, shell scripts, configs, markdown, data files)
- All four backends return insufficient results after a genuine attempt

**Rule**: If you are grepping for functions, classes, imports, call chains, or architecture, stop. Use the appropriate MCP backend. Grep is ~10× more token-expensive and produces noisier results.

Plan reports: follow `skills/plan/` format.
<!-- codebase-memory-mcp:end -->

<!-- CODEBASE_INTELLIGENCE_START -->
# Codebase Intelligence — Runbook (supersedes "Four-Backend Policy" below)

This checkout has **six** code-intelligence backends, not four. The auto-managed block immediately below this one (lines `<!-- codebase-memory-mcp:start -->`→`<!-- codebase-memory-mcp:end -->`) predates graphify's semantic layer and the cross-repo distinction — read it for per-tool detail, but the decision matrix and inventory below are authoritative.

## Inventory

| Backend | Mechanism | Indexed in this checkout | Strength |
|---|---|---|---|
| **CodeGraph** (CLI) | Tree-sitter AST, per-repo SQLite `.codegraph/codegraph.db` | Per-repo indices where you ran `codegraph init` | Verbatim source + call paths incl. dynamic dispatch (callbacks, JSX children). Fastest "read this symbol + how X calls Y" in one call. |
| **Semble** (MCP) | Tree-sitter chunks + Model2Vec embeddings + BM25, indexes on first query | Nothing pre-indexed (caches on demand, watches files) | Natural-language "where is auth done?" / "find code similar to this location". ~98% fewer tokens than grep+read. |
| **Serena** (MCP) | Language servers (LSP), type-aware | Auto-activates from cwd; `.serena/` at root | Safe cross-file renames, safe deletes, diagnostics, go-to-def, find-references. Correctness across files. |
| **codebase-memory** (MCP) | LSP-style type-aware graph, Cypher-queryable | Per-project where you ran `index_repository` | Complexity metrics (`cyclomatic`, `transitive_loop_depth`, `linear_scan_in_loop`), Cypher queries, ADRs, **cross-repo-intelligence mode** (`CROSS_HTTP_CALLS`/`CROSS_ASYNC_CALLS`/`CROSS_CHANNEL` edges between services). |
| **graphify** (CLI) | Tree-sitter AST + LLM semantic extraction | Per-repo where you ran `graphify extract`; merge at root | Community detection, god nodes, surprising connections, **semantic doc↔code hyperedges** (architectural concepts spanning files), `GRAPH_REPORT.md`. Cheapest broad "what's in this codebase" map. |
| **agentmemory** (MCP) | Persistent session memory (semantic+keyword search) | Running — saves across sessions | Past decisions, discoveries, patterns. Search before re-deriving. |

## Decision matrix — which tool for which question

| Question shape | Tool | Why |
|---|---|---|
| "How does X work?" / "show me Y's source" / "trace the call path A→B" | **`codegraph explore -p <repo>`** | One call returns verbatim source + call paths incl. dynamic dispatch. Cheapest source retrieval. Per-repo: target the specific repo, never root. |
| "Where is authentication handled?" / "find code similar to this error pattern" | **`semble_search` / `semble_find_related`** | Embedding+BM25, fuzzy natural-language match. Zero setup, caches on demand. |
| "Rename this function across the codebase" / "safe-delete this class" / "what breaks if I change this signature" | **Serena `rename_symbol` / `safe_delete_symbol` / `find_referencing_symbols`** | LSP guarantees all references updated. Text edits miss shadowed/re-exported callsites. |
| "Which functions have high cyclomatic complexity / deep nested loops / O(n²) scans?" | **codebase-memory `query_graph`** | Only backend with complexity props. `MATCH (f:Function) WHERE f.transitive_loop_depth >= 3 RETURN ...` |
| "How does gateway call app's routes?" / "trace data flow across services" | **codebase-memory `trace_path` mode `cross_service`** | Synthesizes real `CROSS_HTTP_CALLS`/`CROSS_ASYNC_CALLS` edges. Graphify merge is union-only, no cross-repo edges. |
| "What are the main modules / god nodes / surprising connections in a repo?" | **graphify `query` / `GRAPH_REPORT.md`** | Community detection + god-node analysis + hyperedges. The semantic layer surfaces architectural concepts spanning files. |
| "Did we already decide/discover X in a prior session?" | **agentmemory `memory_smart_search`** | Persistent across sessions. Dedup rules: search before save. |

## Key distinctions that trip people up

1. **CodeGraph vs graphify** — both are Tree-sitter AST, both per-repo. CodeGraph is *fast source retrieval + call paths* (query → verbatim code). Graphify is *the map* (communities, god nodes, hyperedges, semantic doc↔code links). Use CodeGraph when you know what you're looking for; use graphify when you're surveying.
2. **graphify merge ≠ cross-repo intelligence.** `graphify merge-graphs` is a union with `repo` tags — it does **not** infer gateway→app HTTP edges. For real cross-service edges, use codebase-memory's `cross-repo-intelligence` mode (`index_repository` with `mode: "cross-repo-intelligence"`, `target_projects: ["*"]`). That's the only backend that synthesizes cross-repo edges.
3. **Serena vs grep/ast_edit for edits.** Cross-file rename with `ast_edit`/`sed` silently drops callsites. Serena's LSP follows shadowing and re-exports. Use Serena whenever a language server is available and correctness across files matters.
4. **codebase-memory can index a project twice** — a full project and subdir subsets. Query the full project unless you specifically need the subdir slice.
5. **Root CodeGraph index is noise** — a root-level `~/<umbrella>/.codegraph/` may index stray scripts only. **Never run bare `codegraph explore` from the umbrella root** — always `-p ~/<umbrella>/<repo>` or `cd` into the repo. The MCP `codegraph_explore` tool is anchored to the root index and may be disabled; use the CLI.

## Maintenance state

- **graphify**: per-repo semantic graphs built via `graphify extract --backend <llm-provider> --mode deep`. Maintenance rule in the `<!-- GRAPHIFY_START -->` block below: `graphify update ./<repo>/` after code changes (small repos), `--no-cluster` for large repos per-edit. Re-merge at root after any update.
- **CodeGraph**: indices auto-sync via file watcher after `codegraph init`. No manual upkeep needed.
- **codebase-memory**: indexes can drift relative to recent code changes — no auto-sync. Re-index with `index_repository` (full or moderate mode) when queries return outdated structure. Run `detect_changes` to check drift.
- **Semble / Serena / agentmemory**: stateless or self-maintaining, no upkeep.

## When to fall back to grep/glob (LAST RESORT ONLY)

Only for: string literals / error messages / config values; non-code files (Dockerfiles, shell scripts, YAML, SQL, markdown, data); or after every relevant backend above has been tried and returned insufficient results. If you reach for grep to find a function definition, class, import, or call chain — **stop** and use the appropriate backend above.
<!-- CODEBASE_INTELLIGENCE_END -->

<!-- CODEGRAPH_START -->
## CodeGraph

Reach for it BEFORE grep/find or reading files when you need to understand or locate code, **in a repo that has a `.codegraph/` index**.

- **Shell (the path you use):** `codegraph explore "<symbol names or question>"` prints the relevant symbols' verbatim source plus the call paths between them, including dynamic-dispatch hops grep can't follow. Name a file or symbol in the query to read its current line-numbered source.
  - **Target the repo**: `cd <repo> && codegraph explore "…"` or `codegraph explore -p <repo> "…"`. Indices are per-repo, not shared.
  - Never run bare `codegraph explore` from the umbrella root (`~/<umbrella>/`) expecting nested-repo results — the root index has none of that code.
- **MCP tool (`codegraph_explore`): DO NOT USE in this checkout.** It is anchored to the umbrella-root index, which has no nested-repo source — only stray scripts. It will return irrelevant results. The server is disabled in `mcp.json`; use the CLI instead.

If a repo has no `.codegraph/` directory, skip CodeGraph for that repo — indexing is the user's decision. Do NOT fall back to the umbrella-root index.
<!-- CODEGRAPH_END -->
---

## mcp-first

# MCP-First Hard Rule

## YOU HAVE MCP TOOLS — USE THEM BEFORE GREP

Before any grep/glob/Read for code discovery, you MUST call one of these:

1. **`codegraph explore`** (CLI, from inside the repo or `codegraph explore -p <repo>`) — for "how does X work", finding symbols, tracing flows. Do NOT use the `codegraph_explore` MCP tool — it queries the umbrella-root index, which has no app/gateway source.
2. **semble_search** — for natural-language code search ("where is auth handled?")
3. **Serena find_symbol / find_referencing_symbols** — for symbol lookup and references
4. **codebase-memory search_graph / trace_path** — for structured graph queries

## RULE

- **code first → grep NEVER** for anything involving functions, classes, imports, call chains, or architecture
- grep/glob are ONLY for: string literals in code, config values, non-code files (Dockerfiles, YAML, markdown)
- If you reach for grep to find a function definition, a class, or an import — STOP. Call an MCP tool instead.
- These tools cost fewer tokens and give better results. There is no reason to grep first.

## WHEN YOU NEED CODE

| Task | Tool |
|---|---|
| "How does X work?" | `codegraph explore` (CLI, `-p <repo>`) |
| "Where is X done?" | semble_search |
| "Find class/function" | Serena find_symbol |
| "Who calls this?" | Serena find_referencing_symbols |
| "Rename/move/delete" | Serena rename_symbol / safe_delete_symbol |
| "Complex graph query" | codebase-memory search_graph |

**DO NOT use grep for any of the above.**

## tool-names

# Tool Names: Use the Exact Names Provided

## THE SHELL TOOL IS NAMED `bash`

The built-in tool for running shell commands is named **`bash`**. Always call
`bash` with a `command` string parameter (and optional `workdir` / `timeout`).

## `execute_bash` IS NOT A REAL TOOL

There is **no** tool called `execute_bash`. It does not exist in this
environment, and calling it will always fail. If you find yourself about to
emit a tool call named `execute_bash`, STOP — you mean `bash`.

## RULE

- Use the exact tool names from the tool schema you were given. Do not
  invent, abbreviate, or "recall" tool names from training data.
- Shell commands (git, npm, gh, ls, rg, ...) are arguments to the `bash`
  tool, not tools of their own.
- If a tool call is rejected with "invalid ... unavailable tool", re-read the
  available tools list and retry with the correct name. Do not repeat the
  rejected name.

## DO NOT

- Call `execute_bash` — it is not a real tool.
- Call `executeBash`, `run_bash`, `shell`, `terminal`, `exec`, or any other
  shell-flavored name. Only `bash` exists.
- Treat a rejected tool call as a reason to abandon the task — retry with the
  correct name.

## agentmemory-conventions

# Agent Memory Policy

## Search-first rule
- BEFORE asking the user about project history, decisions, or schemas, search agentmemory (memory_smart_search preferred, memory_recall for exact matches).
- If memory is stale or ambiguous, ask — but never re-derive from scratch when memory exists.

## Save triggers
Save a memory AFTER:
- Architectural or design decisions (type: architecture)
- Bug root-causes and fixes (type: bug)
- Schema, enum, or API contract changes (type: fact)
- Validated workflow steps or runbooks (type: workflow)
- New patterns or anti-patterns recognized (type: pattern)

## Deduplication
- Search for existing memories on the same topic BEFORE saving.
- If a memory exists on the same topic, update the user's understanding rather than creating a duplicate.

## Quality bar
- Include the "why", not just the "what".
- Link to relevant file paths.
- Use specific concept tags (comma-separated, no spaces).
- Write for future sessions with zero prior context.

## Session handoff
- When a task spans sessions, save a "work in progress" memory (type: workflow) before ending.
- Include next steps, blockers, and files touched.

## Cleanup
- Delete obsolete memories via memory_governance_delete after major refactors.
- Export via memory_export before destructive operations.
- Do NOT save transient debugging states ("currently at line 45").

## memory-first-codebase

# Memory-First Codebase Reference

When the user asks any question about the codebase — including project structure, architecture, file locations, how something works, or why a decision was made:

1. **Search memory first.** Use `memory_recall` or `memory_smart_search` to check if this topic has already been discussed.
2. **Synthesize from memory.** If relevant memories exist, use them as the primary basis for your answer, citing the source memories. Do not re-derive or re-explore from scratch.
3. **Fall back to codebase exploration** only if no relevant memory exists, or if the memory is ambiguous, stale, or contradicts the current codebase state.

Always respect the existing agentmemory save triggers and deduplication rules in `agentmemory-conventions.md`.
For anything pertaining to the local dev workspace — spinning up the native backend + Vite frontend, inference/adapter setup, or the ports/env wiring — search agentmemory first (`memory_smart_search` "spin up local dev"); the strict runbook and its failure-mode memories live there. Do not re-derive the start sequence from READMEs or stale assumptions; the memory holds the verified, current ports and verification gate.


## discovery-protocol

# Discovery Protocol — Tiered & Memory-Augmenting

When discovering information about the codebase, project decisions, architecture, or prior work,
follow this priority ladder. Each tier is more token-efficient than the next — exhaust higher
tiers before descending.

## Priority Ladder

1. **Docs markdown files** — `CONTEXT.md`, ADRs in `docs/adr/`, project READMEs, and any
   markdown documentation in the repo. Use glob + read, not grep, to locate and consume these.
2. **CodeGraph CLI** — `codegraph explore -p <repo> "…"` (when that repo has a `.codegraph/` index).
   Structural code queries with zero brute-force scanning. One call typically answers the whole question.
   Per-repo indices only — target the specific repo, never the umbrella root. See `AGENTS.md` for full decision flow.
3. **Semble MCP** — `semble_search` and `semble_find_related`. Semantic (embedding + BM25)
   code search for vague natural-language queries or finding similar code at a location.
   ~98% fewer tokens than grep+read. Use before grep when the query is descriptive or fuzzy.
4. **Serena MCP** — `find_declaration`, `find_referencing_symbols`, `get_symbols_overview`.
   Symbol-level navigation and diagnostics. Use when editing/refactoring or needing language-server
   precision. See `AGENTS.md` for when to prefer Serena over the others.
5. **codebase-memory MCP** — `search_graph`, `trace_path`, `get_code_snippet`, `query_graph`,
   `get_architecture`. Use when CodeGraph is unavailable and the task needs complexity metrics,
   ADRs, runtime traces, or custom Cypher queries.
6. **Agent Memory MCP** — `memory_smart_search` (preferred) then `memory_recall`. Past sessions'
   discoveries, decisions, patterns, and lessons.
7. **Grep / glob / file search** — Fallback ONLY when tiers 1–6 yield insufficient context
   or when the question is strictly file-level (string literals, config values, non-code files).
   These are the least token-efficient methods; never start here.

## Memory Augmentation (Lighten Future Load)

After every discovery pass, regardless of tier:

- **Upsert to Agent Memory** — Save new findings that aren't already recorded to agentmemory
  (follow save triggers and deduplication rules in `agentmemory-conventions.md`).
- **Deprecate stale memories** — If a memory contradicts the current codebase state or an
  architectural decision has been superseded, delete or update it via `memory_governance_delete`
  or a fresh `memory_save` that supersedes the old one.
- **Update docs** — If you discover something that should live in `CONTEXT.md`, an ADR, or
  another markdown doc, propose or apply the update so the doc tier stays current.

## What to Upsert

- File-to-responsibility mappings (e.g. "auth logic lives in src/auth/")
- Architectural decisions discovered that aren't in ADRs
- Patterns observed (function naming conventions, error-handling strategies)
- Recent changes or refactors that invalidate past memories

## Rationale

Grep is ~10× more token-expensive than a structured memory lookup. Every time an agent
greps for something that was already known, future agents pay the same cost again.
Memory augmentation prevents this — each discovery pass leaves the knowledge surface
richer for the next agent.

<!-- GRAPHIFY_START -->
## Graphify — knowledge graph maintenance

This checkout may have a merged graphify graph: `~/<umbrella>/graphify-out/graph.json` (union of per-repo `<repo>/graphify-out/graph.json`). Each node carries a `repo` attribute. Keep it fresh after code changes so `graphify query` and `/graphify query` answers stay grounded.

## When to run `graphify update`

**After any code change** (edit, create, delete) to a repo that has a `graphify-out/graph.json`, run:

```bash
graphify update ./<repo>/          # from ~/<umbrella>/
```

Then re-merge so the root graph reflects the change:

```bash
graphify merge-graphs ./<repo-a>/graphify-out/graph.json ./<repo-b>/graphify-out/graph.json ./<repo-c>/graphify-out/graph.json --out graphify-out/graph.json
```

## Cost profile — gate on repo size, NOT LoC

Update cost scales with **graph node count** (re-clustering dominates), not lines changed. A 1-line edit costs the same as a 500-line edit. The AST is re-parsed only for changed files (manifest-hashed); `graph.json` is rewritten in place — **no linear memory growth across calls**, but each call re-pays the cluster cost.

Repos fall into two buckets by node count:

| Category | Nodes | `update` wall | RSS | Semantic extract | Guidance |
|---|---|---|---|---|---|
| SMALL | <~5k | ~1.5–2s | ~75 MB | seconds–minutes | `update` after every code change |
| LARGE | >~5k | minutes | gigabytes | tens of minutes | `update --no-cluster` per-edit; full `update` only when you need fresh communities |
| NOT GRAPHED | — | — | — | — | YAML/SQL/config-only repos (no `graphify-out/`) |

## Extraction tiers

Graphify supports two extraction depths. Use the right one for the change:

### `--code-only` (structural, default for updates)

Pure Tree-sitter AST parsing. No LLM, no API key, no tokens. Produces nodes for functions/classes/imports and edges for calls/imports/references. **This is what `graphify update` runs.** Sufficient for "how does X work" / "who calls Y" / call-path queries.

### `--backend <llm-provider> --mode deep` (semantic, for doc-rich repos)

Adds LLM-inferred edges between docs and code (concept relations, shared data contracts, lifecycle coupling) plus hyperedges grouping 3+ nodes into architectural concepts. Uses a custom LLM provider configured in `~/.graphify/providers.json` with `reasoning_effort: "off"` to disable thinking (see your provider's docs for the canonical "disable thinking" field — commonly `reasoning_effort: "off"`, not an `extra_body` thinking block the endpoint may ignore).

```bash
# Full re-extract with semantic layer (AST + LLM-inferred edges). First run or after doc changes.
graphify extract ./<repo>/ --backend <llm-provider> --mode deep --force
graphify merge-graphs ./<repo-a>/graphify-out/graph.json ./<repo-b>/graphify-out/graph.json ./<repo-c>/graphify-out/graph.json --out graphify-out/graph.json
```

| Aspect | `--code-only` | `--backend <llm-provider> --mode deep` |
|---|---|---|
| LLM | none | `<llm-provider>` (`reasoning_effort=off` recommended) |
| Cost | free | per your provider's pricing |
| Wall | seconds (small) / minutes (large) | seconds–tens of minutes |
| Edges | AST calls/imports/references | + semantic concept relations, hyperedges |
| Hyperedges | 0 | varies by repo |
| When | every code change | first build, after doc changes, or when queries need doc↔code links |

**Gotcha — incremental semantic runs lose AST nodes.** `graphify extract --backend ...` on an unchanged tree only re-extracts changed docs; cached code files are skipped and their AST nodes get pruned. Always pass `--force` for a semantic re-extract so all files (code + docs) are in the extraction. Do NOT run `--backend ...` incrementally without `--force`. `graphify update` (the `--code-only` path) is safe to run incrementally — it never prunes.

**Gotcha — large-repo shrink guard.** A repo with duplicated code paths (e.g. `worktrees/`) makes fuzzy dedup collapse same-named symbols, so a semantic re-extract yields fewer nodes than the code-only graph. graphify's shrink guard may refuse the write. Pass `--allow-partial` to accept it — the reduction is dedup, not data loss, and the semantic edges are the value. `graphify extract ./<repo>/ --backend <llm-provider> --mode deep --force --allow-partial`.

**Gotcha — large doc chunks truncate.** Large doc chunks can exceed your LLM's output cap mid-JSON. graphify's adaptive retry bisects them until they fit; this adds time to the semantic run. Not a bug — the chunks complete, just slowly.

## Threshold rule

- **No LoC threshold.** LoC doesn't predict cost; node count does.
- **SMALL repos (or any repo <~5k nodes):** run `graphify update ./<repo>/` after every code change to that repo. Cost is ~1.5–2s — cheaper than letting the graph go stale.
- **LARGE repos (or any repo >~5k nodes):** do NOT run `graphify update ./<large-repo>/` per-edit. Re-clustering is minutes + gigabytes. Instead:
  1. After code edits, run `graphify update ./<large-repo>/ --no-cluster` (refreshes AST nodes/edges only, skips clustering). This keeps structure fresh for `graphify query` traversal.
  2. Run full `graphify update ./<large-repo>/` (with clustering) only when you need fresh communities / god-nodes / `GRAPH_REPORT.md` — typically at end of session, before a PR, or on explicit request. Warn the user it is slow before kicking it off.
- **After any `update`, re-merge** at the root so `graphify-out/graph.json` stays the union of fresh per-repo graphs.
- **`check-update` is NOT a code gate.** It only flags pending semantic (doc/paper/image) re-extraction, not code. Skip it for code-only repos.

## When NOT to run update

- Docs-only, YAML, SQL, or config changes: `graphify update` (code-only) adds nothing — skip. BUT if the docs describe architecture (PRDs, ADRs, design docs), run `graphify extract ./<repo>/ --backend <llm-provider> --mode deep --force` to refresh semantic doc↔code edges.
- YAML/SQL/config-only repos — no `graphify-out/` exists (no code to graph).
- After changes to `node_modules/`, `dist/`, build artifacts, or anything gitignored (graphify respects `.gitignore`).

## Per-repo vs merged graph

- Per-repo queries: `graphify query --graph ./<repo>/graphify-out/graph.json "<q>"`.
- Cross-repo queries: `graphify query "<q>"` from `~/<umbrella>/` (hits merged `graphify-out/graph.json`).
- The merged graph is a union with `repo` tags, NOT cross-repo edge inference. For real cross-service edges (e.g. service-a → service-b HTTP routes), use codebase-memory's `cross-repo-intelligence` mode — graphify does not synthesize those.
<!-- GRAPHIFY_END -->

## never-push

# Push Policy

**Pushing to remotes is permitted when the user explicitly authorizes it.** This rule can be bypassed by a direct, unambiguous push request from the user (e.g., "push this," "go ahead and push," "please push to origin," "you are allowed to push"). If the user grants explicit permission, push promptly without asking for additional confirmation.

- Always ask the user to confirm any force push (`-f`, `--force`, `--force-with-lease`).
- Committing locally is fine.
- If the user has not explicitly authorized pushing, stop and remind yourself: **don't push without permission**.
- If asked, the user should always grant permission or authorize pushing via the shared machine policy.
- This policy is overridable via the shared machine policy (if granted by the user).
- If a push fails due to repository permission (403), inform the user immediately and suggest a fork-and-PR workflow or asking for write access.

## shared-machine

# Shared Machine Policy — HARD RULE

**This is a shared development machine.** Other developers work on it simultaneously. You must never interfere with their work, resources, or processes.

## Ports and networking

- **Assume every port could be in use by another dev.** Before binding to any port, check if it's already occupied (`ss -tlnp`, `lsof -i`, or similar).
- **Never kill or override another dev's port binding.** Choose a different port instead.
- **Never modify system-wide network configuration** (iptables, nftables, /etc/hosts, DNS resolvers) without explicit request.
- **Never expose services on public interfaces (0.0.0.0) without explicit request.**

## Processes and containers

- **Never kill, stop, or restart processes you didn't start.** This includes Docker containers, systemd services, and background daemons.
- **Never run `docker-compose down`, `docker stop`, `docker rm`, `kill`, `pkill`, or `killall`** without explicit confirmation you're targeting your own resources.
- **Never run `systemctl stop/restart/disable` on system services** unless explicitly instructed.
- **If you start a container or long-running process, bind it to your own user context** (e.g. use your username in container names, use non-conflicting ports, clean up when done).

## Filesystem

- **Stay within your home directory** (your home directory, e.g. ~) unless explicitly directed elsewhere.
- **Never read, modify, or delete files owned by other users** or in their home directories.
- **Never change permissions or ownership of shared directories** (`/tmp`, `/opt`, `/usr/local`) unless instructed.
- **Never delete or modify files under `/var`, `/etc`, or `/dev`** without explicit request.

## System-wide resources

- **Never modify shared configuration** (global git config, system PATH, global npm/pip packages, kernel parameters).
- **Never restart the machine or trigger a reboot.**
- **Never install or remove system packages** (`apt`, `yum`, `dnf`, `pacman`) unless instructed.
- **Never run `chown`, `chmod -R` on shared directories.**

## What IS allowed

- Creating, modifying, and deleting files within your home directory.
- Starting processes and containers scoped to your user, on non-conflicting ports, cleaned up after use.
- Installing packages in user-local contexts (user pip, user npm, npx, local venvs).
- Running `git` operations on your own repositories (never push — see never-push policy).
- Using `/tmp/omp` for temporary work.

## When in doubt

If an action could affect another developer — **stop and ask the user first.**

## chinese-model-english

# Chinese Model Language Policy — HARD RULE

Chinese-origin models (DeepSeek, Qwen, Kimi, etc.) have a tendency to slip into Chinese when thinking or responding. This degrades code quality and readability.

**All thinking, reasoning, code comments, and responses MUST be in English at all times.** This is non-negotiable.

- Think in English. Reason in English. Write in English.
- Code comments, variable names, commit messages, documentation — all English.
- Never emit Chinese characters in any output, even when the user writes in Chinese.
- If you catch yourself thinking in Chinese, immediately switch back to English.
- This applies to EVERY message, every tool call, every response — no exceptions.

## karpathy-guidelines

# Karpathy-Style Coding Agent Guidelines

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

---

## 1. Think Before Coding

Don't assume. Don't hide confusion. Surface tradeoffs.

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

---

## 2. Simplicity First

Minimum code that solves the problem. Nothing speculative.

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.
- Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

---

## 3. Surgical Changes

Touch only what you must. Clean up only your own mess.

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it — don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

**The test:** Every changed line should trace directly to the user's request.

---

## 4. Goal-Driven Execution

Define success criteria. Loop until verified.

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

## Success Indicators

These guidelines are working if:
- Fewer unnecessary changes in diffs
- Fewer rewrites due to overcomplication
- Clarifying questions come before implementation rather than after mistakes

## context-efficiency

# Context Efficiency Policy

## Searching before reading
- ALWAYS prefer grep/ripgrep over reading entire files. Search for symbols, function names, or patterns FIRST.
- When you find a match, use Read with offset/limit to read ONLY the relevant function or block (20-50 lines), never the whole file unless critical.
- Do NOT read the same file twice in a conversation. Reference it by path:line once read.

## Stable files
- Files that haven't changed across turns (project dependencies, config files, framework code) are "stable" — do NOT re-read or re-include them.
- Reference stable files by path:line-number if you've already read them. The prompt cache will retain them.
- Only re-read a file if the user explicitly modifies it or asks for a fresh read.

## Context discipline
- Do NOT echo file contents in output unless asked. Reference locations briefly (e.g., "src/foo.ts:42").
- Minimize explanation text. One-line answers unless detail is requested.
- Batch parallel reads. Read multiple small sections in one call rather than sequentially.

## Tool output summarization
- Summarize tool outputs aggressively. Do NOT pipe raw output back into context.
- Reduce command output to the essential signal: success/failure, key values, relevant matches, error line.
- For grep/ripgrep results, report only the matched file:line locations and the matching snippet.
- For build/test output, report only the count of failures and the failing test names or error lines.
- For git output, report only the relevant delta (branch, changed files count, commit message).
- If output exceeds 200 lines, reduce it to a 3-5 line summary of what happened.
- NEVER echo full file paths lists, full logs, or full stack traces — extract the actionable subset.

## gh-cli-preference

# gh = GitHub.com, git = LOCAL ONLY

`gh` is the ONLY client authenticated to github.com on this machine. Reach for it FIRST for any remote GitHub operation — before you ever reach for `git` against a remote. `git` is local-only under its own credentials.

The single exception is `git push` (see THE ONE BRIDGE below).

## Why gh-first

`gh` holds the github.com token (account-scoped, full `repo` access). `git` has no token of its own; its credential helper for `https://github.com` is `!/usr/bin/gh auth git-credential`, so any `git` network command only succeeds by silently borrowing gh's token. That is a leaky implementation detail, not license to use `git` for remote reads. Treat `gh` as the source of truth for remote state and route remote operations through it.

## REMOTE — USE gh (DO NOT USE git)

- PRs / PR comments / PR reviews / PR status → `gh pr ...`
- Issues / labels / milestones → `gh issue ...`
- CI / status checks / releases → `gh run ...`, `gh release ...`, `gh api ...`
- Repo info / branch list from remote / commits on remote → `gh repo ...`, `gh api ...`
- Reading files from a remote branch → `gh api repos/{owner}/{repo}/contents/...`
- Fetch from or sync with remote → `gh repo sync` or `gh api ...`
- ANY operation that reads from or writes to github.com → `gh`

## LOCAL — USE git (NO NETWORK)

- status, add, commit, reset, stash
- rebase, merge (local-only, no fetch), cherry-pick
- branch, checkout (local branch), switch
- log, diff, blame, show (local commits)
- ANY operation that does not contact the remote

## THE ONE BRIDGE — git push

`git push` is the ONLY network `git` operation that is legitimate. It uploads your local commits to a remote branch and is authenticated through gh's credential helper. Use it when the user authorizes pushing (see never-push policy) and you have local commits to upload. There is no `gh push` — gh only commits individual files server-side.

Do NOT use `gh` to push a branch of local commits:

- `gh api` and the GitHub MCP `create_or_update_file` / `push_files` write files server-side; they do NOT upload your local commit history and will rewrite or squash it.
- To push a branch of local commits, `git push` is the only correct tool.

## DO NOT

- `git fetch`, `git pull`, `git ls-remote` → use `gh repo sync` / `gh api` instead. They may succeed by borrowing gh's token, but remote reads are gh's job.
- `git push` without explicit user authorization — see never-push policy.
- GitHub MCP tools for read-only lookups — `gh` is faster and already authenticated.
- Use `git` as a substitute for `gh` when reading PRs, issues, or remote state.

## pr-issue-linkage

# PR ↔ Issue Linkage Policy — HARD RULE

Every PR that implements an issue MUST be linked to that issue on GitHub so the issue's timeline shows the PR as a `cross-referenced`/`connected` event (the same linkage a GitHub project board renders). A bare `Refs #100` or `#100` in the PR body does **not** create the linkage when the PR and the issue live in different repos — only the **full cross-repo form** does.

## The rule

End the PR body with one line:

```
Closes <org>/<issue-repo>#<issue-number>

```

Use `Closes` (not `Refs`/`Fixes`/`Resolves` unless those are specifically intended — `Closes` auto-closes the issue on merge, which is usually what you want for an implementation PR; `Refs` only cross-references without auto-closing). The repo must be the **issue's repo**, fully qualified (`<org>/<app-repo>`), even when the PR is in a different repo (`<gateway-repo>`, `<gateway-db-repo>`). GitHub only links cross-repo when the org/repo prefix is present — a bare `#100` in a service-a PR silently links to service-a issue #100 (or nothing), not the app issue.

## How to do it via `gh` CLI

When creating the PR, append the line to the `--body`. When the PR already exists, edit the body in place:

```bash
# 1. Fetch the current PR body, append the full cross-repo Closes line.
gh pr view <PR> --repo <org>/<pr-repo> --json body \
  | python3 -c "
import sys, json
body = json.load(sys.stdin)['body'].rstrip()
print(body + '\n\nCloses <org>/<issue-repo>#<issue-number>\n')
" > /tmp/omp/pr_body.md

# 2. Update the PR body from the file.
gh pr edit <PR> --repo <org>/<pr-repo> --body-file /tmp/omp/pr_body.md

# 3. Verify the linkage landed on the issue timeline (cross-referenced event).
gh api repos/<org>/<issue-repo>/issues/<issue-number>/timeline --paginate \
  | python3 -c "
import sys, json
for e in json.load(sys.stdin):
    if e.get('event') == 'cross-referenced':
        src = e.get('source', {}).get('issue', {})
        print(f\"EVENT=cross-referenced  pr=#{src.get('number')}  repo={src.get('repository_url','').split('/')[-1]}\")
"
```

The `cross-referenced` event appears within a few seconds of the body edit. If it doesn't, the most likely cause is a typo'd org/repo prefix or using `#100` instead of `<org>/<app-repo>#100`.

## Multiple PRs, one issue

If several PRs implement one issue (e.g. a gateway PR + a gateway-db migration PR), **each** PR body ends with the same `Closes <org>/<issue-repo>#<issue-number>` line. All appear as separate `cross-referenced` events on the issue timeline. Only the PR whose merge should close the issue should use `Closes`; companion/dependency PRs that shouldn't auto-close it should use `Refs` instead (still fully qualified cross-repo) so they link without closing.

## Do NOT

- Use a bare `#N` or `Refs #N` in a cross-repo PR body — it links to the wrong repo (or nothing) and the Planner board won't render the PR.
- Use `gh issue edit <N> --add-label` or any label API to "link" a PR — labels are orthogonal to timeline linkage.
- Edit the issue body to mention the PR — the linkage must originate from the PR side (the `Closes` keyword in the PR body), not the issue side.
- Forget the `<org>/` org prefix — GitHub cross-repo linking requires the fully-qualified `org/repo#N` form.

## commit-message-style

# Commit Message Style — USE EXACTLY THIS FORMAT

When committing, write commit messages that match the style of the project's `main` branch.

## Title (single line)

```
type(scope): imperative description up to ~80 chars (#PR)
```

- `type` — `feat`, `fix`, `chore`, `refactor`, `docs`, `test`, `perf`
- `scope` — the subsystem / page / module (e.g. `usage`, `api-keys`, `auth`, `settings`, `billing`)
- **Imperative mood**: "make", "fix", "add", "remove", "rename" — NOT "made", "fixed", "adding"
- **Specific, not vague**: "make admin dashboard breakdowns exact and period-driven" — NOT "update dashboard"
- Include PR number in parens if known: `(#42)`
- One blank line after title.

## Body

```
The #123 page-wide date selector drove the headline chart but not the
breakdown tiles, so those stayed frozen on the newest raw rows
regardless of the selected period (Alex, 1 Feb).

Source the breakdowns from the server-side GROUP BY (/v1/stats/summary),
which sums the whole window with no row cap:

- Donut chart uses group_by=category. Cross-tenant breakdown was
  hardcoded zeros (#45); it now shows real aggregated values.
- Top items by volume uses group_by=item_id (also the exact active count).
- Breakdown by source uses group_by=workspace.

Headline totals + daily series stay rollup-sourced. Breakdowns fall back
to the raw aggregation if the grouped call fails. The 12-month window
clamps the breakdown start to 365 days (the summary endpoint caps at
366), so the 12m tiles can trail the rollup headline by a few days at
the far edge.

Breakdowns tab clarity: the value columns are now period-scoped while the
cap column is monthly, so the tab states the split in plain text. A
"window" chip scopes the period columns, the two monthly columns carry
"the cap" / "this month" sub-headers (cap used gets an info tooltip),
the summary badges read "Total monthly cap" / "Value this window" /
"over monthly cap", over-cap rows show a warning icon (not colour alone),
and "Current Value" is renamed "Value".
```
- **Lead paragraph**: why the change exists, what was broken. Reference related PRs/issues (`#123`). Name requester if they asked.
- **Blank line** between every paragraph.
- **Blank line before bullets**. Bullet items explain one change each. Wrap at ~72 chars with a 2-space indent for continuation lines.
- **Cross-reference issue numbers** in bullets: `was hardcoded zeros (#45); it now shows...`
- **Edge cases / fallbacks**: state non-obvious consequences after a blank line.
- **UI/UX specifics**: exact copy, badge names, tooltip text, accessibility notes.

## What NOT to do

- `[Scope] Fix: description` — no bracket prefixes. Conventional commit ONLY.
- `Updated things` / `Fixed bug` — vague. Name the file, column, feature, endpoint.
- Bullet-less walls of text — group related changes into bullet groups.
- No body for non-trivial commits — if the diff is >20 lines or touches >2 features, write a body.

## Self-check before committing

1. Is the title in `type(scope): imperative verb...` format?
2. Does the body explain WHY, not just WHAT?
3. Are bullets present for multi-feature changes?
4. Did I name exact files/endpoints/columns the user will see?

## ponytail-scope

# Ponytail scope

When Ponytail mode is active (ponytail-bridge extension or skill), it governs **implementation only**: code shape, scope, YAGNI, stdlib-first, minimal diffs.

It does **not** apply to:

- Git commit messages
- Pull request titles or bodies

For those, always follow:

- `instructions/commit-message-style.md` — conventional title, full body with why/bullets/edge cases
- `skills/submit-for-review/SKILL.md` (or creating-pull-requests rule in Cursor) — PR title + body via `gh pr create`

Ponytail output rules (telegraphic chat, "code first then three lines", output-concision caps) must not shorten commits or PRs. Chat concision and commit/PR prose are separate policies.

## commit-hygiene

# Commit & PR Hygiene — keep internal tooling and review process out

Commit messages, PR titles, and PR bodies are permanent public artifacts. They must read like the project's own commits, not leak the internal tooling or review process that produced them.

## Never include

- **`ponytail:` code-comment markers.** The `ponytail:` prefix marks deliberate simplifications *in source code*. It must never appear in a commit message or PR body. A commit describes the change, not the mode it was written in.
- **Review-skill lingo.** Never name or reference the review skills ("adamsreview", "andrea review") or their terminology (sectors, lenses, waves, passes, finding IDs, confidence scores, etc.) in any commit message or PR body. The words "adamsreview" and "andrea review" never appear in a commit message — not even to say a review was run.
- **Review attribution.** When shipping fixes requested by a PR review, do NOT write "per Jane's review", "addressing feedback from Sarah", "requested by X", or any other attribution to the reviewer. Once a commit merges, the only thing that matters is what changed and why — not who asked for it. Write a normal conventional commit that stands on its own, as if the change were self-evident.

## Why

A merged commit is read months later by people who never saw the review, the tooling, or the chat. "ponytail: ..." or "adamsreview pass 3 found..." or "per a reviewer's request" adds zero signal and leaks private process into public history. The commit-message-style rule governs format; this rule governs content that must stay out regardless of format.

## Self-check

- Does the message contain `ponytail:`? Remove it.
- Does it name a review skill, sector, lens, wave, pass, or finding? Remove it.
- Does it attribute a change to a reviewer ("per X", "requested by", "addressing X's feedback")? Rewrite as a standalone conventional commit.

## output-concision

# CONCISION LAW — OVERRIDES ALL DEFAULT BEHAVIOR

YOU ARE TALKING TO ONE EXPERT PROGRAMMER. YOUR PROSE IS OVERHEAD. MINIMIZE IT.

## HARD CAP — DO NOT EXCEED

| Situation | Max |
|-----------|-----|
| Default user prompt | ≤4 sentences |
| Tool succeeded | 1 sentence stating result OR just the value/diff |
| Lists | ≤5 bullets, ≤12 words each |
| Code changes | Show code/diff → one sentence context max |

YOU MAY ONLY EXCEED THE CAP IF THE USER EXPLICITLY WRITES: "explain in detail", "walk me through", "why", "elaborate". "Help me", "fix this", "what's wrong" ARE NOT requests for elaboration.

## BANNED — DO NOT EMIT

- "Great question!" / "I'll help you with that" / "Let me…" / "Sure!"
- "I've successfully…" / "Done!" / "Here's what I did:"
- "Let me know if you need anything else" / "Hope this helps"
- "In summary," / "To summarize," / "Overall," — summary IS the reply, not an appendix
- Restating the user's question
- Numbered step-by-step walkthroughs of visible work
- Hedging filler: "It seems that", "It appears", "I think it might be", "potentially", "essentially", "basically"
- Markdown headers (`##`) in short replies. Headers are for docs, not chat.

## TELEGRAPHIC STYLE — USE IT

Drop articles, subjects, link verbs. Surviving meaning > natural grammar.

DO:  Bug at foo.ts:42 — uninitialized variable.
DONT: I have read the file and it looks like the bug is on line 42 where the variable is not being initialized properly.

DO:  Added permission to settings.json:14.
DONT: I've gone ahead and updated the config to add the new permission.

DO:  A: simple/slow. B: fast/complex. C: hybrid. Recommend B.
DONT: Here are three options: 1) Use approach A, which is simpler but slower. 2) Use approach B...

## SELF-CHECK BEFORE SENDING

Count your sentences before sending. If >4 and user ASKED for nothing extra, cut. Cutting feels wrong — cut anyway.

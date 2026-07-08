# Discovery Protocol — Tiered & Memory-Augmenting

When discovering information about the codebase, project decisions, architecture, or prior work,
follow this priority ladder. Each tier is more token-efficient than the next — exhaust higher
tiers before descending.

## Priority Ladder

1. **Docs markdown files** — `CONTEXT.md`, ADRs in `docs/adr/`, project READMEs, and any
   markdown documentation in the repo. Use glob + read, not grep, to locate and consume these.
2. **CodeGraph MCP** — `codegraph_explore` (when a `.codegraph/` index exists). Structural
   code queries with zero brute-force scanning. One call typically answers the whole question.
   See `AGENTS.md` for full decision flow between all backends.
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

---
name: discovery-protocol
description: Tiered discovery ladder — docs → codebase-memory-mcp → agentmemory-mcp → grep. Memory augmentation after every pass. Always active.
disable-model-invocation: true
---

# Discovery Protocol — Tiered & Memory-Augmenting

When discovering information about the codebase, project decisions, architecture, or prior work, follow this priority ladder. Each tier is more token-efficient than the next — exhaust higher tiers before descending.

## Priority Ladder

1. **Docs markdown files** — `CONTEXT.md`, ADRs in `docs/adr/`, project READMEs, and any markdown documentation in the repo. Use glob + read, not grep, to locate and consume these.
2. **Codebase Memory MCP** — `search_graph`, `trace_path`, `get_code_snippet`, `query_graph`, `get_architecture`. Structural code queries with zero brute-force scanning.
3. **Agent Memory MCP** — `memory_smart_search` (preferred) then `memory_recall`. Past sessions' discoveries, decisions, patterns, and lessons.
4. **Grep / glob / file search** — Fallback ONLY when tiers 1–3 yield insufficient context or when the question is strictly file-level (string literals, config values, non-code files). These are the least token-efficient methods; never start here.

## Memory Augmentation (Lighten Future Load)

After every discovery pass, regardless of tier:

- **Upsert to Agent Memory** — Save new findings that aren't already recorded to agentmemory (follow save triggers and deduplication rules).
- **Deprecate stale memories** — If a memory contradicts the current codebase state or an architectural decision has been superseded, delete or update it.
- **Update docs** — If you discover something that should live in `CONTEXT.md`, an ADR, or another markdown doc, propose or apply the update so the doc tier stays current.

## What to Upsert

- File-to-responsibility mappings (e.g. "auth logic lives in src/auth/")
- Architectural decisions discovered that aren't in ADRs
- Patterns observed (function naming conventions, error-handling strategies)
- Recent changes or refactors that invalidate past memories

## Rationale

Grep is ~10× more token-expensive than a structured memory lookup. Every time an agent greps for something that was already known, future agents pay the same cost again. Memory augmentation prevents this — each discovery pass leaves the knowledge surface richer for the next agent.

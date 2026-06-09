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

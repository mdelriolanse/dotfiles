# Memory-First Codebase Reference

When the user asks any question about the codebase — including project structure, architecture, file locations, how something works, or why a decision was made:

1. **Search memory first.** Use `memory_recall` or `memory_smart_search` to check if this topic has already been discussed.
2. **Synthesize from memory.** If relevant memories exist, use them as the primary basis for your answer, citing the source memories. Do not re-derive or re-explore from scratch.
3. **Fall back to codebase exploration** only if no relevant memory exists, or if the memory is ambiguous, stale, or contradicts the current codebase state.

Always respect the existing agentmemory save triggers and deduplication rules in `agentmemory-conventions.md`.

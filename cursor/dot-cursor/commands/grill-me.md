---
name: grill-me
description: Interview the user relentlessly about a plan or design until reaching shared understanding, resolving each branch of the decision tree. Use when user wants to stress-test a plan, get grilled on their design, or mentions "grill me".
---

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time.

If a question can be answered by exploring the codebase, explore the codebase instead.

## Memory discipline

Before asking a new question:
- Search agentmemory (`memory_smart_search` or `memory_recall`) for whether this topic or decision has already been resolved.
- If a prior answer exists, present it as a working assumption and ask the user to confirm, revise, or invalidate it.

After the user answers a question:
- Save the answer to agentmemory with type `pattern`, `preference`, or `architecture` depending on the nature of the decision.
- Include the full question text and the user's answer in the memory content, along with relevant concept tags.
- Search for an existing memory on the same topic first; if one exists, update your understanding rather than creating a duplicate.

This prevents duplicate questions across sessions and preserves continuity.

---
description: Generate a detailed implementation plan.
argument-hint: [requirement]
---

**Purpose:**
Produce a sequential technical roadmap for a requirement using extended thinking.

**Input:**
- **Feature Request**: $ARGUMENTS
- **Output Directory**: ./agent/plans/
- **Context**: @CLAUDE.md
- **Timestamp**: !date +%Y-%m-%d_%H-%M-%S

**Workflow:**
## 1. Strict Clarification Protocol (Anti-Hallucination)
- **Constraint:** If a project requirement is missing or ambiguous, you **must not** assume a path forward. 
- **Action:** List specific "Clarification Questions" at the start of your response. 
- **Mantra:** "Better to ask than to assume."

## 2. Dependency Mapping
- Identify what must happen first (e.g., "Database schema must be finalized before API endpoint creation").
- Highlight potential "Blockers" or external dependencies (APIs, permissions, hardware).

## 3. The "Phased" Approach
Structure every plan into logical increments:
- **Phase 1: MVP/Foundational.** The bare minimum to achieve functionality.
- **Phase 2: Scaling/Refining.** Security, performance, and UI polish.
- **Phase 3: Optimization.** Advanced features and technical debt cleanup.

## 4. Risk Assessment
For every plan, include a **Risk/Mitigation** table:
| Risk | Impact | Mitigation Strategy |
| :--- | :--- | :--- |
| e.g., API Rate Limiting | High | Implement local caching and backoff logic |


**Verify the plan against the project architecture.**

## 5. Success Criteria
- Define what "Done" looks like for each phase.
- Suggest specific validation steps (e.g., "Passes integration test X," "Load time < 200ms"). You should create `Suggested Tests` section that the building agent could write to validate code.
- Do not build the plan yourself.

## 6. Builder Bootstrap Instruction
At the very top of every generated plan, include the following directive for the building agent:

> **⚡ PREREQUISITE — Before executing any phase of this plan, run the `/prime` command to initialize your understanding of the codebase architecture. Do not proceed until priming is complete.**

## 7. Commit Strategy Instruction
At the very end of every generated plan, include the following directive for the building agent:

> **📝 COMMIT PROTOCOL — When implementation is complete, launch a `commit-architect` sub-agent instance (via the Task tool with `subagent_type="commit-architect"`) to analyze your changes and produce clean, atomic Conventional Commits. Do not write commits manually.**

**Output:**
**Report Format**: Save one or more files to the `agent/plans` directory as specified by the user. Each saved plan spec should be titled `{{Output Directory}}{{plan name}}-{{timestamp}}.md` and contain a task list and impacted files.

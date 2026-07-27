---
description: Ingest structured JSON context bundles to prime the agent.
allowed-tools: [Read, Bash]
---

**Purpose:**
Establish a comprehensive project state by ingesting business, technical, and strategic context files to inform all subsequent reasoning and code generation.

**Input:**
- **Context Path**: ./agent/context_bundles/
- **Bundle Files**: project_metadata.json, user_personas.json, technical_context.json, strategic_context.json, context_index.json

**Workflow:**
1. **Verification**:
   * Run a Bash check to confirm all five context files exist in the `{{Context Path}}` directory.
   * If any files are missing, alert the user and identify the missing components.
2. **Read Step**: 
   * Execute a sequential read of the context bundles, starting with **context_index.json** to understand ingestion priorities.
3. **Integration**:
   * Map business goals from **project_metadata.json** to technical constraints in **technical_context.json**.
   * Align current tasks with the challenges identified in **strategic_context.json**.
4. **Validation**:
   * **Important**: Cross-reference the ingested data with the existing @CLAUDE.md to resolve any conflicting information.

**Output:**
**Report Step**: Confirm that ingestion is complete and provide a "Context Status" summary highlighting the active project goals and technical stack now in memory.

---
description: Refresh structured JSON context bundles after project updates.
argument-hint: [scope: all|metadata|technical|personas|strategic]
allowed-tools: [Read, Edit, Bash]
---

**Purpose:**
Synchronize existing context bundles with recent codebase changes, ensuring the agent's long-term project knowledge remains current and accurate.

**Input:**
- **Target Files**: ./agent/context_bundles/*.json
- **Source Context**: @CLAUDE.md, Recent Git Diffs, $ARGUMENTS

**Workflow:**
1. **Analysis**:
   * Examine recent changes to the codebase and @CLAUDE.md since the last bundle generation.
   * Identify new features, architectural shifts, or updated strategic priorities.
2. **Update Step**:
   * Modify **project_metadata.json** if project scope or industry focus has evolved.
   * Update **technical_context.json** with new tech stack additions or infrastructure changes.
   * Refine **user_personas.json** and **strategic_context.json** based on new insights or resolved challenges.
3. **Safety Audit**:
   * **Important**: Scan all updated JSON files for credentials, API keys, or secrets. 
   * Immediately redact any sensitive information discovered.
4. **Write Step**:
   * Overwrite existing bundles in the `./agent/context_bundles/` directory with the updated content.

**Output:**
**Report Step**: List the specific bundles modified and provide a summary of the new information integrated into each file.

---
description: Extract project materials into a structured JSON context suite.
argument-hint: [source_directory_or_files]
allowed-tools: [Read, Edit, Bash]
---

**Purpose:**
Transform raw project documentation and codebase materials into a machine-readable JSON context suite to optimize LLM performance and state management.

**Input:**
- **Source Materials**: $ARGUMENTS
- **Output Directory**: ./agent/context_bundles/
- **Target Schemas**: project_metadata, user_personas, technical_context, strategic_context, context_index

**Workflow:**
1. **Read Step**: 
   * Scan the files provided in $ARGUMENTS and @CLAUDE.md.
   * Identify core contextual data including goals, architecture, and user roles.
2. **Extraction Step**:
   * Generate **project_metadata.json**: Capture title, goals, tone, and industry.
   * Generate **user_personas.json**: Define primary users, roles, needs, and system interactions.
   * Generate **technical_context.json**: Outline architecture, stack, APIs, and key infrastructure files.
   * Generate **strategic_context.json**: Summarize current challenges, pending decisions, and AI support areas.
   * Generate **context_index.json**: Define ingestion rules, LLM instructions, and file load priority.
3. **Validation**:
   * Verify all JSON files strictly adhere to the requested schema.
   * **Important**: Ensure no sensitive credentials or PII are included in the extraction.
4. **Write Step**:
   * Execute Bash to create {{Output Directory}} if it does not exist.
   * Write all five JSON files to the output directory.

**Output:**
**Report Step**: Provide a summary of the extracted data points and confirm the paths for the five generated JSON bundles.

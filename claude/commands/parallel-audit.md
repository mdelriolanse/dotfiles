# .claude/commands/parallel-audit.md

---
description: Parallel security and performance audit with persistent logging.
argument-hint: [target_directory]
---

**Purpose:**
Execute simultaneous specialized audits on a directory and archive the results for project tracking.

**Input:**
- **Target Path**: $ARGUMENTS
- **Output Directory**: ./agent/audits/
- **Timestamp**: !date +%Y-%m-%d_%H-%M-%S

**Workflow:**
1. **Preparation**:
   * Ensure the `{{Output Directory}}` exists using Bash.
   * If the directory is missing, create it immediately.
2. **Delegation**:
   <sub_agent name="security-specialist">
   Audit $ARGUMENTS for vulnerability patterns, hardcoded credentials, and insecure dependency versions.
   </sub_agent>
   <sub_agent name="performance-expert">
   Audit $ARGUMENTS for memory leaks, inefficient loops, and unoptimized I/O operations.
   </sub_agent>
3. **Synthesis**:
   * Aggregate findings from both agents.
   * **Important**: Format the data into a "Security vs Performance" comparison table.
4. **Write Step**:
   * Save the synthesized report to `{{Output Directory}}audit-{{Timestamp}}.md`.

**Output:**
**Report**: Confirm the successful creation of the audit file and provide the relative path to the generated report.

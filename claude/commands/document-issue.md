---
description: Document an error and map out debugging strategies to prevent circular reasoning.
argument-hint: [issue_name]
allowed-tools: [Read, Bash]
---

**Purpose:**
Freeze the current debugging state, analyze failed attempts, and generate a strategic roadmap for resolution to ensure continuity across sessions.

**Input:**
- **Context**: Current terminal history and recent file edits.
- **Timestamp**: !date +%Y-%m-%d_%H-%M-%S
- **Output Path**: ./agent/issues/$1-{{timestamp}}.md
- **Variable**: $ARGUMENTS (Issue Description)

**Workflow:**
1. **Evidence Collection**:
   * Capture the most recent error logs or stack traces from the terminal.
   * Identify all files modified during the current debugging session.
2. **Analysis Step**:
   * **Important**: Explicitly list all "Dead Ends"—avenues already attempted that failed.
   * Categorize the error (e.g., Race Condition, Dependency Conflict, Logic Error).
3. **Strategic Mapping**:
   * Propose 3 standard troubleshooting steps not yet attempted.
   * **Novel Avenues**: Brainstorm 2 "outside-the-box" solutions if a solution has not yet been found (e.g., environment parity checks, shim/mock implementations).
   * If the solution is found at the time of invocation, record the solution.
4. **Write Step**:
   * Create `./agent/issues/` if it does not exist.
   * Compile the findings into a structured markdown document.
   * Save the content to `{{Output Path}}`.

**Output:**
**Report**: Provide a "Debugging Snapshot" summary and the path to the document.

---
description: Automatically generate unit tests for a specified file or directory.
argument-hint: [file_path]
allowed-tools: [Read, Edit, Bash]
---

**Purpose:**
Analyze source code and generate a comprehensive, isolated suite of unit tests that adhere to the project's existing testing patterns.

**Input:**
- **Source Code**: $1
- **Testing Context**: @CLAUDE.md
- **Test Command**: !grep -E "jest|pytest|vitest|mocha" package.json || echo "unknown"

**Workflow:**
1. **Discovery Step**:
   * Read the $1 source file and any related type definitions or interfaces.
   * Identify the project's testing framework and directory structure (e.g., `tests/`, `__tests__`, or colocated `.test.ts` files).
2. **Analysis**:
   * Identify all exported functions, classes, and complex logic paths.
   * **Important**: Map out edge cases, including null/undefined inputs, empty states, and error boundaries.
3. **Execution**:
   * If a specialized agent exists (e.g., `test-architect`), delegate the generation:
     <sub_agent name="test-architect">Generate tests for $1 following AAA patterns.</sub_agent>
   * Otherwise, generate the test file directly using the project's established mocking and assertion styles.
4. **Verification**:
   * Run the newly created test via Bash using the project's test runner.
   * If the test fails, perform one iterative fix based on the error output.

**Output:**
**Report Step**: Confirm the creation of the test file and provide a summary of the coverage (e.g., "5 happy paths, 3 edge cases, 2 error states"). Include the terminal command used to run the new tests.

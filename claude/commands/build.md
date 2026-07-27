--- 
description: Build a specific feature or component.
argument-hint: [--branch <name>] [--worktree <path>]
allowed-tools: [Bash, Read, Edit]
---

Purpose: Execute a specific build task by translating requirements into functional code.

Input:
  Requirement: $ARGUMENTS
  Global Rules: @CLAUDE.md

Optional Flags (parsed from $ARGUMENTS):
  --branch <name> — Create and check out a new git branch with the given name before starting work.
  --worktree <path> — Create a new git worktree at the given path (implies --branch if also provided; the worktree will use that branch).

All subsequent work is performed inside the worktree directory.
If neither flag is supplied, work directly on the current branch in the current working directory — do not create a branch or worktree.

Workflow:

  Parse Flags:
    Extract --branch and --worktree values from $ARGUMENTS. Everything remaining after flag extraction is the feature description.
    If --worktree is provided:
      Run git worktree add -b <branch> <path> (use the --branch value if given, otherwise derive a branch name from the feature description in kebab-case).
      cd into the worktree path for all subsequent steps.
    Else if --branch is provided (without --worktree):
      Run git checkout -b <name> to create and switch to the new branch.
    If neither flag is provided, skip this step entirely.

  Read Step:
    Locate relevant existing components or types that must be integrated.

  Implementation:
    Draft new logic following established patterns in @CLAUDE.md.
    Create or modify files using the Edit tool.

  Verification:
    Run a build check or linter via Bash to ensure zero regressions.

Important: If the build fails, analyze the error and perform one iterative fix.

Output:
  Report: List all created/modified files, the branch/worktree used (if any), and a summary of the implementation logic.

Best Practices for Building Code:

  Iterative Task Execution:
    Work through each task in the plan sequentially. Do not proceed to the next task until the current one is fully implemented and verified.

  Thorough Testing:
    After completing each task, run all relevant tests (unit, integration, type-checks, linters). Confirm the task works in isolation before moving forward.

  Atomic Commits:
    Create small, focused commits after each completed task. Each commit should represent a single logical change that leaves the codebase in a working state.
    Use clear, descriptive commit messages that explain what was changed and why.

  Modular Design:
    Write code in small, reusable modules with single responsibilities. Prefer composition over inheritance and keep functions focused on one task.

  Incremental Verification:
    Run the build and test suite frequently—after every significant change, not just at the end. Catch errors early to minimize debugging scope.

  Code Quality:
    Follow existing code conventions and patterns found in the repository. Match the style, naming conventions, and architectural patterns already established.
    Avoid premature optimization; prioritize clarity and correctness first.

  Error Handling:
    Implement proper error handling from the start. Do not defer error cases to "later"—handle them as part of the initial implementation.

  Documentation:
    Add inline comments for complex logic. Update or create documentation if the feature introduces new patterns or APIs.

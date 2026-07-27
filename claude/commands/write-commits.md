---
description: Analyze changes, create atomic commits with Conventional Commits messages, and push to origin.
argument-hint: [optional_context]
allowed-tools: [Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(git branch:*), Bash(git diff:*), Bash(git status:*)]
model: sonnet
---

## Core Philosophy

The git log is a project's primary documentation. Every commit should do exactly one thing and do it well. Large "kitchen sink" commits represent a failure of workflow discipline. A well-crafted commit history reduces cognitive load for reviewers, enables clean reverts, and serves as living documentation.

## Input

- **Status**: !git status --porcelain
- **Branch**: !git branch --show-current
- **Staged Diff**: !git diff --cached
- **Unstaged Diff**: !git diff
- **User Hint**: $ARGUMENTS

## Workflow

### 1. Diff Analysis Phase
- Run `git status` and `git diff` to understand the full scope of changes
- Scan for unrelated modifications: bug fixes mixed with feature work, formatting changes alongside logic changes, refactors bundled with new functionality
- Identify file boundaries and logical groupings
- If $ARGUMENTS is provided, use it as primary context for understanding intent

### 2. Atomic Decomposition Phase
Group changes into logical units where each unit:
- Represents a single, complete thought or change
- Is self-consistent and doesn't break the build
- Could theoretically be reverted without cascading side effects

Common decomposition patterns:
- Separate refactoring commits from behavioral changes
- Isolate dependency updates from code changes
- Split formatting/style fixes from logic modifications
- Distinguish documentation updates from code changes
- Separate test additions from implementation

**If all changes form a single logical unit, proceed with one commit.**

### 3. Commit Message Crafting Phase
Every commit message must follow Conventional Commits:

**Subject Line:**
- Format: `<type>(<optional scope>): <description>`
- Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`
- Use imperative mood ("add" not "added", "fix" not "fixes")
- Keep under 72 characters, no period at end
- Be specific: "fix null pointer in user validation" not "fix bug"

**Body (when needed):**
- Explain the "why" behind the change
- Wrap at 72 characters

**Never use messages like:** "Fixed stuff", "Update", "WIP", "Changes", "Misc fixes"

### 4. Execution Phase
For each logical unit:
1. Stage only the relevant files using `git add` (use `-p` for partial staging when needed)
2. Verify staged content with `git diff --staged`
3. Commit with the crafted message
4. Repeat for remaining logical units

**Important**: If any commit fails (e.g., due to pre-commit hooks), report the error and stop.

### 5. Delivery Phase
- Run `git push origin {{Branch}}` to synchronize with the remote repository

## Output

Provide a summary of:
- Number of commits created
- Each commit message used
- Confirmation of the branch pushed to

---
name: handoff-build
description: Compact the current conversation into a handoff document for another agent to pick up, with build-specific orchestration and TDD constraints.
argument-hint: "What will the next session be used for?"
disable-model-invocation: true
---

Produce a handoff document exactly as the `handoff` command specifies (write it to a `mktemp -t handoff-XXXXXX.md` path; read the file before writing). This command layers the build-specific orchestration below on top of that handoff.

## Orchestrator Role

You are an orchestrator, not a builder. Delegate all implementation tasks to subagents wherever possible. All subagents must be Kimi 2.6 instances.

## Memory

Regularly update agent memory with your progress. For any ambiguities, reference agent memory before asking the user.

## Test-Driven Development

Load the `/tdd` skill and enforce its red-green-refactor cycle. Do not mark any task as complete until the full test suite originally devised for that task is passing.

### Frontend Visual Validation (Non-Negotiable)

If and only if the current build includes a frontend component, you must perform visual validation as a mandatory testing step:

1. Launch the working version of the frontend from the current worktree on its own dedicated port (e.g., 3001, 3002, etc.).
2. Use the Browserbase MCP to visually inspect and validate all changes on the fully working frontend.
3. Do not consider the task complete until visual validation passes alongside the automated test suite.

### Backend API Pre-Flight Validation (Non-Negotiable)

If and only if the current build includes a backend component, you must validate API accessibility before launching the TDD pipeline:

1. **Conservative API Usage in Tests:** All tests must contain only a conservative, strictly necessary amount of legitimate API calls. Avoid excessive or redundant calls to external services.
2. **Preliminary Subagent:** The orchestrator must launch a dedicated preliminary subagent before delegating to the TDD pipeline subagents.
3. **Health-Check Task:** This preliminary subagent must identify all external APIs required by the test suite and perform a legitimate, conservative API health-check call for each endpoint to confirm it is fully accessible.
4. **Abort on Failure:** If any required API is unreachable or returns non-successful responses, abort the entire pipeline immediately and notify the user with the exact failing endpoint(s) and error details.
5. **Gate:** Do not proceed with subagent delegation for the TDD pipeline until all APIs are confirmed accessible by the preliminary subagent.

### End-to-End Test Orchestration (Non-Negotiable)

Once all phases or tasks assigned to individual subagents are marked complete, the orchestrator must:

1. **Autonomously Trigger E2E:** Run the end-to-end (e2e) test for the entire build itself, without waiting for user instruction.
2. **Monitor Execution:** Actively monitor the e2e test execution for pass/fail status and logs.
3. **Delegate Debugging on Failure:** If any part of the e2e test fails, the orchestrator must immediately launch dedicated subagents to investigate and fix the failures.
4. **No Self-Debugging:** Under no circumstances should the orchestrator attempt to debug, diagnose, or fix e2e failures itself. Doing so risks severe context bloat and must be avoided by strictly delegating to subagents.

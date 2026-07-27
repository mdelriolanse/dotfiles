---
description: Research API design patterns for the domain, draft an OpenAPI/GraphQL spec, critique it, then save the reviewed spec as the source of truth before any implementation begins.
argument-hint: <API description or goal> [--graphql] [--openapi] [--contracts]
---

**Input:** $ARGUMENTS
**Timestamp:** !date +%Y-%m-%d_%H-%M-%S
**Context:** @CLAUDE.md

Parse from $ARGUMENTS:
- `--graphql` — design as a GraphQL schema instead of REST/OpenAPI
- `--openapi` — force OpenAPI 3.x output (default for REST)
- `--contracts` — after spec is finalized, also generate contract tests
- Everything else is the API description

## Phase 1 — Research Patterns

Use the Task tool to launch the `researcher` agent with:
- Research topic: "API design patterns and best practices for [API domain from $ARGUMENTS]"
- Instruction: find reference APIs in this domain from reputable companies (Stripe, GitHub, Twilio, etc.); document their conventions for naming, pagination, error formats, versioning, and authentication; save to `agent/research/`

Wait for the research file.

## Phase 2 — Draft Spec

Use the Task tool to launch `plan-architect` with:
- The API description from $ARGUMENTS
- The research file
- Flag: `--graphql` or `--openapi` as applicable
- Instruction: produce an API spec (OpenAPI 3.x YAML or GraphQL SDL) that:
  - Covers all resources/operations described in the goal
  - Uses naming and patterns drawn from the research findings
  - Includes authentication scheme, error response format, and pagination approach
  - Covers at least the happy path and key error cases per endpoint
  - Save the spec file to `agent/specs/api-{{timestamp}}.yaml` (or `.graphql`)

Wait for the spec file path.

## Phase 3 — Critique

Review the draft spec directly (no agent needed for this step) against these criteria:

**Consistency**
- Are resource names consistently plural/singular?
- Are HTTP methods used semantically (GET is idempotent, POST creates, PUT replaces, PATCH modifies)?
- Are status codes appropriate and consistent across similar operations?

**Completeness**
- Is authentication documented on all protected endpoints?
- Are all error cases represented (401, 403, 404, 422, 429, 500 at minimum)?
- Is pagination defined for all collection endpoints?

**Usability**
- Can a developer integrate without reading anything beyond the spec?
- Are request/response examples included?
- Are field names self-explanatory?

**Security**
- No sensitive data in URL parameters
- Rate limiting documented
- Auth scheme is appropriate for the use case

Document all issues found. Categorize as: blocking (must fix) vs. advisory (should fix).

## Phase 4 — Revise

Apply all blocking issues directly to the spec file. Note advisory issues in a separate section at the bottom of the spec as `# Design Notes`.

## Phase 5 — Contract Tests (if --contracts)

Use the Task tool to launch `test-architect` with:
- The finalized spec file
- Instruction: generate contract tests that validate any future implementation against the spec (not implementation tests — the spec IS the source of truth); use tools like `dredd`, `schemathesis`, or plain assertions against the spec schema

## Completion

Save the finalized spec to `agent/specs/api-final-{{timestamp}}.yaml` (or `.graphql`).

Report to the user:
- Spec file path
- Summary of changes made during critique (blocking issues resolved, advisory notes added)
- Contract test file path if generated
- Recommended next step: use this spec as input to `/tdd-pipeline` or `/research-build` for implementation

**MCPs used:** Firecrawl and WebSearch (reference API pattern research via researcher agent)

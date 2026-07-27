---
description: Cheat sheet for all workflow commands — usage, agents, MCPs, and outputs.
---

# Workflow Cheat Sheet

## Quick Reference

| Command | What it does | MCPs needed |
|---------|-------------|-------------|
| `/tdd-pipeline` | Plan → tests first → parallel execution → merge | None |
| `/research-build` | Research best practices → plan → build | Firecrawl |
| `/frontend-race` | N parallel frontend builds → screenshot → evaluate | Browserbase, Figma (opt) |
| `/impl-race` | N parallel full TDD pipelines → evaluate best | None |
| `/hotfix` | Diagnose → minimal fix → PR | GitHub (opt) |
| `/pr-review` | Fetch PR → review → optionally fix → post | GitHub |
| `/security-audit` | CVE research → audit → fix → re-audit | Firecrawl |
| `/dep-upgrade` | Scan deps → research changelogs → upgrade safely | Firecrawl |
| `/tech-spike` | N POC builds with different libs → evaluate | Firecrawl |
| `/refactor-safety` | Characterization tests → refactor → semantic tests | None |
| `/perf-regression` | Baseline → optimize → re-benchmark → gate | None |
| `/self-healing-ci` | Fetch CI failure → diagnose → fix → PR | GitHub |
| `/coverage-gaps` | Coverage analysis → fill gaps → fix caught bugs | None |
| `/scaffold-race` | N stacks scaffold same spec → evaluate | Firecrawl |
| `/api-design-review` | Research patterns → draft spec → critique → save | Firecrawl |

---

## Detailed Reference

### `/tdd-pipeline <task description>`
Tests written before any implementation. Parallel execution per subtask.

```
/tdd-pipeline add user authentication with JWT
```

**Flow:** `plan-architect` → `test-architect` → N×`ralph-executor` (parallel, each in own worktree) → N×`commit-architect` (parallel) → `merge-orchestrator`

**Outputs:** `agent/plans/`, `agent/tests/`, commits on main

**Worktrees created:** `./worktrees/task-N` (cleaned up after merge)

---

### `/research-build <goal> [--topic <research focus>]`
Grounds the build in researched best practices before planning.

```
/research-build migrate REST API to GraphQL
/research-build add caching layer --topic "Redis vs Memcached Node.js"
```

**Flow:** `researcher` → `plan-architect` → `test-architect` → N×`ralph-executor` → `commit-architect` → `merge-orchestrator`

**Outputs:** `agent/research/`, `agent/plans/`, commits on main

**MCPs:** Firecrawl (scraping docs/advisories), WebSearch

---

### `/frontend-race <UI spec> [--n <count>] [--figma <url>] [--base-port <port>]`
N implementations compete. Each runs a dev server. You pick the winner.

```
/frontend-race rebuild the dashboard --n 3 --base-port 3001
/frontend-race login page --figma https://figma.com/file/... --n 2
```

**Flow:** `plan-architect` → ports assigned (3001, 3002, ...) → N×`ralph-executor` (parallel, separate worktrees + ports) → `evaluator`

**Outputs:** `agent/screenshots/race-N/`, `agent/eval/`, live servers at `localhost:PORT`

**MCPs:** Browserbase (screenshots), Figma (design reference)

**After:** Pick winner → `merge-orchestrator` merges winner, cleans up others

---

### `/impl-race <task> [--n <count>]`
Same as TDD pipeline but N independent implementations compete before merge.

```
/impl-race implement rate limiting middleware --n 3
```

**Flow:** `plan-architect` → `test-architect` (shared tests) → N×`ralph-executor` (parallel, independent) → `evaluator` → winner merged

**Outputs:** `agent/plans/`, `agent/tests/`, `agent/eval/`

---

### `/hotfix <error description or stack trace>`
Fast path. No parallelism. Optimized for urgency.

```
/hotfix TypeError: Cannot read property 'id' of undefined at UserController.ts:42
/hotfix #1234
```

**Flow:** Diagnose inline → `plan-architect` (minimal scope) → single `ralph-executor` → `commit-architect` → GitHub PR

**Branch:** `hotfix/<slug>` (stays in main working dir, no worktree)

**MCPs:** GitHub (PR creation, issue fetch — degrades gracefully if unavailable)

---

### `/pr-review <PR number or URL>`
Fetches the PR, reviews it, optionally implements fixes, posts the review.

```
/pr-review 142
/pr-review https://github.com/org/repo/pull/142
```

**Flow:** GitHub fetch → inline review → (optional) `ralph-executor` for fixes → GitHub post review

**Review checks:** Correctness, security, test coverage, conventions, breaking changes

**MCPs:** GitHub (required — fetches diff and posts review)

---

### `/security-audit [target dir] [--research-only] [--audit-only]`
Full pipeline: CVE research → audit → remediation → re-audit.

```
/security-audit
/security-audit src/api --research-only
/security-audit --audit-only
```

**Flow:** `researcher` (CVEs for your stack) → `security-auditor` → `plan-architect` (remediation) → `ralph-executor` → re-audit

**Outputs:** `agent/research/`, `agent/security/audit-*.md`

**MCPs:** Firecrawl (NVD, OWASP, security advisories)

---

### `/dep-upgrade [packages] [--all] [--security-only]`
Safe upgrade pipeline with changelog research before any changes.

```
/dep-upgrade --all
/dep-upgrade express react --security-only
/dep-upgrade prisma
```

**Flow:** Scan outdated/vulnerable → N×`researcher` (changelogs, parallel) → `plan-architect` (safe order) → `ralph-executor` → `commit-architect`

**MCPs:** Firecrawl (changelogs, release notes, migration guides)

---

### `/tech-spike <use case> --candidates "<lib1>, <lib2>, <lib3>" [--n <count>]`
Each candidate gets a POC. Scored and ranked.

```
/tech-spike HTTP client --candidates "axios, ky, got"
/tech-spike state management --n 3
```

**Flow:** `researcher` (if no candidates) → `plan-architect` (standardized POC spec) → N×`ralph-executor` (parallel, one per candidate) → `evaluator`

**Outputs:** `agent/research/`, `agent/plans/`, `agent/spike-notes/<candidate>.md`, `agent/eval/`

**MCPs:** Firecrawl, WebSearch (candidate discovery)

---

### `/refactor-safety <target file or description>`
Guarantees behavioral equivalence before and after refactor.

```
/refactor-safety src/auth/middleware.ts
/refactor-safety convert UserService to repository pattern
```

**Flow:** `test-architect` (characterization tests) → commit baseline → `plan-architect` → `ralph-executor` (tests stay green) → `test-architect` (semantic cleanup) → `commit-architect`

**Two commits produced:** refactored code + deletion of characterization tests

---

### `/perf-regression <goal> [--threshold-p95 <ms>] [--threshold-rps <rps>]`
Only merges if benchmarks actually improve past the threshold.

```
/perf-regression optimize auth endpoint response time --threshold-p95 50
/perf-regression reduce bundle size
```

**Flow:** `profiler` (baseline) → `plan-architect` → `ralph-executor` → `profiler` (compare) → gate: merge if PASS, escalate if REGRESSION

**Outputs:** `agent/perf/` (baseline JSON + comparison report)

**Branch:** `perf/<slug>` — only merged if verdict is PASS

---

### `/self-healing-ci <run URL or ID> [--repo <owner/repo>] [--confidence-threshold <0-10>]`
Diagnoses CI failure and attempts an automated fix. Escalates if not confident.

```
/self-healing-ci 12345678
/self-healing-ci https://github.com/org/repo/actions/runs/12345678
/self-healing-ci 12345678 --confidence-threshold 8
```

**Flow:** GitHub fetch CI logs → diagnose → if confidence ≥ threshold: `plan-architect` → `ralph-executor` → PR; else: structured escalation report

**MCPs:** GitHub (required — CI log fetch and PR creation)

---

### `/coverage-gaps [target dir] [--threshold <percent>] [--high-risk-only]`
Fills the most dangerous coverage gaps and catches bugs in the process.

```
/coverage-gaps
/coverage-gaps src/payments --threshold 90
/coverage-gaps --high-risk-only
```

**Flow:** `coverage-analyzer` → `test-architect` (gap tests) → run new tests → (if failures) `ralph-executor` fixes bugs → `commit-architect`

**Outputs:** `agent/coverage/analysis-*.md`

**Two commits produced:** new tests + bug fixes (if any found)

---

### `/scaffold-race <project spec> --stacks "<s1>, <s2>, <s3>" [--n <count>]`
Best foundation wins. Compares real scaffolds, not opinions.

```
/scaffold-race REST API with auth --stacks "Express+Prisma, Fastify+Drizzle, Hono+Kysely"
/scaffold-race GraphQL API --n 3
```

**Flow:** `researcher` (if no stacks) → `plan-architect` (standardized spec) → N×`ralph-executor` (parallel) → `evaluator`

**Outputs:** `agent/scaffold-notes/<stack>.md`, `agent/eval/`

**MCPs:** Firecrawl, WebSearch (stack research)

---

### `/api-design-review <API description> [--graphql] [--openapi] [--contracts]`
Produces a reviewed spec before any implementation begins.

```
/api-design-review payments API with Stripe webhooks --openapi
/api-design-review user graph API --graphql --contracts
```

**Flow:** `researcher` (reference APIs for the domain) → `plan-architect` (draft spec) → inline critique → revise → (if --contracts) `test-architect`

**Outputs:** `agent/specs/api-final-*.yaml` (or `.graphql`)

**MCPs:** Firecrawl (Stripe, GitHub, Twilio API patterns)

---

## Agents Reference

| Agent | Role | Model |
|-------|------|-------|
| `plan-architect` | Structured planning, saves to `agent/plans/` | opus |
| `ralph-executor` | Executes plans via Ralph loop, test-validate-commit loop | opus |
| `test-architect` | Writes isolated, deterministic unit tests | sonnet |
| `researcher` | Web research via Firecrawl, saves to `agent/research/` | sonnet |
| `commit-architect` | Atomic commits with Conventional Commits | haiku |
| `merge-orchestrator` | Conflict resolution, merges worktrees to main | opus |
| `evaluator` | Weighted rubric scoring across N implementations | opus |
| `security-auditor` | OWASP Top 10 audit, severity-ranked report | opus |
| `coverage-analyzer` | Risk-prioritized coverage gap analysis | sonnet |
| `profiler` | Benchmark baseline + regression comparison | sonnet |

## MCP Status

Run `claude mcp list` to check connection status.

| MCP | Used by | Requires |
|-----|---------|---------|
| `firecrawl-mcp` | researcher (all research workflows) | `FIRECRAWL_API_KEY` |
| `github` | hotfix, pr-review, self-healing-ci | `GITHUB_TOKEN` |
| `browserbase` | frontend-race | `BROWSERBASE_API_KEY`, `BROWSERBASE_PROJECT_ID` |
| `figma` | frontend-race (optional) | `FIGMA_API_KEY` |
| `fetch` | lightweight HTTP in any workflow | none |

Optional (see `mcp-optional.json`): `sentry`, `linear`, `datadog`, `slack`

## Output Directories

| Directory | Written by |
|-----------|-----------|
| `agent/plans/` | plan-architect |
| `agent/tests/` | test-architect |
| `agent/research/` | researcher |
| `agent/security/` | security-auditor |
| `agent/coverage/` | coverage-analyzer |
| `agent/perf/` | profiler |
| `agent/eval/` | evaluator |
| `agent/specs/` | api-design-review |
| `agent/screenshots/` | frontend-race (via Browserbase) |
| `agent/spike-notes/` | tech-spike executors |
| `agent/scaffold-notes/` | scaffold-race executors |
| `worktrees/` | parallel execution workflows |

---
description: Research CVEs for the tech stack, audit the codebase for vulnerabilities, plan and implement remediations, then re-audit to confirm.
argument-hint: [target directory or file] [--research-only] [--audit-only]
---

**Input:** $ARGUMENTS
**Timestamp:** !date +%Y-%m-%d_%H-%M-%S
**Context:** @CLAUDE.md

Parse flags from $ARGUMENTS:
- `--research-only` — stop after Phase 2 (research + audit report, no fixes)
- `--audit-only` — skip Phase 1 research, go straight to audit using existing research if available
- Remaining argument is the target directory (default: entire project)

## Phase 1 — Research (skip if --audit-only)

Read `package.json`, `requirements.txt`, `go.mod`, or equivalent to identify the tech stack and key dependencies.

Use the Task tool to launch the `researcher` agent. Pass it:
- Research topic: "security vulnerabilities and CVEs for [detected stack + top 5 dependencies]"
- Instruction: scrape NVD, OWASP advisories, and official security bulletins for the identified stack. Save to `agent/research/`.

Wait for the research file path.

## Phase 2 — Audit

Use the Task tool to launch the `security-auditor` agent. Pass it:
- Target directory from $ARGUMENTS (or full project if unspecified)
- Research file path from Phase 1 (if available)

Wait for the audit report at `agent/security/`.

If `--research-only`, stop here and present the audit report path to the user.

## Phase 3 — Remediation Plan

Review the audit report. If there are Critical or High severity findings:

Use the Task tool to launch `plan-architect` with:
- The audit report
- Instruction: produce a remediation plan ordered by severity (Critical first); each step should address a specific finding with a concrete code change; include no new features

Wait for the remediation plan file.

If there are only Medium/Low/Informational findings, ask the user whether to proceed with remediation or just present the report.

## Phase 4 — Implement Fixes

Use the Task tool to launch a `ralph-executor` agent with:
- The remediation plan
- Instruction: implement security fixes only; run the existing test suite after each fix; do not change business logic or refactor beyond the fix

Wait for executor completion.

## Phase 5 — Re-Audit

Use the Task tool to launch `security-auditor` again on the same target, passing the original audit report for comparison.

The re-audit should confirm that all Critical and High findings are resolved. If any remain, report them to the user as requiring manual attention.

## Phase 6 — Commit & Report

Use the Task tool to launch `commit-architect`. Security fix commits should reference the finding IDs from the audit report.

Present to the user:
- Original finding count by severity
- Resolved finding count
- Any remaining findings that need manual attention
- Audit report paths (before and after)

**MCPs used:** Firecrawl (CVE/advisory research via researcher agent)

---
name: inspect
description: Answer a question by read-only inspection — investigate as deeply as needed, change nothing, report back CONCISELY with a ponytail recommendation. Use when the user asks a question ("what do you think", "is X a problem", "how does Y work", "should we Z") and wants an answer, not edits. Triggers on "inspect", "read-only", "just tell me", "don't change anything", "what do you think".
allowed-tools: Bash, Read, Grep, Glob, question, Task
disable-model-invocation: true
metadata:
  author: <your-handle>
  domain: analysis
  triggers: inspect, read-only, just tell me, don't change anything, what do you think
  role: specialist
---

# inspect

Answer the question. Change nothing. Report back **concisely** with a
recommendation shaped by the `ponytail` skill.

## Contract

**Read-only. No exceptions.** No `Edit`, `Write`. No shell command that mutates
state — no writes, installs, migrations, `git commit/push`, `docker`, service
restarts, `psql` DDL/DML. Permitted: reading files, `grep`, code-intelligence
queries (semble, serena, codebase-memory), `SELECT` / `\d` / logs /
health checks, `git status/diff/log`, `gh` **read** calls, web fetches. If
answering *seems* to require a change, describe the change — don't make it.

**Never interrupt in-flight work.** A build/test/agent may be running. Inspect
around it; touch nothing it depends on.

## Method — reason long, report short

1. **Investigate as deeply as the question needs.** This is the one place with
   no length cap: chase the call chain, read the PRD, check the schema, follow
   the git history. Verify claims against the source of truth (repo, PRD, code)
   rather than from memory — cite `file:line`. Use the MCP code-intelligence
   tools (semble_search, serena find_symbol /
   find_referencing_symbols, agentmemory recall / smart_search) before
   falling back to grep.
2. **Distil.** A short answer is the *output* of thorough work, not a substitute
   for it. If the reply is short because the work was shallow, that's the bug.

## Reporting — CONCISELY

The whole point of this skill is a **concise** answer. Enforce it:

- Lead with the verdict in one line. Then the minimum evidence that proves it,
  each cited as `file:line`.
- Prefer telegraphic. `Not a divergence — gateway is /v1/* everywhere
  (routes/*.rs).` beats a paragraph.
- No preamble, no "Let me…", no restating the question, no summary section, no
  hedging ("it seems", "essentially").
- If the honest answer is "can't tell without X", say exactly that and name X.

## Recommendation — via ponytail

Every answer ends with a recommendation, and that recommendation is produced
**through the `ponytail` skill** — the lazy-senior-dev lens. Apply its
ladder before you suggest anything:

1. Does this need to exist / be done at all? (YAGNI — say so in one line.)
2. Stdlib / native / already-installed dependency covers it?
3. Can it be one line?
4. Only then: the minimum that works.

So the recommendation names the **laziest solution that actually works** —
delete over add, boring over clever, the shortest correct diff — and, if the
user wants the fuller version, one line telling them to say so. Pattern:

> **Rec:** *[laziest fix that holds]* — skipped *[X]*, add when *[Y]*.

If you're unsure whether the ponytail lens is loaded, invoke the `ponytail`
skill explicitly before writing the recommendation.

## Shape of a reply

```
<one-line verdict>

<2-5 lines of cited evidence, telegraphic>

Rec: <ponytail-shaped, laziest thing that works>
```

Nothing more unless the user asked to "explain in detail" or "walk me through".

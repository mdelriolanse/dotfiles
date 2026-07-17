<!-- codebase-memory-mcp:start -->
# Codebase Knowledge Graph — Four-Backend Policy

This project has FOUR complementary code-intelligence backends. Pick the right one for the task.
**ALWAYS prefer these MCP backends over grep/glob/file-search for code discovery.**
These tools are purpose-built to understand code structure, relationships, and semantics.
Resort to grep/glob ONLY when every backend fails or for non-code files.

## 1. CodeGraph (default — reach for this first for "How does X work?" questions)

When a `.codegraph/` index exists in a repo, use CodeGraph as the **primary** code-exploration tool.

- **One tool does it all**: `codegraph_explore` — ask a natural-language question, get back verbatim line-numbered source + call paths (including dynamic-dispatch: callbacks, React re-renders, JSX children)
- **Best for**: "How does X work?", architecture questions, locating symbols, understanding flows, impact analysis
- **Parser**: Tree-sitter AST (20+ languages)
- **When to use**: ALMOST ALWAYS as the first code-discovery call. Usually zero file reads needed.
- **Availability**: MCP tool + CLI (`codegraph explore "…"`)
- **Setup**: Run `codegraph init` once per repo to build the `.codegraph/` index. Auto-syncs after.
- **If missing index**: skip it, pick from the others below

Examples:
- `codegraph_explore` with query: "how does JWT auth flow work in this repo?"
- `codegraph_explore` with symbols: `["createRouter", "middleware.ts"]` — get sources + paths between them

## 2. Semble (semantic code search — reach for this for "find where X is done" queries)

When you need to **find code by natural-language description** or **find similar code** to a known location, use Semble. Semantic (embedding + BM25) search retrieves relevant code snippets using ~98% fewer tokens than grep+read. CPU-only, no API keys.

- **Two tools**: `semble_search` (natural-language query → code chunks) and `semble_find_related` (find similar code at a location)
- **Best for**:
  - "Where is authentication handled?", "how do we save models?" — vague natural-language queries where you don't know the exact symbol names
  - Finding related code at a specific line — "find code similar to this error handling pattern"
  - Quick semantic lookup when CodeGraph hasn't been indexed yet
- **Parser**: Tree-sitter chunking + Model2Vec embeddings + BM25 lexical matching
- **When to use**: Before grep, when the query is descriptive or fuzzy. Also useful for finding patterns across languages or when you only have a partial description.
- **Setup**: None. Indexes on first search, caches automatically, watches for file changes.

## 3. Serena (symbol-level IDE operations — use when editing or refactoring)

When **refactoring code** or needing **language-server precision** (cross-file renames, safe deletes, diagnostics, type navigation), use Serena first.

- **Best for**:
  - `rename_symbol` — safe cross-file renames (language server guarantees references updated)
  - `replace_symbol_body` — replace an entire function/class definition atomically
  - `insert_before_symbol` / `insert_after_symbol` — inject code at semantic boundaries
  - `safe_delete_symbol` — delete a symbol after checking for remaining usages
  - `find_declaration` / `find_implementations` / `find_referencing_symbols` — go-to-definition / find-references
  - `get_diagnostics_for_file` / `get_diagnostics_for_symbol` — type errors, warnings
  - `get_symbols_overview` — get top-level symbols in a file (faster than full read for navigation)
- **Parser**: Language servers (LSP), fully type-aware
- **When to use**: Whenever correctness across files matters. Serena prevents text-level errors that grep-based edits miss.
- **Setup**: `serena init` (done once globally). Auto-activates the project from cwd — no per-repo setup needed.

## 4. codebase-memory (specialised — use when CodeGraph + Semble + Serena are insufficient)

Keep this as the **fallback / detail** backend for scenarios none of the others cover.

- **Granular multi-tool**: `search_graph`, `trace_path`, `get_code_snippet`, `query_graph`, `get_architecture`
- **Best for**:
  - Complexity analysis (`query_graph` with `cyclomatic`, `transitive_loop_depth`, `linear_scan_in_loop`)
  - Cypher graph queries (`query_graph`) for complex multi-hop patterns
  - ADR management (`manage_adr`)
  - Runtime trace ingestion (`ingest_traces`) — seeing actual execution paths
  - Cross-repo intelligence mode (`index_repository` with `cross-repo-intelligence`)
  - Engineering metrics (bottleneck detection, dead-code analysis via graph queries)
- **Parser**: LSP-style type-aware resolution
- **When to use**: When CodeGraph returns nothing, or when the task specifically needs complexity props, ADRs, traces, or custom Cypher

## Decision Flow

```
Need to understand code / architecture / call chain?
  → codegraph_explore first (if .codegraph/ index exists)

Have a vague natural-language query ("where is auth done?") OR need similar code?
  → Semble first (semble_search / semble_find_related)

Need to refactor, rename, delete, or edit symbols safely?
  → Serena first (rename_symbol, replace_symbol_body, safe_delete_symbol, find_referencing_symbols)

Need type errors / diagnostics / hover info?
  → Serena diagnostics tools

No .codegraph/ index AND query is specific enough for symbol names?
  → codebase-memory search_graph / trace_path

Need loop-depth / complexity?
  → codebase-memory query_graph

Need ADR / traces / cross-repo?
  → codebase-memory specific tool

All four backends return nothing?
  → grep / glob fallback (last resort)
```

## When to fall back to grep/glob (LAST RESORT ONLY)

The following are the **only** legitimate reasons to use grep or glob instead of the MCP backends:
- String literals, error messages, config values
- Non-code files (Dockerfiles, shell scripts, configs, markdown, data files)
- All four backends return insufficient results after a genuine attempt

**Rule**: If you are grepping for functions, classes, imports, call chains, or architecture, stop. Use the appropriate MCP backend. Grep is ~10× more token-expensive and produces noisier results.

Plan reports: follow `skills/plan/` format.
<!-- codebase-memory-mcp:end -->

<!-- CODEGRAPH_START -->
## CodeGraph

Installed and ready. In repositories indexed by CodeGraph (a `.codegraph/` directory exists at the repo root), reach for it BEFORE grep/find or reading files when you need to understand or locate code:

- **MCP tool** (when available): `codegraph_explore` answers most code questions in one call — the relevant symbols' verbatim source plus the call paths between them, including dynamic-dispatch hops grep can't follow. Name a file or symbol in the query to read its current line-numbered source. If it's listed but deferred, load it by name via tool search.
- **Shell** (always works): `codegraph explore "<symbol names or question>"` prints the same output.

If there is no `.codegraph/` directory, skip CodeGraph entirely — indexing is the user's decision.
<!-- CODEGRAPH_END -->

---

## mcp-first

# MCP-First Hard Rule

## YOU HAVE MCP TOOLS — USE THEM BEFORE GREP

Before any grep/glob/Read for code discovery, you MUST call one of these:

1. **codegraph_explore** — for "how does X work", finding symbols, tracing flows
2. **semble_search** — for natural-language code search ("where is auth handled?")
3. **Serena find_symbol / find_referencing_symbols** — for symbol lookup and references
4. **codebase-memory search_graph / trace_path** — for structured graph queries

## RULE

- **code first → grep NEVER** for anything involving functions, classes, imports, call chains, or architecture
- grep/glob are ONLY for: string literals in code, config values, non-code files (Dockerfiles, YAML, markdown)
- If you reach for grep to find a function definition, a class, or an import — STOP. Call an MCP tool instead.
- These tools cost fewer tokens and give better results. There is no reason to grep first.

## WHEN YOU NEED CODE

| Task | Tool |
|---|---|
| "How does X work?" | codegraph_explore |
| "Where is X done?" | semble_search |
| "Find class/function" | Serena find_symbol |
| "Who calls this?" | Serena find_referencing_symbols |
| "Rename/move/delete" | Serena rename_symbol / safe_delete_symbol |
| "Complex graph query" | codebase-memory search_graph |

**DO NOT use grep for any of the above.**

## tool-names

# Tool Names: Use the Exact Names Provided

## THE SHELL TOOL IS NAMED `bash`

The built-in tool for running shell commands is named **`bash`**. Always call
`bash` with a `command` string parameter (and optional `workdir` / `timeout`).

## `execute_bash` IS NOT A REAL TOOL

There is **no** tool called `execute_bash`. It does not exist in this
environment, and calling it will always fail. If you find yourself about to
emit a tool call named `execute_bash`, STOP — you mean `bash`.

## RULE

- Use the exact tool names from the tool schema you were given. Do not
  invent, abbreviate, or "recall" tool names from training data.
- Shell commands (git, npm, gh, ls, rg, ...) are arguments to the `bash`
  tool, not tools of their own.
- If a tool call is rejected with "invalid ... unavailable tool", re-read the
  available tools list and retry with the correct name. Do not repeat the
  rejected name.

## DO NOT

- Call `execute_bash` — it is not a real tool.
- Call `executeBash`, `run_bash`, `shell`, `terminal`, `exec`, or any other
  shell-flavored name. Only `bash` exists.
- Treat a rejected tool call as a reason to abandon the task — retry with the
  correct name.

## agentmemory-conventions

# Agent Memory Policy

## Search-first rule
- BEFORE asking the user about project history, decisions, or schemas, search agentmemory (memory_smart_search preferred, memory_recall for exact matches).
- If memory is stale or ambiguous, ask — but never re-derive from scratch when memory exists.

## Save triggers
Save a memory AFTER:
- Architectural or design decisions (type: architecture)
- Bug root-causes and fixes (type: bug)
- Schema, enum, or API contract changes (type: fact)
- Validated workflow steps or runbooks (type: workflow)
- New patterns or anti-patterns recognized (type: pattern)

## Deduplication
- Search for existing memories on the same topic BEFORE saving.
- If a memory exists on the same topic, update the user's understanding rather than creating a duplicate.

## Quality bar
- Include the "why", not just the "what".
- Link to relevant file paths.
- Use specific concept tags (comma-separated, no spaces).
- Write for future sessions with zero prior context.

## Session handoff
- When a task spans sessions, save a "work in progress" memory (type: workflow) before ending.
- Include next steps, blockers, and files touched.

## Cleanup
- Delete obsolete memories via memory_governance_delete after major refactors.
- Export via memory_export before destructive operations.
- Do NOT save transient debugging states ("currently at line 45").

## memory-first-codebase

# Memory-First Codebase Reference

When the user asks any question about the codebase — including project structure, architecture, file locations, how something works, or why a decision was made:

1. **Search memory first.** Use `memory_recall` or `memory_smart_search` to check if this topic has already been discussed.
2. **Synthesize from memory.** If relevant memories exist, use them as the primary basis for your answer, citing the source memories. Do not re-derive or re-explore from scratch.
3. **Fall back to codebase exploration** only if no relevant memory exists, or if the memory is ambiguous, stale, or contradicts the current codebase state.

Always respect the existing agentmemory save triggers and deduplication rules in `agentmemory-conventions.md`.

## discovery-protocol

# Discovery Protocol — Tiered & Memory-Augmenting

When discovering information about the codebase, project decisions, architecture, or prior work,
follow this priority ladder. Each tier is more token-efficient than the next — exhaust higher
tiers before descending.

## Priority Ladder

1. **Docs markdown files** — `CONTEXT.md`, ADRs in `docs/adr/`, project READMEs, and any
   markdown documentation in the repo. Use glob + read, not grep, to locate and consume these.
2. **CodeGraph MCP** — `codegraph_explore` (when a `.codegraph/` index exists). Structural
   code queries with zero brute-force scanning. One call typically answers the whole question.
   See `AGENTS.md` for full decision flow between all backends.
3. **Semble MCP** — `semble_search` and `semble_find_related`. Semantic (embedding + BM25)
   code search for vague natural-language queries or finding similar code at a location.
   ~98% fewer tokens than grep+read. Use before grep when the query is descriptive or fuzzy.
4. **Serena MCP** — `find_declaration`, `find_referencing_symbols`, `get_symbols_overview`.
   Symbol-level navigation and diagnostics. Use when editing/refactoring or needing language-server
   precision. See `AGENTS.md` for when to prefer Serena over the others.
5. **codebase-memory MCP** — `search_graph`, `trace_path`, `get_code_snippet`, `query_graph`,
   `get_architecture`. Use when CodeGraph is unavailable and the task needs complexity metrics,
   ADRs, runtime traces, or custom Cypher queries.
6. **Agent Memory MCP** — `memory_smart_search` (preferred) then `memory_recall`. Past sessions'
   discoveries, decisions, patterns, and lessons.
7. **Grep / glob / file search** — Fallback ONLY when tiers 1–6 yield insufficient context
   or when the question is strictly file-level (string literals, config values, non-code files).
   These are the least token-efficient methods; never start here.

## Memory Augmentation (Lighten Future Load)

After every discovery pass, regardless of tier:

- **Upsert to Agent Memory** — Save new findings that aren't already recorded to agentmemory
  (follow save triggers and deduplication rules in `agentmemory-conventions.md`).
- **Deprecate stale memories** — If a memory contradicts the current codebase state or an
  architectural decision has been superseded, delete or update it via `memory_governance_delete`
  or a fresh `memory_save` that supersedes the old one.
- **Update docs** — If you discover something that should live in `CONTEXT.md`, an ADR, or
  another markdown doc, propose or apply the update so the doc tier stays current.

## What to Upsert

- File-to-responsibility mappings (e.g. "auth logic lives in src/auth/")
- Architectural decisions discovered that aren't in ADRs
- Patterns observed (function naming conventions, error-handling strategies)
- Recent changes or refactors that invalidate past memories

## Rationale

Grep is ~10× more token-expensive than a structured memory lookup. Every time an agent
greps for something that was already known, future agents pay the same cost again.
Memory augmentation prevents this — each discovery pass leaves the knowledge surface
richer for the next agent.

## never-push

# Push Policy

**Pushing to remotes is permitted when the user explicitly authorizes it.** This rule can be bypassed by a direct, unambiguous push request from the user (e.g., "push this," "go ahead and push," "please push to origin," "you are allowed to push"). If the user grants explicit permission, push promptly without asking for additional confirmation.

- Always ask the user to confirm any force push (`-f`, `--force`, `--force-with-lease`).
- Committing locally is fine.
- If the user has not explicitly authorized pushing, stop and remind yourself: **don't push without permission**.
- If asked, the user should always grant permission or authorize pushing via the shared machine policy.
- This policy is overridable via the shared machine policy (if granted by the user).
- If a push fails due to repository permission (403), inform the user immediately and suggest a fork-and-PR workflow or asking for write access.

## shared-machine

# Shared Machine Policy — HARD RULE

**This is a shared development machine.** Other developers work on it simultaneously. You must never interfere with their work, resources, or processes.

## Ports and networking

- **Assume every port could be in use by another dev.** Before binding to any port, check if it's already occupied (`ss -tlnp`, `lsof -i`, or similar).
- **Never kill or override another dev's port binding.** Choose a different port instead.
- **Never modify system-wide network configuration** (iptables, nftables, /etc/hosts, DNS resolvers) without explicit request.
- **Never expose services on public interfaces (0.0.0.0) without explicit request.**

## Processes and containers

- **Never kill, stop, or restart processes you didn't start.** This includes Docker containers, systemd services, and background daemons.
- **Never run `docker-compose down`, `docker stop`, `docker rm`, `kill`, `pkill`, or `killall`** without explicit confirmation you're targeting your own resources.
- **Never run `systemctl stop/restart/disable` on system services** unless explicitly instructed.
- **If you start a container or long-running process, bind it to your own user context** (e.g. use your username in container names, use non-conflicting ports, clean up when done).

## Filesystem

- **Stay within your home directory** (`$HOME`) unless explicitly directed elsewhere.
- **Never read, modify, or delete files owned by other users** or in their home directories.
- **Never change permissions or ownership of shared directories** (`/tmp`, `/opt`, `/usr/local`) unless instructed.
- **Never delete or modify files under `/var`, `/etc`, or `/dev`** without explicit request.

## System-wide resources

- **Never modify shared configuration** (global git config, system PATH, global npm/pip packages, kernel parameters).
- **Never restart the machine or trigger a reboot.**
- **Never install or remove system packages** (`apt`, `yum`, `dnf`, `pacman`) unless instructed.
- **Never run `chown`, `chmod -R` on shared directories.**

## What IS allowed

- Creating, modifying, and deleting files within `$HOME`.
- Starting processes and containers scoped to your user, on non-conflicting ports, cleaned up after use.
- Installing packages in user-local contexts (user pip, user npm, npx, local venvs).
- Running `git` operations on your own repositories (never push — see never-push policy).
- Using `/tmp/omp` for temporary work.

## When in doubt

If an action could affect another developer — **stop and ask the user first.**

## chinese-model-english

# Chinese Model Language Policy — HARD RULE

Chinese-origin models (DeepSeek, Qwen, Kimi, etc.) have a tendency to slip into Chinese when thinking or responding. This degrades code quality and readability.

**All thinking, reasoning, code comments, and responses MUST be in English at all times.** This is non-negotiable.

- Think in English. Reason in English. Write in English.
- Code comments, variable names, commit messages, documentation — all English.
- Never emit Chinese characters in any output, even when the user writes in Chinese.
- If you catch yourself thinking in Chinese, immediately switch back to English.
- This applies to EVERY message, every tool call, every response — no exceptions.

## karpathy-guidelines

# Karpathy-Style Coding Agent Guidelines

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

---

## 1. Think Before Coding

Don't assume. Don't hide confusion. Surface tradeoffs.

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

---

## 2. Simplicity First

Minimum code that solves the problem. Nothing speculative.

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.
- Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

---

## 3. Surgical Changes

Touch only what you must. Clean up only your own mess.

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it — don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

**The test:** Every changed line should trace directly to the user's request.

---

## 4. Goal-Driven Execution

Define success criteria. Loop until verified.

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

## Success Indicators

These guidelines are working if:
- Fewer unnecessary changes in diffs
- Fewer rewrites due to overcomplication
- Clarifying questions come before implementation rather than after mistakes

## context-efficiency

# Context Efficiency Policy

## Searching before reading
- ALWAYS prefer grep/ripgrep over reading entire files. Search for symbols, function names, or patterns FIRST.
- When you find a match, use Read with offset/limit to read ONLY the relevant function or block (20-50 lines), never the whole file unless critical.
- Do NOT read the same file twice in a conversation. Reference it by path:line once read.

## Stable files
- Files that haven't changed across turns (project dependencies, config files, framework code) are "stable" — do NOT re-read or re-include them.
- Reference stable files by path:line-number if you've already read them. The prompt cache will retain them.
- Only re-read a file if the user explicitly modifies it or asks for a fresh read.

## Context discipline
- Do NOT echo file contents in output unless asked. Reference locations briefly (e.g., "src/foo.ts:42").
- Minimize explanation text. One-line answers unless detail is requested.
- Batch parallel reads. Read multiple small sections in one call rather than sequentially.

## Tool output summarization
- Summarize tool outputs aggressively. Do NOT pipe raw output back into context.
- Reduce command output to the essential signal: success/failure, key values, relevant matches, error line.
- For grep/ripgrep results, report only the matched file:line locations and the matching snippet.
- For build/test output, report only the count of failures and the failing test names or error lines.
- For git output, report only the relevant delta (branch, changed files count, commit message).
- If output exceeds 200 lines, reduce it to a 3-5 line summary of what happened.
- NEVER echo full file paths lists, full logs, or full stack traces — extract the actionable subset.

## gh-cli-preference

# BOUNDARY: gh = GITHUB.COM, git = LOCAL ONLY

This system's `git` CLI is NOT authenticated to GitHub.com. Any command that hits the network (`fetch`, `pull`, `push`, `ls-remote`, etc.) will fail.

## REMOTE — USE gh (DO NOT USE git)

- PRs / PR comments / PR reviews / PR status → `gh pr ...`
- Issues / labels / milestones → `gh issue ...`
- CI / status checks / releases → `gh run ...`, `gh release ...`, `gh api ...`
- Repo info / branch list from remote / commits on remote → `gh repo ...`, `gh api ...`
- Reading files from a remote branch → `gh api repos/{owner}/{repo}/contents/...`
- Fetch from or sync with remote → `gh repo sync` or `gh api ...`
- ANY operation that reads from or writes to github.com → `gh`

## LOCAL — USE git (NO NETWORK)

- status, add, commit, reset, stash
- rebase, merge (local-only, no fetch), cherry-pick
- branch, checkout (local branch), switch
- log, diff, blame, show (local commits)
- ANY operation that does not contact the remote

## DO NOT

- `git fetch`, `git pull`, `git push`, `git ls-remote` — unauthenticated, will fail.
- GitHub MCP tools for read-only lookups — `gh` is faster and already authenticated.
- Use `git` as a substitute for `gh` when reading PRs, issues, or remote state.

## commit-message-style

# Commit Message Style — USE EXACTLY THIS FORMAT

When committing, write commit messages that match the style of the project's `main` branch.

## Title (single line)

```
type(scope): imperative description up to ~80 chars (#PR)
```

- `type` — `feat`, `fix`, `chore`, `refactor`, `docs`, `test`, `perf`
- `scope` — the subsystem / page / module (e.g. `usage`, `api-keys`, `auth`, `settings`, `billing`)
- **Imperative mood**: "make", "fix", "add", "remove", "rename" — NOT "made", "fixed", "adding"
- **Specific, not vague**: "make admin dashboard breakdowns exact and period-driven" — NOT "update dashboard"
- Include PR number in parens if known: `(#953)`
- One blank line after title.

## Body

```
The #925 page-wide period selector drove the headline KPIs and trend but
not the breakdown tiles or the Model Usage / Users & Budgets tabs, so
those stayed frozen on whatever the newest 10k raw rows held regardless
of the selected period (Josh, 25 Jun).

Source the breakdowns from the gateway's server-side GROUP BY
(/v1/usage/summary), which sums the whole window with no row cap:

- Model donut + Model Usage tab use group_by=model. Cross-org Model Usage
  was hardcoded zeros (#212); it now shows real aggregated usage.
- Top Users by Volume uses group_by=user_id (also the exact Active-Users
  count).
- Usage by surface uses group_by=workspace.
- Users & Budgets tab now honours the page period for its spend/usage
  columns; budget % stays month-to-date vs the monthly cap. Per-user
  spend moves to group_by=user_id (exact, replaces the per-user fetch
  fan-out).

Headline totals + daily series stay rollup-sourced. Breakdowns fall back
to the raw aggregation if the grouped call fails. The 12-month window
clamps the breakdown start to 365 days (the summary endpoint caps at
366), so the 12m tiles can trail the rollup headline by a few days at
the far edge.

Budgets tab clarity: the spend/usage columns are now period-scoped while
budget % is monthly, so the tab states the split in plain text. A "Usage
window" chip scopes the period columns, the two monthly columns carry
"the cap" / "this month" sub-headers (Budget used gets an info tooltip),
the summary badges read "Total monthly budget" / "Spend this window" /
"over monthly budget", over-budget rows show a warning icon (not colour
alone), and "Current Spend" is renamed "Spend".
```
- **Lead paragraph**: why the change exists, what was broken. Reference related PRs/issues (`#925`). Name requester if they asked.
- **Blank line** between every paragraph.
- **Blank line before bullets**. Bullet items explain one change each. Wrap at ~72 chars with a 2-space indent for continuation lines.
- **Cross-reference issue numbers** in bullets: `was hardcoded zeros (#212); it now shows...`
- **Edge cases / fallbacks**: state non-obvious consequences after a blank line.
- **UI/UX specifics**: exact copy, badge names, tooltip text, accessibility notes.

## What NOT to do

- `[Scope] Fix: description` — no bracket prefixes. Conventional commit ONLY.
- `Updated things` / `Fixed bug` — vague. Name the file, column, feature, endpoint.
- Bullet-less walls of text — group related changes into bullet groups.
- No body for non-trivial commits — if the diff is >20 lines or touches >2 features, write a body.

## Self-check before committing

1. Is the title in `type(scope): imperative verb...` format?
2. Does the body explain WHY, not just WHAT?
3. Are bullets present for multi-feature changes?
4. Did I name exact files/endpoints/columns the user will see?

## ponytail-scope

# Ponytail scope

When Ponytail mode is active (ponytail-bridge extension or skill), it governs **implementation only**: code shape, scope, YAGNI, stdlib-first, minimal diffs.

It does **not** apply to:

- Git commit messages
- Pull request titles or bodies

For those, always follow:

- `instructions/commit-message-style.md` — conventional title, full body with why/bullets/edge cases
- `skills/submit-for-review/SKILL.md` (or creating-pull-requests rule in Cursor) — PR title + body via `gh pr create`

Ponytail output rules (telegraphic chat, "code first then three lines", output-concision caps) must not shorten commits or PRs. Chat concision and commit/PR prose are separate policies.

## output-concision

# CONCISION LAW — OVERRIDES ALL DEFAULT BEHAVIOR

YOU ARE TALKING TO ONE EXPERT PROGRAMMER. YOUR PROSE IS OVERHEAD. MINIMIZE IT.

## HARD CAP — DO NOT EXCEED

| Situation | Max |
|-----------|-----|
| Default user prompt | ≤4 sentences |
| Tool succeeded | 1 sentence stating result OR just the value/diff |
| Lists | ≤5 bullets, ≤12 words each |
| Code changes | Show code/diff → one sentence context max |

YOU MAY ONLY EXCEED THE CAP IF THE USER EXPLICITLY WRITES: "explain in detail", "walk me through", "why", "elaborate". "Help me", "fix this", "what's wrong" ARE NOT requests for elaboration.

## BANNED — DO NOT EMIT

- "Great question!" / "I'll help you with that" / "Let me…" / "Sure!"
- "I've successfully…" / "Done!" / "Here's what I did:"
- "Let me know if you need anything else" / "Hope this helps"
- "In summary," / "To summarize," / "Overall," — summary IS the reply, not an appendix
- Restating the user's question
- Numbered step-by-step walkthroughs of visible work
- Hedging filler: "It seems that", "It appears", "I think it might be", "potentially", "essentially", "basically"
- Markdown headers (`##`) in short replies. Headers are for docs, not chat.

## TELEGRAPHIC STYLE — USE IT

Drop articles, subjects, link verbs. Surviving meaning > natural grammar.

DO:  Bug at foo.ts:42 — uninitialized variable.
DONT: I have read the file and it looks like the bug is on line 42 where the variable is not being initialized properly.

DO:  Added permission to settings.json:14.
DONT: I've gone ahead and updated the config to add the new permission.

DO:  A: simple/slow. B: fast/complex. C: hybrid. Recommend B.
DONT: Here are three options: 1) Use approach A, which is simpler but slower. 2) Use approach B...

## SELF-CHECK BEFORE SENDING

Count your sentences before sending. If >4 and user ASKED for nothing extra, cut. Cutting feels wrong — cut anyway.

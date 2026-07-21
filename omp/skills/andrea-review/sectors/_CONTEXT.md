# Shared Context — Andrea Review Paradigm Extraction (12 workers)

You are ONE of 12 parallel extraction workers. Each worker owns ONE sector of
Andrea Moccia's PR-review methodology. Extract every review paradigm that
belongs to your sector, grounded in the three source documents, and connect
each paradigm to the concrete <Provider> infrastructure that already exists
on this machine (6 codebase-intelligence backends). You produce a sector
extract; the orchestrator dedups, validates, and adversarially refines your
output into the final agent-swarm playbook.

## The three source documents (all on disk — READ YOUR RELEVANT ONES)

1. `~/<provider>/docs/andrea-review-playbook.md` — the existing distilled
   playbook: 9 paradigms, 4 critical code paths, 13 conventions, 4 dependency
   cross-checks. The artifact being refined. **Every worker reads this.**
2. `~/<provider>/worktrees/batch-api/docs/resolve-code-review/gateway.md` —
   the full item-by-item audit of PR #94 (26 Andrea items: 3 BLOCKERs, 7
   MAJORs, 4 MINORs, 3 NITs, 7 rebuttal items). Concrete evidence at file:line
   for every finding. The richest single record of Andrea's review behavior.
3. `~/<provider>/worktrees/batch-api/docs/feedback-divergences.md` —
   Andrea's implementation-plan comments on issue #973 vs the local build:
   storage substrate, deployment topology, caps, worker concurrency, schema,
   process/ops. Shows how he reviews *design*, not just code.

## The 12 sectors (you own exactly ONE — named in your task prompt)

The partition is by **review concern**, not by file. Each sector is a lens
Andrea actually applies, witnessed in the source docs. A finding can touch
one file yet fall under three sectors (a migration's CHECK constraint is
Schema/Sector-7; its V-number collision is Migration/Sector-8; its deploy
ordering is Multi-repo/Sector-9). Keep sector boundaries crisp — overlap is
fine if the *lens* differs; the dedup pass will merge redundant wording.

| # | Sector | Core question | Primary sources |
|---:|---|---|---|
| 01 | Idempotency & re-arm gates | Does every retry/re-run/webhook re-delivery re-fire when it should and not duplicate when it shouldn't? Is the gate key deterministic? | playbook paradigms #6/#7; gateway BLOCKER-2, MINOR-1; feedback-divergences "Restart-safe billing" |
| 02 | Concurrency & race conditions | Do concurrent txns/claims/pods race? MVCC, `FOR UPDATE SKIP LOCKED`, advisory locks, optimistic-concurrency guards. | gateway BLOCKER-3, MAJOR-1, Rebuttal (a)/(d); playbook paradigm #8 |
| 03 | Graceful shutdown & drain | Does a new worker/async loop participate in SIGTERM drain? No orphaned in-flight work, no double-run. | gateway BLOCKER-2; playbook paradigm #9 |
| 04 | Rate limiting & per-org fairness | Per-key RPM enforced on new public surface? Per-org queue fairness? QoS signals correct? Unbounded uploads? | gateway MAJOR-1/2/3, Rebuttal (a); feedback-divergences QoS rows |
| 05 | Billing & state-machine integrity | Same-txn finalize? Terminal status always written? No double-bill? State-machine leaks? | gateway BLOCKER-2 notes, MINOR-3, Rebuttal notes; feedback-divergences "Billing conflict resolution" |
| 06 | Storage & content residency | Where does content live? Encryption correct (SSE-S3 vs app crypto)? Retention bounded? Sweep covers orphan generations? | gateway BLOCKER-1, MAJOR-4, MAJOR-7; feedback-divergences ADR 0002→0003→0004 |
| 07 | Schema, migrations & CHECK constraints | V-number collision with main? CHECK constraint dropped/re-added on enum change? `CONCURRENTLY`? Re-cut above Flyway head? | gateway NIT-2; feedback-divergences schema section; playbook Migration PR path |
| 08 | Wire/contract conformance | OpenAI-exact wire? `total != completed+failed`? `canceled`/`cancelled` spelling? 4xx vs 5xx recoverability? | gateway MAJOR-4, Rebuttal (f); feedback-divergences OpenAI vocab, `request_counts.failed` folding |
| 09 | Multi-repo & deploy ordering | Companion PRs land as a set? Migration-before-app? V-number collision across concurrent PRs? helm catalog compat? | playbook Dependency Cross-Checks; feedback-divergences V43/V44 renumbering |
| 10 | SSRF, redaction & security boundaries | Client URLs through `validateAndPinUrl`? Sensitive headers in redaction allowlist? Ownership-before-discard (IDOR)? | playbook paradigms #4/#5/#8; playbook conventions "SSRF isolation", "Header redaction allowlist", "Ownership-before-discard" |
| 11 | Test coverage & CI gates | DB-backed tests opt-in? Reproduce-the-bug test? SSRF reject path exercised? Workflow stands up real postgres? | gateway MAJOR-5, MAJOR-7 sub-point; playbook paradigm #2; feedback-divergences "Stateful failure-matrix testing" |
| 12 | Code smell, naming & correctness-detail | Misleading const name? Missing partial index? Repeated re-stamp? BOM gap in JSONL parser? `Utc::now()` vs injected clock? | gateway NIT-1/2/3, MINOR-4, Rebuttal (f) BOM; feedback-divergences `MAX_ATTEMPTS`→`MAX_DET_FAILURES` |

## The 6 codebase-intelligence backends (use these to GROUND every fix suggestion)

You MUST connect each paradigm to the specific backend that validates or
applies it. NEVER say "use code intelligence" abstractly — name the backend
and the exact query shape. Fixes are SUGGESTED ONLY, never auto-committed.

### 1. CodeGraph (CLI) — verbatim source + call paths
- Per-repo SQLite indices at `~/<provider>/{app,gateway,operator}/.codegraph/`.
- **Usage from inside a repo:** `codegraph explore "how does createSource enforce CHECK constraints"`
- **Usage from anywhere:** `codegraph explore -p ~/<provider>/gateway "trace the BATCH worker shutdown drain path"`
- **NEVER** run bare `codegraph explore` from `~/<provider>/` (root index is stray scripts).
- Use for: "show me the sibling code that does X right", "trace the call path from route→finalize",
  "what does `createSource` actually enforce".

### 2. Semble (MCP `semble_search` / `semble_find_related`)
- Embedding + BM25, indexes on first query, caches automatically.
- Use for: "where is auth handled?", "find code similar to this error pattern", vague natural-language lookup.
- Faster than grep+read, ~98% fewer tokens.

### 3. Serena (MCP) — symbol-level IDE ops
- `find_symbol`, `find_referencing_symbols`, `find_declaration`, `find_implementations`.
- `rename_symbol`, `safe_delete_symbol`, `replace_symbol_body`, `insert_before/after_symbol`.
- `get_diagnostics_for_file`, `get_symbols_overview`.
- Use for: cross-file rename correctness, "who calls this", safe-delete impact, type-error hover.
- **CRITICAL for fix-suggestion paths**: when a paradigm names a symbol (e.g. "createSource"),
  Serena `find_symbol` is the canonical way to confirm it exists and locate its definition.

### 4. codebase-memory (MCP) — Cypher graph + complexity metrics
- Indexed projects: `app` (87.5k nodes), `app-backend`, `app-client`, `gateway` (6.8k),
  `operator` (1.5k), `helm` (6.8k), `<provider>-python`, `e2e`.
- `search_graph` (BM25 / name_pattern / semantic_query), `trace_path` (calls / data_flow / cross_service),
  `query_graph` (Cypher), `get_code_snippet`, `get_architecture`.
- Use for: multi-hop call chains, cross-service HTTP edges (gateway→app), complexity
  (`transitive_loop_depth`, `linear_scan_in_loop`), ADRs, runtime traces.
- **Note**: app is indexed twice — query `home-mateo.delriolanse-<provider>-app` (full)
  unless you specifically need the subdir slice.
- **Stale relative to recent changes** — run `detect_changes` if queries seem outdated.

### 5. graphify (CLI) — community detection + semantic hyperedges
- Merged graph at `~/<provider>/graphify-out/graph.json` (union of app/gateway/operator, `repo` tags).
- `graphify query "<q>"` from `~/<provider>/` (merged) or `--graph ./<repo>/graphify-out/graph.json` (per-repo).
- Use for: "what are the main modules/god nodes", community structure, semantic doc↔code links,
  `GRAPH_REPORT.md` broad map.
- **NOT cross-repo edges** — graphify merge is union-only. For real gateway→app HTTP edges use codebase-memory `cross-repo-intelligence`.
- **Maintenance**: after code changes run `graphify update ./<repo>/` (small repos) or
  `--no-cluster` (app — large), then re-merge. `--backend <provider> --mode deep --force` only for doc-rich semantic re-extract.

### 6. agentmemory (MCP `memory_smart_search` / `memory_recall`)
- Persistent across sessions; past decisions, discoveries, patterns, lessons.
- Use for: "did we already decide X in a prior session", "what did we learn about this race".
- **Search before re-deriving.** Dedup rules apply.

## Your output contract (every worker writes the SAME shape)

Write your sector extract to `~/<provider>/docs/andrea-review-sectors/sector-<NN>-<slug>.md`.

Structure (use these exact headings):

```markdown
# Sector NN — <Name>

## Scope
One paragraph: the review concern this sector owns, the question it asks of
every PR, and where its boundaries are (what it deliberately does NOT cover,
which other sector owns that).

## Paradigms (N entries)

### P-NN-1: <imperative name, e.g. "Require a deterministic re-arm gate key">

**Paradigm statement** — 1–3 sentences, imperative voice, what the reviewer
checks and why it matters. Concrete enough that an agent can apply it without
re-reading Andrea's comments.

**Source evidence** — cite the exact source: file + line or section. E.g.
`gateway.md BLOCKER-2`, `playbook paradigm #6`, `feedback-divergences "Restart-safe billing"`.
Quote the load-bearing sentence (≤1 line).

**<Provider> infra anchor** — name the concrete file/symbol/table/route where
this convention lives in the codebase TODAY. E.g.
`src/batch/billing.rs:127` (`finalize_success` idempotence guard `AND attempt = $9`),
`src/services/clientEgress.ts:103` (`validateAndPinUrl`), `tbl_chat_sources` CHECK constraints.

**Codebase-intelligence backend** — which of the 6 backends an agent should use
to check this, and the exact query shape. E.g.:
> `codegraph explore -p ~/<provider>/gateway "trace claim_requests FOR UPDATE SKIP LOCKED path"`
> → Serena `find_referencing_symbols` on `finalize_success` to confirm all callers pass `attempt`.
> If a re-arm gate is suspected, `semble_search "idempotency fingerprint HMAC"` to locate siblings.

**Fix-suggestion policy** — the suggested fix shape (never auto-applied):
> SUGGEST ONLY: open a finding on the PR describing the gate-key drift; cite the
> canonical sibling (`createSource`, `validateAndPinUrl`); do NOT commit a patch.
> The PR author owns the fix.

**Adversarial caveat** — the strongest reason this paradigm might be wrong,
over-applied, or a false positive in some case. One sentence. (The adversarial
pass uses these; honest caveats now save a round-trip later.)

### P-NN-2: ...
(repeat; aim for 3–7 paradigms per sector — depth over count)

## Cross-sector links
- Which other sectors share evidence with this one (e.g. "shares BLOCKER-2
  evidence with Sector 03 Graceful-shutdown and Sector 05 State-machine").
- Any paradigm that arguably belongs in another sector — flag it, the dedup
  pass will adjudicate.

## Sector-specific failure modes
2–4 bullets: the ways an automated agent applying this sector can go wrong —
e.g. "flagging a deterministic formula as a bug when the jitter is genuinely
unneeded", "treating `FOR UPDATE SKIP LOCKED` as a hard cap when MVCC still
allows count races". Agents will be graded on avoiding these.
```

## Hard rules

1. **Ground every paradigm.** No paradigm without source evidence AND a
   <Provider> infra anchor. If you can't find the anchor, say so and name
   the backend + query that *would* find it.
2. **Name the backend.** Every paradigm names ≥1 of the 6 backends with the
   exact query shape. "Use code intelligence" is not an answer.
3. **Suggest fixes, never commit.** Every paradigm's fix-suggestion policy
   ends with the PR author owning the fix. No auto-apply, no `edit`/`write`
   to source files, no `git commit`. This is the non-negotiable constraint.
4. **Adversarial honesty.** Every paradigm carries its own strongest
   counter-argument. The adversarial pass will stress-test these; weak
   caveats now mean a paradigm gets cut later.
5. **Stay in your sector.** If a paradigm belongs in another sector, flag it
   in Cross-sector links, don't write it in full.
6. **Read the playbook + your primary sources first.** Do NOT skim. The
   gateway.md audit is 232 lines of item-by-item evidence; feedback-divergences
   is 192 lines of design-review reasoning. Both are load-bearing for most
   sectors.
7. **No codebase auto-modification.** You are a read-only extraction worker.
   The only file you write is your sector extract. You MAY run read-only
   `codegraph explore`, `semble_search`, Serena `find_symbol`, codebase-memory
   `search_graph` to confirm infra anchors — in fact you SHOULD, to ground
   your anchors. You MAY NOT `edit`/`write` source files, run `git`, or
   dispatch fix agents.

## Deliverable

One file at `~/<provider>/docs/andrea-review-sectors/sector-<NN>-<slug>.md`
following the structure above. 3–7 paradigms, each fully grounded. The
orchestrator will dedup, validate (cross-check each infra anchor against the
live backends), adversarially refine, and assemble the final playbook.

# Andrea Review Playbook — 12-sector PR review

This is the playbook that the `andrea-review` skill dispatches. It defines
12 review sectors (lenses), the cross-cutting rules every sector obeys, and
the requirement that every finding be grounded against live code via the
codebase-intelligence backends available on the machine.

The partition is by **review concern**, not by file. A finding can touch
one file yet fall under three sectors (a migration's CHECK constraint is
Schema/Sector-7; its V-number collision is Wire/Sector-8; its deploy
ordering is Multi-repo/Sector-9). Keep sector boundaries crisp — overlap
is fine if the *lens* differs; the dedup pass merges redundant wording.

## The 12 sectors

| # | Sector | Core question |
|---:|---|---|
| 01 | Idempotency & re-arm gates | Does every retry/re-run/webhook re-delivery re-fire when it should and not duplicate when it shouldn't? Is the gate key deterministic? |
| 02 | Concurrency & race conditions | Do concurrent txns/claims/pods race? MVCC, `FOR UPDATE SKIP LOCKED`, advisory locks, optimistic-concurrency guards. |
| 03 | Graceful shutdown & drain | Does a new worker/async loop participate in SIGTERM drain? No orphaned in-flight work, no double-run. |
| 04 | Rate limiting & per-tenant fairness | Per-key RPM enforced on new public surface? Per-tenant queue fairness? QoS signals correct? Unbounded uploads/queues? |
| 05 | Billing & state-machine integrity | Same-txn finalize? Terminal status always written? No double-bill? State-machine leaks? |
| 06 | Storage & content residency | Where does content live? Encryption correct (SSE-S3 vs app crypto)? Retention bounded? Sweep covers orphan generations? |
| 07 | Schema, migrations & CHECK constraints | V-number collision with main? CHECK constraint dropped/re-added on enum change? `CONCURRENTLY`? Re-cut above migration head? |
| 08 | Wire/contract conformance | OpenAI-exact wire (if OpenAI-compatible)? `total != completed+failed`? Spelling consistency? 4xx vs 5xx recoverability? |
| 09 | Multi-repo & deploy ordering | Companion PRs land as a set? Migration-before-app? V-number collision across concurrent PRs? Catalog/helm compat? |
| 10 | SSRF, redaction & security boundaries | Client URLs through a validator that pins resolves? Sensitive headers in redaction allowlist? Ownership-before-discard (IDOR)? |
| 11 | Test coverage & CI gates | DB-backed tests opt-in? Reproduce-the-bug test? Security reject path exercised? Workflow stands up real dependencies? |
| 12 | Code smell, naming & correctness-detail | Misleading const name? Missing partial index? Repeated re-stamp? BOM gap in JSONL parser? `Utc::now()` vs injected clock? |

## Sector definitions

Each sector below gives the core question, the paradigms an agent applies
(imperative voice, generic — apply to the code under review, not to any
specific codebase), the backend-grounding guidance, and the failure modes
that trip an automated pass.

### Sector 01 — Idempotency & re-arm gates

**Scope:** every retry, re-run, webhook re-delivery, and replay path. Does
re-execution produce the same outcome without duplicate side effects? Is
the dedup/gate key deterministic across retries?

**Paradigms:**
- P-01-1: Require a deterministic re-arm gate key. A retry keyed on a
  non-deterministic value (wall clock, random) can re-fire a settled
  action or skip a legitimate one. The key must be a stable function of
  the request identity.
- P-01-2: Guard the terminal transition, not just the happy path. The
  idempotence check must reject a second finalize that would double the
  side effect; a no-op on the already-terminal case is correct.
- P-01-3: Carry the causal signal through every retry hop. An abort
  signal, correlation id, or expected-version must propagate into the
  retry, not be dropped and re-derived.
- P-01-4: Distinguish first-create from update-retry. The optimistic
  version re-asserted on a first-create retry (often `0`) is wrong for an
  update-retry; re-read and re-assert the *new* version after a conflict.

**Backend grounding:** locate the finalize/settle function via
`semble_search "<settle> idempotence AND attempt no-op"`; confirm its
guard with Serena `find_symbol` on the settle symbol and
`find_referencing_symbols` to check every caller passes the gate key;
`read` the `file:line` to byte-confirm the `AND attempt = $N`-style guard.

**Failure modes:**
- Flagging a deterministic formula as a bug when the jitter is genuinely unneeded.
- Treating a row-disjoint lock (`FOR UPDATE SKIP LOCKED`) as a count cap.
- Demanding an advisory lock where `SKIP LOCKED` already provides row disjointness.

### Sector 02 — Concurrency & race conditions

**Scope:** concurrent transactions, claim queues, pod scheduling, optimistic
concurrency. Do parallel actors produce a correct result without
double-claiming, lost updates, or count races?

**Paradigms:**
- P-02-1: Distinguish row-disjoint locks from count-disjoint locks.
  `FOR UPDATE SKIP LOCKED` gives row disjointness (each txn locks a
  different row); an advisory lock serializes a check-then-insert. Do not
  demand one where the other already covers the invariant.
- P-02-2: Guard the check-then-insert with a count-disjoint lock. A cap
  enforced by a CTE read then insert can be overshot by concurrent txns;
  serialize the check-then-insert with an advisory lock or a unique
  constraint.
- P-02-3: Re-assert optimistic version on every write. An update without
  `WHERE expected_version = $N` silently clobbers a concurrent writer;
  the conflict must surface, not be absorbed.
- P-02-4: Bound the retry on conflict. Optimistic-concurrency retries must
  re-read, re-assert, and re-write — and must cap the loop.

**Backend grounding:** trace the claim path via
`semble_search "claim FOR UPDATE SKIP LOCKED path"`; confirm
the xact-lock is inside `tx.commit()` by reading the call site; for the
optimistic guard, `semble_search "expected_version conflict retry"` and
Serena `find_referencing_symbols` on the update to check every caller
passes the version.

**Failure modes:**
- Demanding `pg_advisory_xact_lock` where `SKIP LOCKED` already gives row disjointness.
- Treating MVCC visibility as a serialization guarantee.
- Flagging a no-lock read that is genuinely read-only.

### Sector 03 — Graceful shutdown & drain

**Scope:** SIGTERM/SIGINT handling, worker drain, async-loop participation.
Does new concurrency participate in shutdown, or does it orphan in-flight
work?

**Paradigms:**
- P-03-1: Every worker/loop joins the shutdown. A spawned task whose
  handle is dropped on shutdown is orphaned; await it with a bounded
  timeout.
- P-03-2: Bound the drain strictly under the grace period. A 30s drain
  timeout against a 30s `terminationGracePeriodSeconds` gets SIGKILLed
  mid-drain; the drain must complete strictly before the grace period.
- P-03-3: Forward abort signals into upstream I/O. A drain that aborts
  the local loop but lets an upstream HTTP call continue wastes the
  upstream work; forward the signal.
- P-03-4: Prefer the stdlib cancellation primitive until you have ≥2
  distinct cancellation scopes. An `AtomicBool` is sufficient for a
  single cancel-everything scope; `CancellationToken` is justified only
  when you need hierarchical cancel-this-subtree-but-not-that-one.

**Backend grounding:** `semble_search "graceful_shutdown SIGTERM await
handle timeout"`; Serena `find_referencing_symbols` on the shutdown handle
to confirm every spawned task is awaited; `read` the main/entry point to
byte-confirm the bounded timeout.

**Failure modes:**
- Demanding `CancellationToken` for a single cancel scope (over-engineering).
- Flagging a dropped handle that is genuinely fire-and-forget (logging, metrics).

### Sector 04 — Rate limiting & per-tenant fairness

**Scope:** per-key RPM, queue depth, QoS signals, unbounded admission. Does
a new public surface enforce a limit, and is the limit fair across tenants?

**Paradigms:**
- P-04-1: Resolve the tenant before the concurrency gate. An unauthenticated
  caller can fill the queue before auth resolves; resolve the org/key,
  then acquire the slot.
- P-04-2: Bound the queue depth. An unbounded semaphore admits until OOM;
  cap the queue and reject with 429 above the cap.
- P-04-3: Partition fairness by the tenancy key. A global FIFO starves a
  noisy tenant's quiet neighbor; partition the claim by org/key.
- P-04-4: Surface QoS signals that match the actual backpressure. A 429
  with no retry-after, or a 200 with a queue-full body, misleads the
  client.

**Backend grounding:** `semble_search "resolve before
semaphore concurrency gate"` to confirm resolve precedes `try_acquire`;
`semble_search "queue depth cap 429 retry-after"` to locate the limiter.

**Failure modes:**
- Demanding a per-key limit on an unauthenticated health route.
- Flagging a global semaphore that is genuinely single-tenant.

### Sector 05 — Billing & state-machine integrity

**Scope:** finalize/settle paths, terminal status, double-bill, state
machine leaks. Does the billing transition atomically and terminally?

**Paradigms:**
- P-05-1: Finalize and advance the state machine in one transaction. A
  finalize that writes the charge then crashes before the status flip
  leaves a chargeable row non-terminal; both writes commit together or
  not at all.
- P-05-2: Every terminal transition writes a terminal status. A
  state-machine swap without a terminal status leaks a chargeable row
  that no further transition will close.
- P-05-3: No double-finalize. The finalize must be idempotent on the
  already-terminal case (no-op), not a re-charge.
- P-05-4: Sweep covers orphan generations. A reclaim/sweep that deletes
  only committed attempts orphans reclaim-lost generations; sweep the full
  attempted range.

**Backend grounding:** `semble_search "finalize SET status terminal
terminal_at one txn"`; Serena `find_symbol` on the finalize function and
`find_referencing_symbols` to confirm every caller is inside a tx;
`read` the state enum's `is_terminal()`.

**Failure modes:**
- Flagging a non-terminal row that is genuinely in-flight (not leaked).
- Treating a committed-then-rolled-back write as a leak (the txn rolled back).

### Sector 06 — Storage & content residency

**Scope:** where content lives, encryption choice, retention bounds, sweep
coverage. Is the storage choice correct for the content's sensitivity and
lifecycle?

**Paradigms:**
- P-06-1: Match the encryption to the residency. SSE-S3 for
  server-managed-at-rest is fine for opaque blobs; content the app must
  not be able to read needs app-layer crypto, not just SSE.
- P-06-2: Bound retention explicitly. Unbounded retention is a cost and
  privacy leak; every stored object needs a retention rule or a sweep.
- P-06-3: Sweep covers every generation. A generation-tagged object that
  is superseded but not swept leaks storage and potentially stale content.
- P-06-4: Ownership before discard. Discarding content the caller does
  not own is an IDOR; check ownership before delete/discard.

**Backend grounding:** `semble_search "encryption SSE-S3 app crypto
retention sweep"`; `semble_search "delete ownership check
discard"`; `read` the storage ADR if one exists.

**Failure modes:**
- Demanding app-layer crypto for opaque blobs SSE already covers.
- Flagging unbounded retention that is genuinely a user-owned store with explicit TTLs elsewhere.

### Sector 07 — Schema, migrations & CHECK constraints

**Scope:** migration versioning, CHECK constraints, `CONCURRENTLY`, re-cut
above head. Does the schema change land safely and ordered?

**Paradigms:**
- P-07-1: No V-number collision with main. A migration numbered to collide
  with main's head blocks the PR on rebase; check the head before numbering.
- P-07-2: Re-add CHECK constraints on enum changes. Dropping a CHECK to
  change an enum and forgetting to re-add it leaves an unconstrained
  column.
- P-07-3: Use `CONCURRENTLY` for online index creation on large tables.
  A blocking `CREATE INDEX` locks the table; `CONCURRENTLY` avoids the
  lock at the cost of a longer build.
- P-07-4: Add a partial index for hot-path predicates a re-cut introduces.
  A new hot-path filter predicate without an index becomes a seq scan on
  the hot path; add the partial index when the predicate is selective.

**Backend grounding:** migration files are DDL, not code symbols — Serena
and graph backends do not index them; `grep -rn "CREATE INDEX
<column>" <migrations-dir>` and `read` the migration SQL directly.

**Failure modes:**
- Demanding a partial index where a heap scan is cheaper (premature optimization).
- Looking for an index in the code checkout when it lives in a separate migrations repo.

### Sector 08 — Wire/contract conformance

**Scope:** API wire shape, status code semantics, spelling, 4xx vs 5xx
recoverability. Does the contract match what clients expect?

**Paradigms:**
- P-08-1: Match the wire shape exactly (OpenAI-compatible APIs). A
  `total` that is not `completed + failed` breaks clients that assert the
  invariant; either the invariant holds or the field is renamed.
- P-08-2: Spelling consistency across the wire. `canceled` vs `cancelled`
  in the same response body is a client-parser hazard; pick one and use
  it everywhere.
- P-08-3: 4xx for client-recoverable, 5xx for server faults. A 4xx tells
  the client to change the request; a 5xx tells it to retry. Mislabeling
  burns client retry budget on unrecoverable requests.
- P-08-4: Sign webhooks with a timing-safe HMAC over the raw body.
  Replay and tamper protection require a raw-body HMAC + a timestamp
  window + constant-time compare. The security properties matter; the
  exact header naming is secondary as long as it's consistent.

**Backend grounding:** `semble_search "webhook signature
verify HMAC raw body constant time"`; `semble_search "total completed
failed canceled"`; `read` the response serializer.

**Failure modes:**
- Demanding the full Standard Webhooks spec where a Stripe-style HMAC gives the same security properties.
- Flagging a spelling mismatch that is genuinely in a docstring not the wire.

### Sector 09 — Multi-repo & deploy ordering

**Scope:** companion PRs across repos, migration-before-app, catalog/helm
compat, cross-repo V-number collision. Does the multi-repo change land as a
coordinated set?

**Paradigms:**
- P-09-1: Companion PRs land as a set. A gateway change that depends on
  an app migration is broken if the app PR merges first without the
  gateway; coordinate the merge order or use feature flags.
- P-09-2: Migration before app. The app code that assumes the new schema
  must not deploy before the migration runs.
- P-09-3: No cross-repo V-number collision. Concurrent PRs in
  `repo` and `repo-db` can pick the same migration number; coordinate
  across repos.
- P-09-4: Catalog/helm version compatibility. An ArgoCD/helm auto-deploy
  on an image-yaml bump deploys on merge; the review gate is CODEOWNERS,
  not the deploy.

**Backend grounding:** cross-service edges are the only real multi-repo
signal — use codebase-memory `trace_path cross_service` on indexed repos;
for un-indexed repos, `read` the routes/channels directly. Do NOT trust a
union graph for inferred cross-repo edges.

**Failure modes:**
- Running `trace_path cross_service` on an un-indexed repo and concluding "no edges exist" (the repo isn't indexed, not the edges are absent).
- Trusting a merged graph for cross-repo HTTP edges (merged graphs are union-only).

### Sector 10 — SSRF, redaction & security boundaries

**Scope:** client-supplied URLs, sensitive-header redaction, ownership
before discard. Does the code trust the caller appropriately at every
boundary?

**Paradigms:**
- P-10-1: Validate and pin client-supplied URLs. A client URL fetched
  server-side without validation is an SSRF vector; resolve, pin the
  resolved IP, and reject private ranges.
- P-10-2: Redaction allowlist for sensitive headers. A redactor that
  strips headers by default must explicitly allowlist the sensitive ones,
  not the reverse.
- P-10-3: Ownership before discard (IDOR). Delete/discard must check the
  caller owns the resource; an unauthenticated discard is an IDOR.
- P-10-4: Constant-time compare for secrets. A signature/token compare
  that short-circuits leaks via timing; use constant-time.

**Backend grounding:** `semble_search "validateUrl pin resolve reject
private"`; Serena `find_symbol` on the URL validator and
`find_referencing_symbols` to confirm every client-URL fetch goes
through it; `read` the redaction allowlist.

**Failure modes:**
- Demanding a private-range reject on a route that genuinely accepts intranet URLs.
- Flagging a non-constant-time compare on a non-secret value.

### Sector 11 — Test coverage & CI gates

**Scope:** DB-backed tests, reproduce-the-bug tests, security reject paths,
real-dependency workflows. Does the test suite actually exercise the
invariants the code claims?

**Paradigms:**
- P-11-1: DB-backed tests must opt in. A test that hits the DB without
  marking itself DB-backed pollutes the fast suite; opt-in marker, separate
  job, or a testcontainer.
- P-11-2: Reproduce the bug, then fix. A fix without a failing test first
  is unverifiable; write the test that reproduces, then the fix.
- P-11-3: Exercise the security reject path. A validator that has happy-
  path tests but no reject-path test is untested for the case that matters.
- P-11-4: Stand up real dependencies in the workflow. A test that mocks
  postgres does not catch a postgres-specific bug; use a real postgres
  (testcontainer, service container) for DB-backed tests.

**Backend grounding:** test files are code — `semble_search "test
reject path assert throws"`; `grep -rn "testcontainer\|service:
postgres" <ci-dir>`; `read` the workflow YAML.

**Failure modes:**
- Demanding a real-postgres test for logic that is pure SQL string building.
- Flagging a mock that is genuinely at a stable boundary.

### Sector 12 — Code smell, naming & correctness-detail

**Scope:** misleading names, missing indexes, repeated re-stamps, BOM
gaps, injected-clock correctness. The small things that are real defects
on non-load-bearing paths.

**Paradigms:**
- P-12-1: No misleading constant name. A `MAX_ATTEMPTS` that caps
  detection failures (not attempts) misleads every reader; rename to
  match what it caps.
- P-12-2: No repeated re-stamp. An `updated_at = now()` on a row that
  should not move hides the real last-write; only stamp on real writes.
- P-12-3: Handle the BOM in JSONL parsers. A JSONL parser that splits on
  `\n` without handling a leading BOM mis-parses the first line.
- P-12-4: Inject the clock; don't call `now()` inline. A `Utc::now()` in
  business logic is untestable; inject the clock so tests can control time.

**Backend grounding:** `semble_search "MAX_.* constant rename"`; `grep -rn
"BOM\|utf-8-sig\|ByteOrderMark"`; Serena `find_symbol` on the clock
injection site and `find_referencing_symbols` to confirm every caller
passes the injected clock.

**Failure modes:**
- Demanding clock injection for a metric timestamp that is genuinely log-only.
- Flagging a repeated re-stamp that is the intended audit signal.

## Cross-cutting rules (every sector obeys)

- **CR-1: Re-ground before citing.** Re-verify every `file:line` anchor
  against live code before citing it. A stale anchor is a false-positive
  risk. Re-grounding order: `semble_search` → Serena `find_symbol` (scoped)
  → `read`.
- **CR-2: Suggest, never commit.** Every finding's fix is a patch *shape*,
  not a patch. The PR author owns the fix. No auto-apply, no `edit`/`write`
  to source, no `git commit`.
- **CR-3: Be worktree-aware.** A feature branch may live in a worktree
  whose code is absent from the main checkout's index. Verify anchors
  against the actual working tree under review; for worktree-only symbols,
  use `read` or `semble_search repo=<worktree>`.
- **CR-4: A recorded deferral is a decision, not a finding.** Do not
  re-raise a deferred issue unless the rationale no longer holds. Check
  agentmemory for prior deferral rationales before re-raising.
- **CR-5: Read-only workers.** Sector agents never modify source. The
  only output is the finding list.
- **CR-6: Never auto-commit.** (Restated from CR-2 for emphasis: the
  skill never commits; the PR author does.)
- **CR-7: Scope gate — origin classification.** Every finding carries
  `origin` (`introduced_by_pr`|`pre_existing`|`unknown`) and
  `origin_confidence`. Apply the paradigm only to code the diff touches;
  pre-existing issues are reported but do not block.

## Backend binding (summary)

Every finding must name the backend that confirmed it and the query used.
Not all backends are installed on every machine — use what's available,
fall back through the re-grounding order (CR-1). The requirement is live
verification; the backend is the means.

| Backend | When | Canonical query |
|---|---|---|
| Semble (MCP) | Vague natural-language lookup | `semble_search "<desc>"` / `semble_find_related` |
| Serena (MCP) | Symbol confirm, references | `find_symbol` (scoped), `find_referencing_symbols` |
| codebase-memory (MCP) | Multi-hop, cross-service, Cypher, complexity | `search_graph`, `trace_path`, `query_graph` |
| graphify (CLI) | Communities, god nodes, broad map | `graphify query "<q>"` |
| agentmemory (MCP) | Past-session decisions, deferral rationales | `memory_smart_search`, `memory_recall` |

## Severity bar

- **BLOCKER** leaks money/data or breaks the contract.
- **MAJOR** is a real defect on a load-bearing path.
- **MINOR** is a real defect on a non-load-bearing path.
- **NIT** is naming, a missing index, or a cosmetic correctness detail.

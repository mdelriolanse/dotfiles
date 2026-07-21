# Sector 02 — Concurrency & race conditions

## Scope

This sector owns the question Andrea asks of every PR that touches shared
state: **do concurrent transactions, claims, or pods race?** It covers
multi-transaction count-vs-row-disjoint claims, `FOR UPDATE SKIP LOCKED`
semantics, advisory locks (session vs xact), optimistic-concurrency
guards, multi-pod oversubscription, and per-org vs physical-resource
keying. It deliberately does NOT own idempotency gate-key determinism
(→ Sector 01), graceful-shutdown drain (→ Sector 03), per-key RPM
enforcement (→ Sector 04), or state-machine terminal-status leaks
(→ Sector 05) — though the *concurrency mechanism* under several of
those is grounded here and cross-linked.

## Paradigms (6 entries)

### P-02-1: A per-process counter is not a fleet-wide QoS signal

**Paradigm statement** — When a correctness property (a concurrency cap,
a "quiet" tier, an oversubscription guard) is derived from a counter
held in process memory, the reviewer must ask: *what keeps that counter
consistent across replicas?* If the answer is "nothing" (a `DashMap`, an
`AtomicUsize`, an in-memory semaphore), the property holds only under an
**unenforced** `replicas: 1` invariant — and an unenforced invariant is a
silent failure waiting for the first horizontal scale event. The fix is
either a fleet-wide shared signal (a SQL clamp, an external
coordinator) or a loud, explicit lock that degrades to a no-op on the
second pod.

**Source evidence** — `gateway.md` BLOCKER-3: *"`AppState.interactive_in_flight` is per-process; `slots.rs:6` computes cap from it; `claim_requests` clamps only to caller's own limit. Two pods each read 'quiet' and oversubscribe."* Rebuttal (a) reinforces it: Andrea's conclusion (no split) was right but her reasoning (co-location) was wrong — "co-location doesn't make QoS correct; singleton-ness does, unenforced."

**<Provider> infra anchor** — `src/batch/slots.rs:6`
(`allowed_batch_slots(scheduler_slots, interactive_in_flight)`) computes
the tier purely from the caller-supplied counter; `src/batch/worker.rs:166-171`
reads `state.interactive_in_flight.get(deployment)` — a
`dashmap::DashMap` (declared `Arc::new(dashmap::DashMap::new())` at
`worker.rs:881`, `reaper.rs:223`, `preflight.rs:811`, `batches.rs:629`,
`files.rs:523`). The `AppState` field docstring (surfaced via semble) states
explicitly: *"In-process counter — exact while the gateway runs
single-replica."* That single-replica assumption is the load-bearing,
unenforced invariant.

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/gateway "trace advisory lock claim path"` → confirms `interactive_in_flight` is read by `drain_deployment`'s tick loop, not by any cross-pod path.
> `semble_search "pg_advisory_xact_lock per-org atomic create cap"` with `repo=~/<provider>/worktrees/batch-api/feat-batch-api-gateway` → surfaces both the `create_batch_capped` canonical hard-cap sibling and the `interactive_in_flight` docstring that admits the single-replica assumption.
> Serena `find_symbol` on `allowed_batch_slots` to confirm it is a pure function of its arguments (no fleet state).

**Fix-suggestion policy** —
> SUGGEST ONLY: open a finding on the PR naming the per-process counter and the unenforced `replicas: 1`; cite the sibling (`create_batch_capped`'s `pg_advisory_xact_lock`) as the fleet-wide pattern; require either a documented/checked singleton invariant or a shared tier signal. Do NOT commit a patch. The PR author owns the fix.

**Adversarial caveat** — If the deployment is *genuinely* and *durably* pinned to `replicas: 1` (a pod-disruption-budget of min-available 1, a helm value with a CEL admission gate, a NetworkPolicy that makes a second pod unschedulable), the per-process counter is correct and adding a SQL fleet clamp is dead weight. The paradigm is only a real finding when the singleton invariant is asserted but not enforced — the smell is the *gap*, not the in-process counter itself.

---

### P-02-2: A CTE-inlined `count(*)` is not a hard cap under MVCC; distinguish row-disjoint from count-disjoint locks

**Paradigm statement** — Under Postgres MVCC, two concurrent
transactions each read the *same* `count(*)` snapshot and both proceed;
a `count(*) < N` guard inlined into a CTE is a **coarse pre-check, not a
hard ceiling**. A true hard cap needs a lock that serializes the
check-then-act: `pg_advisory_xact_lock` (per-transaction, auto-released
at commit/rollback) for count-based caps, or `FOR UPDATE SKIP LOCKED`
for **row-disjoint** claims (each txn locks different rows, so they
don't contend on the count). The reviewer must name which kind of
disjointness the claim relies on and confirm the SQL provides it —
conflating the two is the classic MVCC race.

**Source evidence** — `gateway.md` BLOCKER-3 notes: Mateo's rebuttal
*"the 'inline subquery into CTE LIMIT' does NOT yield a hard cap under
MVCC (two concurrent txns read same count, both claim); a true hard cap
needs `pg_advisory_xact_lock` per-deployment (the `create_batch_capped`
pattern)"* — verdict **ADDRESSED (rebuttal verified true)**. The audit
confirms: *"a CTE-inlined `count(*)` subquery would indeed not be a hard
cap under MVCC."*

**<Provider> infra anchor** — `src/batch/store.rs:211`
(`SELECT pg_advisory_xact_lock($1, hashtext($2))` inside
`create_batch_capped`'s transaction — the canonical count-disjoint hard
cap; its docstring at `store.rs:194-200` states *"The lock closes the
check-then-insert race for both caps: concurrent creates for one org
serialize, so each cap is a hard ceiling rather than a coarse
pre-check. Unrelated orgs never contend (the lock key is the org)."*).
Contrast with `src/batch/store.rs:460-475` (`claim_requests`):
`FOR UPDATE OF br3 SKIP LOCKED` — row-disjoint, *not* count-disjoint.
The two patterns coexist precisely because they solve different
disjointness problems.

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/gateway "FOR UPDATE SKIP LOCKED claim_requests"` → confirm `claim_requests` uses row-level locking, no count-based lock.
> codebase-memory `query_graph` (project `home-mateo-delriolanse-<provider>-app-backend`) — `MATCH (n) WHERE n.name CONTAINS 'create_batch_capped' OR n.name CONTAINS 'claim_requests' RETURN n.qualified_name, n.transitive_loop_depth` to gauge whether the claim path is acyclic (the gateway project is not indexed; the query shape is the contract a future gateway index would satisfy).
> Serena `find_symbol` on `create_batch_capped` to confirm the xact lock is inside the `pool.begin()`…`tx.commit()` span (not a session lock).

**Fix-suggestion policy** —
> SUGGEST ONLY: open a finding asking the author to name the disjointness class ("row-disjoint via SKIP LOCKED" vs "count-disjoint via advisory xact lock"); if the PR claims a cap, require the `pg_advisory_xact_lock` sibling and cite `store.rs:211`. Do NOT commit a patch. The PR author owns the fix.

**Adversarial caveat** — For genuinely row-disjoint workloads (each txn
claims a distinct row by PK), `FOR UPDATE SKIP LOCKED` *is* a hard cap
on double-claim of the same row — the paradigm must not be over-applied
to demand an advisory lock where SKIP LOCKED already provides the
needed disjointness. The smell is specifically a *count-based* cap
guarded only by a CTE read, not a row-based claim guarded by SKIP
LOCKED.

---

### P-02-3: Name the advisory-lock class — session vs xact — and match it to the failure mode

**Paradigm statement** — `pg_advisory_lock` (session-level, held until
explicit `pg_advisory_unlock` or session end) and
`pg_advisory_xact_lock` (transaction-scoped, auto-released at
commit/rollback) solve different problems and fail differently. A
session lock turns a silent oversubscription into a **loud no-op** (the
second pod logs and exits) — the right shape for an
enforce-singleton-worker invariant. A xact lock serializes a
check-then-act **within one transaction** — the right shape for a
count-based cap that must be a hard ceiling. The reviewer must confirm
the lock class matches the intent: a session lock used where a xact
lock is needed leaves the cap race open; a xact lock used where a
session singleton is needed releases on every commit and protects
nothing across ticks.

**Source evidence** — `gateway.md` BLOCKER-3: Mateo resolved with a
session-level `pg_try_advisory_lock` before the tick loop; the
`ponytail:` comment at `worker.rs:684-685` records *"session-level
advisory lock; SQL fleet clamp + shared tier signal is the upgrade path
for permanent replicas > 1."* The audit notes Mateo correctly
distinguished: the session lock is "the shorter path for `replicas: 1`"
while `create_batch_capped`'s `pg_advisory_xact_lock` is "the per-xact
pattern he cites as the true hard cap" for count-based caps.

**<Provider> infra anchor** —
- Session lock: `src/batch/worker.rs:693-701` — `SELECT pg_try_advisory_lock($1)` bound `42_i64`, held on the acquired connection for the worker's lifetime; `if !locked { tracing::warn!("another batch worker holds the advisory lock; this pod will not run batch work"); return; }`.
- Xact lock: `src/batch/store.rs:211` — `SELECT pg_advisory_xact_lock($1, hashtext($2))` inside `create_batch_capped`'s `tx` span (begin at `:209`, commit at `:228`); the docstring at `:216` notes *"tx drops on early return → rollback → lock released; nothing inserted."*

The two-class distinction is load-bearing: the worker lock must survive across ticks (session), the create-cap lock must release on commit (xact).

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/gateway "trace advisory lock claim path"` → confirm the session lock at `worker.rs:693` is acquired *before* the tick loop and held on one connection (not per-tick).
> Serena `find_symbol` on `create_batch_capped` → confirm the xact lock is inside the `pool.begin()…tx.commit()` transaction span (the lock class is defined by the span it lives in).
> `semble_search "pg_advisory_xact_lock per-org atomic create cap"` → surfaces the canonical sibling and its docstring naming the class.

**Fix-suggestion policy** —
> SUGGEST ONLY: open a finding on the PR asking the author to state the lock class and the failure mode it addresses; if a count-based cap uses a session lock (or a singleton uses a xact lock), flag the mismatch and cite the sibling (`store.rs:211` for xact, `worker.rs:693` for session). Do NOT commit a patch. The PR author owns the fix.

**Adversarial caveat** — `pg_try_advisory_lock` (non-blocking) silently
returns `false` on contention — which is exactly the desired loud no-op
*if* the loser logs and exits. But if the loser logs and **retries in a
tight loop**, the session lock becomes a busy-spin and a logging storm;
the paradigm must check the loser's behavior, not just the lock's
presence. The worker's `return` (not `continue`) at `worker.rs:700` is
the detail that makes the session lock safe.

---

### P-02-4: The optimistic-concurrency guard must travel to the retry handler, not just the happy path

**Paradigm statement** — An optimistic-concurrency version guard
(`expectedVersion`, `AND attempt = $N`, `AND version = $N`) is worthless
if it is checked on the first attempt but **dropped on the retry**. A
retry that re-reads and re-writes without re-asserting the version can
clobber a concurrent committer. The reviewer walks the *retry* path:
does the conflict handler re-forward `expectedVersion` (or re-bind the
claim generation `attempt`) on the second try? The guard is a
per-attempt contract, not a per-request contract.

**Source evidence** — `andrea-review-playbook.md` paradigm #8 (review
paradigm): *"Check that retries carry the optimistic-concurrency guard.
`expectedVersion` or equivalent must travel to the retry handler, not
just the happy path."* Convention list: *"Optimistic concurrency.
Versioned rows (`tbl_chat_artifacts`, `tbl_chat_drafts`) require
`expectedVersion`; retries must forward it."* Critical code path
(Agentic tool / model-call PR, step 4): *"Optimistic concurrency. Does
a retry or edit carry `expectedVersion`? `DraftTextTool.ts`,
`executeTool.ts:470`."*

**<Provider> infra anchor** —
- `app/backend/src/services/insertNextArtifactVersion.ts:86-92` — the guard: `if (params.expectedVersion !== undefined && params.expectedVersion !== currentVersion) throw new ArtifactVersionConflictError(...)`; `:78-82` documents the no-prior-row case ("a caller asserting any specific `expected_version` (>= 1) against a non-existent artifact is stale").
- `app/backend/src/controllers/<provider>Chat.libs/agenticLoop/executeTool.ts:545-586` — the retry handler: reads `args.expected_version` (`:545-548`), forwards `expectedVersion` to the first `insertNextArtifactVersion` (`:559`); on `ArtifactVersionConflictError && actualVersion === 0` it **re-asserts `expectedVersion: 0`** on the retry (`:586`), with a comment (`:573-577`) explaining *"Retry asserting v0 (create) so a concurrent first-create loser still conflicts instead of silently inserting a second version."*
- Gateway sibling (claim-generation guard): `src/batch/billing.rs:127` (`finalize_success`: `AND attempt = $9`) and `src/batch/billing.rs:263` (`finalize_failure`: `AND attempt = $7`); the comment at `:254-257` states the guard "pins the commit to the caller's claim generation… Under a double-reclaim a stale worker no-ops."

**Codebase-intelligence backend** —
> Serena `find_symbol` on `insertNextArtifactVersion` → confirm the `expectedVersion` parameter and the conflict throw; then `find_referencing_symbols` to enumerate every caller and check each forwards the version on retry.
> codebase-memory `search_graph` (project `home-mateo-delriolanse-<provider>-app-backend`, `query="artifact version optimistic concurrency expectedVersion guard"`) → locate sibling guards (`isConcurrencySafe`, upload concurrency limiters) to confirm the convention is repo-wide.
> `semble_search "expectedVersion retry conflict ArtifactVersionConflictError"` with `repo=~/<provider>/app` → find the retry-handler sites.

**Fix-suggestion policy** —
> SUGGEST ONLY: open a finding on the PR tracing the retry path; if the conflict handler re-invokes without re-forwarding `expectedVersion` (or the gateway equivalent `attempt`), flag the dropped guard and cite the sibling (`executeTool.ts:586` re-asserts v0; `billing.rs:127`/`:263` re-bind `attempt`). Do NOT commit a patch. The PR author owns the fix.

**Adversarial caveat** — Some retries are *intentionally* unguarded
because the retry is idempotent by construction (a deterministic
re-arm-key gate, Sector 01) — re-asserting a version there can
dead-loop a legitimate retry against a concurrent committer that will
never yield. The paradigm targets *clobbering* writes (state-machine
flips, versioned artifact saves, claim finalize), not idempotent
re-applies.

---

### P-02-5: Global FIFO starves; partition the claim by the fairness key

**Paradigm statement** — A claim query ordered only by a global
timestamp (`ORDER BY created_at`) lets one tenant's large batch monopolize
a shared deployment and starve a smaller tenant's batch to expiry. The
reviewer asks: *what is the fairness key?* If the claim is global FIFO,
the fix is a single window-function query that ranks rows **within the
fairness partition** (`ROW_NUMBER() OVER (PARTITION BY <fairness_key>
ORDER BY created_at, line_no)`) and claims by rank — not a cursor or a
round-robin state machine, which adds state and a race of its own. The
fairness key is almost always the tenant/org; name it explicitly.

**Source evidence** — `gateway.md` MAJOR-1: *"`claim_requests` is global
FIFO with no per-org fairness… org A's 50k batch starves org B's small
batch to expiry on a shared deployment."* Resolved with
`ROW_NUMBER() OVER (PARTITION BY b.org ORDER BY b.created_at, br2.line_no) AS rn` and `ORDER BY r.rn`. The "Notes on the review" rebuttal
verifies: *"A single window-function query, not a cursor/round-robin
state machine"* — verdict **ADDRESSED (rebuttal verified true)**.

**<Provider> infra anchor** — `src/batch/store.rs:448-451`
(`ROW_NUMBER() OVER (PARTITION BY b.org ORDER BY b.created_at, br2.line_no) AS rn`) and `src/batch/store.rs:472` (`ORDER BY r.rn`) — one
CTE, no new state table. The `ponytail:` comment at `store.rs:470-471`
records the ceiling and upgrade path: *"per-org round-robin within a
claim; per-batch or weighted fair-share is the next axis if orgs submit
many batches."*

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/gateway "FOR UPDATE SKIP LOCKED claim_requests"` → confirm the `PARTITION BY b.org` and `ORDER BY r.rn` are in the same CTE as the `SKIP LOCKED` claim (no separate state).
> Serena `find_symbol` on `claim_requests` → confirm it is a single `query_as` call (one round-trip), not a cursor loop.
> codebase-memory `trace_path` (mode `calls`) from the worker tick → `claim_requests` → `billing.rs` finalize, to confirm the fairness rank survives the claim→finalize span (no re-ordering that would reintroduce global FIFO).

**Fix-suggestion policy** —
> SUGGEST ONLY: open a finding on the PR asking for the fairness key; if the claim is global FIFO, suggest the single `ROW_NUMBER() OVER (PARTITION BY <key>)` query and cite `store.rs:448-472`. Name the next-axis ceiling (per-batch / weighted) only if the org submits many batches. Do NOT commit a patch. The PR author owns the fix.

**Adversarial caveat** — Partition-by-org fairness is *within one
deployment*; if one org has multiple deployments, a per-org rank can
still starve across deployments unless the scheduler also partitions
deployments. And if the fleet runs `replicas: 1` with one org, global
FIFO is correct and the partition adds cost for no fairness gain. The
paradigm fires only when **multiple tenants share one schedulable
resource**.

---

### P-02-6: Atomic multi-org claims are a cross-pod race, not a docs gap — fold them into the singleton finding

**Paradigm statement** — When a reviewer self-flags a concern as "atomic
multi-org claim — docs gap," the right move is to recognize it as the
*same* concurrency finding as the per-process-counter / unenforced-singleton
race, not a separate documentation task. Atomicity holds **within one
process**; across pods it is the oversubscription race (P-02-1). The
reviewer does not open a second ticket for the "atomic claim" wording —
they fold it into the load-bearing concurrency finding and resolve both
with the one fix (the advisory lock or the shared tier signal). Opening
two findings for one root cause dilutes the fix.

**Source evidence** — `gateway.md` Rebuttal (d): *"Atomicity holds within
one process; across pods it's BLOCKER-3. Same finding, not a docs
task."* — verdict **ADDRESSED (folded into BLOCKER-3)**. Rebuttal (a)
reinforces: *"Conclusion right (dedicated worker pod not needed),
reasoning wrong (co-location doesn't make QoS correct; singleton-ness
does, unenforced). See BLOCKER-3."* `feedback-divergences.md` "Worker
concurrency model" row: Andreas wanted *"Atomic, concurrency-aware claim
keyed on physical vLLM upstream (not per org)"*; local docs describe
per-deployment caps but *"do not claim atomic multi-org claim"* — the
admitted gap is the same finding.

**<Provider> infra anchor** — The fold is witnessed in the resolution:
the session advisory lock at `src/batch/worker.rs:693` bounds
oversubscription to **one claimer across pods** (the cross-pod atomicity
that Rebuttal (d) asked for), while `claim_requests` at
`src/batch/store.rs:460-475` retains the within-process `FOR UPDATE SKIP
LOCKED` atomicity. The two mechanisms compose: the advisory lock is the
cross-pod gate, SKIP LOCKED is the within-process row-disjoint gate.
`feedback-divergences.md` "Deployment topology" records the local
rationale: *"`FOR UPDATE SKIP LOCKED` claim is sufficient; brief 2×
concurrency on rolling deploy is safe"* — the accepted residual race.

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/gateway "trace advisory lock claim path"` → confirm the advisory lock wraps the entire tick loop (the cross-pod gate) and `claim_requests` runs *inside* it (the within-process gate).
> codebase-memory `query_graph` for `transitive_loop_depth` on the claim path (project `gateway` once indexed) to confirm the claim→finalize span is acyclic under the composed locks.
> agentmemory `memory_smart_search "cross-pod oversubscription advisory lock"` → check whether a prior session already decided the singleton invariant vs the shared-tier-signal upgrade path.

**Fix-suggestion policy** —
> SUGGEST ONLY: when a PR review surfaces both a "per-process counter" concern and an "atomic multi-org claim — docs gap" concern, open ONE finding that names the shared root cause (cross-pod race on an in-process signal) and the composed fix (session/xact advisory lock + SKIP LOCKED). Do NOT commit a patch. The PR author owns the fix.

**Adversarial caveat** — Folding is correct **only** when the two
concerns share a root cause. If the "atomic multi-org claim" is actually
about a *different* resource (e.g., a shared GPU upstream whose
contention is independent of the worker singleton), folding it into
the worker-count finding hides a real second race. The reviewer must
confirm the two concerns key on the *same* physical resource before
folding; otherwise keep them separate.

## Cross-sector links

- **Shares BLOCKER-2 evidence with Sector 03 (Graceful shutdown) and Sector 05 (State-machine integrity).** The `attempt` claim-generation guard (`billing.rs:127`/`:263`) is the *concurrency* mechanism that makes a stale worker no-op under double-reclaim (this sector, P-02-4), but its *purpose* — no double-billing, no orphaned in-flight row — is the state-machine integrity concern (Sector 05), and the *trigger* — a SIGTERM-dropped worker whose lease the reaper reclaims — is the graceful-shutdown concern (Sector 03). The same `AND attempt = $N` clause is load-bearing for all three lenses; the dedup pass should keep the *mechanism* here and cross-link the *consequence*.
- **P-02-1 (per-process counter) overlaps Sector 04 (Rate limiting & per-org fairness).** The `interactive_in_flight` counter drives the QoS tier (P-02-1's correctness concern) *and* the per-org fairness signal (Sector 04's concern). The lens differs: here it is "is the signal fleet-consistent?"; in Sector 04 it is "does the tier actually enforce fairness?". Flag for dedup — the per-process-counter finding likely belongs here, the fairness-tier semantics there.
- **P-02-4 (optimistic-concurrency guard) is the *mechanism* twin of Sector 01 (Idempotency) P-01.** Sector 01 owns "is the re-arm gate key deterministic?" (the *what*); this sector owns "does the version guard travel to the retry handler?" (the *how*). A webhook re-delivery that re-fires correctly (Sector 01) but drops `expectedVersion` on the retry (this sector) is a single PR with two findings — same evidence, different lens.
- **P-02-6 arguably belongs in Sector 09 (Multi-repo & deploy ordering).** The "atomic multi-org claim — docs gap" folding is partly a *deploy-topology* question (does the worker run as a separate Deployment?). The local team *rejected* the split (`feedback-divergences.md` "Deployment topology"), which is a deploy-ordering decision. The dedup pass may adjudicate that the deploy-topology framing lives in Sector 09 and the concurrency-mechanism framing stays here.
- **`create_batch_capped`'s `pg_advisory_xact_lock` is also a cap-enforcement anchor for Sector 04.** The per-org create cap (`max_batches`, `max_enqueued`) is a rate-limit/fairness concern (Sector 04); the *xact lock that makes it a hard ceiling* is this sector. Cross-link, do not duplicate.

## Sector-specific failure modes

- **Treating `FOR UPDATE SKIP LOCKED` as a hard cap on the *count*.** SKIP LOCKED makes two concurrent claims *row-disjoint* (they lock different rows); it does NOT make them *count-disjoint* (they can each read the same `count(*)` and both proceed past a `LIMIT` derived from a count). An agent that flags "missing advisory lock" on a SKIP LOCKED claim is over-applying P-02-2; an agent that accepts a CTE-inlined `count(*) < N` as a hard cap is under-applying it. The smell is *count-based caps without a count-serializing lock*, not the absence of SKIP LOCKED.
- **Flagging a per-process counter as a bug when the singleton invariant *is* enforced.** If a CEL admission gate, a pod-disruption-budget, or a helm value with a webhook genuinely pins `replicas: 1`, the `DashMap` is correct and a SQL fleet clamp is dead weight. An agent must check whether the `replicas: 1` invariant is *enforced*, not merely *asserted in a docstring*, before opening P-02-1. The `interactive_in_flight` docstring ("exact while the gateway runs single-replica") is an *admission* of the assumption, not proof of enforcement.
- **Demanding a xact lock where a session lock is correct (and vice versa).** The worker singleton needs a *session* lock (held across ticks, loser no-ops); the create-cap needs a *xact* lock (released on commit, serializes the check-then-insert). An agent that reflexively asks for `pg_advisory_xact_lock` on the worker, or `pg_advisory_lock` on the create cap, is mismatching the lock class to the failure mode (P-02-3). The lock class is defined by the span it must survive.
- **Folding two concerns that key on different resources.** P-02-6's fold is correct only when the "per-process counter" and "atomic multi-org claim" concerns race on the *same* physical resource (the worker singleton). If one keys on the worker process and the other on a shared GPU upstream, folding hides a real second race. An agent must confirm the shared root cause before merging findings — otherwise keep them separate even if the wording overlaps.
- **Treating the retry-without-`expectedVersion` as always-wrong.** P-02-4 targets *clobbering* writes. A retry that is idempotent by a deterministic re-arm key (Sector 01) is intentionally unguarded; re-asserting a version there can dead-loop a legitimate retry. An agent must distinguish a clobbering retry (state-machine flip, versioned save) from an idempotent re-apply before flagging the dropped guard.

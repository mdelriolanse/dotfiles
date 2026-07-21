# Sector 04 — Rate limiting & per-org fairness

## Scope

This sector owns the question Andrea asks of every PR that opens new public
surface or touches a queue/admission path: **is there a bound on what one
caller, one key, or one org can consume, and is it enforced at the right
layer?** It covers per-key RPM on new routes, concurrency permits on
unbounded uploads, per-org queue fairness (no starvation), QoS signals that
actually gate (in-process `interactive_in_flight` vs vLLM `/metrics`), the
two-tier slot cap, and the resolve()-org-before-semaphore ordering that
stops unauthenticated queue pre-fill. It deliberately does NOT own the
*correctness* of the claim's optimistic-concurrency guard (Sector 02), the
graceful-shutdown drain of the worker (Sector 03), the billing
same-txn finalize (Sector 05), or the storage residency of uploaded
content (Sector 06) — those sectors share the same code paths but ask a
different question. The MVCC-vs-hard-cap distinction (a count-based CTE is
not a hard cap) lives here because it determines whether a *fairness* signal
actually bounds anything.

## Paradigms (7 entries)

### P-04-1: Enforce per-key RPM on every new public route, after auth

**Paradigm statement** — Every new public route that accepts an API key
must call `rate_limiter.check(&key.id, key.rate_limit_rpm)` after
authentication and before doing real work. A `rate_limit_rpm` column on the
key table is dead weight if any route reachable by that key skips the
check: the limit is unenforceable across the surface that lacks it. New
routes that share an auth helper inherit the check by routing through that
helper; routes with a bespoke auth path must add the call themselves.

**Source evidence** — `gateway.md MAJOR-3`:
> "`batches.rs:45-50` and the files handlers don't rate-limit; `key.rate_limit_rpm` unenforceable across the new public surface."

`playbook` convention "Per-model rate-limit gate":
> "`enforceChatLimits` per `model_id`; new call paths must gate or explicitly justify bypass."

**<Provider> infra anchor** — `src/routes/batches.rs:50`
(`state.rate_limiter.check(&key.id, key.rate_limit_rpm).await?` inside
`gate_and_auth`, covering the 4 batch routes create/list/retrieve/cancel);
`src/routes/files.rs:59` (upload) and `src/routes/files.rs:205` (content)
add the same call to the bespoke auth path; `src/rate_limit.rs:39`
(`pub async fn check(&self, key_id: &str, limit_rpm: i32) -> Result<(),
GatewayError>`). The canonical sibling that pre-existed the batch PR is
`src/routes/preflight.rs:324` and `:410` (the chat/embeddings path's
`enforce_rpm` branch). On the app side, the analog is
`backend/src/controllers/<provider>Chat.libs/enforceChatLimits.ts:34`
(`enforceChatLimits`, per-`model_id` + per-user sliding-window).

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/gateway "trace rate_limiter check route auth"` — lists every caller of `check`; a new route that *doesn't* appear is the gap.
> → Serena `find_referencing_symbols` on `RateLimiter::check` to enumerate all call sites; a new public handler absent from the set is the finding.
> → `semble_search "rate_limit_rpm check after authenticate"` to locate the sibling pattern (preflight) a new route should mirror.
> On the app side: `codegraph explore -p ~/<provider>/app "enforceChatLimits model_id gate"` to confirm a new model-call path routes through the canonical gate.

**Fix-suggestion policy** —
> SUGGEST ONLY: open a finding listing each new route missing the `check` call, citing the canonical sibling (`gate_and_auth` for batch routes, `preflight.rs:324` for chat, `enforceChatLimits` on the app side). Do NOT commit a patch; the PR author adds the one-line `check` after auth on each bespoke route. Per-org storage quota (the harder half of MAJOR-2) is deferred, not silently dropped — name the deferral.

**Adversarial caveat** — The limiter is in-memory per gateway instance
(`DashMap` with a 60s window, `rate_limit.rs:6,15`); under `replicas: 1` the
per-key cap holds, but the moment the gateway runs >1 replica the effective
RPM is `N × limit_rpm` and the check is a soft cap, not a hard one. Flagging
a missing `check` is always correct; assuming the *check alone* enforces
the published RPM under multi-replica is not.

### P-04-2: Bound concurrent uploads with a fail-fast permit, not a body limit

**Paradigm statement** — An upload route that holds the full body in RAM
while persisting must cap *concurrency*, not just per-request body size.
`DefaultBodyLimit` bounds one request; N concurrent requests each under the
limit still pin N × body-size of resident memory. The fix is a
`Semaphore::try_acquire` that fails fast to 429 when exhausted, acquired
after auth so anonymous callers cannot pre-fill it. Per-org storage quota
is hardening, not MVP-blocking, and may be deferred *if* retention is
bounded by a sweep (so the deferral is time-limited, not silent).

**Source evidence** — `gateway.md MAJOR-2`:
> "`/v1/files` upload has no concurrency permit, no per-key RPM, no per-org quota; N×50MB resident with only 64MB `DefaultBodyLimit` per request."

And the fix:
> "`FILE_UPLOAD_MAX_CONCURRENCY = 6` with `try_acquire` fail-fast 429 after auth in `upload_file_inner`. Per-org storage quota deferred (29-day sweep bounds retention)."

**<Provider> infra anchor** — `src/routes/files.rs:28`
(`pub const FILE_UPLOAD_MAX_CONCURRENCY: usize = 6;`), `src/routes/files.rs:53-57`
(`state.file_upload_concurrency.try_acquire().map_err(|_|
GatewayError::TooManyRequests("file upload at capacity, retry later"))`),
acquired at `files.rs:52` *after* `authenticate` at `files.rs:50` and
*before* the `rate_limiter.check` at `files.rs:59`. AppState wires the
semaphore at `src/batch/reaper.rs:229` and `src/batch/worker.rs:887`
(`file_upload_concurrency: Arc::new(Semaphore::new(FILE_UPLOAD_MAX_CONCURRENCY))`).
The sibling that proves the pattern is canonical is
`BATCH_CREATE_MAX_CONCURRENCY = 4` at `src/routes/batches.rs:39` (create
holds ~3× the 50MB input in RAM; same fail-fast shape).

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/gateway "file_upload_concurrency try_acquire Semaphore"` — confirms the semaphore is wired into AppState and acquired exactly once on the upload path.
> → Serena `find_symbol` on `FILE_UPLOAD_MAX_CONCURRENCY` and `file_upload_concurrency` to confirm the constant and the AppState field exist and are referenced.
> → `semble_search "Semaphore::try_acquire fail fast 429"` to find every fail-fast permit site (image-gen, batch-create, file-upload) and check a new one matches.

**Fix-suggestion policy** —
> SUGGEST ONLY: open a finding citing the N×body-size resident-memory math, the missing `try_acquire`, and the canonical sibling (`BATCH_CREATE_MAX_CONCURRENCY`). Recommend the constant + `try_acquire` + 429. Per-org quota: name it as a deferred hardening item with the sweep as the bound that makes deferral safe; do NOT patch it. The PR author owns the constant value and the acquire ordering.

**Adversarial caveat** — A global semaphore caps the *fleet* of uploaders,
not per-org; one noisy org can exhaust all 6 permits and 429 every other
org's upload. That is the exact unfairness P-04-3 addresses for the *queue*,
but the upload permit has no per-org partition — the fix is correct for
the OOM bound, and the per-org fairness gap is a real but separately-scoped
finding.

### P-04-3: Partition the claim queue by org so no org starves another to expiry

**Paradigm statement** — A batch claim query ordered purely by
`created_at` is global FIFO: one org's large batch can occupy every claim
slot for long enough to starve a second org's small batch past its
`expires_at`. The fix is a single window-function query that ranks rows
*within* an org partition (`ROW_NUMBER() OVER (PARTITION BY b.org ORDER BY
...)`) and orders the claim by that rank, so each tick round-robins across
orgs. No new state table, no cursor, no per-org worker — one CTE.

**Source evidence** — `gateway.md MAJOR-1`:
> "`store.rs:495` orders `ORDER BY b.created_at, br2.line_no` with no org partition; org A's 50k batch starves org B's small batch to expiry on a shared deployment."

The "Notes on the review" correction:
> "A single window-function query, not a cursor/round-robin state machine."

**<Provider> infra anchor** — `src/batch/store.rs:448-451`
(`ROW_NUMBER() OVER (PARTITION BY b.org ORDER BY b.created_at, br2.line_no)
AS rn` inside the `ranked` CTE of `claim_requests`), ordered by
`store.rs:472` (`ORDER BY r.rn`), with the explicit `ponytail:` comment at
`store.rs:470-471`:
> "per-org round-robin within a claim; per-batch or weighted fair-share is the next axis if orgs submit many batches."

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/gateway "claim_requests PARTITION BY org ROW_NUMBER"` — confirms the window function is in the claim CTE.
> → codebase-memory `search_graph name_pattern="claim_requests"` then `trace_path mode=calls` from `worker::tick` → `claim_requests` to confirm the claim is the only admission point the worker uses.
> → `semble_search "ORDER BY created_at line_no no org partition"` to catch a *new* claim-shaped query that reintroduces global FIFO.

**Fix-suggestion policy** —
> SUGGEST ONLY: open a finding quoting the global-FIFO `ORDER BY` and the starvation scenario; cite the `ROW_NUMBER() OVER (PARTITION BY ...)` sibling in `claim_requests`. Recommend the single-CTE rewrite, not a cursor or state machine. The PR author owns the SQL. Flag (do not implement) the next axis the `ponytail:` comment names — per-batch or weighted fair-share — if the PR's workload has many batches per org.

**Adversarial caveat** — Round-robin by rank is fair across *orgs*, not
across *batches within an org*: an org with 50k requests in one batch and
50k in another still gets the same claim share as an org with one 100-row
batch, because the rank partitions by org, not batch. The `ponytail:`
comment names this exact gap. Flagging global FIFO is always correct;
claiming the window function solves all fairness is not.

### P-04-4: A count-based CTE is not a hard cap under MVCC — use a per-xact advisory lock for atomic admission

**Paradigm statement** — When a cap must be *atomic* across concurrent
transactions (create-time org caps, fleet slot caps), an inlined
`count(*)` subquery or `LIMIT` derived from a `count(*)` is not a hard cap:
two concurrent transactions each read the same pre-claim count and both
admit, overshooting the cap. The genuinely atomic pattern is
`pg_advisory_xact_lock` held inside the inserting transaction, so the
count-then-insert sequence is serialized. A session-level
`pg_try_advisory_lock` is sufficient only when the invariant is
`replicas: 1` (it makes the silent oversubscription a loud no-op, not a
true hard cap).

**Source evidence** — `gateway.md BLOCKER-3` (Mateo's rebuttal, verified true):
> "the 'inline subquery into CTE LIMIT' does NOT yield a hard cap under MVCC (two concurrent txns read same count, both claim); a true hard cap needs `pg_advisory_xact_lock` per-deployment."

And the verified rebuttal under "Notes on the review":
> "`create_batch_capped` at `store.rs:211` uses `pg_advisory_xact_lock` (the per-xact pattern he cites as the true hard cap), and `claim_requests` ... uses `FOR UPDATE SKIP LOCKED` (row-disjoint, not count-disjoint)."

**<Provider> infra anchor** — `src/batch/store.rs:211`
(`SELECT pg_advisory_xact_lock($1, hashtext($2))` inside
`create_batch_capped`'s transaction, the per-org create cap), vs
`src/batch/worker.rs:693` (`SELECT pg_try_advisory_lock($1)` bound
`42_i64`, session-level, the `replicas:1` worker guard with the
`ponytail:` comment at `worker.rs:684-685`: "session-level advisory lock;
SQL fleet clamp + shared tier signal is the upgrade path for permanent
replicas > 1"). The two are deliberately different: the create path needs
true atomicity (multi-replica safe); the worker path only needs
singleton-enforcement.

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/gateway "pg_advisory_xact_lock create_batch_capped per-org cap"` — confirms the per-xact lock is inside the insert tx.
> → codebase-memory `query_graph` Cypher: `MATCH (f:Function {name:"create_batch_capped"})-[r:calls]->(g:Function) RETURN g.name` to see the lock + count + insert sequence.
> → `semble_search "pg_try_advisory_lock session level replicas 1"` to find every singleton-guard that is *not* a true hard cap and should be flagged as such if a PR claims it bounds a count.

**Fix-suggestion policy** —
> SUGGEST ONLY: if a PR adds a count-derived `LIMIT` and calls it a cap, open a finding citing the MVCC read-read race, the `create_batch_capped` per-xact sibling, and the specific scenario (two pods/p txns, same count, both admit). Recommend `pg_advisory_xact_lock` inside the inserting tx. If the PR's invariant is genuinely `replicas: 1`, recommend the session-level `pg_try_advisory_lock` *plus a documented invariant* — and flag that the `ponytail:` upgrade path to a shared-tier signal is owed. The PR author owns the SQL and the invariant doc.

**Adversarial caveat** — `pg_advisory_xact_lock` serializes the
count-then-insert sequence, which is correct for *admission* but
introduces contention proportional to create frequency; for a
high-frequency path the lock itself becomes the bottleneck and a
`FOR UPDATE SKIP LOCKED` row-disjoint claim (as `claim_requests` uses) is
the better trade. The right pattern depends on whether the cap gates
*creation* (rare, serialize) or *claiming* (frequent, disjoint).

### P-04-5: Resolve the org before the concurrency semaphore — no unauthenticated queue pre-fill

**Paradigm statement** — A route that gates on a concurrency semaphore
must `resolve()` (authenticate, resolve the org/key, and burn any
rate-limit slot) *before* it waits on the semaphore. If the semaphore is
acquired first, an unauthenticated caller can occupy a queue position
cheaply and flood the gate, starving authenticated callers behind a queue
full of anonymous waiters that will all eventually fail auth anyway. The
cost model is asymmetric: one rate-limit slot per authenticated caller
(failed auth loses one slot) vs. an unbounded anonymous-DoS vector if the
queue is pre-fillable.

**Source evidence** — `playbook` Image-generation PR path, step 1:
> "Does the route `resolve()` the org before the concurrency semaphore (so unauthenticated callers cannot pre-fill the queue)? `src/routes/images.rs:169`"

`src/routes/images.rs:152-156` (the code comment Andrea is checking against):
> "Parse `n` early so we can validate against image_max_n without consuming a rate-limit slot. resolve() comes next — it auths the caller and burns 1 slot, so unauthenticated callers can't occupy queue positions in the concurrency gate below."

**<Provider> infra anchor** — `src/routes/images.rs:169`
(`let resolved = resolve(&state, &headers, &request.model, start).await?`)
executes *before* `src/routes/images.rs:180`
(`try_acquire_image_gen_slot(...)`). The ordering is load-bearing: the
rate-limit slot consumed at `images.rs:169` is lost if the caller later
times out on the semaphore — a bounded per-key cost, explicitly chosen
over the unbounded anonymous-queue-stuffing alternative. The queue-depth
gate itself is `try_acquire_image_gen_slot` at `src/routes/images.rs:71`,
backed by `image_gen_pending: Arc<AtomicUsize>` (`main.rs:81`) and
`image_gen_max_queue_depth` (default 50, `config.rs:104,185`).

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/gateway "resolve authenticate before semaphore try_acquire_image_gen_slot"` — confirms `resolve` precedes the slot acquire on the images path.
> → Serena `find_referencing_symbols` on `try_acquire_image_gen_slot` to confirm its only caller is the images route, and that caller calls `resolve` first.
> → `semble_search "resolve before Semaphore queue depth 429"` to find every concurrency-gated route and check the resolve-then-acquire ordering.

**Fix-suggestion policy** —
> SUGGEST ONLY: if a new route acquires a semaphore or queue slot before auth, open a finding citing the anonymous-queue-pre-fill vector and the `images.rs:169→180` sibling. Recommend moving `resolve()` (or the route's auth equivalent) before the acquire. The PR author owns the reorder; the cost-model comment (bounded per-key loss vs unbounded anonymous DoS) should be added so the ordering's rationale survives the next reviewer.

**Adversarial caveat** — Resolving first means a *failed* auth still
burns a rate-limit slot only if `check` runs before the auth failure is
detected — in `images.rs` the slot is burned inside `resolve`, so a failed
auth returns before `check`. The ordering protects the queue, but the
"burns 1 slot" claim is only true on the *successful*-auth path; on
failure, no slot is burned and no queue is filled, which is the correct
outcome. The caveat is: do not claim the failed-auth path also costs a
slot — it doesn't, and it shouldn't.

### P-04-6: A queue-depth gate must 429 immediately when full, not park waiters unbounded behind the semaphore

**Paradigm statement** — A concurrency semaphore alone bounds *concurrent
work* but not *pending waiters*: an unbounded queue of waiters piles up
behind the semaphore, each holding a connection, until the server exhausts
file descriptors or memory. The fix is a queue-depth gate that checks the
pending-waiter count *before* waiting on the semaphore and returns 429
immediately when the count exceeds a configured depth. Setting the max
concurrency to 0 is the escape hatch (gate disabled); the depth default
must be explicit and configurable, not magic.

**Source evidence** — `playbook` Image-generation PR path, step 2:
> "Is there a queue-depth gate that immediately `429`s when full? `src/routes/images.rs:180`"

`src/routes/images.rs:172-179` (the gate's own rationale comment):
> "Queue-depth gate (image_gen_max_queue_depth, default 50) returns 429 immediately when the pending-waiter count exceeds the limit, preventing unbounded connection pileup behind the semaphore. Waiters that pass the gate then wait on the semaphore for up to 60s before timing out with 429."

**<Provider> infra anchor** — `src/routes/images.rs:71`
(`async fn try_acquire_image_gen_slot(pending, semaphore, max_queue_depth)`)
backed by `image_gen_pending: Arc<AtomicUsize>` (`main.rs:81`,
incremented by the `PendingGuard` at `images.rs:42-55`, decremented on
drop) and `image_gen_max_queue_depth: usize` (`config.rs:104`, default 50
at `config.rs:185-188`). The gate is invoked at `images.rs:180-202`; the
`Err(GatewayError::TooManyRequests(_))` arm at `images.rs:192-200`
records the access-log and returns 429 without waiting. The escape hatch
is `images.rs:183-187`: `if image_gen_max_concurrency > 0 { depth } else
{ 0 }`, and `images.rs:70-71` documents "When `max_queue_depth == 0`,
returns Ok immediately (escape hatch)".

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/gateway "try_acquire_image_gen_slot pending AtomicUsize queue depth 429"` — confirms the pending counter, the guard, and the 429 arm.
> → codebase-memory `search_graph semantic_query=["queue depth gate semaphore 429 fail fast"]` to find any other semaphore-gated route that *lacks* a queue-depth gate and parks waiters unbounded.
> → Serena `find_symbol` on `try_acquire_image_gen_slot` and `PendingGuard` to confirm the RAII drop decrements the counter on every early-return path (timeout, closed semaphore, upstream error).

**Fix-suggestion policy** —
> SUGGEST ONLY: if a new route waits on a semaphore with no pending-count check, open a finding citing the unbounded-waiter pileup and the `try_acquire_image_gen_slot` sibling. Recommend the `AtomicUsize` pending counter + RAII `PendingGuard` + 429-when-exceeded pattern, with an explicit configurable depth and a documented `concurrency==0` escape hatch. The PR author owns the depth value and the guard.

**Adversarial caveat** — The queue-depth gate 429s *new* waiters but
does not evict *existing* ones; if the semaphore drains slowly, waiters
that passed the gate still hold connections for up to the 60s timeout.
The gate bounds the queue, not the per-waiter dwell time — a slow
upstream can still exhaust connections via the 50 admitted waiters each
holding one for 60s. The depth default (50) × timeout (60s) is the real
connection ceiling; flag the depth without acknowledging the dwell-time
component and you'll under-size the gate.

### P-04-7: QoS signals must be correct under the deployment topology — singleton-ness, not co-location

**Paradigm statement** — A QoS signal that decides whether to widen or
floor a batch slot cap (the two-tier `interactive_in_flight` →
`allowed_batch_slots` path) is only correct if it reflects the *fleet's*
interactive load, not one process's. An in-process `DashMap` counter is
correct only because the worker is a singleton on a single-replica
gateway (enforced by the advisory lock, P-04-4); co-location of worker and
chat route in the same process is *not* what makes it correct. The moment
the deployment splits (worker pod separate, or replicas > 1), the
in-process signal silently understates fleet load and the cap widens
when it should floor. The fix is either (a) keep the singleton invariant
documented and enforced, or (b) move the signal to vLLM `/metrics` and
read it cross-process. Do not let a "works today" in-process signal stand
without naming the invariant it depends on.

**Source evidence** — `gateway.md BLOCKER-3`:
> "`AppState.interactive_in_flight` is per-process; `slots.rs:6` computes cap from it; `claim_requests` clamps only to caller's own limit. Two pods each read 'quiet' and oversubscribe."

`gateway.md Rebuttal (a)`:
> "Conclusion right (dedicated worker pod not needed), reasoning wrong (co-location doesn't make QoS correct; singleton-ness does, unenforced)."

`feedback-divergences.md` "Deployment topology" + "Summary matrix":
> "QoS signal: Andreas → vLLM `/metrics` (if split); Local → In-process `interactive_in_flight`. Signal only works because worker shares the gateway process; `/metrics` migration only needed if split."

**<Provider> infra anchor** —
`src/batch/slots.rs:6-14` (`allowed_batch_slots(scheduler_slots,
interactive_in_flight)` — quiet iff `in_flight * 20 < slots * 3`, widens
to 75% or floors at 25%), fed by `AppState.interactive_in_flight` at
`main.rs:86-87` (`Arc<DashMap<String, Arc<AtomicUsize>>>`, per-deployment
slug), incremented by `InFlightGuard::enter` at
`src/routes/completions.rs:187` and `:289` (the chat path), read by the
worker at `src/batch/worker.rs:166-170`. The singleton invariant is
enforced by `worker.rs:693` (`pg_try_advisory_lock(42)`, session-level);
the `ponytail:` comment at `worker.rs:684-685` names the upgrade path:
"SQL fleet clamp + shared tier signal is the upgrade path for permanent
replicas > 1". The two-tier cap is unit-tested at `slots.rs:17-71`
(quiet/busy floor arithmetic pinned).

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/gateway "enforceChatLimits model_id gate"` (app-side analog) and `codegraph explore -p ~/<provider>/gateway "interactive_in_flight allowed_batch_slots slots"` (gateway) — confirms the signal path: completions `InFlightGuard` → `AppState.interactive_in_flight` → worker `tick` → `slots::allowed_batch_slots` → `claim_requests` LIMIT.
> → codebase-memory `trace_path mode=data_flow` from `InFlightGuard::enter` to `allowed_batch_slots` to confirm the counter is the only input to the cap and there is no cross-process source.
> → `semble_search "interactive_in_flight per-process DashMap singleton replicas 1"` to find any doc or comment claiming co-location (not singleton-ness) is the correctness argument — that claim is the finding.
> → agentmemory `memory_smart_search "QoS singleton in-process signal vLLM metrics split"` to recall whether a prior session decided to keep vs migrate the signal.

**Fix-suggestion policy** —
> SUGGEST ONLY: if a PR touches the slot cap or the in-flight signal and *doesn't* name the singleton invariant, open a finding citing BLOCKER-3 and Rebuttal (a): the signal is correct only because `replicas: 1` is enforced (advisory lock), not because worker and route share a process. Recommend either (a) a code comment + doc pinning the `replicas: 1` invariant and naming the `ponytail:` upgrade path, or (b) if the PR moves toward split/replicas, the vLLM `/metrics` migration. The PR author owns the invariant doc or the migration; do NOT patch the signal.

**Adversarial caveat** — The in-process signal has *lower latency* than a
`/metrics` scrape (no HTTP round-trip, no scrape interval lag), so for a
genuinely single-replica gateway it is the *better* QoS source, not a
stopgap. Recommending `/metrics` migration for a deployment that is and
will remain `replicas: 1` over-engineers the signal and adds a failure
mode (scrape timeout). The fix is correct *only* when the topology
actually splits; for the singleton case the right finding is "document the
invariant", not "migrate the signal".

## Cross-sector links

- **Shares BLOCKER-2 evidence with Sector 03 (Graceful shutdown) and
  Sector 05 (Billing).** The worker's `pg_try_advisory_lock(42)` at
  `worker.rs:693` is read here as the *singleton-enforcement* that makes
  the QoS signal correct (P-04-7); Sector 03 reads the same lock as the
  no-double-run guard; Sector 05 reads the `finalize_success` `AND
  attempt` guard for no-double-bill. Same code, three lenses.
- **Shares BLOCKER-3 / Rebuttal (a) evidence with Sector 02 (Concurrency
  & race).** The MVCC count-race (P-04-4) is a concurrency finding; this
  sector owns it because it determines whether a *fairness* cap bounds
  anything, while Sector 02 owns the broader `FOR UPDATE SKIP LOCKED`
  claim-disjointness argument. The dedup pass may merge the MVCC
  counter-point into Sector 02 and keep the fairness framing here.
- **P-04-1's per-key RPM check on the app side (`enforceChatLimits`)
  overlaps with the app-side rate-limit concern in the playbook's
  "Per-model rate-limit gate" convention.** If a future sector owns
  app-side gating specifically, P-04-1's app anchor may belong there; the
  gateway-side anchor stays here.
- **P-04-5 (resolve-before-semaphore) and P-04-6 (queue-depth 429) share
  the image-gen route with Sector 10 (SSRF & security) and Sector 08
  (Wire/contract).** Sector 10 owns the `validateAndPinUrl` /
  ownership-before-discard lens on the same route; Sector 08 owns the
  4xx-vs-5xx recoverability of the 429. The ordering-of-operations
  concern (P-04-5) is uniquely this sector's.
- **P-04-2's per-org quota deferral depends on Sector 06 (Storage &
  content residency)** — the deferral is safe only because the 29-day
  sweep bounds retention; if the sweep leaks (BLOCKER-1, Sector 06), the
  deferral's safety argument breaks. Flag here, owned there.

## Sector-specific failure modes

- **Flagging a missing `rate_limiter.check` on a route that is
  *intentionally* unauthenticated or internal.** The check is for public
  API-key surface; an internal/admin route or a health-check route has no
  key to check. The finding must distinguish "new public route" from "new
  route" — the playbook convention is per-`model_id` / per-key, both
  assume a key exists.
- **Treating the in-process `interactive_in_flight` signal as a fleet
  signal.** It is a single-process counter; under `replicas: 1` it is
  fleet-equivalent, under any other topology it is not. An agent that
  flags "the QoS signal understates load" without checking the
  `replicas: 1` invariant (advisory lock at `worker.rs:693`) is firing on
  a non-bug. The invariant is the load-bearing detail.
- **Conflating `pg_try_advisory_lock` (session-level, singleton guard)
  with `pg_advisory_xact_lock` (per-xact, true hard cap).** They solve
  different problems; recommending the per-xact lock for the worker guard
  (which only needs singleton-ness) adds contention for no correctness
  gain, and recommending the session lock for `create_batch_capped`
  (which needs true atomicity under multi-replica) leaves the count race
  open. The two patterns are not interchangeable.
- **Claiming the `ROW_NUMBER() OVER (PARTITION BY org)` fix solves
  *all* fairness.** It solves cross-org starvation; within-org
  multi-batch fairness is the unimplemented next axis the `ponytail:`
  comment names. An agent that declares the queue "fair" after the
  window function is over-claiming — it is fair across orgs, not across
  an org's batches.
- **Recommending a per-org partition on the upload semaphore
  (`FILE_UPLOAD_MAX_CONCURRENCY`) without measuring.** The global
  semaphore solves the OOM bound; a per-org partition solves fairness
  but shrinks the effective cap per org and may 429 legitimate uploads.
  The fix is correct for fairness but trades OOM-safety margin; flag it
  as a tradeoff, not a free improvement.

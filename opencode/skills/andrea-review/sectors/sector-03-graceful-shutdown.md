# Sector 03 — Graceful shutdown & drain

## Scope

This sector owns the SIGTERM/drain review concern: **does every new worker,
background loop, and upstream call participate in graceful shutdown so no
in-flight work is orphaned and no job runs twice?** The question Andrea asks
of every `tokio::spawn` / `setInterval` / `AbortController` is three-part:
(1) can the loop observe a stop signal and exit on its own? (2) does main
await its handle with a bounded timeout before the process dies? (3) does
every retry/upstream call forward the abort signal so a half-finished S3 PUT
or GPU inference does not keep burning after the parent gave up?

Boundaries — what this sector deliberately does NOT cover:
- **The idempotence guard that makes a re-run safe** (`finalize_success … AND attempt = $9`) — that is Sector 01 (Idempotency & re-arm gates). This sector only cares that the drain *happens*; Sector 01 cares that a re-run *doesn't double-bill*.
- **The advisory lock that prevents two pods running the worker** (`pg_try_advisory_lock`) — that is Sector 02 (Concurrency). This sector cares about one process shutting down cleanly; Sector 02 cares about two processes not both claiming.
- **The lease-TTL reclamation of orphaned rows** (`reclaim_expired_leases`) — that is Sector 05 (Billing & state-machine). This sector cares that SIGTERM does not *create* orphans; Sector 05 cares that orphans the reaper *does* see are requeued safely.
- **Clock injection for expiry** — Sector 12 (Clock-vs-`Utc::now`).

## Paradigms (6 entries)

### P-03-1: Thread a stop flag into every new worker or async loop

**Paradigm statement** — A newly spawned background loop must accept a shared
stop signal as a parameter and check it at every claim boundary, not just
rely on its `JoinHandle` being dropped. The stop flag is threaded from the
spawner (`main`) through `spawn(..., stop)` into `tick(..., stop)` and into
the inner `drain_deployment(..., stop)` so the gate is checked exactly where
new work is admitted — before a claim, not after. A loop that only checks
`stop` once per outer tick (or never) keeps admitting rows for the full tick
window after SIGTERM.

**Source evidence** — `gateway.md` BLOCKER-2:
> "`main.rs:319-324` spawns worker/reaper/sweep bound to `_handle`s never awaited/aborted; SIGTERM drops a worker mid-S3-PUT-to-finalize → orphan leak + double GPU run; fix = `Arc<AtomicBool>` stop flag threaded into `spawn→tick→drain_deployment`."

`playbook.md` convention **"Graceful-shutdown drain"**:
> "In-flight BATCH workers drain on `SIGTERM`; new workers must join the drain."

**<Provider> infra anchor** — `src/batch/worker.rs:672` (`pub fn spawn(state: AppState, clock: Arc<dyn Clock>, stop: Arc<AtomicBool>) -> JoinHandle<()>`), `src/batch/worker.rs:81` (`tick`'s `stop: &Arc<AtomicBool>` param), `src/batch/worker.rs:158` (`drain_deployment`'s `stop: &Arc<AtomicBool>` param), `src/batch/worker.rs:175` (the claim gate `if want > 0 && !claim_failed && !stop.load(Ordering::SeqCst)`), `src/batch/worker.rs:704` (loop-top `if stop.load(Ordering::SeqCst) { break; }`), `src/main.rs:329` (`let batch_worker_stop = Arc::new(std::sync::atomic::AtomicBool::new(false));`).

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/gateway "trace batch worker spawn stop flag drain"`
> → Serena `find_symbol` on `batch::worker::spawn` to confirm the `stop` param; `find_referencing_symbols` on `stop` to confirm it reaches both `tick` and `drain_deployment`.
> `semble_search "AtomicBool stop flag worker drain"` to find sibling loops (key_reaper, rollup) and confirm whether THEY thread a stop flag or rely on `.abort()` — the contrast is itself a finding.

**Fix-suggestion policy** —
> SUGGEST ONLY: open a finding on the PR naming the new `spawn` that lacks a `stop` param; cite the canonical sibling `batch::worker::spawn(state, clock, stop: Arc<AtomicBool>)` and the claim-gate at `worker.rs:175`. Do NOT commit a patch. The PR author owns threading the flag through `spawn → tick → drain`.

**Adversarial caveat** — A stop flag checked only at the outer loop top (`worker.rs:704`) is not enough; the gate must also block *new claims* mid-tick at `drain_deployment:175`, else a long tick keeps admitting rows for minutes after SIGTERM. An agent verifying "stop flag present" without checking the claim-site gate would pass a loop that exits cleanly between ticks but orphans work within one.

### P-03-2: Await the worker handle with a bounded timeout — never drop it

**Paradigm statement** — After signaling stop, `main` must `await` the
worker's `JoinHandle` inside `tokio::time::timeout(bound, handle)`. Binding
the spawned handle to a `_handle` (underscore = "intentionally unused") and
letting it drop on process exit is the exact bug: the tokio runtime tears
down the task mid-S3-PUT, the row stays `in_flight` past its lease, the
reaper reclaims it, and the next pod re-runs it — a double GPU run. The
timeout must be long enough to cover the critical window (S3 PUT → DB
finalize) but short enough that K8s does not SIGKILL the pod first.

**Source evidence** — `gateway.md` BLOCKER-2:
> "after axum drains + metering 5s, main signals stop and awaits worker handle with 30s timeout."

**<Provider> infra anchor** — `src/main.rs:378-380`:
```rust
batch_worker_stop.store(true, std::sync::atomic::Ordering::SeqCst);
if let Some(handle) = batch_worker_handle {
    let _ = tokio::time::timeout(std::time::Duration::from_secs(30), handle).await;
}
```
The `if let Some(handle)` guards the `None` case (worker never spawned when catalog is off — `main.rs:330`). The `let _ =` discards the `Result<_, Elapsed>` so a timeout does not panic; the row is left `in_flight` for the reaper, which is the designed fallback (ADR 0001).

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/gateway "where is batch_worker_handle awaited timeout main"`
> → Serena `find_referencing_symbols` on `batch_worker_handle` to confirm it is consumed exactly once and in a `timeout`.
> `semble_search "tokio::time::timeout JoinHandle shutdown"` to find sibling shutdown joins (none currently — key_reaper and rollup use `.abort()`, see P-03-6).

**Fix-suggestion policy** —
> SUGGEST ONLY: cite `main.rs:378-380` as the canonical join-with-timeout; flag any new `tokio::spawn` whose handle is bound to `_` or dropped without a `timeout(..., handle).await`. Do NOT commit. The PR author owns adding the join.

**Adversarial caveat** — A 30s timeout that exceeds the K8s `terminationGracePeriodSeconds` (default 30s) is a no-op — the pod is SIGKILLed before the timeout elapses, re-introducing the orphan. An agent confirming "timeout present" without comparing it to the helm `terminationGracePeriodSeconds` can pass a nominally-correct but operationally-dead drain. The 30s here is deliberately at the edge; raising it requires raising the helm value (Sector 09).

### P-03-3: No double-run on SIGTERM — drain in-flight, don't abort mid-PUT

**Paradigm statement** — Graceful shutdown must *drain* in-flight work to a
terminal state, not *abort* it mid-flight. The specific hazard Andrea named:
SIGTERM drops a worker between the S3 PUT of a result body and the DB
`finalize_success`/`finalize_failure` that marks the row terminal. The row
stays `in_flight` past its lease; the reaper reclaims it; the next pod
re-runs the GPU inference — a double GPU run and, without the idempotence
guard, a double bill. The drain design (stop flag + handle-join) exists so
that window closes before the process exits, and any row that still slips
through is caught by `finalize_success … AND attempt = $9` (Sector 01) so
the re-run bills once.

**Source evidence** — `gateway.md` BLOCKER-2:
> "SIGTERM drops a worker mid-S3-PUT-to-finalize → orphan leak + double GPU run."

`gateway.md` "Notes on the review — BLOCKER-2 severity overstated":
> "No double-billing: `finalize_success` guards `AND attempt = $9`; reclaim bumps attempt; a stale finalize no-ops. The re-run bills once. The orphan leak is rare (only if the batch expires before re-claim+re-finalize)."

**<Provider> infra anchor** — `src/batch/worker.rs:66-68` (the docstring invariant "persist the result/error body to S3 (idempotent PUT) — ONLY on success continue, so a committed finalize always has its body stored (ADR 0004 ordering invariant)"), `src/batch/billing.rs:127` (`AND attempt = $9` — the idempotence guard that makes a post-drain re-run safe), `src/batch/store.rs:453` (`WHERE br2.status = 'queued'` — only queued rows are reclaimable, so a drained-to-terminal row is not re-claimed).

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/gateway "trace finalize_success attempt guard reclaim double run"`
> → codebase-memory `trace_path` mode `data_flow` from `claim_requests` → `finalize_success` to confirm the `attempt` value travels claim→process→finalize and a stale worker's attempt mismatches.
> `memory_smart_search "double GPU run SIGTERM orphan"` to recall any prior session decision on the drain window.

**Fix-suggestion policy** —
> SUGGEST ONLY: when a new code path writes to S3 then to DB, cite the ADR 0004 ordering invariant (`worker.rs:66-68`) and require the drain to cover the PUT→finalize window. Do NOT commit. The PR author owns the ordering.

**Adversarial caveat** — "No double-run" is a *defense in depth*, not a single gate: the stop flag prevents most cases, the handle-join covers the rest, the lease TTL reclaims stragglers, and `AND attempt = $9` makes any residual re-run idempotent. An agent that treats any one of these as sufficient will miss a new path that bypasses the others. The honest statement is "the drain makes double-run *rare*; the idempotence guard makes the residual *safe*."

### P-03-4: Forward the abort signal to the upstream call

**Paradigm statement** — When a worker, tool, or retry loop calls an upstream
service (GPU inference, S3, another HTTP API), it must forward the abort
signal it received from its parent into that call. A loop that checks
`signal.aborted` *between* retries but passes no signal into the `chat()`
call itself leaves the upstream inference running for its full timeout after
the user (or SIGTERM) cancelled — wasted GPU, wasted budget, and a delayed
drain. The signal must travel to the leaf I/O, not just to the retry
scaffolding around it.

**Source evidence** — `playbook.md` Image-generation PR path step 5:
> "Abort signal. Is the abort signal forwarded to the upstream inference call? `generateCosmosImage.ts:217`"

`playbook.md` convention **"Retry backoff"**:
> "Jittered, abort-signal-carrying; deterministic formula is a bug."

`playbook.md` Webhook path step 2:
> "Does the retry loop forward the abort signal? `src/jobs/trainingWebhook.job.ts:51`"

**<Provider> infra anchor** — `app/backend/src/controllers/<provider>Chat.libs/agenticLoop/generateCosmosImage.ts:215` (`if (ctx.abortSignal?.aborted) { throw ... code: 'ABORTED', recoverable: true }`), `:225` (`await chat({ user_id: ctx.userId }, { ... }, ctx.abortSignal, true)` — the signal is the 3rd arg to `chat`, reaching the upstream), `:240-241` (the retry-sleep's `onAbort` listener clears the timer so the sleep does not block a cancelled retry). Cross-process analog: `app/backend/src/controllers/<provider>Chat.libs/agentAbortRegistry.ts:15-26` (`abortAgent` → `controller.abort()`), wired from `saveStoppedMessage.ts:32` (`abortAll(conversation_id)`).

**Codebase-intelligence backend** —
> `semble_search "abortSignal forwarded chat upstream inference"` (app) to find every `chat(...)` / `fetch(...)` call and confirm each passes the signal.
> `codegraph explore -p ~/<provider>/gateway "proxy_non_streaming abort signal upstream"` to check whether the gateway's own upstream proxy call forwards a signal (it currently takes `timeout_ms` only — a candidate finding).
> Serena `find_referencing_symbols` on `agentAbortRegistry.abortAll` to confirm the cancel path reaches every registered controller.

**Fix-suggestion policy** —
> SUGGEST ONLY: for a new upstream call, cite `generateCosmosImage.ts:225` (`chat(..., ctx.abortSignal, true)`) as the canonical forward; flag any `chat()`/`fetch()`/`proxy_*` call whose signal arg is `undefined` or omitted. Do NOT commit. The PR author owns the forward.

**Adversarial caveat** — Forwarding the signal is correct only if the upstream actually honors it; a vLLM `/v1/completions` call that ignores `AbortSignal` will still run to completion server-side, so the signal saves client-side wait but not GPU. An agent that confirms "signal passed" without checking the upstream's abort semantics can pass a cosmetic forward. Also: aborting a streaming bridge mid-flight can lose the final `usage_log` metering row (see `main.rs:361-368` comment) — drain order matters (P-03-6).

### P-03-5: Prefer stdlib `AtomicBool` over a new cancellation abstraction

**Paradigm statement** — When adding a stop/cancel signal, use the stdlib
primitive already in the codebase (`Arc<AtomicBool>`) rather than pulling a
new dependency (`tokio_util::CancellationToken`). The review explicitly
recorded the deliberate choice: `tokio_util::CancellationToken` was
*considered and not added*; `AtomicBool` was already present and sufficient
for a cooperative stop flag checked at claim boundaries. This is the
Ponytail ladder rung 2 (stdlib) over rung 4 (new dep) — a new abstraction for
a value that never changes is debt, not safety.

**Source evidence** — `gateway.md` BLOCKER-2 Notes:
> "`tokio_util::CancellationToken` was not added (Mateo used stdlib `AtomicBool`, already in the codebase) — consistent with his claim."

**<Provider> infra anchor** — `src/main.rs:329` (`Arc::new(std::sync::atomic::AtomicBool::new(false))`), `src/batch/worker.rs:11` (`use std::sync::atomic::{AtomicBool, Ordering};` — no `tokio_util` import). The `Ordering::SeqCst` at `worker.rs:175,704` and `main.rs:378` is the strongest ordering, chosen because a missed stop signal orphans work; `Relaxed` would be a false economy here.

**Codebase-intelligence backend** —
> `grep` in gateway for `tokio_util` to confirm the crate is NOT a dependency (it is not); `semble_search "CancellationToken AtomicBool stop"` to surface any sibling that *did* add `CancellationToken` and assess whether it justified the dep.
> codebase-memory `query_graph` "MATCH (f:File)-[:DEPENDS_ON]->(d:Dependency) WHERE d.name CONTAINS 'tokio-util' RETURN f" on the `gateway` project to confirm zero such deps.

**Fix-suggestion policy** —
> SUGGEST ONLY: if a PR adds `tokio_util = "…"` to `Cargo.toml` for a stop flag, cite `main.rs:329` and ask whether `Arc<AtomicBool>` covers the case. Do NOT commit. The PR author owns the dependency decision.

**Adversarial caveat** — `AtomicBool` is a *cooperative* flag: it only stops the loop at the next check point. A loop blocked in an uncancelable `await` (e.g. a DB query with no timeout) will not notice the flag until it returns. `CancellationToken`'s advantage is that `select!` on `token.cancelled()` can interrupt a blocked `await` that `AtomicBool` cannot. An agent that reflexively prefers `AtomicBool` for a loop with unbounded `await`s will produce a drain that hangs. The honest rule: `AtomicBool` for check-at-boundary loops (the worker); `CancellationToken` or `select!` only when an `await` must be interruptible.

### P-03-6: Order the drain — metering before worker, worker before brute abort of reaper/sweep

**Paradigm statement** — When multiple background tasks must drain, the
order matters and must be explicit in `main`. The gateway drains in a
deliberate sequence: (1) axum `with_graceful_shutdown` stops admitting HTTP,
(2) the metering channel drains up to 5s (so in-flight handlers' final
`usage_log` rows land), (3) the worker stop flag is set and its handle joined
with 30s (so S3-PUT-to-finalize completes), (4) only then are the reaper and
sweep handles — which have no stop flag — left to be `.abort()`ed by runtime
teardown. Reversing (2) and (3) loses metering rows; skipping (3) before
runtime teardown reintroduces the orphan leak.

**Source evidence** — `gateway.md` BLOCKER-2:
> "after axum drains + metering 5s, main signals stop and awaits worker handle with 30s timeout."

`main.rs:361-368` comment:
> "Drain the metering channel before exiting… We give the drain task up to 5s… the streaming-bridge clones hold past that, and we accept losing their final usage_log row on a hard timeout."

`key_reaper.rs:60-61` docstring (the brute-abort sibling):
> "Returns a `JoinHandle` so graceful shutdown can `.abort()` it when the server stops."

**<Provider> infra anchor** — `src/main.rs:357` (`with_graceful_shutdown(shutdown_signal())` — axum stops first), `:374` (`tokio::time::timeout(Duration::from_secs(5), metering_drain)` — metering second), `:378-380` (worker stop + 30s join — worker third), `:326` (`let _batch_sweep_handle = ...` — sweep bound to `_`, no join, dropped at end — the *contrast* that proves the ordering is deliberate: only the worker that holds GPU work gets a join). `src/batch/reaper.rs:77` (`spawn(pool, clock)` — no `stop` param, confirming the reaper is the brute-abort tier, not the drain tier). `src/rollup.rs:55` (same `.abort()`-on-shutdown pattern, `rollup.rs:49-51` docstring).

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/gateway "main shutdown order axum metering worker reaper"` to read the full sequence in `main.rs`.
> Serena `find_symbol` on `shutdown_signal` (`main.rs:508`) to confirm it handles both SIGINT and SIGTERM (`tokio::signal::unix::SignalKind::terminate()` at `:510`).
> `semble_search "with_graceful_shutdown metering drain timeout"` to find the sibling pattern in other services.

**Fix-suggestion policy** —
> SUGGEST ONLY: when a new background task is added, cite the ordering at `main.rs:357→374→378` and require the author to place its drain in the right tier — join-with-timeout if it holds GPU/billing-critical work, `.abort()` if it is idempotent and re-runnable on next boot. Do NOT commit. The PR author owns the placement.

**Adversarial caveat** — The tiering assumes the reaper and sweep are safe to abort mid-tick. That holds for the reaper (each `reaper_tick` is a separate transaction; an aborted tick just re-runs next boot) and for sweep (`delete_idempotent` treats `NotFound` as `Ok`, `sweep.rs:19`). But a *new* background task that is NOT transactionally idempotent cannot be dropped into the brute-abort tier — it needs a stop flag + join like the worker. An agent that copies the reaper's `spawn(pool, clock)` shape for a non-idempotent loop reintroduces the orphan. The tier is a property of the task's idempotence, not of the spawn pattern.

## Cross-sector links

- **Sector 01 (Idempotency & re-arm gates)** — shares BLOCKER-2's double-run evidence. P-03-3's "no double-run" depends on Sector 01's `finalize_success … AND attempt = $9` (`billing.rs:127`) to make a residual re-run safe; the drain makes it rare, the guard makes it safe. A finding about double-run belongs in *both* sectors with different lenses: Sector 03 asks "did the drain happen?", Sector 01 asks "if it didn't, is the re-run idempotent?".
- **Sector 02 (Concurrency)** — shares BLOCKER-3 evidence. The advisory lock at `worker.rs:693` (`pg_try_advisory_lock`) prevents two *live* pods from running the worker; P-03-1's stop flag prevents one pod from running the worker *after* SIGTERM. Different problem, same spawn site.
- **Sector 05 (Billing & state-machine)** — the lease-TTL reclamation (`reclaim_expired_leases`) is the fallback that catches rows the drain missed. P-03-3 names it; Sector 05 owns its correctness. Also `main.rs:374` metering-drain overlap with Sector 05's "no double-bill" (`metering.rs` records `usage_log` on the same discounted basis as `finalize_success`).
- **Sector 08 (Wire/contract)** — the abort-signal forwarding in P-03-4 overlaps with the "4xx vs 5xx recoverability" lens (`generateCosmosImage.ts` marks `ABORTED` as `recoverable: true` at `:216`); Sector 08 owns the recoverability classification, Sector 03 owns that the signal reaches the upstream.
- **Sector 09 (Multi-repo & deploy ordering)** — P-03-2's 30s timeout must be ≤ helm `terminationGracePeriodSeconds`; if a PR raises the timeout it must land with a helm bump. Flagged here, owned by Sector 09.
- **Sector 12 (Code smell)** — the `_handle` binding pattern (`main.rs:326` `_batch_sweep_handle`) is also a naming smell ("intentionally unused" hides the drop); Sector 12 owns the naming lens, Sector 03 owns the consequence (orphan).

### Paradigms that arguably belong elsewhere

- **P-03-5 (AtomicBool over CancellationToken)** is half a Sector 12 (dependency-choice / Ponytail-ladder) concern. Kept here because the *trigger* is a shutdown-signal addition, which is this sector's entry point; the dependency decision is the secondary lens. The dedup pass may split it.
- **P-03-4 (abort-signal forwarding)** spans the Rust gateway and the TS app; the *gateway-side* forwarding (does `proxy_non_streaming` take a signal?) is not yet implemented and may belong in Sector 08 or a future Sector. Flagged, not moved.

## Sector-specific failure modes

- **Flagging a `_handle` binding as a bug without checking idempotence.** `main.rs:326` (`_batch_sweep_handle`) and the reaper are *deliberately* brute-aborted because their ticks are transactionally idempotent. An agent that mechanically flags every `_handle` will produce false positives on the reaper/sweep/rollup and miss that only the *worker* holds non-idempotent GPU work. The gate is "does this task hold work that a re-run cannot safely redo?", not "is the handle bound to `_`?".
- **Treating `AtomicBool` as universally sufficient.** A loop blocked in an uncancelable `await` (DB query, HTTP call with no per-request timeout) will not check the flag until it returns. P-03-5's caveat is load-bearing: `AtomicBool` works for the worker because every `await` (`claim_requests`, `proxy_non_streaming`, S3 PUT) is individually bounded; a new loop with an unbounded `await` needs `select!` on a `CancellationToken`, not a flag check at the top.
- **Confirming "stop flag present" without checking the claim-site gate.** P-03-1's adversarial caveat: a flag checked only at the outer loop top (`worker.rs:704`) still admits rows for the whole tick after SIGTERM. The *real* gate is `drain_deployment:175` (`!stop.load(Ordering::SeqCst)` before `claim_requests`). An agent that greps for `stop.load` and finds one hit will pass a loop that orphans within a tick.
- **Assuming the 30s timeout is safe because it exists.** P-03-2's caveat: 30s equals the K8s default `terminationGracePeriodSeconds`, so the pod can be SIGKILLed concurrently with the timeout elapsing. An agent that confirms "timeout present" without cross-checking the helm value (Sector 09) can pass a drain that never completes in production. The timeout is a *bound*, not a guarantee.
- **Confusing "drain" with "abort".** P-03-3: draining means letting in-flight work reach a terminal state; aborting means cancelling it mid-flight. The reaper/sweep are *aborted* (safe because idempotent); the worker is *drained* (necessary because GPU work). An agent that suggests `.abort()` for the worker, or a stop-flag-join for the reaper, has inverted the tiering and either reintroduces orphans or adds unneeded complexity.

# Sector 05 — Billing & state-machine integrity

## Scope

This sector owns the billing-transaction and batch-state-machine invariants
Andrea applies to every batch PR: that cost is booked in the *same* transaction
as the terminal state flip (so a crash between them cannot bill-without-state
or state-without-bill), that no retry/reclaim/re-delivery path can double-bill,
that every terminalization writes a terminal status (no row is ever left in a
non-terminal state after the operation returns), that state-machine swaps are
complete on both the request and batch rows, and that the half-rate discount
is applied *exactly once* at one site so `batch_request.cost_usd` and
`usage_log.cost_usd` agree. Its boundaries: idempotency *gate-key* shape and
re-arm semantics live in Sector 01 (Idempotency); the `FOR UPDATE SKIP LOCKED`
claim race and `lock_batch` serialization live in Sector 02 (Concurrency);
SIGTERM drain of the in-flight worker that *prevents* the orphan+double-run
lives in Sector 03 (Graceful shutdown); the `BatchStatus::is_terminal` *409
gate contract* on the files route is shared with Sector 08 (Wire conformance)
for its OpenAI SDK meaning but the *terminal-status-always-written* invariant
is this sector's. The no-double-billing rebuttal is the load-bearing evidence
this sector contributes to the playbook.

## Paradigms (7 entries)

### P-05-1: Book cost and terminal-state flip in one transaction

**Paradigm statement** — The bill (usage_log INSERT + `spent_usd` increments)
and the terminal state flip (`batch_request.status → 'succeeded'`,
`result_attempt` stamp, batch-level `completed` flip) MUST commit in a single
database transaction. A crash, panic, or `?` error between the bill and the
state flip must not leave a billed row marked `in_flight` (re-billable) or a
flipped row unbilled (theft). The billing function owns the transaction; it
does not delegate the flip to a caller that commits separately.

**Source evidence** — `feedback-divergences.md` "Restart-safe billing: cost
booked in same transaction as terminal state flip, guarded by row state" (ADR
0001, "Andreas explicitly praised this in the review"); `feedback-divergences.md`
"First-build items Andreas praised" — "Crash-safe exactly-once finalize
(`in_flight` guard + `lock_batch` drain)"; playbook convention
"State-machine terminal status". Load-bearing sentence: *"cost booked in
same transaction as terminal state flip"*.

**<Provider> infra anchor** — `src/batch/billing.rs:109` (`let mut tx =
pool.begin().await?`), `billing.rs:113-139` (the `UPDATE batch_request SET
status='succeeded' … result_attempt = $9 … AND attempt = $9` flip), `billing.rs:146`
(`apply_usage_writes(&mut tx, &record, Some(args.batch_id))` — the usage_log
INSERT + spend increments on the *same* `tx`), `billing.rs:148`
(`complete_batch_if_drained(&mut tx, …)` — the batch→`completed` flip on the
same `tx`), `billing.rs:149` (`tx.commit().await?`). The `lock_batch` at
`billing.rs:110` (`SELECT 1 FROM batch WHERE id = $1 FOR UPDATE`) serializes
concurrent finalizes for one batch so two drain checks can't each see the
other's uncommitted flip and both no-op (documented at `billing.rs:158-160`).
`metering.rs:240` (`apply_usage_writes`) is the shared INSERT used by both the
sync path (`metering.rs:212`, `batch_id=None`) and the batch finalize path
(`billing.rs:146`, `batch_id=Some`), so the batch path reuses the
already-audited billing writes rather than hand-rolling a second INSERT.

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/gateway "trace finalize_success billing transaction"`
> → confirm `finalize_success` holds the `tx` open across the flip +
> `apply_usage_writes` + `complete_batch_if_drained` + `commit`. Then
> `codebase-memory` `trace_path` mode `data_flow` on `apply_usage_writes` to
> confirm both the sync and batch callers pass it a `&mut PgConnection`
> they own (not a free-standing pool) — the caller-owned-connection contract
> is what makes same-txn possible.

**Fix-suggestion policy** —
> SUGGEST ONLY: if a PR splits the bill from the flip (e.g. a new finalize
> that calls `apply_usage_writes` on a pool then flips status in a second
> query), open a finding citing `billing.rs:109-149` as the canonical
> single-txn sibling and ADR 0001. Do NOT commit a patch; the PR author
> owns the fix.

**Adversarial caveat** — A single transaction is necessary but not sufficient
for exactly-once: it guarantees atomicity *within one finalize call*, not
across two calls racing on the same row. The `AND attempt = $9` guard
(P-05-3) is what makes two racing finalizes not double-bill; the transaction
only ensures neither half-commits alone.

### P-05-2: Apply the half-rate discount at exactly one site

**Paradigm statement** — The batch discount (50% / half-rate) MUST be applied
at exactly one place in the call path, and that place MUST be where the cost
is bound into the row that both `batch_request.cost_usd` and
`usage_log.cost_usd` are derived from. If two layers each halve, the customer
is billed 25%; if zero layers halve, the discount is silently dropped; if the
worker halves *and* finalize halves, `usage_log.cost_usd` (the audit/billing
row) drifts from `batch_request.cost_usd` (the per-line row). Andrea's praise
is explicit: "half-rate applied exactly once at one site, landing identically
on `batch_request.cost_usd` and `usage_log.cost_usd`".

**Source evidence** — `gateway.md` Rebuttal(f) endorsement row "half-rate
applied once, metering no sync-path regression" — *"Half-rate applied exactly
once at one site, landing identically on `batch_request.cost_usd` and
`usage_log.cost_usd`; worker's route() budget re-check is fresh; no sync-path
regression in metering.rs"* (verdict ADDRESSED, Andrea endorsed).
`feedback-divergences.md` "From the original implementation plan" — "Half-rate
metering as internal budget incentive, not '50% cheaper' marketing".

**<Provider> infra anchor** — The single discount site is
`src/batch/billing.rs:112` (`let discounted = discount(args.record.cost_usd)`)
inside `finalize_success`, immediately followed by `billing.rs:145`
(`record.cost_usd = discounted`) so the `record` handed to
`apply_usage_writes` already carries the discounted value. The worker
deliberately passes the *full* cost: `src/batch/worker.rs:492` comment
*"FULL usage-priced cost — finalize_success applies the 50% batch discount
itself"* and `worker.rs:517` (`cost_usd: cost` where `cost` is the undiscounted
`preflight::compute_cost`). Because `apply_usage_writes` binds `u.cost_usd`
straight onto both `usage_log.cost_usd` (`metering.rs:265`) and the
`spent_usd` increments (`metering.rs:296`, `metering.rs:326`), the discounted
value lands identically on all three columns. The `discount` function itself
is pure and unit-pinned: `billing.rs:300` `discount_is_exactly_half_with_no_rounding`
asserts `0.000003 / 2 = 0.0000015` survives 7 decimal places.

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/gateway "where is the batch discount applied"`
> → confirm `discount(` appears in exactly one non-test call site
> (`billing.rs:112`). Cross-check with `semble_search "cost_usd half batch
> discount finalize"` to surface any sibling that might re-apply it. Then
> `codebase-memory` `trace_path` `data_flow` from `worker.rs:494`
> (`preflight::compute_cost`) → `worker.rs:517` (`cost_usd`) → `billing.rs:112`
> (`discount`) → `metering.rs:265` (`usage_log.cost_usd`) to verify the value
> is halved once and never re-halved.

**Fix-suggestion policy** —
> SUGGEST ONLY: if a PR adds a second `discount(` call (e.g. in the worker or
> in a new metering wrapper), open a finding citing `billing.rs:112` as the
> single canonical site and the `discount_is_exactly_half` test as the pin.
> Do NOT commit; the PR author owns the fix.

**Adversarial caveat** — "Exactly one site" is a property of the *value's
lifetime*, not a grep count. A refactor that moves the discount from
`finalize_success` into the worker (still one site, earlier in the path) is
correct as long as the discounted value is what reaches `apply_usage_writes`;
the paradigm flags *drift between the two cost_usd columns*, not literal call
count. A false positive: flagging a test helper that calls `discount` to build
expected values.

### P-05-3: Pin every finalize to the claim generation with `AND attempt = $N`

**Paradigm statement** — Every terminalization (`finalize_success` and
`finalize_failure`) MUST guard its `UPDATE … WHERE` with `AND attempt = $N`
bound to the claim generation the worker used to write the result object. A
stale worker whose lease was reclaimed (bumping `attempt`) must no-op
(`rows_affected() == 0 → AlreadyFinal`), never stamp `result_attempt` at a
wrong generation or re-bill. This is the guard that makes a SIGTERM-dropped
worker safe to re-run: the re-claim bumps `attempt`, so the stale finalize's
`WHERE` matches zero rows.

**Source evidence** — `gateway.md` "Notes on the review" no-double-billing
rebuttal — *"`finalize_success` guards `AND attempt = $9`; reclaim bumps
attempt; a stale finalize no-ops. The re-run bills once."* (verdict
ADDRESSED, rebuttal verified true). `gateway.md` MINOR-1 — *"finalize_failure
has no attempt guard, unlike finalize_success … a double-reclaim can stamp
`result_attempt` at a wrong generation"* (Mateo added `AND attempt = $7`,
symmetric with `finalize_success`). Playbook paradigm #6 "Check the re-arm /
idempotency gate".

**<Provider> infra anchor** — `src/batch/billing.rs:127` (`AND attempt = $9`
inside `finalize_success`, the guard Andrea cited verbatim);
`billing.rs:140-142` (`if flipped.rows_affected() == 0 { return
Ok(FinalizeOutcome::AlreadyFinal) }` — the no-op, no-bill branch);
`src/batch/billing.rs:262-263` (`AND attempt = $7` inside `finalize_failure`,
the symmetry fix from MINOR-1); `billing.rs:274-276` (the matching
`AlreadyFinal` no-op branch). The pinning comment at `billing.rs:114-120`
documents the exact invariant: *"result_attempt := the claim generation the
worker used to key the just-written result object … if a lease-reclaim race
advanced the row's attempt after the PUT, this stale finalize no-ops"*.
`store.rs:538` — `select_exhausted_queued` returns `(String, i32, i32)`
including `attempt` so the worker threads the live generation into both
finalize calls. The test `finalize_success_second_call_is_noop_and_never_double_bills`
at `billing.rs:594` pins it: two calls → `AlreadyFinal`, exactly one
`usage_log` row, `spent_usd` unmoved on the second.

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/gateway "BatchStatus is_terminal gate"`
> is the wrong query here — use `codegraph explore -p ~/<provider>/gateway
> "finalize_success finalize_failure attempt guard"` to surface both UPDATE
> statements. Then Serena `find_symbol` on `finalize_success` and
> `finalize_failure` and `find_referencing_symbols` to enumerate every
> caller; confirm each caller threads an `attempt` value (not a literal or
> `None`). `codebase-memory` `query_graph` Cypher:
> `MATCH (f:Function)-[:CALLS]->(t:Function) WHERE t.name IN
> ['finalize_success','finalize_failure'] RETURN f.name, f.file` to catch a
> new caller that forgets the param.

**Fix-suggestion policy** —
> SUGGEST ONLY: if a PR adds a third finalize path (e.g. a new
> `finalize_cancelled`) without `AND attempt = $N` and the `rows_affected()
> == 0 → AlreadyFinal` branch, open a finding citing `billing.rs:127` and
> `billing.rs:262-263` as the symmetric pair and MINOR-1 as the precedent
> ("a missing guard is a bug, not a style choice"). Do NOT commit; the PR
> author owns the fix.

**Adversarial caveat** — The guard protects against *stale-worker* double
billing, not against a worker that legitimately re-claims and re-runs the
same line — that re-run *should* bill (it did new GPU work). A reviewer who
reads "no double-bill" too broadly might demand the re-run be free, which
would be under-billing. The `reclaim bumps attempt` semantics are the reason
the re-run bills: the new claim's `attempt` matches, so the guard passes.

### P-05-4: Every terminalization writes a terminal status — no non-terminal leak

**Paradigm statement** — No function that advances the batch state machine may
return leaving a row in a non-terminal state when the operation's intent was
terminal. `expire_batches` must set `status='expired'` (not just clear
`expires_at`). `finalize_failure` must set a terminal `RequestStatus`
(`errored`/`canceled`/`expired`), never leave `queued`/`in_flight`.
`complete_batch_if_drained` must either flip the batch to `completed` (or
hand off to the reaper for `cancelling`→`cancelled`) — never leave a fully
drained batch in `in_progress`. A swap that leaves the row in a non-terminal
state is a leak: the reaper re-touches it, the files route 409s forever, or
the batch never terminates.

**Source evidence** — Playbook convention "State-machine terminal status" —
*"Every state-machine swap must write a terminal status; a swap that leaves
the row in a non-terminal state is a leak."* Playbook critical path
"User-memory / dream PR" step 2 — *"Does every state-machine swap write a
terminal status (not leave the row in a non-terminal state)?
`src/controllers/reviewActions.ts:74`"*. `gateway.md` MAJOR-4 — *"An expired
batch produces no result file and no error file … `total != completed +
failed` breaks the OpenAI SDK contract"* — fixed by `expire_batches` setting
`status='expired'` + `error_code='batch_expired'`.

**<Provider> infra anchor** — `src/batch/store.rs:805` (`SET status =
'expired', error_code = 'batch_expired'` for queued rows of expired batches)
and `store.rs:822` (`UPDATE batch SET status = 'expired', expired_at = $1,
terminal_at = $1` — the batch-level terminal flip writes `terminal_at`, the
terminal timestamp). `src/batch/billing.rs:196-200` (`complete_batch_if_drained`
flips `batch.status = 'completed' … WHERE status = 'in_progress' AND NOT
EXISTS (SELECT 1 FROM batch_request WHERE status = 'expired')` — the
`NOT EXISTS expired` guard prevents a drained batch with expired lines from
being mislabeled `completed`; those are the reaper's to expire).
`src/batch/billing.rs:261` (`finalize_failure` sets `result_attempt = attempt`
and a terminal `status = $3` in the same UPDATE — never leaves `in_flight`).
The `BatchStatus::is_terminal` predicate at `types.rs:48-54` returns true only
for `Completed | Expired | Cancelled | Failed`, and the files route gates on
it at `src/routes/files.rs:216-220` (`if !status.is_terminal() { return
Err(GatewayError::Conflict(…)) }`), so a leaked non-terminal batch is
*observable* — callers get 409, which is how MINOR-3 was caught.

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/gateway "BatchStatus is_terminal gate"`
> → confirm `is_terminal` is the single predicate both the files route and
> the `batches.rs` file-id gate route through. Then `grep` the gateway for
> `UPDATE batch SET status` and `UPDATE batch_request SET status` to
> enumerate every state-write site; for each, confirm it sets a terminal
> status (or is a `queued`→`in_flight` non-terminal advance, which is
> legitimate). `codebase-memory` `search_graph` `name_pattern =
> ".*expire.*|.*finalize.*|.*cancel.*"` to find every terminalizer and check
> it writes a terminal value.

**Fix-suggestion policy** —
> SUGGEST ONLY: if a PR adds a state transition that `UPDATE`s `status`
> without either landing a terminal value or being an explicit
> `queued`→`in_flight` advance, open a finding citing `store.rs:805,822`
> (expire writes terminal + `terminal_at`) and `billing.rs:196` (complete
> writes `completed` + `terminal_at`). Do NOT commit; the PR author owns the
> fix.

**Adversarial caveat** — "Terminal status always written" does not mean
"every UPDATE must go to terminal." The legitimate non-terminal advance is
`queued`→`in_flight` (the claim) and `in_progress`→`cancelling` (cancel
requested, draining). A reviewer who flags the claim UPDATE as a "leak" is
wrong — the leak invariant is about *terminalization* paths, not advance
paths. The distinguishing question: does the operation *intend* to end the
lifecycle? If yes, it must write terminal; if it's an intermediate step, it
must not.

### P-05-5: Enforce budget at admission (fresh re-check), not at finalize-time grace

**Paradigm statement** — The per-key/user budget cap MUST be enforced when the
worker admits a row (a fresh read of `spent_usd` via `route()`), NOT as a
finalize-time predicate that skips billing when over budget. The
`spent_usd` counter MUST move unconditionally on every successful bill (#1347
direction: the counter's job is to be *true*, the cap is enforced
post-hoc). Mixing the two — bumping `spent_usd` only when under budget —
produces a counter that lies (it never crosses the cap, so the cap never
fires) and a silent under-bill.

**Source evidence** — `feedback-divergences.md` "Billing conflict
resolution (Mateo's comment, aligned with post-#1347 main)" — *"Unconditional
`spent_usd` bump (#1347 direction)"* and *"Budget enforced at worker
admission (`route()` fresh re-check), not finalize-time grace"*. The
`metering.rs:278-281` comment states it directly: *"No budget predicate
(#1347): the counter's job is to be true; the cap is enforced post-hoc at
admission."*

**<Provider> infra anchor** — `src/batch/worker.rs:339`
(`store::fetch_fresh_key_by_id(&state.pool, &row.key_id)` — the worker reads
a *fresh* key, not the cached auth-time key, so `spent_usd` reflects bills
landed by other workers/concurrent sync traffic since the batch was created);
`worker.rs:369` (`let key = cached_key_from_fresh(fresh)`) builds the
`CachedKey` the budget check reads; the budget arm at `worker.rs:410-422`
(`finalize_failure(Errored, …, "insufficient_budget", …)` + `bulk_error_queued`)
terminalizes the row *and* errors the queued siblings when the fresh re-check
shows insufficient budget — admission enforcement. On the write side,
`metering.rs:281` (`if u.cost_usd > Decimal::ZERO`) unconditionally runs the
`spent_usd` increments (`metering.rs:282-296` for the user,
`metering.rs:326` for the key) with no budget predicate; the test
`apply_usage_writes_user_over_budget_still_increments` at `metering.rs:684`
pins it (over-budget still writes the row and moves `spent_usd` to 6.0).

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/gateway "worker fresh key budget
> admission route"` → confirm the worker calls `fetch_fresh_key_by_id` and
> `preflight::route` per row, not the auth-cached key. Then `semble_search
> "spent_usd budget predicate skip"` to catch any new write path that
> conditions the increment on `spent_usd < budget_usd` (the anti-pattern).
> `codebase-memory` `search_graph` `semantic_query = ["budget guard
> admission enforce spent_usd"]` to locate the admission site and verify no
> finalize path carries a budget predicate.

**Fix-suggestion policy** —
> SUGGEST ONLY: if a PR adds a `WHERE spent_usd < budget_usd` predicate to
> the `spent_usd` increment (making the counter stop at the cap) or moves
> the budget check from the worker's fresh `route()` into `finalize_success`
> (finalize-time grace), open a finding citing `metering.rs:278-281` (the
> #1347 comment) and `worker.rs:339-422` (admission enforcement). Do NOT
> commit; the PR author owns the fix.

**Adversarial caveat** — Unconditional increment means a buggy or malicious
upstream that inflates `cost_usd` can push `spent_usd` arbitrarily far past
the cap before the next admission check fires. The cap is *not* a hard
spend ceiling; it is enforced at the *next* row's admission, so over-bill is
bounded by one row's cost × concurrency, not zero. A reviewer demanding "the
counter can never exceed the cap" is asking for a different (and more
expensive — per-row `FOR UPDATE` on the users row) invariant than #1347
chose.

### P-05-6: Keep `request_counts` folding honest — `failed` is errored only, never canceled/expired

**Paradigm statement** — The OpenAI `request_counts` rollup MUST map
`succeeded→completed` and `errored→failed`, with `canceled` and `expired`
counting *only toward `total`* (never folded into `failed`). Folding
canceled/expired into `failed` breaks the OpenAI SDK invariant
`total == completed + failed + (in_flight/queued)` and makes an expired batch
look like a pile of model failures. The error-file gate must likewise key on
*real* failures (`failed > 0 || expired > 0`), not on a status bucket that
silently includes lifecycle cancellations.

**Source evidence** — `feedback-divergences.md` schema row —
*"`request_counts.failed` must not fold canceled/expired; gate `error_file_id`
on real failures"* — *"Already correct in first build; Andreas said keep"*.
`gateway.md` MAJOR-4 — the expired-batch fix widened error-file synthesis to
`["errored", "expired"]` and the `error_file_id` gate to `failed > 0 ||
expired > 0`. `feedback-divergences.md` "First-build items Andreas praised" —
*"`request_counts` serializers"*.

**<Provider> infra anchor** — `src/batch/types.rs:99-114`
(`RequestCounts::from_tallies`): `completed: tallies.succeeded`, `failed:
tallies.errored`, and `total` sums all six buckets including `canceled` and
`expired` — canceled/expired are deliberately *not* in `failed`. The comment
at `types.rs:100-101` pins the mapping: *"succeeded→completed, errored→failed;
canceled and expired count only toward total"*. The error-file gate at
`src/routes/batches.rs:95` (`(counts.failed > 0 || tallies.expired >
0).then(|| error_file_id_for(&row.id))`) keys on real failures and expired,
not on canceled. The synthesis filter at `src/routes/files.rs:288`
(`SyntheticKind::Error => &["errored", "expired"]`) matches the same set.
The `RequestStatus`/`BatchStatus` serializers at `types.rs:9-33` use
`#[serde(rename_all = "snake_case")]` so the wire spelling (`in_progress`,
`cancelled` double-L at batch level, `canceled` single-L at request level)
is pinned by derive, not hand-rolled.

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/gateway "request_counts from_tallies
> failed completed rollup"` → confirm the mapping is the single source of
> truth for the rollup. `semble_search "error_file_id failed expired gate"`
> to verify the gate and the synthesis filter agree on the same status set
> (a drift between them is the bug). `codebase-memory` `search_graph`
> `name_pattern = "RequestCounts|RequestTallies"` to find every reader and
> confirm none hand-rolls its own fold.

**Fix-suggestion policy** —
> SUGGEST ONLY: if a PR changes `failed: tallies.errored` to
> `failed: tallies.errored + tallies.canceled` (or adds a new terminal
> status without deciding whether it folds into `failed`), open a finding
> citing `types.rs:99-114` and the OpenAI SDK `total != completed + failed`
> contract from MAJOR-4. Do NOT commit; the PR author owns the fix.

**Adversarial caveat** — "Never fold canceled/expired into failed" is an
OpenAI-wire *contract*, not a universal truth — a different API dialect might
legitimately fold them. The paradigm is specific to OpenAI-exact conformance
(Sector 08 owns the dialect question); a reviewer flagging a fold in a
non-OpenAI-shaped internal endpoint is over-applying. The distinguishing test:
does the endpoint claim OpenAI wire conformance? If yes, no fold; if no, the
fold is a design choice.

### P-05-7: Gate result-file reads on batch terminality — 409 while in-flight

**Paradigm statement** — A synthetic result/error file download for a batch
MUST 409 Conflict (not 200 with partial content, not 404) while the batch is
in a non-terminal state. Serving a partial output file mid-run lets a caller
read an incomplete `request_counts` and a half-written result set,
materializing a transient state as if it were final. The gate must route
through a single `is_terminal()` predicate shared by the file-id gate and the
content gate so the two cannot drift.

**Source evidence** — `gateway.md` MINOR-3 — *"Synthetic result files served
for non-terminal batches … `files.rs:166-179` doesn't gate the download on
`batch.status`; a caller can pull a partial output file mid-run."* Mateo
added `BatchStatus::is_terminal()`; `file_content_inner` returns 409 if not
terminal; the duplicated inline `matches!` in `batches.rs` was replaced with
the shared method (verdict ADDRESSED).

**<Provider> infra anchor** — `src/routes/files.rs:216-220` (`if
!status.is_terminal() { return Err(GatewayError::Conflict(format!("Batch is
still {}; results are not available until the batch is complete.",
batch.status))) }`) inside `file_content_inner`. The shared predicate is
`src/batch/types.rs:48-54` (`impl BatchStatus { pub fn is_terminal(&self) ->
bool { matches!(self, Self::Completed | Self::Expired | Self::Cancelled |
Self::Failed) } }`). The file-id gate at `src/routes/batches.rs:92` reuses
the same `is_terminal()` (MINOR-3's "replaced duplicated inline `matches!`"),
so the gate and the content route cannot disagree on what "terminal" means.
`GatewayError::Conflict` maps to HTTP 409 — the correct "state conflict,
retry later" code, not 404 (which would hide a real missing batch) or 200
(which would serve partial data).

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/gateway "BatchStatus is_terminal gate"`
> → confirm both `files.rs:216` and `batches.rs:92` call `is_terminal()`,
> not a hand-rolled `matches!`. Serena `find_referencing_symbols` on
> `BatchStatus::is_terminal` to enumerate every caller; a new caller that
> inlines its own terminal-set is the drift smell. `semble_search "409
> Conflict batch not terminal"` to locate any sibling route that should
> gate but doesn't.

**Fix-suggestion policy** —
> SUGGEST ONLY: if a PR adds a new read route over batch results that does
> not call `is_terminal()` (or inlines a `matches!` with a different status
> set), open a finding citing `files.rs:216-220` as the canonical gate and
> MINOR-3 as the precedent. Do NOT commit; the PR author owns the fix.

**Adversarial caveat** — 409 while in-flight is correct for *synthetic*
result files (assembled from the live `batch_request` rows), but a
*real* S3 object (a per-line result PUT before finalize, per ADR 0004) is
already immutable and could legitimately be read directly by an internal
debug path — gating it on batch terminality would be wrong. The paradigm
applies to the *aggregated/synthetic* surface, not to raw object fetches
that are individually terminal the moment they're PUT.

## Cross-sector links

- **Sector 01 (Idempotency & re-arm gates)** — P-05-3 (`AND attempt = $N`) is
  the idempotency gate for the finalize path; its *gate-key shape* (deterministic
  claim-generation counter, not ciphertext) is Sector 01's lens, while the
  *billing-no-double-bill* consequence is this sector's. The two sectors share
  the `billing.rs:127` evidence and the
  `finalize_success_second_call_is_noop_and_never_double_bills` test. Dedup
  pass: keep the gate-key-shape framing in Sector 01, the no-double-bill
  framing here.
- **Sector 02 (Concurrency & race conditions)** — `lock_batch`
  (`billing.rs:110`, `SELECT … FOR UPDATE`) serializes concurrent finalizes
  for one batch; P-05-1 depends on it (without the lock, two drain checks each
  see the other's uncommitted flip and neither completes the batch). The
  `FOR UPDATE SKIP LOCKED` claim race and the `FOR UPDATE` batch lock are both
  Sector 02's concurrency lens; this sector cites the lock only as a
  precondition for same-txn atomicity.
- **Sector 03 (Graceful shutdown & drain)** — BLOCKER-2's orphan-leak +
  double-GPU-run is a shutdown bug whose *billing consequence* (could the
  re-run double-bill?) is this sector's. The no-double-billing rebuttal
  (`AND attempt = $9` makes the stale finalize no-op) is the load-bearing
  evidence that BLOCKER-2's severity was overstated *on the billing axis*
  while remaining a real shutdown/orphan bug. Shares BLOCKER-2 evidence;
  Sector 03 owns the drain, this sector owns the "but it doesn't double-bill"
  rebuttal.
- **Sector 08 (Wire/contract conformance)** — P-05-6 (`request_counts` fold)
  and P-05-7 (409 while in-flight) are OpenAI-wire contracts; the *folding
  rule* and the *409 status code choice* are arguably Sector 08's wire lens,
  while the *state-machine-terminality* invariant that motivates them is this
  sector's. Dedup pass: the 409 gate and the fold may be summarized in
  Sector 08 with a backreference here; this sector keeps the "terminal status
  always written so the gate can fire" causal chain.
- **Sector 07 (Schema & migrations)** — The `batch_id` column on `usage_log`
  (V43, `metering.rs:269`) is what lets the batch finalize path tag its
  usage_log row; the `result_attempt` / `det_failures` columns (V43/V44) are
  what the `AND attempt` guard and the exhaustion sweep key on. A migration
  that drops or renames these columns silently breaks P-05-3 and P-05-1.
  Flagged, not written here.

## Sector-specific failure modes

- **Flagging a re-claim re-run as a double-bill.** The `AND attempt = $N`
  guard no-ops a *stale* worker; a *fresh* re-claim bumps `attempt` and the
  re-run legitimately matches and bills (it did new GPU work). An agent that
  reads "no double-bill" as "the re-run must be free" will demand under-billing.
  The distinguishing test: did the `attempt` the worker holds match the row's
  current `attempt`? Yes → bill (correct); No → no-op (correct). Both are
  correct; neither is a bug.
- **Treating `lock_batch` / `FOR UPDATE` as the same-txn guarantee.** The
  `SELECT … FOR UPDATE` serializes concurrent finalizes; it does NOT make the
  bill-and-flip atomic — `tx.commit()` does. An agent that "fixes" a
  split-bill by adding a lock without merging the queries has not fixed the
  crash-between-bill-and-flip hole. The lock is necessary (P-05-1 depends on
  it via Sector 02), but the single `tx.commit()` is the load-bearing piece.
- **Demanding the `spent_usd` counter never exceed the cap.** P-05-5's
  #1347 direction is *unconditional* increment with post-hoc admission
  enforcement; the counter will exceed the cap by up to one row's cost ×
  concurrency. An agent that flags this as "budget violated" is wrong — the
  invariant is "the cap is enforced at the next admission," not "the counter
  is a hard ceiling." A hard ceiling needs per-row `FOR UPDATE` on the users
  row, which #1347 deliberately rejected.
- **Flagging the `queued`→`in_flight` claim UPDATE as a "non-terminal leak."**
  P-05-4's "terminal status always written" applies to *terminalization*
  paths, not intermediate advances. The claim (`queued`→`in_flight`) and the
  cancel-request (`in_progress`→`cancelling`) are legitimate non-terminal
  writes. An agent that flags every `UPDATE … SET status` that doesn't land
  a terminal value is over-applying; the test is whether the operation
  *intends* to end the lifecycle.
- **Treating `discount(` grep count as the "exactly one site" proof.** P-05-2
  is a property of the *value's lifetime* (the discounted value reaches both
  `cost_usd` columns without re-halving), not a literal call count. Test
  helpers that call `discount` to build expected values are fine; the bug is
  two *production* halvings in series. An agent that flags a test-helper
  `discount` call is a false positive.

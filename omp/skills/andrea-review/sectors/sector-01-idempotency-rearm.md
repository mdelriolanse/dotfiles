# Sector 01 — Idempotency & re-arm gates

## Scope

This sector owns the single question Andrea puts to every retry, re-run, reclaim,
or webhook re-delivery: **does the gate re-fire when it should and not duplicate
when it shouldn't — and is the gate key deterministic?** It covers deterministic
idempotency keys (HMAC / hash / UID, NOT ciphertext), retry-backoff jitter,
`expectedVersion` / optimistic-concurrency travel into retry handlers, finalize
idempotence guards (`AND attempt = $N`), and claim/lease re-claim safety. It does
NOT own the *concurrency* mechanism itself (`FOR UPDATE SKIP LOCKED` as an MVCC
disjointness primitive belongs to Sector 02 Concurrency, and the *graceful-shutdown*
drain that prevents the orphan leak in the first place belongs to Sector 03); this
sector owns only the *idempotence gate* that makes a double-run harmless when the
drain fails. Billing-correctness-as-state-machine (terminal-status-always-written,
same-txn finalize) is Sector 05; this sector owns only the `attempt` guard that
makes the finalize idempotent across re-claims.

## Paradigms (7 entries)

### P-01-1: Require a finalize idempotence guard pinned to the claim generation

**Paradigm statement** — Every terminal-status write on a reclaimable row must
be guarded by `AND attempt = $N` (the claim generation the worker holds), so a
stale worker whose lease was already reclaimed no-ops (`rows_affected() == 0` →
`AlreadyFinal`) instead of stamping `result_attempt` past the object it actually
wrote or double-billing. The guard is what turns "crash → reclaim → re-run" into
"bills exactly once" rather than "bills once per surviving worker." Both the
success and failure finalizes must carry it symmetrically — a guard on success
only leaves the failure path open to a double-reclaim stamping a wrong
`result_attempt` generation.

**Source evidence** — `gateway.md MINOR-1`: "`billing.rs:258` does
`SET result_attempt = attempt WHERE status IN ('queued','in_flight')` with no
`AND attempt = $N`; a double-reclaim can stamp `result_attempt` at a wrong
generation." `gateway.md` "Notes on the review" BLOCKER-2 no-double-billing
rebuttal: "`finalize_success` guards `AND attempt = $9`; reclaim bumps attempt;
a stale finalize no-ops. The re-run bills once." `playbook paradigm #6`: "Check
the re-arm / idempotency gate … must actually re-fire when it should, and not
duplicate when it shouldn't. The gate key must be deterministic."

**<Provider> infra anchor** —
`src/batch/billing.rs:121-128` (`finalize_success` UPDATE, guard
`WHERE batch_id = $1 AND line_no = $2 AND status = 'in_flight' AND attempt = $9`,
with doc comment "Guarding WHERE attempt = $9 pins the commit to that generation:
if a lease-reclaim race advanced the row's attempt after the PUT, this stale
finalize no-ops"). `src/batch/billing.rs:250-275` (`finalize_failure` UPDATE,
guard `... AND status IN ('queued', 'in_flight') AND attempt = $7`, symmetric).
The no-op branch: `billing.rs:140-142` / `:274-276`
(`if flipped.rows_affected() == 0 { return Ok(FinalizeOutcome::AlreadyFinal) }`).
Pinned by test `finalize_success_second_call_is_noop_and_never_double_bills` at
`billing.rs:594` and `finalize_failure_second_call_is_noop` at `billing.rs:818`.
The re-arm that makes the guard load-bearing: `claim_requests` at
`store.rs:460-463` does `SET ... attempt = br.attempt + 1` — each reclaim advances
the generation, so a stale worker's `attempt` no longer matches and the guard
rejects it. (All paths resolve to the gateway worktree
`feat-batch-api-gateway/src/batch/`.)

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/gateway "trace finalize_success AND attempt guard"` — confirms the guard, the `AlreadyFinal` no-op, and the reclaim-bumps-attempt call path. The verbatim source block it returns is byte-identical to `read` on `billing.rs:121-128`.
> Serena `find_symbol` on `finalize_success` and `finalize_failure` to confirm both carry the `attempt` param and the `AND attempt = $N` guard; `find_referencing_symbols` on `finalize_success` to confirm every caller (the worker's per-row path) passes `args.attempt` from the claim, not a fresh `Utc::now`-derived value.
> `semble_search "finalize attempt guard rows_affected AlreadyFinal"` to locate any sibling finalize path that forgot the guard (the MINOR-1 finding was exactly such a sibling).

**Fix-suggestion policy** —
> SUGGEST ONLY: open a finding on the PR quoting MINOR-1 ("no `AND attempt = $N`;
> a double-reclaim can stamp `result_attempt` at a wrong generation"); cite the
> canonical sibling (`finalize_success` at `billing.rs:127`, `finalize_failure`
> at `billing.rs:263` after the fix); require the author to add the `attempt: i32`
> param and the `AND attempt = $N` guard symmetrically on both finalizes and to
> return `AlreadyFinal` on `rows_affected() == 0`. Do NOT commit a patch. The PR
> author owns the fix.

**Adversarial caveat** — The guard is a *correctness* gate, not a *billing*
gate: it prevents a stale worker from stamping the wrong `result_attempt`
generation (which would orphan the result object), but billing-once actually
depends on the same-txn `usage_log` insert + status flip (ADR 0001, Sector 05).
An agent could over-claim "this guard prevents double-billing" when the real
double-billing defense is the atomic transaction, not the `attempt` guard alone
— the guard is what makes the *re-run* no-op, the txn is what makes the *first*
finalize atomic. Also, the guard is useless if the caller passes a stale
`attempt` cached across the PUT; the worker must pass the `attempt` from the
claim that keyed the S3 object, not re-read it.

---

### P-01-2: Make every transient-failure counter re-arm-aware, not just the terminal writes

**Paradigm statement** — It is not enough to guard the terminal finalize; every
intermediate counter that a stale worker could double-stamp (transient-failure
counter, cancel stamp, retry counter) must also be guarded on the claim
generation. A worker that crashed after a 5xx but before bumping
`det_failures`, then had its lease reclaimed, must not increment the new
generation's `det_failures` — otherwise a row burns its entire retry budget
back-to-back in one outage window instead of spacing retries by the lease. The
re-arm gate is a property of *all* mutation paths on a reclaimable row, not
just the billable one.

**Source evidence** — `gateway.md MINOR-1` (the symmetry principle: "unlike
`finalize_success`" — the finding is that the failure path drifted from the
success path's guard, and the fix is to make them symmetric). `playbook
paradigm #6`: "Any retry, re-run, or webhook re-delivery must actually re-fire
when it should, and not duplicate when it shouldn't." `feedback-divergences`
"Attempt cap counts deterministic failures, not lease reclaims" row:
"`det_failures` column + bb925ba" — the cap is *deterministic* failures, so a
reclaim must not count as a deterministic failure, which is only true if the
bump is generation-guarded.

**<Provider> infra anchor** —
`src/batch/store.rs:505-524` (`bump_transient_failure`, UPDATE
`SET det_failures = det_failures + 1 WHERE ... AND attempt = $4 RETURNING
det_failures`, returning `None` for a stale worker — the doc comment at
`:499-503`: "Guarded on the claim generation (`attempt`) so a stale worker whose
lease was already reclaimed no-ops (returns None) instead of double-counting the
new generation. Returns the new `det_failures` so the caller can terminalize
once the count reaches the cap." This is the sibling that proves the pattern is
applied uniformly, not just on `finalize_success`. The re-arm increment that
makes it load-bearing is the same `claim_requests` `attempt = br.attempt + 1`
at `store.rs:463`.

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/gateway "bump_transient_failure attempt guard"` to confirm the guard and the `None`-on-stale return.
> codebase-memory `query_graph` (Cypher) on the gateway project: `MATCH (f:Function)-[:CALLS]->(g:Function) WHERE f.qualified_name CONTAINS 'bump_transient_failure' RETURN g` to find every caller and confirm each passes `row.attempt` from the claim, not a re-read.
> `semble_search "det_failures increment attempt guard reclaim"` to locate any sibling counter (cancel stamps, retry counters) that forgot the guard.

**Fix-suggestion policy** —
> SUGGEST ONLY: open a finding if a new per-row counter or stamp is added without
> an `AND attempt = $N` guard; cite the canonical sibling (`bump_transient_failure`
> at `store.rs:505-524`); require the author to add the guard and return a
> stale/no-op signal on `rows_affected() == 0`. Do NOT commit a patch.

**Adversarial caveat** — A generation-guarded counter that returns `None` on
stale must be *handled* by the caller: if the caller ignores the `Option` and
treats `None` as `Some(0)`, the guard silently becomes a no-op. The correctness
is in the caller's match, not just the SQL. Also, over-applying this to
*non-reclaimable* rows (e.g. a status field on a batch that is never reclaimed)
adds a guard that can never trip and obscures the intent.

---

### P-01-3: Key re-arm / re-delivery gates on a deterministic fingerprint, never on ciphertext

**Paradigm statement** — A re-arm or idempotency gate key must be a deterministic
function of stable inputs — `HMAC(secret, url)`, a content hash, or an entity UID
— never a non-deterministic ciphertext blob. `encrypt()` uses a random IV, so the
ciphertext of the same plaintext differs on every call; comparing ciphertext for
equality or using it as a dedup key fails to match the re-delivery it should
match, and a gate keyed on ciphertext either always rejects (false negative) or,
worse, is worked around with a "compare the decrypted plaintext" path that
re-introduces the comparison as a side channel. The canonical signed-webhook
pattern signs `id.timestamp.body` with HMAC and puts the timestamp *inside* the
signed string so it cannot be tampered with to widen the replay window — that is
the deterministic fingerprint shape.

**Source evidence** — `playbook` conventions "Non-deterministic encryption":
"`encrypt()` uses a random IV — ciphertext differs per call; never compare
ciphertext for equality or use it as a gate key." `playbook` conventions
"Deterministic idempotency fingerprint": "Re-arm / re-fire gates key on
`HMAC(secret, url)` or entity UID, not ciphertext." `playbook` Webhook path step
3: "Is the gate keyed on a deterministic fingerprint (HMAC/hash/UID), NOT
non-deterministic ciphertext? `src/controllers/trainingJob.controller.ts:540`."
`playbook` Webhook path step 1: "Does the signer match Standard Webhooks
(`webhook-id` / `webhook-timestamp` / `webhook-signature: v1,<b64>` over
`id.timestamp.body`)?"

**<Provider> infra anchor** —
`backend/src/controllers/automation.controller.ts:1373-1403` (`verifyWebhookSignature`):
the signed string is `` `${timestamp}.${rawBody}` `` with
`crypto.createHmac('sha256', signingSecret)` (`:1394-1396`); the timestamp is
*inside* the signed string (`:1336-1342` comment: "The timestamp is inside the
signed string, so it cannot be tampered with to widen the replay window, and
requests outside the tolerance are rejected. That bounds replay of a captured
request to the tolerance window without needing server-side nonce storage.");
constant-time compare via `crypto.timingSafeEqual` (`:1362-1367`). The signing
secret is stored encrypted-at-rest (`:1476-1482`) but the *gate key* is the
deterministic HMAC over the raw body, not the ciphertext column. NOTE: the
playbook's `trainingJob.controller.ts:540` anchor is **stale** — the webhook
signing path now lives in `automation.controller.ts:1329-1403`
(`triggerWebhook`), and `trainingJob.controller.ts` no longer carries a webhook
idempotency fingerprint (its tail at `:529-555` is a K8s custom-object delete).
The Standard-Webhooks signing convention is preserved; the idempotency
*fingerprint* anchor moved.

**Codebase-intelligence backend** —
> `semble_search "webhook signature HMAC timestamp body deterministic"` to locate the current signing site (returns `automation.controller.ts`, not the playbook's stale `trainingJob.controller.ts`).
> Serena `find_symbol` on `verifyWebhookSignature` to confirm the signed string is `timestamp.body` (timestamp *inside*), not `body` alone.
> codebase-memory `search_graph` `name_pattern="encrypt"` on the app project to confirm `encrypt()` uses a random IV (the anti-pattern), then `semble_search "compare ciphertext equality dedup key"` to catch any gate that violates the convention.

**Fix-suggestion policy** —
> SUGGEST ONLY: if a PR adds a re-delivery dedup gate keyed on a ciphertext
> column, open a finding quoting the playbook convention ("never compare
> ciphertext for equality or use it as a gate key"); cite the canonical sibling
> (`verifyWebhookSignature`'s HMAC-over-`timestamp.body`); require the author to
> re-key on `HMAC(secret, stable-input)` or an entity UID. Do NOT commit a patch.

**Adversarial caveat** — A re-delivery gate can be *correctly* absent by design:
the current `triggerWebhook` (`automation.controller.ts:1405-1543`) inserts a new
`automation_run` on every authenticated hit and relies on the HMAC timestamp
tolerance (±300s) + per-workflow rate limit to bound replays, with no explicit
dedup fingerprint. That is a deliberate "at-most-once-per-tolerance-window, no
server-side nonce storage" choice, not a missing gate — an agent flagging "no
idempotency key" here would be a false positive unless the caller's semantics
require exactly-once *across* the tolerance window. The honest state of the
codebase is: the *signing* is deterministic (HMAC), the *dedup* is bounded by
replay-window, not by a stored fingerprint. Flag the gap only if the workflow
contract requires cross-window exactly-once delivery.

---

### P-01-4: Carry `expectedVersion` into the retry handler, not just the happy path

**Paradigm statement** — Optimistic-concurrency (`expectedVersion` /
`WHERE version = $N`) must travel into the *retry* path, not die at the first
conflict. When a versioned insert conflicts because the LLM passed
`expected_version` on a first create (no prior row), the retry must re-assert
`expectedVersion: 0` (assert the create) so a concurrent first-create loser
still conflicts instead of silently inserting a second version — *and* the
retry's own conflict must surface a recoverable code so the model re-reads and
retries again rather than treating it as a fatal DB error. A retry that drops
`expectedVersion` or swallows the conflict reverts the optimistic-concurrency
guarantee to "last writer wins," which is exactly the race the version column
exists to prevent.

**Source evidence** — `playbook paradigm #7`: "Check that retries carry the
optimistic-concurrency guard. `expectedVersion` or equivalent must travel to the
retry handler, not just the happy path." `playbook` Agentic-tool path step 4:
"Does a retry or edit carry `expectedVersion`? `DraftTextTool.ts`,
`executeTool.ts:470`." `playbook` convention "Optimistic concurrency": "Versioned
rows (`tbl_chat_artifacts`, `tbl_chat_drafts`) require `expectedVersion`; retries
must forward it."

**<Provider> infra anchor** —
`backend/src/controllers/<provider>Chat.libs/agenticLoop/executeTool.ts:545-559`:
`expectedVersion` is read from `args.expected_version` (`:545-548`), forwarded
into `insertNextArtifactVersion({...expectedVersion})` on the happy path
(`:559`). On `ArtifactVersionConflictError && actualVersion === 0`
(`:569-572`, "LLM passed expected_version on a first create — no prior artifact
exists, so the assertion is meaningless"), the retry at `:577-587` re-asserts
`expectedVersion: 0` (NOT undefined) so a concurrent first-create loser still
conflicts; the retry's own conflict at `:598-608` surfaces a *recoverable*
`version_conflict` code so the model re-reads and retries rather than fataling.
`backend/src/tools/DraftTextTool.ts:83,104` is the sibling: happy path
`expectedVersion: args.expected_version` (`:83`), retry path
`expectedVersion: 0` (`:104`), retry-conflict surfaces the code marker (`:115`).
The primitive: `backend/src/services/insertNextArtifactVersion.ts:86-90`
(`if params.expectedVersion !== undefined && params.expectedVersion !==
currentVersion → throw ArtifactVersionConflictError`).
NOTE: the playbook's `executeTool.ts:470` anchor is **stale by ~75 lines** — the
expectedVersion forwarding now lives at `:545-559` (file grew); the *pattern* is
intact, the line number drifted.

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/app "expectedVersion retry handler"` — confirms the symbol cluster; the verbatim source block shows `expectedVersion` read, forwarded, and re-asserted-to-0 on the retry. (The warning that results come from a different worktree is expected — the app index is at `~/<provider>/app`.)
> Serena `find_symbol` on `insertNextArtifactVersion` to confirm it throws `ArtifactVersionConflictError` on `expectedVersion !== currentVersion`; `find_referencing_symbols` to enumerate every caller and check each has a retry path that re-asserts (not drops) the version.
> `semble_search "expectedVersion 0 retry conflict first create"` to locate any sibling insert path that swallows the conflict instead of surfacing a recoverable code.

**Fix-suggestion policy** —
> SUGGEST ONLY: if a PR adds a versioned insert whose retry path drops
> `expectedVersion` (passes `undefined`) or swallows the conflict as a fatal
> error, open a finding citing the canonical sibling (`executeTool.ts:577-587`
> retry re-asserts `0`; `DraftTextTool.ts:104`); require the author to re-assert
> the version on retry and surface a recoverable `version_conflict` code so the
> model re-reads. Do NOT commit a patch.

**Adversarial caveat** — The "retry asserts `0`" pattern is specific to the
*first-create* conflict (no prior row → the LLM's `expected_version` is
meaningless). On an *update* conflict (row exists at vN), the correct retry is to
re-read and re-assert the *new* version, not `0` — an agent that copies the `0`
pattern onto an update-retry path would create a new bug. The pattern is "re-assert
the version that makes the retry's intent correct," not "always retry with 0."

---

### P-01-5: Make retry backoff jittered and abort-signal-carrying; a deterministic formula is a bug

**Paradigm statement** — Any retry loop that backs off must use real jitter
(`delay = base * 2^attempt + random(jitter)`), not a deterministic exponential
formula, because deterministic backoff makes every concurrent retryer retry at
the same instant and re-triggers the thundering herd the backoff exists to
prevent. The retry loop must also forward the abort/cancel signal so a SIGTERM
mid-backoff stops the retry rather than blocking shutdown. The reviewer's check
is not "is there a backoff formula" but "does the loop actually call `jitter()`
and forward the signal" — the PR description saying "jittered backoff" does not
make it so.

**Source evidence** — `playbook` Webhook path step 2: "Is backoff jittered (not
deterministic formula)? Does the retry loop forward the abort signal?
`src/jobs/trainingWebhook.job.ts:51`." `playbook paradigm #1`: "Verify claims
independently … The PR description says 'jittered backoff' — does the retry loop
actually call `jitter()`?" `playbook` convention "Retry backoff": "Jittered,
abort-signal-carrying; deterministic formula is a bug."

**<Provider> infra anchor** —
The playbook's `src/jobs/trainingWebhook.job.ts:51` anchor is **stale** — that
file does not exist in the current app tree (`find` on
`backend/src/jobs/` returns no `trainingWebhook*`; the training-job code lives in
`backend/src/controllers/trainingJob.controller.ts` and talks to a K8s
custom-object API, not a retry loop). The jittered-retry convention must be
grounded elsewhere. The *reaper* cadence carries the pattern's spirit:
`feat-batch-api-gateway/src/batch/reaper.rs:66-107` — the reaper loop uses a
configurable interval with warmup (`:72-75`, "key_reaper.rs precedent") and an
env kill-switch (`reaper_disabled()`, `:99`); the gateway does not implement
client-delivery retry jitter in the audited PR (the batch worker re-runs lapsed
leases via the reaper at minute-scale, which is spacing-by-lease not
exponential-backoff — see P-01-6). The honest anchor state: the *convention* is
documented in the playbook; the *live implementation* of a jittered
abort-signal-carrying client retry loop is NOT in the audited batch-api code and
the playbook's cited file is gone. A grep for `jitter|Math.random|backoff` across
`backend/src/jobs/` and `backend/src/services/` returns no client-delivery retry
jitter implementation (only `backoffLimit` on K8s Job specs, which is K8s's own
retry, not app jitter). **This anchor could not be fully grounded in live
source** — the backend that *would* find it is `semble_search "jitter backoff
retry abort signal Math.random"` across the full app tree (including
`backend/src/` subdirs not in the batch worktree); if no hit, the convention is
currently unenforced in app code and the gateway relies on the reaper's
lease-spacing instead.

**Codebase-intelligence backend** —
> `semble_search "jitter backoff retry abort signal Math.random setTimeout"` across `~/<provider>/app` — the only way to locate the live implementation (if any) of the playbook's claimed `trainingWebhook.job.ts:51` jitter.
> `codegraph explore -p ~/<provider>/gateway "reaper interval warmup jitter"` to confirm the reaper's cadence is spacing-by-lease, not exponential-backoff-jitter (so an agent does not mis-cite it as the jitter anchor).
> If the anchor is genuinely absent, `memory_smart_search "jittered backoff trainingWebhook"` to check whether a prior session relocated or deleted the retry loop.

**Fix-suggestion policy** —
> SUGGEST ONLY: if a PR adds a client-delivery retry loop with a deterministic
> formula (e.g. `delay = 1000 * 2^attempt` with no `Math.random` term) or
> swallows the abort signal, open a finding citing the playbook convention
> ("deterministic formula is a bug"); require the author to add jitter and
> forward the signal. If the PR's cited anchor is stale, name the stale
> citation in the finding so the author can re-ground. Do NOT commit a patch.

**Adversarial caveat** — For the *batch* path specifically, the reaper's
lease-spacing (a row reclaims at most once per reaper interval, minute-scale) is
a legitimate *alternative* to exponential jitter — the two solve different
problems (jitter deters thundering herds of *concurrent* retryers; lease-spacing
deters *back-to-back* retries of the *same* row in one outage window). An agent
flagging "no jitter on the batch re-run" would be a false positive: the batch
path deliberately spaces by lease, not by per-retry jitter. The jitter paradigm
applies to *client-delivery* retry (webhooks outbound), not to *lease reclaim*
(inbound re-run).

---

### P-01-6: Make re-claim a status flip, not a re-run — and prove it with a crash→reclaim→bill-once test

**Paradigm statement** — Lease re-claim must be a pure status flip
(`in_flight → queued` on `lease_expires_at < now`), never a re-run in the same
transaction; the *next* worker tick re-runs the row under a fresh `attempt`, and
the finalize guard (P-01-1) makes the stale worker's late finalize no-op. The
correctness claim — "crash → reclaim → re-run bills exactly once" — must be
pinned by a test that simulates the crash (claim then no finalize), advances the
clock past the lease, runs the reaper, runs the worker, and asserts exactly one
`usage_log` row and exactly one `spent_usd` increment. The re-claim must not
filter by batch status (it is safe only while terminalization requires zero
in-flight leases); if that invariant ever changes the reclaim query must grow an
`AND batch NOT terminal` guard, and that coupling must be a doc comment on the
reclaim function.

**Source evidence** — `feedback-divergences` "Restart-safe billing" row:
"cost booked in same transaction as terminal state flip, guarded by row state
✅ ADR 0001; Andreas explicitly praised this in the review." `feedback-divergences`
"First-build items Andreas praised … Crash-safe exactly-once finalize (`in_flight`
guard + `lock_batch` drain)." `gateway.md` "Where you're right — reclaim path
can't resurrect a terminal batch": "Holds on four independent guards (status
predicates on claim, expire, and the finalize lock)." `gateway.md` BLOCKER-2
(the double-run that *would* happen without the drain + the guard). `playbook
paradigm #9`: graceful-shutdown drain prevents the orphan; this paradigm owns
the *idempotence* that makes a missed drain harmless.

**<Provider> infra anchor** —
`feat-batch-api-gateway/src/batch/store.rs:564-580` (`reclaim_expired_leases`):
`UPDATE batch_request SET status = 'queued', lease_expires_at = NULL WHERE
status = 'in_flight' AND lease_expires_at < $1` — a pure status flip, no
re-run; the doc comment at `:565-568` records the coupling: "no batch-status
guard — safe only while terminalization requires zero in_flight leases … Add
`AND batch NOT terminal` here if that invariant ever changes." The crash-reclaim
invariant is pinned by `feat-batch-api-gateway/src/batch/reaper.rs:521-592`
(`e7_worker_restart_reclaims_lease_and_bills_exactly_once`): claims a row
(`:543-552`), simulates the crash (no finalize, asserts `in_flight` `:553`),
advances 120s past the 60s lease (`:556`), runs `reaper_tick` (asserts
`reclaimed >= 1`, row back to `queued` `:562-566`), runs `worker::tick`
(`:571`), and asserts the ADR 0001 headline: exactly one `usage_log` row
(`:581-585`, "worker restart must never double-bill") and `spent_usd`
incremented exactly once (`:587-591`). The re-arm increment `attempt =
br.attempt + 1` at `store.rs:463` is what gives the re-run a fresh generation
for the finalize guard to check.

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/gateway "trace reclaim_expired_leases status flip queued"` — confirms the reclaim is a status flip (no re-run in-txn), and surfaces the e7 test as the pinning evidence.
> Serena `find_symbol` on `reclaim_expired_leases` to confirm no `JOIN batch` / no status filter beyond `in_flight`; read the doc comment to confirm the terminalization invariant coupling is recorded.
> `semble_search "e7 worker restart reclaims lease bills exactly once"` to confirm the test exists and asserts the single-`usage_log` / single-`spent_usd` invariant (not just "reclaim happened").

**Fix-suggestion policy** —
> SUGGEST ONLY: if a PR changes reclaim to re-run work in the same transaction,
> or removes the e7 test, or adds a `batch.status` filter to reclaim without
> updating the doc-comment coupling, open a finding citing the e7 invariant and
> the `:565-568` coupling comment; require the author to keep reclaim a pure
> status flip and to either keep the e7 test green or update the coupling
> comment + guard together. Do NOT commit a patch.

**Adversarial caveat** — The "exactly one `usage_log`" assertion in e7 is a
*count* assertion, not a *generation* assertion — it proves the stale worker's
finalize no-op'd (only the re-run billed), but it does not prove the stale
worker's `result_attempt` stamp was rejected; that is covered separately by the
`finalize_success_second_call_is_noop` test. An agent could cite e7 as proving
both when it proves only the billing-once half. Also, e7 advances the clock
*past* the lease then runs the reaper — it does not test the race where the
reaper and the stale worker run concurrently; that concurrent case is defended
by the `AND attempt` guard (P-01-1), not by e7's sequential simulation.

---

### P-01-7: Symmetrize the re-arm gate across every finalize sibling — a guard on success only is a latent bug

**Paradigm statement** — When a row has multiple terminal finalizes
(success / failure / cancel / expire), every one of them must carry the same
shape of re-arm guard (`AND attempt = $N` and `status IN (...)`). A guard on the
success path only is a latent bug: the failure path can still be double-stamped
by a stale worker, and the asymmetry is invisible until a reclaim race hits the
unguarded path. The reviewer's check is explicitly "is the failure path
symmetric with the success path?" — Andrea raised MINOR-1 precisely because
`finalize_failure` lacked the guard `finalize_success` already had. The fix is
not "add a guard to the new path" but "make every sibling symmetric, and add a
test that pins both no-op on the second call."

**Source evidence** — `gateway.md MINOR-1`: "`finalize_failure` has no attempt
guard, unlike `finalize_success` … a double-reclaim can stamp `result_attempt`
at a wrong generation." Fix: "added `attempt: i32` param and `AND attempt = $7`;
symmetric with `finalize_success`." `playbook paradigm #6` (the re-arm gate must
hold on *every* re-fire, not just the happy one). `gateway.md` "Notes on the
review" BLOCKER-2 rebuttal: the no-double-bill claim rests on the *symmetric*
presence of the guard, and Mateo's rebuttal cites `finalize_success`'s guard as
the proof — which only holds if the failure path is symmetric (which it now is,
post-MINOR-1).

**<Provider> infra anchor** —
The symmetric pair in `feat-batch-api-gateway/src/batch/billing.rs`:
`finalize_success` guard `AND attempt = $9` at `:127`; `finalize_failure` guard
`AND attempt = $7` at `:263`. Both return `FinalizeOutcome::AlreadyFinal` on
`rows_affected() == 0` (`:140-142`, `:274-276`). Both pinned by symmetric tests:
`finalize_success_second_call_is_noop_and_never_double_bills` (`:594`) and
`finalize_failure_second_call_is_noop` (`:818`). The `select_exhausted_queued`
change that made the symmetry possible: `store.rs:538` now returns `attempt`
(MINOR-1 fix: "select_exhausted_queued now returns attempt") so the failure
path has the generation to bind. The four-guard terminal-batch-resurrection
claim in `gateway.md` ("reclaim path can't resurrect a terminal batch — holds on
four independent guards") is the generalization: claim, expire,
`finalize_success`, `finalize_failure` all guard on status + attempt
symmetrically.

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/gateway "trace finalize_success AND attempt guard"` — returns both `finalize_success` and `finalize_failure` in the same symbol cluster, making the symmetry (or its absence) visible in one pass.
> Serena `find_symbol` on `finalize_failure` then `find_referencing_symbols` to confirm `select_exhausted_queued` now returns `attempt` and the failure caller binds it (the MINOR-1 fix).
> codebase-memory `query_graph`: `MATCH (f:Function) WHERE f.qualified_name ENDS WITH 'finalize_success' OR f.qualified_name ENDS WITH 'finalize_failure' RETURN f.qualified_name, f.line_number` to list every finalize sibling and diff their guard clauses for symmetry.

**Fix-suggestion policy** —
> SUGGEST ONLY: if a PR adds a new terminal finalize (e.g. `finalize_cancelling`,
> `finalize_expired`) without the `AND attempt = $N` guard and the
> `AlreadyFinal` no-op, open a finding citing the symmetric pair (`finalize_success`
> `:127` / `finalize_failure` `:263`) and the symmetric test pair (`:594` / `:818`);
> require the author to add the guard, the no-op branch, and a `_second_call_is_noop`
> test. Do NOT commit a patch.

**Adversarial caveat** — Symmetry is a *structural* invariant, not a semantic
one: a new finalize that genuinely cannot be reclaimed (e.g. a status flip on a
row that is never `in_flight`) does not need the guard, and forcing it adds a
guard that can never trip. The reviewer must confirm the new path is reachable by
a stale worker before requiring the guard — the test for "is this path
reclaimable" is "can a `claim_requests`-incremented `attempt` ever be stale when
this UPDATE runs?" If no, the guard is dead weight; if yes, it is required.

---

## Cross-sector links

- **Sector 02 Concurrency & race conditions** — owns the *mechanism*
  (`FOR UPDATE SKIP LOCKED` as MVCC row-disjointness, `pg_advisory_xact_lock` as
  the true count-cap). This sector owns only the *idempotence gate* that makes a
  double-claim harmless. P-01-1's re-arm increment
  (`claim_requests` `attempt = br.attempt + 1` at `store.rs:463`) is the seam:
  Sector 02 verifies the claim is row-disjoint, this sector verifies the
  finalize guard rejects the stale generation. `gateway.md BLOCKER-3` and
  Rebuttal (d) (atomic multi-org claim) are Sector 02's evidence; the
  `AND attempt` guard that makes Mateo's "brief 2× concurrency on rolling deploy
  is safe" claim hold is this sector's.
- **Sector 03 Graceful shutdown & drain** — owns the *drain* that prevents the
  BLOCKER-2 orphan leak in the first place (`Arc<AtomicBool>` stop, 30s await).
  This sector owns the *idempotence* that makes a missed drain harmless (the
  `AND attempt` guard + reclaim). The two are complementary: Sector 03 prevents
  the double-run; this sector makes the double-run no-op if it happens.
  `gateway.md BLOCKER-2` is shared evidence; the "Notes on the review"
  no-double-billing rebuttal is this sector's reading of it.
- **Sector 05 Billing & state-machine integrity** — owns same-txn finalize
  (ADR 0001), terminal-status-always-written, no-finalize-time-budget-grace.
  This sector owns only the `attempt` guard that makes the finalize idempotent
  across re-claims. The e7 test (`reaper.rs:521`) is shared evidence: Sector 05
  reads it as "bills in the same txn as the status flip"; this sector reads it
  as "the stale worker's finalize no-op'd so the re-run bills once."
  `feedback-divergences` "Restart-safe billing" and "Crash-safe exactly-once
  finalize" rows are shared; the split is Sector 05 = the txn shape, this
  sector = the re-arm gate.
- **Sector 08 Wire/contract conformance** — arguably owns the webhook
  *signing* shape (Standard Webhooks `id.timestamp.body`); this sector owns the
  *gate key determinism* (HMAC not ciphertext). The split is thin; the dedup pass
  may fold P-01-3's signing detail into Sector 08 and keep only the
  "deterministic not ciphertext" half here. Flagged for adjudication.
- **Sector 12 Code smell & correctness-detail** — owns the `MAX_ATTEMPTS` →
  `MAX_DET_FAILURES` rename (NIT-1), which is naming for the `det_failures` cap
  that P-01-2's `bump_transient_failure` guards. The rename makes the guard's
  intent readable; this sector owns the guard, Sector 12 owns the name.

## Sector-specific failure modes

- **Flagging a deterministic formula as a bug when lease-spacing is the intended
  backoff.** The batch path deliberately spaces retries by the reaper's
  lease interval (minute-scale), not by per-retry exponential jitter; the
  jitter paradigm applies to *outbound client-delivery* retry (webhooks), not to
  *inbound lease reclaim*. An agent that flags "no `Math.random` in the reaper"
  is a false positive — see P-01-5 caveat.
- **Treating the `AND attempt` guard as the double-billing defense.** The guard
  makes the *re-run* no-op; the *first* finalize's atomicity (same-txn
  `usage_log` + status flip, ADR 0001) is the double-billing defense. Citing
  the guard as "prevents double-billing" without the txn is an over-claim —
  Sector 05 owns the txn, this sector owns the gate.
- **Citing the playbook's stale `trainingJob.controller.ts:540` /
  `trainingWebhook.job.ts:51` / `executeTool.ts:470` anchors as live.** All
  three have drifted: the webhook signing moved to `automation.controller.ts`,
  the `trainingWebhook.job.ts` file no longer exists, and the expectedVersion
  forwarding slid from `:470` to `:545-559`. An agent must re-ground via
  `semble_search` before citing; citing the playbook line numbers verbatim
  produces wrong file:line evidence. (This extract ground-truths all three;
  the playbook should be updated separately.)
- **Over-applying the "retry asserts `0`" pattern.** The `expectedVersion: 0`
  retry in `executeTool.ts:586` / `DraftTextTool.ts:104` is specific to the
  *first-create* conflict (no prior row). On an *update* conflict the correct
  retry re-asserts the *new* version after re-reading, not `0`. An agent that
  copies the `0` pattern onto an update-retry path creates a new bug.
- **Flagging the missing webhook re-delivery dedup as a defect without checking
  the contract.** `triggerWebhook` deliberately inserts a new run per
  authenticated hit and bounds replays by HMAC timestamp tolerance (±300s) +
  per-workflow rate limit, with no stored nonce. That is a legitimate
  "at-most-once-per-tolerance-window" design; flagging "no idempotency key" is a
  false positive unless the workflow contract requires cross-window exactly-once.
  See P-01-3 caveat.

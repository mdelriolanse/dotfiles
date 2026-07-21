# Synthesis — Validation Pass

## Method

Independently re-verified a load-bearing sample of **27 paradigms** drawn from all 12 sectors (~27 of the ~77 total), selected by drift-risk: every paradigm whose anchor is a `file:line` in `app/` or gateway batch code, every paradigm citing a moved/renamed symbol (`validateAndPinUrl`, `verifyWebhookSignature`, `finalize_success`, `expectedVersion`), and every paradigm naming a backend whose project indexing I could falsify. Verification used four backends live: (1) `read` on the cited `file:line` in the `feat-batch-api-gateway` worktree and the `app/backend` tree to confirm anchor text byte-matches the claim; (2) `mcp__codebase_memory_list_projects` + `search_graph` to test whether gateway is actually indexed (it is NOT — see systemic gaps); (3) `codegraph explore -p ~/<provider>/gateway` to confirm the main-branch index surfaces (or fails to surface) batch symbols; (4) `bash` `find`/`grep`/`git log` for filesystem facts (`clientEgress.ts` absence, `test.yaml` absence, gateway-db migration heads, CODEOWNERS). Serena `find_symbol` was attempted but timed out on the large app tree (30s) — noted as a reliability caveat, not a project-indexing failure. The pre-flagged worker issues (S06 CodeGraph worktree mismatch, S11 missing test.yaml, S10 moved `validateAndPinUrl`, S01 stale playbook anchors, S02 no gateway in codebase-memory, S07 worktree mismatch) were all re-verified independently and confirmed; one additional drift (S09 gateway-db main head mis-stated as V42, actual V37) was found.

## Verified anchors (27 entries)

### V-1: S01 P-01-1 — Require a finalize idempotence guard pinned to the claim generation
- **Cited anchor**: `src/batch/billing.rs:121-128` (`finalize_success` UPDATE, guard `WHERE ... AND attempt = $9`); `billing.rs:250-275` (`finalize_failure`); no-op at `:140-142`/`:274-276`
- **Verified**: YES
- **Reality**: `billing.rs:113-142` — guard `AND attempt = $9` at line 127 (bind at `:137`), doc comment `:114-120` byte-matches, `AlreadyFinal` no-op at `:140-142`. `finalize_failure` guard `AND attempt = $7` at `:263` (bind `:271`), no-op `:274-276`. Anchor is exact.
- **Backend claimed**: `codegraph explore -p ~/<provider>/gateway "trace finalize_success AND attempt guard"`; Serena `find_symbol` on `finalize_success`/`finalize_failure`; `semble_search`.
- **Backend works?**: WORKTREE-MISMATCH (codegraph); Serena timed out; semble untested.
  - codegraph on `~/<provider>/gateway` (main-branch index, no batch module) returned `images.rs` test code tangentially — NOT `billing.rs`. Fallback: `read` the worktree file directly (`~/<provider>/worktrees/batch-api/feat-batch-api-gateway/src/batch/billing.rs`), or `codegraph init -i` in the worktree for a local index.
- **Fix to playbook**: Replace `codegraph explore -p ~/<provider>/gateway "..."` for any batch symbol with a direct `read` of `~/<provider>/worktrees/batch-api/feat-batch-api-gateway/src/batch/<file>:<line>`, or a worktree-local `codegraph init`; the main index does not contain the batch module.

### V-2: S01 P-01-3 — Key re-arm gates on a deterministic fingerprint, never ciphertext
- **Cited anchor**: `backend/src/controllers/automation.controller.ts:1373-1403` (`verifyWebhookSignature`); NOTE that the playbook's `trainingJob.controller.ts:540` is stale.
- **Verified**: YES (and the stale-playbook flag is correct)
- **Reality**: `automation.controller.ts` has `verifyWebhookSignature` defined at line 1373, `crypto.createHmac('sha256', signingSecret).update(\`${timestamp}.${rawBody}\`)` at `:1396`, `timingSafeEqual` at `:1366`. `trainingJob.controller.ts:535-545` is a K8s `deleteNamespacedCustomObject` block — NOT webhook signing. The sector's self-correction is accurate.
- **Backend claimed**: `semble_search`; Serena `find_symbol` on `verifyWebhookSignature`; codebase-memory `search_graph name_pattern="encrypt"`.
- **Backend works?**: YES for semble/Serena (app is indexed; symbol is in app tree). codebase-memory `search_graph` works on the `app`/`app-backend` projects.
- **Fix to playbook**: The final playbook MUST correct `trainingJob.controller.ts:540` → `automation.controller.ts:1373` (HMAC signing) and drop any reference to `trainingJob.controller.ts` for the webhook-fingerprint anchor.

### V-3: S01 P-01-4 — Carry `expectedVersion` into the retry handler
- **Cited anchor**: `backend/src/controllers/<provider>Chat.libs/agenticLoop/executeTool.ts:545-586`; NOTE playbook's `executeTool.ts:470` is stale by ~75 lines.
- **Verified**: YES
- **Reality**: `executeTool.ts:545-547` reads `expectedVersion` from `args.expected_version`; `:559` forwards it into `insertNextArtifactVersion`; `:586` re-asserts `expectedVersion: 0` on the retry. The playbook's `:470` line is stale — the file grew; the pattern is intact, the line number drifted.
- **Backend claimed**: `codegraph explore -p ~/<provider>/app`; Serena `find_symbol` on `insertNextArtifactVersion`; `semble_search`.
- **Backend works?**: YES (app is indexed in codegraph at `~/<provider>/app/.codegraph`; app-backend in codebase-memory).
- **Fix to playbook**: Correct `executeTool.ts:470` → `executeTool.ts:545-586` (read at `:545`, forward at `:559`, re-assert `0` at `:586`).

### V-4: S01 P-01-5 — Jittered abort-signal-carrying retry backoff
- **Cited anchor**: playbook's `src/jobs/trainingWebhook.job.ts:51` is stale (file does not exist); sector falls back to `feat-batch-api-gateway/src/batch/reaper.rs:66-107` and admits the anchor "could not be fully grounded."
- **Verified**: YES (the staleness claim is correct)
- **Reality**: `find ~/<provider>/app/backend/src -name "trainingWebhook*"` returns nothing — the file is gone. `grep jitter|Math.random|backoff` over `backend/src/jobs/` and `backend/src/services/` returns no client-delivery retry jitter implementation. The sector honestly reports the convention is documented in the playbook but not grounded in live source.
- **Backend claimed**: `semble_search "jitter backoff retry abort signal Math.random"` across `~/<provider>/app`; `codegraph explore -p ~/<provider>/gateway "reaper interval warmup jitter"`; `memory_smart_search`.
- **Backend works?**: semble/codegraph on app YES; codegraph on gateway is WORKTREE-MISMATCH for the reaper (reaper is batch code, main index lacks it).
- **Fix to playbook**: Drop `trainingWebhook.job.ts:51` as a live anchor; mark the jittered-retry convention as "documented but not currently implemented in the audited batch path" and cite `reaper.rs` only as a lease-spacing analog, NOT as a jitter implementation.

### V-5: S02 P-02-1 — A per-process counter is not a fleet-wide QoS signal
- **Cited anchor**: `src/batch/slots.rs:6` (`allowed_batch_slots`); `src/batch/worker.rs:166-171` (reads `interactive_in_flight` DashMap); `worker.rs:881` DashMap decl.
- **Verified**: PARTIAL (anchors plausible; line numbers for DashMap decl not re-read)
- **Reality**: `worker.rs:672` `spawn(state, clock, stop)` confirmed; the `interactive_in_flight` DashMap usage at `:166-171` and the `:881` declaration were not re-read but the `slots.rs` / `worker.rs` files exist in the worktree. The `AppState` field docstring claim ("In-process counter — exact while the gateway runs single-replica") was not re-read verbatim.
- **Backend claimed**: `codegraph explore -p ~/<provider>/gateway`; `semble_search repo=~/<provider>/worktrees/batch-api/feat-batch-api-gateway`; Serena `find_symbol` on `allowed_batch_slots`.
- **Backend works?**: WORKTREE-MISMATCH (codegraph); semble against the worktree path SHOULD work (semble indexes on first query).
- **Fix to playbook**: For `slots.rs`/`worker.rs` anchors, use `semble_search` with `repo=~/<provider>/worktrees/batch-api/feat-batch-api-gateway` or direct `read`, NOT `codegraph explore -p ~/<provider>/gateway`.

### V-6: S02 P-02-2 — A CTE-inlined `count(*)` is not a hard cap under MVCC
- **Cited anchor**: `src/batch/store.rs:211` (`pg_advisory_xact_lock` in `create_batch_capped`); docstring `:194-200`; `claim_requests` at `store.rs:460-475`.
- **Verified**: YES
- **Reality**: `store.rs:201-230` — `create_batch_capped` opens `pool.begin()` at `:209`, `SELECT pg_advisory_xact_lock($1, hashtext($2))` at `:211` (bind `973_i32` + `b.org`), comment `:210` "Namespaced (issue #973) per-org lock; auto-released at commit/rollback", `:216` "tx drops on early return → rollback → lock released", commit at `:228`. Exact match.
- **Backend claimed**: `codegraph explore -p ~/<provider>/gateway`; codebase-memory `query_graph` (project `home-mateo.delriolanse-<provider>-app-backend` — explicitly notes "the gateway project is not indexed"); Serena `find_symbol` on `create_batch_capped`.
- **Backend works?**: codegraph WORKTREE-MISMATCH; codebase-memory NO-PROJECT for gateway (the sector correctly hedges: "the query shape is the contract a future gateway index would satisfy"); Serena timed out.
- **Fix to playbook**: The sector already hedges codebase-memory correctly. Keep the hedge; add the explicit fallback: `read ~/<provider>/worktrees/batch-api/feat-batch-api-gateway/src/batch/store.rs:201-230` to confirm the xact-lock span.

### V-7: S02 P-02-3 — Name the advisory-lock class — session vs xact
- **Cited anchor**: session lock `worker.rs:693-701`; xact lock `store.rs:211`.
- **Verified**: YES
- **Reality**: `worker.rs:693` `SELECT pg_try_advisory_lock($1)` bind `42_i64`, `:698-701` "another batch worker holds the advisory lock; this pod will not run batch work" then `return;` (the no-op-not-retry that makes the session lock safe). `ponytail:` comment at `:684-685`. `store.rs:211` xact lock confirmed in V-6. Both exact.
- **Backend claimed**: `codegraph explore -p ~/<provider>/gateway`; Serena `find_symbol` on `create_batch_capped`; `semble_search`.
- **Backend works?**: codegraph WORKTREE-MISMATCH; semble (worktree) SHOULD work.
- **Fix to playbook**: Direct `read` of `worker.rs:672-713` to confirm the session-lock-acquire-before-loop + return-on-fail shape.

### V-8: S02 P-02-4 — Optimistic-concurrency guard must travel to the retry handler
- **Cited anchor**: `app/backend/src/services/insertNextArtifactVersion.ts:86-92`; `app/backend/src/controllers/<provider>Chat.libs/agenticLoop/executeTool.ts:545-586`; gateway sibling `billing.rs:127`/`:263`.
- **Verified**: YES (gateway sibling verified in V-1; app side verified in V-3)
- **Reality**: `executeTool.ts:545-586` confirmed (V-3). `billing.rs:127`/`:263` confirmed (V-1). `insertNextArtifactVersion.ts:86-92` not re-read but the call from `executeTool.ts:559` is confirmed.
- **Backend claimed**: Serena `find_symbol` on `insertNextArtifactVersion` + `find_referencing_symbols`; codebase-memory `search_graph` on `app-backend`; `semble_search`.
- **Backend works?**: YES for app-side (app-backend IS indexed in codebase-memory — confirmed `6413` nodes).
- **Fix to playbook**: None — the app-side backends work; only the gateway-side sibling citation needs the worktree-read fallback.

### V-9: S03 P-03-1 — Thread a stop flag into every new worker or async loop
- **Cited anchor**: `worker.rs:672` (`spawn(state, clock, stop)`); `worker.rs:81` (`tick`'s `stop`); `worker.rs:175` (claim gate `!stop.load(Ordering::SeqCst)`); `worker.rs:704` (loop-top break); `main.rs:329`.
- **Verified**: YES
- **Reality**: `worker.rs:672` `pub fn spawn(state: AppState, clock: Arc<dyn Clock>, stop: Arc<AtomicBool>)` confirmed. `tick` at `:77-82` takes `stop: &Arc<AtomicBool>`. `:704` `if stop.load(Ordering::SeqCst) { break; }`. The `:175` claim gate inside `drain_deployment` was not re-read but the spawn/tick signatures are exact.
- **Backend claimed**: `codegraph explore -p ~/<provider>/gateway`; Serena `find_symbol` on `batch::worker::spawn`; `semble_search`.
- **Backend works?**: codegraph WORKTREE-MISMATCH; semble (worktree) SHOULD work.
- **Fix to playbook**: Direct `read worker.rs:672-713` for the spawn+stop shape; do not rely on `codegraph explore -p ~/<provider>/gateway` for batch symbols.

### V-10: S03 P-03-2 — Await the worker handle with a bounded timeout
- **Cited anchor**: `src/main.rs:378-380` (stop store + 30s timeout join).
- **Verified**: PARTIAL (not re-read verbatim; line numbers consistent with sector's other main.rs citations)
- **Reality**: `main.rs` exists in the worktree; the `:329`/`:374`/`:378-380` citations are internally consistent across sectors 03/02/05. Not byte-verified this pass.
- **Backend claimed**: `codegraph explore -p ~/<provider>/gateway`; Serena `find_referencing_symbols` on `batch_worker_handle`.
- **Backend works?**: codegraph WORKTREE-MISMATCH.
- **Fix to playbook**: Direct `read ~/<provider>/worktrees/batch-api/feat-batch-api-gateway/src/main.rs:370-385` to confirm the timeout join.

### V-11: S04 P-04-1 — Enforce per-key RPM on every new public route, after auth
- **Cited anchor**: `src/routes/batches.rs:50` (`state.rate_limiter.check(&key.id, key.rate_limit_rpm)` in `gate_and_auth`); `files.rs:59`; `rate_limit.rs:39`.
- **Verified**: YES
- **Reality**: `batches.rs:45` `async fn gate_and_auth`, `:50` `state.rate_limiter.check(&key.id, key.rate_limit_rpm).await?`; `rate_limit.rs:39` `pub async fn check(&self, key_id: &str, limit_rpm: i32)`. `files.rs:28` `FILE_UPLOAD_MAX_CONCURRENCY`, `:53-54` `try_acquire`. Exact.
- **Backend claimed**: `codegraph explore -p ~/<provider>/gateway`; Serena `find_referencing_symbols` on `RateLimiter::check`; `semble_search`.
- **Backend works?**: codegraph WORKTREE-MISMATCH (returns main-branch `preflight.rs`/`images.rs`, not batch `batches.rs`); semble (worktree) SHOULD work.
- **Fix to playbook**: Direct `read` of `batches.rs:45-50` and `rate_limit.rs:39-48`; use `semble_search repo=<gateway-worktree>` for the caller enumeration.

### V-12: S04 P-04-4 — A count-based CTE is not a hard cap under MVCC
- **Cited anchor**: `src/batch/store.rs:211` (xact lock); `worker.rs:693` (session lock).
- **Verified**: YES (same as V-6, V-7)
- **Reality**: Both anchors confirmed.
- **Backend claimed**: `codegraph explore -p ~/<provider>/gateway`; codebase-memory `query_graph` Cypher; `semble_search`.
- **Backend works?**: codegraph WORKTREE-MISMATCH; codebase-memory NO-PROJECT (gateway not indexed — a Cypher `MATCH (f:Function {name:"create_batch_capped"})` would return zero rows).
- **Fix to playbook**: Drop the codebase-memory Cypher query for gateway symbols; replace with `read store.rs:201-230` + `read worker.rs:684-701`.

### V-13: S04 P-04-5 — Resolve the org before the concurrency semaphore
- **Cited anchor**: `src/routes/images.rs:169` (`resolve`); `images.rs:180` (`try_acquire_image_gen_slot`); `main.rs:81` (`image_gen_pending`).
- **Verified**: YES
- **Reality**: `images.rs:169` `let resolved = resolve(&state, &headers, &request.model, start).await?` with the `:164-168` comment "Runs before the concurrency gate so unauthenticated callers can't fill the queue"; `:180` `let _slot = match try_acquire_image_gen_slot(...)` AFTER resolve. The ordering is load-bearing and confirmed.
- **Backend claimed**: `codegraph explore -p ~/<provider>/gateway`; Serena `find_referencing_symbols` on `try_acquire_image_gen_slot`; `semble_search`.
- **Backend works?**: codegraph — `images.rs` IS in the main gateway index (it pre-existed batch), so `codegraph explore -p ~/<provider>/gateway "try_acquire_image_gen_slot"` SHOULD surface it; semble (worktree) works.
- **Fix to playbook**: None — `images.rs` is main-branch code present in the gateway `.codegraph` index; codegraph works here. (Distinct from batch-module symbols.)

### V-14: S05 P-05-1 — Book cost and terminal-state flip in one transaction
- **Cited anchor**: `billing.rs:109` (`pool.begin()`); `:113-139` (flip); `:146` (`apply_usage_writes`); `:148` (`complete_batch_if_drained`); `:149` (`commit`); `:110` (`lock_batch`).
- **Verified**: YES (partial — begin/flip/commit confirmed; `:146`/`:148` not re-read but `:146` visible at end of V-1's read)
- **Reality**: `billing.rs` `let mut tx = pool.begin().await?` at `:109` (per sector; the read started at `:113`), flip `:113-139` confirmed, `:146` `apply_usage_writes(&mut tx, &mut record, Some(args.batch_id))` confirmed, `:148` `complete_batch_if_drained`, `:149` `tx.commit()`. Same-txn confirmed.
- **Backend claimed**: `codegraph explore -p ~/<provider>/gateway`; codebase-memory `trace_path mode=data_flow` on `apply_usage_writes`.
- **Backend works?**: codegraph WORKTREE-MISMATCH; codebase-memory NO-PROJECT (gateway not indexed → `trace_path` returns nothing for `apply_usage_writes` in a gateway project).
- **Fix to playbook**: `read billing.rs:109-149` for the single-txn proof; drop codebase-memory `trace_path` for gateway symbols.

### V-15: S05 P-05-3 — Pin every finalize to the claim generation with `AND attempt = $N`
- **Cited anchor**: `billing.rs:127` (`AND attempt = $9`); `:140-142` (no-op); `:262-263` (`AND attempt = $7`); `:274-276`; `store.rs:538` (`select_exhausted_queued` returns `attempt`).
- **Verified**: YES (V-1 confirmed `:127`/`:140-142`/`:263`/`:274-276`)
- **Reality**: All four guard/no-op sites confirmed. The test name `finalize_success_second_call_is_noop_and_never_double_bills` at `:594` cited but not re-read.
- **Backend claimed**: `codegraph explore -p ~/<provider>/gateway`; Serena `find_symbol`/`find_referencing_symbols`; codebase-memory `query_graph` Cypher.
- **Backend works?**: codegraph WORKTREE-MISMATCH; codebase-memory NO-PROJECT; Serena timed out.
- **Fix to playbook**: `read billing.rs:113-142` and `:255-280` for both guards; drop the codebase-memory Cypher query (gateway not indexed).

### V-16: S05 P-05-4 — Every terminalization writes a terminal status
- **Cited anchor**: `store.rs:805` (`SET status = 'expired', error_code = 'batch_expired'`); `store.rs:822` (batch-level `status='expired', terminal_at`); `billing.rs:196-200` (`complete_batch_if_drained`); `types.rs:48-54` (`is_terminal`).
- **Verified**: YES
- **Reality**: `store.rs:804-812` `UPDATE batch_request br SET status = 'expired', error_code = 'batch_expired' FROM batch b WHERE ...`; `:819-830` `UPDATE batch b SET status = 'expired', expired_at = $1, terminal_at = $1 WHERE ... AND NOT EXISTS (in_flight)`. Exact. `billing.rs:196-200` and `types.rs:48-54` not re-read.
- **Backend claimed**: `codegraph explore -p ~/<provider>/gateway`; `grep` gateway for `UPDATE batch SET status`; codebase-memory `search_graph name_pattern=".*expire.*|.*finalize.*|.*cancel.*"`.
- **Backend works?**: codegraph WORKTREE-MISMATCH; codebase-memory NO-PROJECT (gateway).
- **Fix to playbook**: `read store.rs:799-835` for the expire stamps; `grep` the worktree (not main) for `UPDATE batch SET status`.

### V-17: S06 P-06-1 — Sweep must delete every generation up to the claim high-water mark
- **Cited anchor**: `src/batch/sweep.rs:47-48` (`WHERE ... attempt > 0`); `:60-61` (`for gen in 1..=attempt`); `:54-59` (comment); `reaper.rs:1241` (test).
- **Verified**: PARTIAL (anchors plausible; not byte-verified this pass — `sweep.rs` exists in worktree)
- **Reality**: `sweep.rs` confirmed to exist in worktree; the `:47-48`/`:60-61` selectors and `reaper.rs:1241` test not re-read verbatim.
- **Backend claimed**: `semble_search` against `~/<provider>/worktrees/batch-api/feat-batch-api-gateway`; `codegraph explore -p <gateway-worktree> "trace claim_requests attempt bump reclaim"`.
- **Backend works?**: semble (worktree) SHOULD work; codegraph against the worktree would require `codegraph init -i` first (no `.codegraph` in worktree).
- **Fix to playbook**: Use `semble_search repo=<gateway-worktree>` or direct `read sweep.rs:40-65`; note `codegraph explore -p <worktree>` needs `codegraph init -i` first.

### V-18: S07 P-07-1 — Ship a partial index for every hot per-tick query predicate
- **Cited anchor**: `src/batch/store.rs:538-552` (`select_exhausted_queued`); `worker.rs:93` (caller); migration `V44__batch_api.sql` ships 7 partial indexes but none on `det_failures`.
- **Verified**: YES (the `worker.rs:93` caller confirmed in V-12-1's read; the missing-index claim is the sector's own finding)
- **Reality**: `worker.rs:93` `store::select_exhausted_queued(&state.pool, MAX_ATTEMPTS, clock.now())` confirmed (V-19 read). The migration `V44__batch_api.sql` exists in `~/<provider>/worktrees/batch-api/feat-batch-api-gateway-db/migrations/`. The "zero indexes on det_failures" claim is plausible (sector explicitly greps); not re-grepped this pass.
- **Backend claimed**: `grep`/`glob` the gateway-db migrations (DDL not indexed by CodeGraph/Serena/codebase-memory); `semble_search "CREATE INDEX det_failures"`; `codegraph explore -p ~/<provider>/gateway` (locates the query, not the index).
- **Backend works?**: YES for grep/glob (DDL is text); codegraph WORKTREE-MISMATCH for the query (batch module).
- **Fix to playbook**: The sector's backend choice is correct — grep/glob the migration dirs. The codegraph caveat (main index lacks batch query) is already noted by the sector. Keep as-is.

### V-19: S07 P-07-2 — Re-cut migrations above main's Flyway head
- **Cited anchor**: `gateway-db/flyway.conf` (`outOfOrder=false`, `validateOnMigrate=true`); main head V37; worktree ships V38, V40, V41, V42, V44 (V39, V43 gaps).
- **Verified**: YES
- **Reality**: `flyway.conf` lines 5-6: `flyway.outOfOrder=false`, `flyway.validateOnMigrate=true`. Main `gateway-db/migrations/` highest = `V37__org_default_budget.sql`. Worktree `feat-batch-api-gateway-db/migrations/` highest = `V44__batch_api.sql`, with V38/V40/V41/V42/V44 present and V39/V43 missing (re-cut gaps). The sector's "V39 unusable, renumbered to V43+V44" narrative matches `git log` (`59af680` "renumber batch migrations to V43/V44 after main V40–V42", `32fda04` "squash V43/V44 into single V44"). Note: the worktree's V40-V42 are NOT yet on main (main stops at V37), so the "main already owns V40" framing is about a prior concurrent-PR state, not current main.
- **Backend claimed**: `glob`/`bash` (`git log`, `ls-tree`); `semble_search "V44 batch_api migration"`.
- **Backend works?**: YES (filesystem/git is the correct tool, as the sector says).
- **Fix to playbook**: None — the sector's backend (glob/bash) is correct. (See V-24 for the S09 variant that mis-states main head.)

### V-20: S08 P-08-1 — Emit OpenAI-exact wire shapes
- **Cited anchor**: `feat-batch-api-gateway/src/batch/types.rs:1-3` (file header); `types.rs:11-20` (`BatchStatus` 8-term enum); `types.rs:286-316` (round-trip tests); `types.rs:315` (reject `canceled`).
- **Verified**: PARTIAL (file exists; enum not re-read)
- **Reality**: `types.rs` confirmed to exist in worktree `src/batch/`. The 8-term `BatchStatus` and the `:315` reject-`canceled` test cited but not byte-verified this pass.
- **Backend claimed**: `codegraph explore -p ~/<provider>/gateway`; Serena `find_symbol` on `BatchStatus`; `semble_search`.
- **Backend works?**: codegraph WORKTREE-MISMATCH; semble (worktree) SHOULD work.
- **Fix to playbook**: `read types.rs:1-23` and `:286-316` for the enum and tests; do not use `codegraph explore -p ~/<provider>/gateway` for `BatchStatus`.

### V-21: S10 P-10-1 — Route every client URL through `validateAndPinUrl`
- **Cited anchor**: `backend/src/libs/ssrfGuard.ts:166` (`validateAndPinUrl`); `:95-119` (`resolveAndAssertPublic`); `:32-65` (`isBlockedIP`); `:197-202` (pinned lookup). NOTE playbook's `clientEgress.ts:103` is stale.
- **Verified**: YES (and the stale-playbook flag is correct)
- **Reality**: `validateAndPinUrl` exported at `ssrfGuard.ts:166` (`export async function validateAndPinUrl(url, opts)`). `find ~/<provider>/app/backend/src -name "clientEgress*"` returns NOTHING — `clientEgress.ts` does not exist. The playbook's `clientEgress.ts:103` anchor is fully stale; the sector's `ssrfGuard.ts:166` correction is accurate.
- **Backend claimed**: `codegraph explore -p ~/<provider>/app`; Serena `find_symbol` on `validateAndPinUrl`; `semble_search`.
- **Backend works?**: YES (app is indexed; `validateAndPinUrl` is an app symbol — codegraph/semble/Serena all work on the app tree).
- **Fix to playbook**: The final playbook MUST correct `clientEgress.ts:103` → `ssrfGuard.ts:166` everywhere the playbook cites the SSRF guard. `clientEgress.ts` does not exist in the current app tree.

### V-22: S11 P-11-1 — A DB-backed test that skips when env unset needs CI that sets it
- **Cited anchor**: `feat-batch-api-gateway/src/batch/testdb.rs:17` (`pool() -> Option<PgPool>`, returns `None` on unset `TEST_DATABASE_URL`); `require_pool!` macro; intended CI `.github/workflows/test.yaml`.
- **Verified**: YES (the missing-`test.yaml` claim is the load-bearing finding)
- **Reality**: `~/<provider>/worktrees/batch-api/feat-batch-api-gateway/.github/workflows/` contains ONLY `build.yaml` (triggers `on: push: tags: ["[0-9]*"]` — tag-only, no `pull_request`, no `TEST_DATABASE_URL`, no `cargo test`). `test.yaml` does NOT exist. The sector honestly flags: "the `test.yaml` the audit cites as evidence was NOT present on disk at verification time." `testdb.rs` and `require_pool!` not re-read but the workflow absence is the decisive fact.
- **Backend claimed**: `codegraph explore -p ~/<provider>/gateway`; `semble_search`; `glob "**/.github/workflows/*.y*ml"`.
- **Backend works?**: glob/`ls` YES (the decisive check); codegraph WORKTREE-MISMATCH.
- **Fix to playbook**: The final playbook must record that the gateway batch tests are NOT gated by any CI workflow on the worktree — MAJOR-5's "ADDRESSED" verdict is not yet landed on disk. The fix the playbook should prescribe is "add `.github/workflows/test.yaml`" as an open action, not a completed one.

### V-23: S11 P-11-3 — A security reject path must be exercised with a real reject
- **Cited anchor**: `worktrees/training-webhooks/app/backend/src/jobs/__tests__/trainingWebhook.job.test.ts:21/408/414/442/444`; real guard at `app/backend/src/libs/ssrfGuard.ts`; egress boundary `src/services/clientEgress.ts:103`.
- **Verified**: PARTIAL (the `clientEgress.ts:103` egress anchor is stale — same as V-21)
- **Reality**: The test file `trainingWebhook.job.test.ts` lives under a SEPARATE worktree (`worktrees/training-webhooks/app/...`) — distinct from the batch-api worktree and the main `app/` checkout. The `clientEgress.ts:103` egress-boundary anchor is stale (file does not exist in `app/backend/src` — see V-21). The real guard `ssrfGuard.ts` is correctly located.
- **Backend claimed**: `semble_search repo=training-webhooks/app/backend`; `codegraph explore -p ~/<provider>/gateway`; Serena `find_referencing_symbols` on `validateAndPinUrl`.
- **Backend works?**: semble (separate worktree) SHOULD work; the `clientEgress.ts:103` citation must be corrected to `ssrfGuard.ts:166`.
- **Fix to playbook**: Correct the "egress boundary at `src/services/clientEgress.ts:103`" → the SSRF boundary is `src/libs/ssrfGuard.ts:166` (no `clientEgress.ts` exists). The test file is in a third worktree (`training-webhooks`), not the batch-api worktree — note the path explicitly.

### V-24: S09 P-09-3 — V-number collision across concurrent PRs on main
- **Cited anchor**: "`gateway-db` main head is `e0ae137 V42: per-org moderation policy` (`V42__org_moderation_policy.sql`)"; `app-db` commit `c5a3703` (Andrea-authored renumber).
- **Verified**: PARTIAL (the gateway-db main head claim is STALE/WRONG)
- **Reality**: Main `~/<provider>/gateway-db/migrations/` highest file is `V37__org_default_budget.sql` (NOT V42). `V42__org_moderation_policy.sql` exists ONLY in the `feat-batch-api-gateway-db` worktree, not on main. The sector's statement "main already owns V40 (`usage_log_auth_org`)" is false against current main (main stops at V37; V40-V42 are worktree-only). The worktree's `git log` confirms the renumber (`59af680`, `32fda04`). The `app-db` Andrea-authored renumber commit was not re-verified but is plausible.
- **Backend claimed**: `glob`/`bash` (`git log`, `ls-tree`).
- **Backend works?**: YES (filesystem/git is correct).
- **Fix to playbook**: Correct "gateway-db main head is V42" → "gateway-db main head is V37 (`V37__org_default_budget.sql`); the batch worktree ships V38-V44 above main's head, with V39/V43 as re-cut gaps." The concurrent-PR-collision narrative (V40 already taken on main) describes a PRIOR state, not current main — the playbook should phrase it as "at the time of the re-cut, main had advanced to V40-V42; the branch renumbered above that."

### V-25: S12 P-12-1 — Rename a constant whose name lies about what it caps
- **Cited anchor**: `src/batch/worker.rs:41` (`const MAX_ATTEMPTS: i32 = 3;`); `worker.rs:93` (`select_exhausted_queued(&state.pool, MAX_ATTEMPTS, ...)`); `store.rs:549` (`WHERE br.det_failures >= $1`).
- **Verified**: YES
- **Reality**: `worker.rs:41` `const MAX_ATTEMPTS: i32 = 3;` with doc comment `:37-40` explaining the cap keys on `det_failures`. `worker.rs:93` `store::select_exhausted_queued(&state.pool, MAX_ATTEMPTS, clock.now())` confirmed. The name-vs-column mismatch is real: the constant is named `MAX_ATTEMPTS` but gates `det_failures` (per the doc comment and the `store.rs` predicate). Verdict UNADDRESSED (rename not done) is consistent with the on-disk name.
- **Backend claimed**: `codegraph explore -p ~/<provider>/gateway`; Serena `find_referencing_symbols` on `MAX_ATTEMPTS`; codebase-memory `search_graph name_pattern=".*MAX_ATTEMPTS.*"`.
- **Backend works?**: codegraph WORKTREE-MISMATCH; Serena timed out; codebase-memory NO-PROJECT (gateway).
- **Fix to playbook**: `read worker.rs:37-41` and `:93` for the name/column mismatch; `read store.rs:545-555` for the predicate. Drop codebase-memory `search_graph` for this gateway symbol.

### V-26: S12 P-12-5 — Inject the clock into every route that stamps lifecycle/money timestamps
- **Cited anchor**: `src/routes/batches.rs:238` (`Utc::now()` in create → `expires_at`); `batches.rs:518` (`Utc::now()` in cancel); injected clock at `worker.rs:672` spawn, `reaper.rs`.
- **Verified**: YES (the injected-clock spawn confirmed in V-9; the route `Utc::now()` not re-read but the sector's `batches.rs:238/518` are internally consistent)
- **Reality**: `worker.rs:672` `spawn(state, clock, stop)` confirms the clock is a spawn param, NOT an `AppState` field — consistent with the sector's "clock injection stops at the route layer" claim. The route `batches.rs:238/518` `Utc::now()` calls were not byte-verified this pass.
- **Backend claimed**: `codegraph explore -p ~/<provider>/gateway`; Serena `find_symbol` on `AppState`; `grep -rn "Utc::now()" src/routes/`.
- **Backend works?**: codegraph WORKTREE-MISMATCH; Serena timed out; grep on the worktree YES.
- **Fix to playbook**: `grep -rn "Utc::now()" ~/<provider>/worktrees/batch-api/feat-batch-api-gateway/src/routes/` for the smell; `read worker.rs:672` for the clock-as-spawn-param (not AppState) shape.

### V-27: S12 P-12-7 — Don't call a multi-file behavior change a "one-line fix"
- **Cited anchor**: `src/batch/s3_client.rs:34` (`Forbidden(String)` variant); `:143`/`:193`/`:214` (three 403 match arms); `src/batch/sweep.rs:20-22` (sweep caller).
- **Verified**: PARTIAL (`s3_client.rs`/`sweep.rs` exist in worktree; match arms not byte-verified)
- **Reality**: `s3_client.rs` and `sweep.rs` confirmed to exist in `~/<provider>/worktrees/batch-api/feat-batch-api-gateway/src/batch/`. The `:34`/`:143`/`:193`/`:214` match-arm sites and `sweep.rs:20-22` caller cited but not byte-verified this pass.
- **Backend claimed**: `codegraph explore -p ~/<provider>/gateway`; Serena `find_implementations`/`find_referencing_symbols` on `S3Error::Forbidden`; codebase-memory `trace_path mode=calls`.
- **Backend works?**: codegraph WORKTREE-MISMATCH; Serena timed out; codebase-memory NO-PROJECT (gateway).
- **Fix to playbook**: `read s3_client.rs:26-40` and `:140-220` for the variant + match arms; `read sweep.rs:17-26` for the caller. Drop the codebase-memory `trace_path` for this gateway symbol.

## Systemic grounding gaps

Cross-cutting issues that affect many paradigms (not per-paradigm):

- **codebase-memory gateway project NOT indexed.** `mcp__codebase_memory_list_projects` returns 7 projects: `helm`, `app` (87.5k nodes), `app-backend`, `operator`, `<provider>-python`, `app-client`, `e2e`. **Gateway is absent** — contradicting `_CONTEXT.md`'s claim that "gateway (6.8k)" is indexed. Every paradigm citing `codebase-memory search_graph` / `trace_path` / `query_graph` for gateway Rust symbols (`finalize_success`, `create_batch_capped`, `claim_requests`, `bump_transient_failure`, `S3Error::Forbidden`, `apply_usage_writes`, `MAX_ATTEMPTS`) returns zero rows. Confirmed live: `search_graph query="finalize_success" project="home-mateo.delriolanse-<provider>-app-backend"` → `total: 0`. **Fallback:** for gateway symbols, use direct `read` of `~/<provider>/worktrees/batch-api/feat-batch-api-gateway/src/<file>:<line>`, or `semble_search` with `repo=~/<provider>/worktrees/batch-api/feat-batch-api-gateway`, or run `index_repository repo_path=~/<provider>/gateway mode="fast"` to add it. Sectors 02, 04, 05, 06, 07, 12 all carry codebase-memory queries that need this fallback. S02 P-02-2 already hedges correctly ("the gateway project is not indexed; the query shape is the contract a future gateway index would satisfy"); S05/S12 do not hedge and must be corrected.

- **CodeGraph worktree mismatch.** `~/<provider>/gateway/.codegraph/codegraph.db` is dated Jul 9 (main-branch, pre-batch). The batch module lives ONLY in `~/<provider>/worktrees/batch-api/feat-batch-api-gateway/src/batch/`, which has NO `.codegraph/`. Confirmed live: `codegraph explore -p ~/<provider>/gateway "finalize_success AND attempt guard"` returned `images.rs` test code tangentially — NOT `billing.rs`. Every `codegraph explore -p ~/<provider>/gateway "..."` query for a batch symbol (`billing.rs`, `store.rs`, `worker.rs`, `sweep.rs`, `reaper.rs`, `slots.rs`, `types.rs`, `s3_client.rs`, `jsonl.rs`) will miss or surface unrelated main-branch code. **Workaround:** (a) `read` the worktree source directly (authoritative, byte-for-byte); (b) `semble_search` with `repo=~/<provider>/worktrees/batch-api/feat-batch-api-gateway` (indexes on first query); (c) `codegraph init -i` in the worktree for a local index. **Exception:** main-branch gateway files that pre-existed batch (`routes/images.rs`, `routes/preflight.rs`, `rate_limit.rs`, `proxy.rs`, `main.rs` non-batch parts) ARE in the main index and codegraph works for those. The playbook must distinguish "batch symbol (worktree-only)" from "main-branch gateway symbol (indexed)" for every codegraph citation. S06, S07, S11 already flag this; S01, S02, S04, S05, S08, S12 do not consistently flag it.

- **Playbook anchor drift — the consolidated stale-anchor list.** The 12 workers collectively showed these playbook file:line anchors are stale and the refined playbook MUST correct all of them:
  - `validateAndPinUrl` at `clientEgress.ts:103` → **`ssrfGuard.ts:166`** (S10). `clientEgress.ts` does not exist in `app/backend/src`.
  - `trainingJob.controller.ts:540` (webhook fingerprint) → **`automation.controller.ts:1373`** (`verifyWebhookSignature`) (S01). `trainingJob.controller.ts:540` is a K8s custom-object delete.
  - `trainingWebhook.job.ts:51` (jittered backoff) → **file does not exist**; `find` returns nothing (S01). Convention is documented but unimplemented in audited batch code; cite `reaper.rs` only as lease-spacing, not jitter.
  - `executeTool.ts:470` (expectedVersion) → **`executeTool.ts:545-586`** (read `:545`, forward `:559`, re-assert `0` at `:586`) (S01, S02). File grew ~75 lines.
  - `generateCosmosImage.ts` path (playbook Image-gen step 3/5) → file now lives under `agenticLoop/` (`backend/src/controllers/<provider>Chat.libs/agenticLoop/generateCosmosImage.ts`) (S03, S08). The playbook's bare `generateCosmosImage.ts` path is ambiguous post-refactor.
  - `test.yaml` cited as ADDRESSED (gateway CI) → **absent on disk**; only `build.yaml` (tag-only) exists in the gateway worktree (S11). MAJOR-5's "ADDRESSED" is not landed.
  - `gateway-db main head V42` (S09) → **main head is V37**; V40-V42 are worktree-only. The concurrent-collision narrative describes a prior state, not current main.
  - `reviewActions.ts:74` (playbook User-memory path step 2) → flagged by S05/S10 as the terminal-status-always-written anchor; not re-verified this pass but cited across sectors — the playbook should re-ground via `semble_search` before the final assembly.

- **Serena `find_symbol` reliability on large trees.** Serena `mcp__serena_find_symbol` with `name_path_pattern="finalize_success"` timed out at 30s against the active project (likely the large `app/` tree). Serena is the canonical backend for "confirm a moved symbol exists and locate its definition," but unscoped `find_symbol` over the full app tree is slow. **Workaround:** scope Serena with `relative_path` to the specific file/dir (e.g. `relative_path="backend/src/libs/ssrfGuard.ts"` for `validateAndPinUrl`, `relative_path="src/batch/billing.rs"` for `finalize_success`), or fall back to `grep` + `read` for symbol location.

- **Three-worktree split for the batch feature.** The batch evidence spans three separate worktrees: (1) `worktrees/batch-api/feat-batch-api-gateway/` (gateway Rust), (2) `worktrees/batch-api/feat-batch-api-gateway-db/` (migrations), (3) `worktrees/training-webhooks/app/backend/` (the SSRF-reject test, S11 P-11-3). Plus the main `app/` checkout (TS controllers, SSRF guard). The playbook's infra anchors must name the worktree path explicitly for each citation; a bare `src/...` is ambiguous across these trees.

## Confidence per sector

- **S01 Idempotency & re-arm** — HIGH. Anchors byte-verified (`billing.rs:127`/`:263` exact); sector self-flagged all three stale playbook anchors (trainingJob:540, trainingWebhook:51, executeTool:470) accurately and supplied corrected locations; only the jitter anchor is ungrounded, which the sector admits honestly.
- **S02 Concurrency & races** — HIGH. `store.rs:211` xact lock and `worker.rs:693` session lock both byte-verified; codebase-memory NO-PROJECT hedge for gateway is correctly stated; the MVCC-vs-hard-cap distinction is precisely anchored.
- **S03 Graceful shutdown** — MEDIUM. `worker.rs:672` spawn signature and `:704` stop-load verified; `main.rs:378-380` timeout-join and the drain ordering (`:357`/`:374`/`:378`) cited consistently but not byte-verified this pass; `images.rs` abort-signal forwarding at `:215-241` not re-read. Internally consistent across sectors.
- **S04 Rate limiting & fairness** — HIGH. `batches.rs:50` rate-limit check, `files.rs:28/53-54` semaphore, `rate_limit.rs:39`, `images.rs:169→180` resolve-before-acquire all byte-verified. The `store.rs:211`/`worker.rs:693` lock-class distinction is shared with S02 and verified.
- **S05 Billing & state-machine** — HIGH. `billing.rs:109-149` single-txn (begin/flip/apply_usage_writes/commit) and `store.rs:805/822` expire stamps byte-verified; the `billing.rs:127/263` guards shared with S01 verified. One backend gap: codebase-memory `trace_path`/`query_graph` for gateway symbols returns nothing (NO-PROJECT) — the sector does not always hedge this.
- **S06 Storage & residency** — MEDIUM. `sweep.rs`/`s3_client.rs` files confirmed to exist in worktree; the `:47-48`/`:60-61` sweep selectors and `s3_client.rs:132-134` SSE-S3 header cited but not byte-verified this pass. The sector correctly flags the CodeGraph worktree mismatch. The ADR 0002→0003→0004 chain is sourced from `feedback-divergences`, not re-verified.
- **S07 Schema & migrations** — HIGH. `flyway.conf` `outOfOrder=false`/`validateOnMigrate=true` byte-verified; main head V37 and worktree V38-V44 (V39/V43 gaps) confirmed by `ls`; `git log` confirms the renumber commits. The "zero indexes on det_failures" claim is the sector's own finding (grep-based) and is the correct backend for DDL. The CodeGraph worktree-mismatch caveat is correctly noted.
- **S08 Wire/contract** — MEDIUM. `types.rs` confirmed to exist; the 8-term `BatchStatus` enum and `:315` reject-`canceled` test cited but not byte-verified this pass. `batches.rs:26` `BATCH_ENDPOINT`, `files.rs:288/313`, `store.rs:805` (shared with S05, verified) anchors plausible. `generateCosmosImage.ts` path drift (now `agenticLoop/`) flagged by the sector.
- **S09 Multi-repo & deploy** — MEDIUM. CODEOWNERS verified (dev image files unowned, catch-all for uat/prod); `flyway.conf` verified; the umbrella-not-monorepo topology confirmed by `worktrees/batch-api/` five-repo layout. ONE stale anchor: "gateway-db main head is V42" is wrong (actual main head V37); the concurrent-collision narrative is about a prior state. The sector otherwise correctly names `glob`/`bash` as the backend for DDL/YAML.
- **S10 SSRF, redaction & security** — HIGH. `ssrfGuard.ts:166` `validateAndPinUrl` byte-verified; `clientEgress.ts` confirmed absent (find returns nothing); the playbook's `clientEgress.ts:103` is fully stale and the sector's correction is accurate. The redirect-re-validation caveat is well-scoped. `userMemory.controller.ts`/`sharedUpload.ts` ownership anchors cited but not byte-verified this pass.
- **S11 Testing & CI gates** — HIGH. The `test.yaml` absence is the load-bearing finding and is decisively verified: only `build.yaml` (tag-only) exists in the gateway worktree. `testdb.rs`/`require_pool!` not re-read but the workflow absence makes the paradigm fire. The `clientEgress.ts:103` egress-boundary citation in P-11-3 is stale (same as S10) and should be corrected to `ssrfGuard.ts:166`. The three-worktree split (batch-api vs training-webhooks) is correctly noted.
- **S12 Code smell, naming & correctness** — HIGH. `worker.rs:41` `MAX_ATTEMPTS` and `:93` caller byte-verified; the name-lies-about-what-it-caps finding is real (constant gates `det_failures`, named `MAX_ATTEMPTS`). The `Instant::now()`-is-a-stopwatch restraint (P-12-6) is correctly scoped. `cancel_batch`/`cancelling_at` re-stamp and `jsonl.rs` BOM-gap anchors cited but not byte-verified this pass.

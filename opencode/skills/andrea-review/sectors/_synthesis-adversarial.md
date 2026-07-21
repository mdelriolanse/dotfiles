# Synthesis — Adversarial Pass

## Method

I scored all 77 paradigms (S01:7, S02:6, S03:6, S04:7, S05:7, S06:6, S07:5,
S08:7, S09:7, S10:6, S11:6, S12:7) on four axes, 1–5 each:

- **False-positive risk** — how easily the paradigm flags code that is
  actually correct. I weighted this highest: a paradigm that fires on
  correct code is net-negative signal because every false finding costs the
  PR author's time and erodes trust in the playbook. A score of 5 means an
  agent following the paradigm literally will produce wrong findings on
  common, correct code (e.g. demanding an advisory lock where SKIP LOCKED
  already provides row disjointness).
- **Over-application risk** — would an agent apply this to code paths where
  it doesn't belong? Distinct from FP: the finding *shape* is correct, but
  the *scope* is wrong (e.g. "inject the clock into every route" applied to
  read-only `Utc::now()` defaults). A score of 5 means the paradigm is
  phrased broadly enough that scoping requires judgment the agent often
  won't apply.
- **Grounding fragility** — how likely is the infra anchor to drift, break,
  or move, making the paradigm ungroundable? The sectors already self-flag
  three stale playbook anchors (`trainingJob.controller.ts:540`,
  `trainingWebhook.job.ts:51`, `executeTool.ts:470`); anchors in the
  `feat-batch-api-*` worktrees (not the main checkout) are inherently
  more fragile because the main CodeGraph index cannot see them.
- **Sector confusion** — does this paradigm actually belong in another
  sector, creating duplicate findings? I used each sector's self-reported
  Cross-sector links plus the overlap pattern: paradigms that name the same
  evidence as another sector (e.g. P-05-3 and P-01-1 both ground
  `billing.rs:127`; P-10-5 and P-05-4 both ground `reviewActions.ts:69`)
  score high on this axis.

A paradigm is **high-risk** (enters the table below) if it scores ≥4 on any
axis. A paradigm is **robust** if it scores ≤2 on all four. I name the
codebase-intelligence backend for every cross-sector merge decision as the
contract requires. The naming convention is:

- **CodeGraph** — verbatim source + call paths, per-repo SQLite, must run
  with `-p <repo>` from a worktree that has the code.
- **Serena** — symbol-level `find_symbol` / `find_referencing_symbols`,
  the canonical way to confirm a symbol exists before citing it.
- **semble** — embedding + BM25 search, the only reliable way to relocate a
  symbol whose playbook-cited path has drifted.
- **codebase-memory** — Cypher graph, the only backend that materializes
  real cross-repo HTTP edges (`trace_path cross_service`); the gateway
  project is NOT in the default index list.
- **agentmemory** — prior-session decisions; the canonical way to check
  whether a deferral or infra prereq was already decided.

I leaned toward KEEP-WITH-GUARDRAIL over REFINED over KILL: the paradigm
authors already wrote honest adversarial caveats, so most paradigms are
right in their core and wrong only in their scope — a guardrail is cheaper
than a rewrite and preserves the source evidence.

## High-risk paradigms (score >= 4 on any axis)

### A-1: S01 P-01-3 — Key re-arm / re-delivery gates on a deterministic fingerprint, never on ciphertext
- **FP risk**: 5 — The live `triggerWebhook` deliberately inserts a new `automation_run` per authenticated hit and bounds replays by HMAC timestamp tolerance (±300s) + per-workflow rate limit, with no stored nonce. An agent applying this paradigm naively will flag "no idempotency key" on a codebase whose design is at-most-once-per-tolerance-window — a false positive the sector's own caveat names.
- **Over-application risk**: 3 — A gate is correctly absent when the contract is per-window, not cross-window.
- **Grounding fragility**: 5 — The playbook anchor `trainingJob.controller.ts:540` is **stale**; the signing path moved to `automation.controller.ts:1329-1403`. The sector self-flagged this. Any agent citing the playbook line verbatim produces wrong file:line evidence.
- **Sector confusion**: 4 — P-01-3 overlaps S08 (wire signing shape) and S10 (P-10-6 webhook HMAC). The "deterministic not ciphertext" half is Sector 01; the "Standard Webhooks header shape" half is arguably S08.
- **Worst-case agent behavior**: An agent flags every webhook trigger without a stored dedup nonce as a missing-idempotency-key defect, ignoring that `triggerWebhook`'s design bounds replays by timestamp tolerance and rate limit, and cites a playbook anchor (`trainingJob.controller.ts:540`) that no longer exists.
- **Guardrail**: Before flagging a missing dedup gate, confirm the caller's contract requires cross-window exactly-once (not just per-window); before citing the playbook's `trainingJob.controller.ts:540` anchor, re-ground via `semble_search "webhook signature HMAC timestamp body deterministic"` — the anchor moved to `automation.controller.ts`.
- **Kill / keep / refine**: KEEP-WITH-GUARDRAIL

### A-2: S01 P-01-4 — Carry `expectedVersion` into the retry handler, not just the happy path
- **FP risk**: 4 — The "retry asserts `0`" pattern is specific to the *first-create* conflict (no prior row). On an *update* conflict the correct retry re-reads and re-asserts the *new* version. An agent copying the `0` pattern onto an update-retry path creates a new bug.
- **Over-application risk**: 4 — Sector 02 P-02-4 is the *same* paradigm (optimistic-concurrency guard must travel to retry); the two sectors explicitly twin this. An agent applying both produces a duplicate finding on the same `executeTool.ts:586` evidence.
- **Grounding fragility**: 4 — The playbook anchor `executeTool.ts:470` is **stale by ~75 lines** (now `:545-559`). The sector self-flagged this drift.
- **Sector confusion**: 5 — P-01-4 and P-02-4 are explicitly twins ("Sector 01 owns the *what*; this sector owns the *how*"). The dedup pass will have to merge them.
- **Worst-case agent behavior**: An agent flags an update-retry path for not asserting `expectedVersion: 0` (the first-create pattern), creating a new bug; or opens two findings (one from S01, one from S02) on the same `executeTool.ts` evidence.
- **Guardrail**: The retry must re-assert the version that makes the retry's intent correct — `0` only on first-create conflicts; the *new* version after a re-read on update conflicts. Merge P-01-4 and P-02-4 into one finding (the dedup pass owns this); cite `executeTool.ts:545-559`, not the playbook's stale `:470`.
- **Kill / keep / refine**: REFINED (merge with P-02-4; narrow the `0` pattern to first-create only)

### A-3: S01 P-01-5 — Make retry backoff jittered and abort-signal-carrying; a deterministic formula is a bug
- **FP risk**: 5 — For the batch path, the reaper's lease-spacing (a row reclaims at most once per reaper interval, minute-scale) is a legitimate *alternative* to exponential jitter. An agent flagging "no `Math.random` in the reaper" is a false positive: the batch path deliberately spaces by lease, not by per-retry jitter.
- **Over-application risk**: 4 — The paradigm applies to *outbound client-delivery* retry (webhooks), not to *inbound lease reclaim* (batch re-run). An agent that does not distinguish the two over-applies.
- **Grounding fragility**: 5 — The playbook anchor `trainingWebhook.job.ts:51` is **gone**; the file does not exist. The live implementation of a jittered abort-signal-carrying client retry loop is NOT in the audited batch-api code. The anchor could not be fully grounded.
- **Sector confusion**: 3 — P-01-5 and S03 P-03-4 (forward the abort signal) share the abort-signal half. The jitter half is unique to S01; the signal half overlaps S03.
- **Worst-case agent behavior**: An agent flags the batch reaper for missing jitter (false positive) and cites `trainingWebhook.job.ts:51` (a file that no longer exists) as the canonical sibling.
- **Guardrail**: The jitter paradigm applies to *concurrent* client-delivery retryers (webhooks outbound); lease reclaim uses *spacing-by-lease* (inbound), which is a different problem. Before flagging "no jitter", confirm the retry is concurrent-client-delivery, not lease-spaced. Before citing `trainingWebhook.job.ts:51`, re-ground via `semble_search "jitter backoff retry abort signal Math.random"` across the full app tree.
- **Kill / keep / refine**: REFINED (scope to outbound client-delivery retry; the abort-signal half is shared with P-03-4)

### A-4: S02 P-02-1 — A per-process counter is not a fleet-wide QoS signal
- **FP risk**: 4 — If the deployment is genuinely and durably pinned to `replicas: 1` (PDB min-available 1, helm CEL admission gate, NetworkPolicy making a second pod unschedulable), the per-process counter is correct and adding a SQL fleet clamp is dead weight. The smell is the *gap* (asserted but unenforced invariant), not the in-process counter itself.
- **Over-application risk**: 4 — S04 P-04-7 is the *same* paradigm (QoS signal must be correct under deployment topology — singleton-ness, not co-location). The two sectors explicitly share BLOCKER-3 / Rebuttal (a) evidence. An agent applying both opens two findings on the same `interactive_in_flight` counter.
- **Grounding fragility**: 3 — The `AppState.interactive_in_flight` anchor at `worker.rs:881`/`reaper.rs:223`/`preflight.rs:811`/`batches.rs:629`/`files.rs:523` is live but spread across the worktree.
- **Sector confusion**: 5 — P-02-1 and P-04-7 are explicit twins ("here it is 'is the signal fleet-consistent?'; in Sector 04 it is 'does the tier actually enforce fairness?'"). The dedup pass will merge.
- **Worst-case agent behavior**: An agent flags the in-process counter as a fleet-wide race on a deployment that is and will remain `replicas: 1`, demanding a vLLM `/metrics` migration that adds a scrape-timeout failure mode for no correctness gain; or opens two findings (S02 + S04) on the same counter.
- **Guardrail**: The paradigm fires *only* when the `replicas: 1` invariant is asserted but not enforced (the gap is the finding). Confirm the invariant is unenforced (no PDB, no CEL gate, no NetworkPolicy) before flagging; if enforced, the in-process signal is the *better* QoS source (lower latency). Merge P-02-1 and P-04-7 into one finding (the dedup pass owns this).
- **Kill / keep / refine**: REFINED (merge with P-04-7; require confirming the invariant is unenforced before flagging)

### A-5: S02 P-02-2 — A CTE-inlined `count(*)` is not a hard cap under MVCC; distinguish row-disjoint from count-disjoint locks
- **FP risk**: 5 — For genuinely row-disjoint workloads (each txn claims a distinct row by PK), `FOR UPDATE SKIP LOCKED` *is* a hard cap on double-claim of the same row. The paradigm must not be over-applied to demand an advisory lock where SKIP LOCKED already provides the needed disjointness. This is the canonical FP the contract names.
- **Over-application risk**: 4 — The smell is specifically a *count-based* cap guarded only by a CTE read, not a row-based claim guarded by SKIP LOCKED. An agent that greps for "no advisory lock" and flags every SKIP LOCKED site over-applies.
- **Grounding fragility**: 3 — The `create_batch_capped` / `claim_requests` anchors at `store.rs:211` / `store.rs:460-475` are live but in the worktree.
- **Sector confusion**: 4 — S04 P-04-4 is the *same* paradigm (a count-based CTE is not a hard cap under MVCC). The two sectors explicitly twin this. Also S02 P-02-3 (advisory-lock class) is a sibling.
- **Worst-case agent behavior**: An agent demands `pg_advisory_xact_lock` on `claim_requests` (which already uses `FOR UPDATE SKIP LOCKED` for row-disjoint claims), adding contention for no correctness gain.
- **Guardrail**: Distinguish row-disjoint locks (`FOR UPDATE SKIP LOCKED`, each txn locks a different row) from count-disjoint locks (`pg_advisory_xact_lock`, serializes a check-then-insert). Do NOT demand an advisory lock where SKIP LOCKED already provides row disjointness. The smell is specifically a *count-based* cap guarded only by a CTE read. Merge P-02-2 and P-04-4 into one finding (the dedup pass owns this); name the codebase-intelligence backend: `codegraph explore -p ~/<provider>/gateway "FOR UPDATE SKIP LOCKED claim_requests"` confirms row-disjoint; `Serena find_symbol on create_batch_capped` confirms xact-lock-inside-tx.
- **Kill / keep / refine**: KEEP-WITH-GUARDRAIL

### A-6: S02 P-02-5 — Global FIFO starves; partition the claim by the fairness key
- **FP risk**: 3 — Flagging global FIFO is always correct *when multiple tenants share one schedulable resource*; the FP is when the fleet runs `replicas: 1` with one org (global FIFO is correct and the partition adds cost for no fairness gain).
- **Over-application risk**: 3 — The fairness key is "almost always the tenant/org"; an agent that demands partition by a different key (per-batch, per-user) over-applies the next axis.
- **Grounding fragility**: 3 — The `ROW_NUMBER() OVER (PARTITION BY b.org)` anchor at `store.rs:448-451` is live but in the worktree.
- **Sector confusion**: 4 — S04 P-04-3 is the *same* paradigm (partition the claim queue by org so no org starves another to expiry). The two sectors explicitly twin this. An agent applying both opens two findings on the same `claim_requests` query.
- **Worst-case agent behavior**: An agent flags the claim as "unfair" on a single-org `replicas: 1` deployment, or demands per-batch / weighted fair-share (the next axis the `ponytail:` comment defers) when per-org round-robin already solves the reported starvation.
- **Guardrail**: The paradigm fires only when multiple tenants share one schedulable resource. Partition-by-org is fairness *across orgs*, not across batches within an org (the `ponytail:` comment names the unimplemented next axis). Flag global FIFO; do NOT claim the window function solves all fairness. Merge P-02-5 and P-04-3 into one finding.
- **Kill / keep / refine**: REFINED (merge with P-04-3; scope to multi-tenant shared-resource deployments)

### A-7: S02 P-02-4 — The optimistic-concurrency guard must travel to the retry handler
- **FP risk**: 4 — Some retries are intentionally unguarded because the retry is idempotent by construction (a deterministic re-arm-key gate, S01). Re-asserting a version there can dead-loop a legitimate retry against a concurrent committer that will never yield.
- **Over-application risk**: 4 — The paradigm targets *clobbering* writes (state-machine flips, versioned artifact saves, claim finalize), not idempotent re-applies.
- **Grounding fragility**: 3 — The `executeTool.ts:545-586` and `billing.rs:127/263` anchors are live.
- **Sector confusion**: 5 — P-02-4 is the explicit twin of P-01-4 ("Sector 01 owns the *what*; this sector owns the *how*"). A webhook re-delivery that re-fires correctly (S01) but drops `expectedVersion` on retry (S02) is a single PR with two findings.
- **Worst-case agent behavior**: An agent flags an idempotent retry for not re-asserting `expectedVersion`, dead-looping a legitimate retry; or opens two findings (S01 + S02) on the same `executeTool.ts` evidence.
- **Guardrail**: The paradigm targets *clobbering* writes, not idempotent re-applies. Distinguish a clobbering retry (state-machine flip, versioned save) from an idempotent re-apply (deterministic re-arm-key gate, S01) before flagging the dropped guard. Merge P-02-4 and P-01-4 into one finding.
- **Kill / keep / refine**: REFINED (merge with P-01-4; scope to clobbering writes only)

### A-8: S04 P-04-1 — Enforce per-key RPM on every new public route, after auth
- **FP risk**: 3 — Flagging a missing `check` is always correct *on a new public API-key route*; the FP is flagging it on an internal/admin route or a health-check route that has no key to check.
- **Over-application risk**: 4 — The paradigm is scoped to "new public route that accepts an API key", but an agent that greps for "new route without `rate_limiter.check`" will flag internal and health routes. The sector's own failure-mode bullet names this.
- **Grounding fragility**: 3 — The `rate_limiter.check` anchor at `batches.rs:50` / `files.rs:59` / `rate_limit.rs:39` is live.
- **Sector confusion**: 3 — The app-side `enforceChatLimits` analog overlaps the playbook's "Per-model rate-limit gate" convention, which a future app-side sector may claim.
- **Worst-case agent behavior**: An agent flags every new route (including internal admin and health-check routes) for missing `rate_limiter.check`, producing a pile of false positives on routes with no API key to check.
- **Guardrail**: The check is for public API-key surface only. Before flagging, confirm the route accepts an API key (not internal/admin/health); the playbook convention is per-`model_id` / per-key, both assume a key exists.
- **Kill / keep / refine**: KEEP-WITH-GUARDRAIL

### A-9: S04 P-04-2 — Bound concurrent uploads with a fail-fast permit, not a body limit
- **FP risk**: 2 — The N×body-size resident-memory math is unambiguous; the fix (semaphore + 429) is correct for the OOM bound.
- **Over-application risk**: 3 — A global semaphore caps the *fleet* of uploaders, not per-org; one noisy org can exhaust all 6 permits. The fix is correct for OOM, but an agent that declares the upload "fair" over-claims.
- **Grounding fragility**: 3 — The `FILE_UPLOAD_MAX_CONCURRENCY` / `try_acquire` anchors at `files.rs:28/53-57` are live.
- **Sector confusion**: 4 — The per-org quota deferral depends on S06 (the 29-day sweep bounds retention; if the sweep leaks, the deferral's safety argument breaks). An agent applying this in isolation misses the S06 dependency.
- **Worst-case agent behavior**: An agent recommends a per-org partition on the upload semaphore without measuring, shrinking the effective cap per org and 429-ing legitimate uploads; or declares the upload "fair" when the global semaphore is OOM-only, not per-org fair.
- **Guardrail**: The global semaphore solves the OOM bound, not per-org fairness; the per-org fairness gap is a real but separately-scoped finding (name it, do not patch it). A per-org partition trades OOM-safety margin for fairness — flag as a tradeoff, not a free improvement. The per-org quota deferral is safe only because the 29-day sweep (S06) bounds retention; if the sweep leaks, the deferral's safety breaks.
- **Kill / keep / refine**: KEEP-WITH-GUARDRAIL

### A-10: S04 P-04-4 — A count-based CTE is not a hard cap under MVCC — use a per-xact advisory lock for atomic admission
- **FP risk**: 5 — Same as A-5: `pg_advisory_xact_lock` serializes the count-then-insert sequence, which is correct for *admission* but introduces contention proportional to create frequency; for a high-frequency path the lock becomes the bottleneck and a `FOR UPDATE SKIP LOCKED` row-disjoint claim is the better trade. The right pattern depends on whether the cap gates *creation* (rare, serialize) or *claiming* (frequent, disjoint).
- **Over-application risk**: 4 — An agent that demands the per-xact lock for a frequent claim path adds contention for no correctness gain.
- **Grounding fragility**: 3 — The `create_batch_capped` / `claim_requests` anchors are live.
- **Sector confusion**: 5 — P-04-4 is the explicit twin of P-02-2. The two sectors share BLOCKER-3 / Rebuttal evidence.
- **Worst-case agent behavior**: An agent demands `pg_advisory_xact_lock` on `claim_requests` (row-disjoint, frequent), adding contention for no correctness gain.
- **Guardrail**: Distinguish row-disjoint (SKIP LOCKED, frequent claims) from count-disjoint (advisory xact lock, rare creates). The right pattern depends on whether the cap gates *creation* (rare, serialize) or *claiming* (frequent, disjoint). Merge P-04-4 and P-02-2 into one finding; name the backend: `Serena find_symbol on create_batch_capped` confirms the xact lock is inside the `pool.begin()…tx.commit()` span.
- **Kill / keep / refine**: REFINED (merge with P-02-2; the over-application is the same finding)

### A-11: S04 P-04-7 — QoS signals must be correct under the deployment topology — singleton-ness, not co-location
- **FP risk**: 4 — The in-process signal has *lower latency* than a `/metrics` scrape (no HTTP round-trip, no scrape interval lag), so for a genuinely single-replica gateway it is the *better* QoS source, not a stopgap. Recommending `/metrics` migration for a deployment that is and will remain `replicas: 1` over-engineers the signal and adds a failure mode (scrape timeout).
- **Over-application risk**: 4 — The fix is correct *only* when the topology actually splits; for the singleton case the right finding is "document the invariant", not "migrate the signal".
- **Grounding fragility**: 3 — The `allowed_batch_slots` / `interactive_in_flight` anchors at `slots.rs:6` / `main.rs:86-87` are live.
- **Sector confusion**: 5 — P-04-7 is the explicit twin of P-02-1. The two sectors share BLOCKER-3 / Rebuttal (a) evidence.
- **Worst-case agent behavior**: An agent recommends a vLLM `/metrics` migration for a `replicas: 1` deployment, over-engineering the signal and adding a scrape-timeout failure mode; or opens two findings (S02 + S04) on the same counter.
- **Guardrail**: For a genuinely single-replica gateway, the in-process signal is the *better* QoS source; the right finding is "document the `replicas: 1` invariant + name the `ponytail:` upgrade path", not "migrate to `/metrics`". Migrate only when the topology actually splits. Merge P-04-7 and P-02-1 into one finding.
- **Kill / keep / refine**: REFINED (merge with P-02-1; scope to enforced-vs-unenforced singleton invariant)

### A-12: S05 P-05-2 — Apply the half-rate discount at exactly one site
- **FP risk**: 3 — "Exactly one site" is a property of the *value's lifetime*, not a grep count. A refactor that moves the discount from `finalize_success` into the worker (still one site, earlier in the path) is correct as long as the discounted value reaches `apply_usage_writes`. An agent that flags a refactor as "two sites" because the call moved over-applies. A test helper that calls `discount` to build expected values is also a false positive.
- **Over-application risk**: 4 — An agent that greps for `discount(` and flags every non-`billing.rs:112` call over-applies.
- **Grounding fragility**: 3 — The `discount` / `billing.rs:112` / `worker.rs:492` anchors are live but in the worktree.
- **Sector confusion**: 2 — The half-rate concern is uniquely S05.
- **Worst-case agent behavior**: An agent flags a test helper that calls `discount` to build expected values as a "second discount site", or flags a correct refactor that moved the single discount site earlier in the path.
- **Guardrail**: "Exactly one site" is a property of the *value's lifetime* (the discounted value reaches both `cost_usd` columns without re-halving), not a literal `discount(` call count. The bug is two *production* halvings in series; test helpers and single-site refactors are fine. Confirm via `codebase-memory trace_path mode=data_flow` from `worker.rs:494` → `billing.rs:112` → `metering.rs:265` that the value is halved once and never re-halved.
- **Kill / keep / refine**: KEEP-WITH-GUARDRAIL

### A-13: S05 P-05-3 — Pin every finalize to the claim generation with `AND attempt = $N`
- **FP risk**: 4 — The guard protects against *stale-worker* double-billing, not against a worker that legitimately re-claims and re-runs the same line — that re-run *should* bill (it did new GPU work). A reviewer who reads "no double-bill" too broadly might demand the re-run be free, which would be under-billing.
- **Over-application risk**: 4 — S01 P-01-1, S01 P-01-7, and S05 P-05-3 all ground `billing.rs:127` / `billing.rs:263` and the `AND attempt = $N` guard. Three paradigms, one mechanism, one anchor. An agent applying all three opens three findings on the same evidence.
- **Grounding fragility**: 3 — The `billing.rs:127/263` anchors are live but in the worktree.
- **Sector confusion**: 5 — P-05-3 is the explicit twin of P-01-1 (gate-key shape vs. no-double-bill consequence) and P-01-7 (symmetrize across finalize siblings). The three sectors explicitly share the `billing.rs:127` evidence.
- **Worst-case agent behavior**: An agent flags a legitimate re-claim re-run as a double-bill (demanding the re-run be free = under-billing), or opens three findings (S01 P-01-1, S01 P-01-7, S05 P-05-3) on the same `billing.rs:127` guard.
- **Guardrail**: The guard no-ops a *stale* worker; a *fresh* re-claim bumps `attempt` and the re-run legitimately matches and bills. The distinguishing test: did the `attempt` the worker holds match the row's current `attempt`? Yes → bill (correct); No → no-op (correct). Merge P-01-1, P-01-7, and P-05-3 into one finding (the dedup pass owns this); keep the gate-key-shape framing in S01, the no-double-bill framing in S05, the symmetry framing in S01.
- **Kill / keep / refine**: REFINED (merge with P-01-1 and P-01-7; the over-application is the same finding)

### A-14: S05 P-05-4 — Every terminalization writes a terminal status — no non-terminal leak
- **FP risk**: 4 — "Terminal status always written" does not mean "every UPDATE must go to terminal." The legitimate non-terminal advance is `queued`→`in_flight` (the claim) and `in_progress`→`cancelling` (cancel requested, draining). An agent that flags the claim UPDATE as a "leak" is wrong — the leak invariant is about *terminalization* paths, not advance paths.
- **Over-application risk**: 4 — S10 P-10-5 is the *same* paradigm (write a terminal status on every state-machine swap — a non-terminal row is a leak). The two sectors explicitly twin this. Also S05 P-05-7 (409 while in-flight) is a sibling.
- **Grounding fragility**: 3 — The `store.rs:805/822` / `billing.rs:196/261` / `types.rs:48-54` anchors are live.
- **Sector confusion**: 5 — P-05-4 and P-10-5 explicitly share `reviewActions.ts:69` and `billing.rs:127` evidence. S05 owns the correctness lens; S10 owns the security-adjacent lens (a non-terminal row a user can still act on is an IDOR-adjacent leak).
- **Worst-case agent behavior**: An agent flags the `queued`→`in_flight` claim UPDATE as a "non-terminal leak", or opens two findings (S05 + S10) on the same `reviewActions.ts:69` evidence.
- **Guardrail**: The leak invariant is about *terminalization* paths, not advance paths. The distinguishing question: does the operation *intend* to end the lifecycle? If yes, it must write terminal; if it's an intermediate step (`queued`→`in_flight`, `in_progress`→`cancelling`), it must not. Merge P-05-4 and P-10-5 into one finding; keep the correctness lens in S05, the security lens in S10.
- **Kill / keep / refine**: REFINED (merge with P-10-5; scope to terminalization paths, not advances)

### A-15: S05 P-05-5 — Enforce budget at admission (fresh re-check), not at finalize-time grace
- **FP risk**: 4 — Unconditional increment means a buggy or malicious upstream that inflates `cost_usd` can push `spent_usd` arbitrarily far past the cap before the next admission check fires. The cap is *not* a hard spend ceiling; it is enforced at the *next* row's admission. A reviewer demanding "the counter can never exceed the cap" is asking for a different (and more expensive — per-row `FOR UPDATE` on the users row) invariant than #1347 chose.
- **Over-application risk**: 3 — An agent that flags "budget violated" when `spent_usd` exceeds the cap by one row's cost × concurrency is wrong — the invariant is "the cap is enforced at the next admission", not "the counter is a hard ceiling".
- **Grounding fragility**: 3 — The `worker.rs:339` / `metering.rs:278-281` anchors are live.
- **Sector confusion**: 2 — The budget-admission concern is uniquely S05.
- **Worst-case agent behavior**: An agent flags `spent_usd > budget_usd` as a "budget violation" on a system that deliberately increments unconditionally and enforces at the next admission, demanding a per-row `FOR UPDATE` on the users row that #1347 deliberately rejected.
- **Guardrail**: The #1347 direction is *unconditional* increment with post-hoc admission enforcement; the counter will exceed the cap by up to one row's cost × concurrency. The invariant is "the cap is enforced at the next admission", not "the counter is a hard ceiling". A hard ceiling needs per-row `FOR UPDATE` on the users row, which #1347 deliberately rejected. Do not flag the over-cap state as a violation.
- **Kill / keep / refine**: KEEP-WITH-GUARDRAIL

### A-16: S05 P-05-6 — Keep `request_counts` folding honest — `failed` is errored only, never canceled/expired
- **FP risk**: 3 — "Never fold canceled/expired into failed" is an OpenAI-wire *contract*, not a universal truth — a different API dialect might legitimately fold them.
- **Over-application risk**: 4 — An agent that flags a fold in a non-OpenAI-shaped internal endpoint over-applies. The distinguishing test: does the endpoint claim OpenAI wire conformance?
- **Grounding fragility**: 3 — The `types.rs:99-114` / `batches.rs:95` / `files.rs:288` anchors are live.
- **Sector confusion**: 5 — P-05-6 and S08 P-08-2 explicitly share MAJOR-4 evidence (the expired-batch fix serves both lenses: wire reconciliation here, state-machine terminality in S05). The fold rule is arguably S08's wire lens; the state-machine-terminality motivation is S05's.
- **Worst-case agent behavior**: An agent flags a fold in a non-OpenAI internal endpoint, or opens two findings (S05 + S08) on the same MAJOR-4 fix.
- **Guardrail**: The fold rule is specific to OpenAI-exact conformance (S08 owns the dialect question). The distinguishing test: does the endpoint claim OpenAI wire conformance? If yes, no fold; if no, the fold is a design choice. Merge the wire lens into S08 P-08-2; keep the state-machine-terminality motivation in S05.
- **Kill / keep / refine**: REFINED (merge wire lens with P-08-2; scope to OpenAI-exact endpoints)

### A-17: S05 P-05-7 — Gate result-file reads on batch terminality — 409 while in-flight
- **FP risk**: 4 — 409 while in-flight is correct for *synthetic* result files (assembled from live `batch_request` rows), but a *real* S3 object (a per-line result PUT before finalize, per ADR 0004) is already immutable and could legitimately be read by an internal debug path — gating it on batch terminality would be wrong.
- **Over-application risk**: 3 — The paradigm applies to the *aggregated/synthetic* surface, not to raw object fetches that are individually terminal the moment they're PUT.
- **Grounding fragility**: 3 — The `files.rs:216-220` / `types.rs:48-54` / `batches.rs:92` anchors are live.
- **Sector confusion**: 4 — P-05-7 and S08 P-08-2 share MINOR-3 evidence (the 409 gate). S08 owns the wire 409 contract; S05 owns the state-machine-terminality invariant that motivates it.
- **Worst-case agent behavior**: An agent flags a raw S3 object fetch (an immutable per-line result PUT) for not gating on batch terminality, breaking an internal debug path.
- **Guardrail**: The 409 gate applies to the *aggregated/synthetic* surface (assembled from live rows), not to raw object fetches that are individually terminal the moment they're PUT. Merge the wire-409 lens into S08; keep the state-machine-terminality motivation in S05.
- **Kill / keep / refine**: KEEP-WITH-GUARDRAIL

### A-18: S06 P-06-1 — Sweep must delete every generation up to the claim high-water mark
- **FP risk**: 2 — The `1..=attempt` loop is the residency invariant; the FP is flagging it as "O(n²) overkill" on a pathological reclaim storm.
- **Over-application risk**: 3 — An agent that demands the loop be optimized (batched LIST, etc.) over-applies: S3 has no LIST in the gatekeeper posture, and under-deleting is a residency violation while over-deleting is a cheap idempotent 404.
- **Grounding fragility**: 3 — The `sweep.rs:47-48` / `sweep.rs:60-61` anchors are live.
- **Sector confusion**: 2 — The sweep residency concern is uniquely S06 (S03 owns the drain that prevents orphans, S06 owns the sweep that reclaims them).
- **Worst-case agent behavior**: An agent flags the `1..=attempt` loop as "O(n²) overkill" on a batch with `attempt = 1000`, demanding a batched LIST optimization that S3's gatekeeper posture does not provide.
- **Guardrail**: S3 has no LIST in the gatekeeper posture; the brute-force `1..=attempt` scan is the design. Under-deleting is a residency violation; over-deleting is a cheap idempotent 404. Do not flag the loop as overkill; flag a *narrowed* selector (`result_attempt IS NOT NULL`) that skips the orphans the loop exists to reclaim.
- **Kill / keep / refine**: KEEP-WITH-GUARDRAIL

### A-19: S07 P-07-1 — Ship a partial index for every hot per-tick query predicate
- **FP risk**: 3 — `select_exhausted_queued` returns the *exhausted* rows (about to be terminalized); the result set is small and the query runs once per tick. An adversary could argue the sequential scan over `status='queued'` rows (which the existing `idx_batch_request_claim` narrows) plus an in-memory `det_failures >= $1` filter is fine at fleet scale.
- **Over-application risk**: 4 — S12 P-12-2 is the *same* paradigm (add a partial index for every hot-path predicate a re-cut introduces). The two sectors explicitly share NIT-2 evidence. An agent applying both opens two findings on the same `select_exhausted_queued` query.
- **Grounding fragility**: 4 — The index lives in `gateway-db` (DDL, not code symbols); CodeGraph's `~/<provider>/gateway/.codegraph` is the *main*-branch index, which has no batch module. An agent must target `gateway-db/migrations/` (or its worktree), not the gateway checkout.
- **Sector confusion**: 5 — P-07-1 and P-12-2 explicitly twin. S07 owns the migration/index lens; S12 owns the naming/code-smell lens.
- **Worst-case agent behavior**: An agent greps `~/<provider>/gateway/` for `CREATE INDEX det_failures`, concludes "no index" by looking in the wrong repo, and files a false positive; or opens two findings (S07 + S12) on the same missing index.
- **Guardrail**: The index lives in `gateway-db/migrations/`, not the gateway checkout; CodeGraph's main-branch gateway index has no batch module. Target `gateway-db/migrations/` (or its worktree) with `grep -rn "det_failures"`. Whether the scan is "fine" depends on max queued rows per deployment (capped at 10k/file); state the cap before deciding the NIT is a non-issue. Merge P-07-1 and P-12-2 into one finding; keep the migration lens in S07, the code-smell lens in S12.
- **Kill / keep / refine**: REFINED (merge with P-12-2; require targeting gateway-db, not gateway)

### A-20: S07 P-07-2 — Re-cut migrations above main's Flyway head; V-numbers are globally unique per DB
- **FP risk**: 2 — `outOfOrder=false` + `validateOnMigrate=true` makes the rule hold under this repo's config; the FP is on a repo with `validateOnMigrate=false`.
- **Over-application risk**: 3 — An agent that demands re-cutting on a team that sets `outOfOrder=true` over-applies (though `validateOnMigrate` still checksum-validates).
- **Grounding fragility**: 3 — The `gateway-db/flyway.conf` / `V37__org_default_budget.sql` anchors are live.
- **Sector confusion**: 4 — P-07-2 (the rule) and S09 P-09-3 (the cross-PR coordination) explicitly twin. S07 owns the globally-unique-per-DB rule; S09 owns the concurrent-PR collision.
- **Worst-case agent behavior**: An agent flags a V-number gap (V39, V43 missing) as a flyway-integrity bug, missing that the gap is a documented re-cut scar explained by the V44 supersession header.
- **Guardrail**: The rule holds under this repo's `outOfOrder=false` + `validateOnMigrate=true` config; it would not hold on a repo with `validateOnMigrate=false`. A V-number gap is a re-cut scar, not a defect — check for a supersession comment explaining the gap before flagging. The concurrent-PR collision is S09's lens, not S07's. Name the backend: `glob path="gateway-db/migrations/V*.sql"` and `read path="gateway-db/flyway.conf"` confirm the rule's preconditions.
- **Kill / keep / refine**: KEEP-WITH-GUARDRAIL

### A-21: S07 P-07-4 — Use CREATE INDEX CONCURRENTLY for indexes on existing large tables; plain CREATE INDEX is correct on fresh tables
- **FP risk**: 4 — The fresh-table exemption is real: a migration that `CREATE TABLE`s and `CREATE INDEX`es in the same transaction cannot use `CONCURRENTLY` and has no rows to lock. An agent that demands `CONCURRENTLY` on V44's `idx_batch_request_claim` is wrong — it would reject a correct migration. The check is "is the table already populated in prod", not "is the word CONCURRENTLY present".
- **Over-application risk**: 4 — An agent that greps for `CREATE INDEX` without `CONCURRENTLY` and flags every hit over-applies; the fresh-table case is correct.
- **Grounding fragility**: 3 — The `V19`/`V26`/`V28` concurrent siblings and the V44 plain-`CREATE INDEX` anchors are live.
- **Sector confusion**: 2 — The CONCURRENTLY concern is uniquely S07.
- **Worst-case agent behavior**: An agent flags V44's plain `CREATE INDEX IF NOT EXISTS` as a blocker, rejecting a correct migration on a fresh table; or demands `CONCURRENTLY` on a small config table where the locked build finishes in milliseconds and `CONCURRENTLY` adds failure modes (INVALID index) for no benefit.
- **Guardrail**: The rule is "match the build mode to the table state", not "always concurrent". The fresh-table exemption: a migration that `CREATE TABLE`s and `CREATE INDEX`es in the same transaction cannot use `CONCURRENTLY` and has no rows to lock. The check is "is the table already populated in prod (or will it grow large before the next migration window)", not "is the word CONCURRENTLY present". Both directions of mismatch (concurrent-on-fresh, plain-on-populated) are findings.
- **Kill / keep / refine**: KEEP-WITH-GUARDRAIL

### A-22: S08 P-08-1 — Emit OpenAI-exact wire shapes the official SDK parses unchanged
- **FP risk**: 4 — "OpenAI-exact" can be over-applied: OpenAI ships draft/beta fields (`metadata`, `completion_window` values beyond `24h`) the local build intentionally omits as out-of-scope. An agent that flags every absent OpenAI field as a contract break is wrong — the contract is "the SDK parses what we send", not "we send every OpenAI field".
- **Over-application risk**: 4 — An agent that diffs the local `BatchObject` against the full OpenAI spec and flags every absent field over-applies. The round-trip test at `types.rs:360` is the authority, not the OpenAPI spec.
- **Grounding fragility**: 3 — The `types.rs:11-20` / `types.rs:286-316` / `types.rs:360-426` anchors are live.
- **Sector confusion**: 3 — The wire-shape concern is uniquely S08, but P-08-2 / P-08-3 are siblings.
- **Worst-case agent behavior**: An agent diffs the local `BatchObject` against the full OpenAI spec and flags every absent field (`metadata`, `completion_window` values beyond `24h`) as a wire bug, producing a pile of false positives on intentionally-omitted draft/beta fields.
- **Guardrail**: The contract is "the SDK parses what we send", not "we send every OpenAI field". The round-trip test at `types.rs:360` (asserting the exact JSON including `"object": "batch"` and `"request_counts": {...}`) is the authority, not the OpenAPI spec. Flag a status string that drifts from the OpenAI vocabulary; do NOT flag an absent draft/beta field as a contract break.
- **Kill / keep / refine**: KEEP-WITH-GUARDRAIL

### A-23: S08 P-08-2 — Hold the `request_counts` reconciliation invariant end-to-end
- **FP risk**: 3 — A reviewer might argue `total - completed - failed` should always be `0` for a terminal batch, so canceled/expired "belong" in `failed`. That is the SDK's *reconciliation expectation* for *error files*, not a reason to fold the counts — folding would double-count.
- **Over-application risk**: 3 — An `expired` row with `error_code = 'batch_expired'` is arguably *not* a per-request error (the request was never attempted), so putting it in the *error* file is a semantic stretch vs OpenAI; the local choice trades OpenAI-exactness for SDK reconciliation completeness.
- **Grounding fragility**: 3 — The `types.rs:99-113` / `store.rs:805` / `files.rs:288` / `batches.rs:95` anchors are live.
- **Sector confusion**: 5 — P-08-2 and S05 P-05-6 explicitly share MAJOR-4 evidence (the expired-batch fix serves both lenses). S06 P-06-6 is also a sibling (the residency consequence: expired rows have a deletable footprint).
- **Worst-case agent behavior**: An agent flags a terminal batch with `total != completed + failed` as an invariant violation, missing that the gap is canceled/expired rows reconciled via the error file; or opens three findings (S05 + S06 + S08) on the same MAJOR-4 fix.
- **Guardrail**: A terminal batch *can* legitimately have `total != completed + failed` when rows are canceled or expired — that is the design. The invariant is reconciled via the error file (expired rows get error-file entries), not by folding counts. Folding would double-count. Flag the divergence (expired rows in the error file is a semantic stretch vs OpenAI) rather than treat it as obviously correct. Merge the wire lens here, the state-machine lens in S05 P-05-6, the residency lens in S06 P-06-6 — one finding, three lenses; name the backend: `codebase-memory trace_path mode=data_flow` from `request_tallies` → `RequestCounts::from_tallies` → `batch_object` confirms no caller mutates the rollup.
- **Kill / keep / refine**: REFINED (merge with P-05-6 and P-06-6; flag the semantic stretch, do not treat as obviously correct)

### A-24: S08 P-08-4 — Classify 4xx as non-recoverable and 5xx per-semantic, never blanket "retry everything ≥400"
- **FP risk**: 4 — Marking all 5xx non-recoverable is wrong for a generic LLM text endpoint where 503/504 genuinely means "retry later". The non-recoverable-5xx choice at `generateCosmosImage.ts:449` is specific to an *image* service known to abuse 5xx for content-safety.
- **Over-application risk**: 4 — An agent applying this paradigm to a different upstream must check whether *that* upstream uses 5xx semantically before copying the classification.
- **Grounding fragility**: 3 — The `generateCosmosImage.ts:404-468` anchor is live (the playbook's pre-refactor path predates the move to `agenticLoop/`).
- **Sector confusion**: 2 — The 4xx/5xx recoverability concern is uniquely S08 (S04 owns the 429 rate-limit status; S08 owns the recoverability contract the agent loop reads).
- **Worst-case agent behavior**: An agent copies the image-service 5xx-non-recoverable classification to a generic text LLM endpoint where 503 genuinely means "retry later", killing legitimate retries.
- **Guardrail**: The non-recoverable-5xx choice is specific to an image service known to abuse 5xx for content-safety. An agent applying this paradigm to a different upstream must check whether *that* upstream uses 5xx semantically before copying the classification. The 4xx-non-recoverable default holds broadly; the 5xx classification is upstream-specific.
- **Kill / keep / refine**: KEEP-WITH-GUARDRAIL

### A-25: S08 P-08-5 — Pin the endpoint vocabulary now; widen deliberately, never by accident
- **FP risk**: 3 — A single hard-coded `BATCH_ENDPOINT` constant is brittle but intentional YAGNI until embeddings is actually in scope.
- **Over-application risk**: 4 — An agent might flag the hard-code as a smell and propose a `match`/set now. That pre-builds the widening the design explicitly deferred.
- **Grounding fragility**: 3 — The `BATCH_ENDPOINT` / `batches.rs:224-226` / `jsonl.rs:159-160` anchors are live.
- **Sector confusion**: 3 — The vocabulary decision is S08; the companion-PR ordering of a widening is S09.
- **Worst-case agent behavior**: An agent refactors `BATCH_ENDPOINT` into a `match`/set now, "to be ready", pre-building the deferred embeddings scope and violating the explicit YAGNI decision.
- **Guardrail**: The single hard-coded constant is intentional until embeddings is actually in scope (the `ponytail:` YAGNI decision). Do NOT pre-build the widening. Flag a widening that drops the equality check; do NOT flag the hard-code itself as a smell.
- **Kill / keep / refine**: KEEP-WITH-GUARDRAIL

### A-26: S09 P-09-1 — Land companion PRs as a set — none ready until all open and approved
- **FP risk**: 2 — "Open and approved" is necessary but not sufficient: a companion can be approved on a stale base.
- **Over-application risk**: 3 — An agent that flags every multi-repo change as a "set" requiring all companions open may over-apply when one repo's change is independent.
- **Grounding fragility**: 3 — The five-worktree set `feat-batch-api-{app,gateway,gateway-db,helm,sdk}` is the physical artifact.
- **Sector confusion**: 3 — The set contract is uniquely S09 (S07 owns the single-migration internals; S09 owns the cross-repo ordering).
- **Worst-case agent behavior**: An agent marks the set "ready" because all companion PRs are open and approved, missing that a companion is approved on a stale base (a V-number collision or schema-column drift appears only at merge/rebase time).
- **Guardrail**: "Open and approved" is necessary but not sufficient: the set is only safe if every companion is rebased on its repo's current `main` at merge time. A V-number collision (P-09-3) or schema-column drift (P-09-2) is the failure mode that "approved" doesn't catch. Re-check against `origin/main` HEAD at merge, not at open.
- **Kill / keep / refine**: KEEP-WITH-GUARDRAIL

### A-27: S09 P-09-2 — Migration-before-app — the DB PR lands first, the code PR behind it
- **FP risk**: 3 — `verify_schema` only probes the tables/columns listed; a migration that adds a column the code reads but the probe doesn't check will boot fine and 500 on first use — the probe is a defense-in-depth, not a complete contract.
- **Over-application risk**: 3 — An agent that treats `verify_schema` as the complete migration→code contract over-applies; a new column needs its own probe entry.
- **Grounding fragility**: 3 — The `verify_schema` / `db.rs:54` / `main.rs:143` / `BATCH_PROBE_TABLES` anchors are live.
- **Sector confusion**: 4 — P-09-2 shares the `verify_schema` probe with S11 P-11-1 (the CI gate that exercises it). S09 owns the migration→code ordering contract; S11 owns the test-coverage gate.
- **Worst-case agent behavior**: An agent sees `verify_schema` pass and marks the migration→code ordering "safe", missing that a new column the code reads but the probe doesn't check will boot fine and 500 on first use.
- **Guardrail**: `verify_schema` is a defense-in-depth, not a complete contract — a new column the code reads needs its own probe entry (`BATCH_PROBE_TABLES` / `BATCH_PROBE_COLUMNS`). The probe list is enforced only against tables already known, not against new ones. A code PR that adds a column read by `verify_schema`'s probe list MUST extend the probe in the same PR.
- **Kill / keep / refine**: KEEP-WITH-GUARDRAIL

### A-28: S09 P-09-3 — V-number collision across concurrent PRs on main — renumber above main's head
- **FP risk**: 2 — "Above main's head" is a snapshot; a concurrent PR can merge between your renumber and your merge, re-colliding.
- **Over-application risk**: 3 — An agent that flags every V-number near main's head as a "collision risk" over-applies; the only safe check is at-merge-time.
- **Grounding fragility**: 3 — The `gateway-db` main head (V42) and the batch branch renumber (V43/V44 → V44) are live.
- **Sector confusion**: 4 — P-09-3 (the cross-PR coordination) and S07 P-07-2 (the globally-unique-per-DB rule) explicitly twin.
- **Worst-case agent behavior**: An agent marks the renumber "fixed" at PR-open time, missing that a concurrent PR can merge between the renumber and the merge, re-colliding; or marks the renumber "fixed" without the `flyway repair` ops follow-up (renaming a file does NOT rewrite `flyway_schema_history` on a DB that already applied the old filename).
- **Guardrail**: "Above main's head" is a snapshot; the only safe check is at-merge-time against `origin/main` HEAD, not at-PR-open-time. The `flyway repair` ops step is real: renaming a file does NOT rewrite `flyway_schema_history` on a DB that already applied the old filename — envs that ran the old V39 need manual repair, which is invisible to the graph. Name the backend: `glob path="gateway-db/migrations/V*.sql"` and `bash git -C gateway-db log --oneline main..<branch> -- migrations/` confirm the renumber; `agentmemory memory_smart_search "flyway repair V39 renumber"` recalls whether the ops step was done.
- **Kill / keep / refine**: KEEP-WITH-GUARDRAIL

### A-29: S09 P-09-5 — Cross-repo HTTP edges (gateway→app) are real but must be confirmed via cross_service trace, not graphify union
- **FP risk**: 3 — `trace_path cross_service` only works on indexed projects; gateway is NOT in the default index list. Treating "no edge found" as "no edge exists" is a false negative when the project isn't indexed.
- **Over-application risk**: 3 — An agent that runs `graphify query "gateway to app"` and sees no edge wrongly concludes the edge doesn't exist, or sees app-internal calls and mistakes them for the cross-repo edge.
- **Grounding fragility**: 4 — The gateway project is NOT in the default `codebase-memory` project list; a naive `trace_path` on `"gateway"` returns "project not found".
- **Sector confusion**: 2 — The cross-repo edge concern is uniquely S09.
- **Worst-case agent behavior**: An agent runs `trace_path cross_service` on the un-indexed `gateway` project, gets "project not found", and concludes "no cross-repo edge exists"; or runs `graphify query "gateway to app"` and mistakes app-internal calls for the cross-repo edge.
- **Guardrail**: `trace_path cross_service` only works on indexed projects; gateway is NOT in the default `codebase-memory` project list. The agent must either query the helm index for the infra `__route__` node, or `index_repository repo_path=~/<provider>/gateway mode="fast"` first. Graphify is union-only and does NOT infer cross-repo HTTP calls — do NOT trust a merged-graph query for cross-repo edges.
- **Kill / keep / refine**: KEEP-WITH-GUARDRAIL

### A-30: S09 P-09-6 — ArgoCD auto-deploys on image-yaml bump — the deploy is the merge, review gate is CODEOWNERS
- **FP risk**: 2 — The CODEOWNERS map is explicit; the FP is flagging a dev image bump as "needs review" (dev image files are unowned).
- **Over-application risk**: 3 — An agent that flags every image-yaml bump as "needs CODEOWNERS" over-applies on dev bumps.
- **Grounding fragility**: 4 — The "ocp-ny5-dev sometimes needs a hard refresh" gotcha means "merged" ≠ "deployed" on that cluster; the deploy-ordering claim can be true on paper and stale in fact.
- **Sector confusion**: 3 — P-09-6 is as much a release-process concern as a review concern; the sector self-flagged it for the dedup pass.
- **Worst-case agent behavior**: An agent flags a dev image bump as "needs CODEOWNERS review" (dev image files are unowned), or marks a dev bump "deployed" on ocp-ny5-dev without the hard-refresh gotcha.
- **Guardrail**: Dev image files (`environments/dev/{app,gateway,mcp,shell-pods,operator-hub}-images.yaml`) are unowned in CODEOWNERS — no review required, the merge IS the dev deploy. UAT/prod image files are governed by the catch-all (require CODEOWNERS: Andrea or Michael). The "ocp-ny5-dev sometimes needs a hard refresh" gotcha means "merged" ≠ "deployed" on that cluster.
- **Kill / keep / refine**: KEEP-WITH-GUARDRAIL

### A-31: S09 P-09-7 — Ops/infra prerequisites are review-blockers, not follow-ups — name the owner
- **FP risk**: 3 — Naming an owner is not the same as the owner having done the work; "Andreas handles infra" in `feedback-divergences` is marked ◻ NOT RUN, meaning the owner was named but the work was not completed at review time.
- **Over-application risk**: 3 — An agent that closes the finding on "owner assigned" is premature; the only real closure is the owner's NOT-RUN→DONE flip, which the graph cannot observe.
- **Grounding fragility**: 3 — The ADR 0004 bucket table and `prd-conformance.md` NOT-RUN markers are live.
- **Sector confusion**: 3 — P-09-7 shares the live-S3 spike with S11 P-11-6 (the test/spike lens on S06's substrate lens).
- **Worst-case agent behavior**: An agent closes the infra-prereq finding on "owner assigned", missing that the owner was named but the work was not done (NOT-RUN→DONE is the only real closure, and the graph cannot observe it).
- **Guardrail**: Naming an owner is not the same as the owner having done the work. The only real closure is the owner's NOT-RUN→DONE flip, which the graph cannot observe — an agent that closes the finding on "owner assigned" is premature. The finding stays open until the owner confirms DONE; record the gate in `agentmemory` so a future session can verify it passed before the PR merges.
- **Kill / keep / refine**: KEEP-WITH-GUARDRAIL

### A-32: S10 P-10-1 — Route every client-supplied URL through `validateAndPinUrl` — resolve before pin, pin before connect
- **FP risk**: 3 — The guard validates the *hostname's* resolved records, not the redirect chain. A public host that 302s to an internal IP is caught only if the caller re-validates after each redirect. A finding that demands `validateAndPinUrl` on the initial URL only is necessary but not sufficient if the upstream follows redirects.
- **Over-application risk**: 4 — An agent that flags a path that legitimately uses `allowPrivate` (the operator-allowlist escape for in-cluster egress) over-applies; `allowPrivate` still blocks loopback/metadata/0.0.0.0/8.
- **Grounding fragility**: 3 — The `validateAndPinUrl` / `ssrfGuard.ts:166` anchor is live.
- **Sector confusion**: 3 — P-10-1 and S11 P-11-3 share the SSRF reject-path test (S10 owns the guard, S11 owns whether the test forces a reject).
- **Worst-case agent behavior**: An agent flags a legitimate `allowPrivate` caller (in-cluster egress on the operator `RestEgressAllowlist`) as "missing the default guard", or demands `validateAndPinUrl` on the initial URL only, missing that a 302-redirect to an internal IP bypasses the initial validation.
- **Guardrail**: Confirm the caller's host is in the operator `RestEgressAllowlist` before flagging a `allowPrivate` path; `allowPrivate` still blocks loopback/metadata/0.0.0.0/8. The guard validates the *hostname's* resolved records, not the redirect chain — a public host that 302s to an internal IP is caught only if the caller re-validates after each redirect (`WebFetchTool.ts:5-8` notes websearchmcp re-checks server-side; `AutomationExecutor`'s axios call has no documented redirect re-validation — a candidate finding).
- **Kill / keep / refine**: KEEP-WITH-GUARDRAIL

### A-33: S10 P-10-2 — Redact sensitive headers from every log path by name — allowlist, not denylist
- **FP risk**: 4 — The `app.ts` allowlist is explicit (enumerates exact header names); the `apiHandler` redactor is a regex. A header like `x-auth` is caught by the regex (`x-.*-key` matches `x-auth-key` but NOT bare `x-auth`) — so the playbook's claim that `x-auth` is redacted is true only for `x-auth-key`-shaped names. A bare `x-auth` header in an inbound request log (the `app.ts` path) is NOT in the explicit list and would leak.
- **Over-application risk**: 3 — An agent that assumes "x-auth is covered" without checking the exact header name against the exact redaction surface over-applies.
- **Grounding fragility**: 3 — The `app.ts:201-213` / `apiHandler.ts:40-54` / `insertServiceAlertMiddleware.ts:58-67` anchors are live.
- **Sector confusion**: 3 — P-10-2 and S12 share the `x-auth`-vs-`x-.*-key`-regex gap (security leak vs naming precision).
- **Worst-case agent behavior**: An agent assumes "x-auth is covered" by the redaction allowlist, missing that bare `x-auth` is in neither the `app.ts` explicit list nor matched by the `apiHandler` `x-.*-key` regex, and leaks in an inbound request log.
- **Guardrail**: The reviewer must check the *exact* header name against the *exact* redaction surface the logging path uses, not assume "x-auth is covered". The `app.ts` allowlist is explicit (exact names); the `apiHandler` redactor is a regex (`x-.*-key` matches `x-auth-key` but NOT bare `x-auth`). A header caught by one surface is not necessarily caught by the other.
- **Kill / keep / refine**: KEEP-WITH-GUARDRAIL

### A-34: S10 P-10-3 — Check ownership before any discard of user-scoped rows — no IDOR
- **FP risk**: 4 — A 404 on not-owned hides existence from an outsider, but an *org-admin* legitimately sees cross-user rows within their org. A finding that demands `user_id` in every `WHERE` clause would break org-admin oversight paths.
- **Over-application risk**: 4 — An agent that conflates user-scoped (must carry `user_id`) with org-scoped (must carry `org`) deletes produces a false positive on org-admin routes.
- **Grounding fragility**: 3 — The `deleteMyMemory` / `userMemory.controller.ts:88-111` / `createSource` / `sharedUpload.ts:114-215` anchors are live.
- **Sector confusion**: 3 — P-10-3 and S05 share the discard-without-terminal-status overlap (one bug, two lenses).
- **Worst-case agent behavior**: An agent demands `user_id` in every `WHERE` clause, breaking org-admin oversight paths that legitimately see cross-user rows within their org.
- **Guardrail**: Distinguish user-scoped (must carry `user_id`) from org-scoped (must carry `org`, see P-10-4) deletes — conflating them produces a false positive on org-admin routes. A 404 on not-owned hides existence from an outsider, but an org-admin legitimately sees cross-user rows within their org.
- **Kill / keep / refine**: KEEP-WITH-GUARDRAIL

### A-35: S10 P-10-4 — Enforce tenant isolation — cross-org returns 404, no `scopedOrgId == null` sentinel hole
- **FP risk**: 3 — `WHERE org = $1` with a non-nullable `org` is safe, but a caller that derives `org` from an unauthenticated or default-null context still produces the sentinel hole at the *binding* site, not the SQL.
- **Over-application risk**: 4 — An agent that stops at the SQL string and gives a false-clean on a route that binds `org = req.body.org_id` (attacker-controlled) or `org = scopedOrgId ?? null` (sentinel fallback) over-applies the SQL-only check.
- **Grounding fragility**: 3 — The `cancel_batch` / `store.rs:608-628` / `list_batches` / `store.rs:845-875` anchors are live.
- **Sector confusion**: 3 — P-10-4 and S02 share the `FOR UPDATE` in `cancel_batch` (tenant boundary + concurrency guard).
- **Worst-case agent behavior**: An agent runs a SQL-only check on `WHERE org = $1`, gives a false-clean, and misses that the route binds `org = req.body.org_id` (attacker-controlled) or `org = scopedOrgId ?? null` (sentinel fallback) — the leak is at the binding site, not the SQL.
- **Guardrail**: The reviewer must trace `org` back to its source (auth middleware, not request body) — a SQL-only check gives a false-clean on a route that binds `org = req.body.org_id` or `org = scopedOrgId ?? null`. The leak is at the binding site, not the SQL.
- **Kill / keep / refine**: KEEP-WITH-GUARDRAIL

### A-36: S10 P-10-5 — Write a terminal status on every state-machine swap — a non-terminal row is a leak
- **FP risk**: 4 — Not every state machine has a terminal status (some are cyclical); demanding one on a cycle is a false positive.
- **Over-application risk**: 4 — S05 P-05-4 is the *same* paradigm (every terminalization writes a terminal status). The two sectors explicitly twin this. An agent applying both opens two findings on the same `reviewActions.ts:69` evidence.
- **Grounding fragility**: 3 — The `reviewActions.ts:69-74` / `billing.rs:127` anchors are live.
- **Sector confusion**: 5 — P-10-5 and P-05-4 explicitly share `reviewActions.ts:69` and `billing.rs:127` evidence. S05 owns the correctness lens; S10 owns the security-adjacent lens.
- **Worst-case agent behavior**: An agent flags a cyclical state machine for missing a terminal status, or opens two findings (S05 + S10) on the same `reviewActions.ts:69` evidence.
- **Guardrail**: Not every state machine has a terminal status (some are cyclical); demanding one on a cycle is a false positive. Merge P-10-5 and P-05-4 into one finding; keep the correctness lens in S05, the security lens in S10.
- **Kill / keep / refine**: REFINED (merge with P-05-4; scope to non-cyclical state machines)

### A-37: S10 P-10-6 — Sign webhooks with a timing-safe HMAC over the raw body — reject replay and tamper
- **FP risk**: 4 — The playbook names this convention "Standard Webhooks" and cites the spec's header names (`webhook-id` / `webhook-timestamp` / `webhook-signature: v1,<b64>` over `id.timestamp.body`). The <Provider> implementation is a **Stripe-style HMAC**, not the full Standard Webhooks spec: headers are `x-webhook-timestamp` / `x-webhook-signature` (no `webhook-id`), the signature prefix is `sha256=` (hex), not `v1,` (base64), and the signed payload is `${timestamp}.${rawBody}` — **no `id` in the signed material**. A finding that demands literal Standard Webhooks header names would be a false positive against an implementation that meets the security bar under a different wire format.
- **Over-application risk**: 3 — An agent that demands the spec's wire format over-applies; the security properties (raw-body HMAC + timestamp window + constant-time) are what matter.
- **Grounding fragility**: 3 — The `verifyWebhookSignature` / `automation.controller.ts:1373-1403` anchor is live.
- **Sector confusion**: 3 — P-10-6 and S01 P-01-3 share the webhook signing anchor (S01 owns the gate-key determinism; S10 owns the HMAC security properties).
- **Worst-case agent behavior**: An agent demands literal Standard Webhooks header names (`webhook-id` / `v1,<b64>`) against an implementation that meets the security bar under Stripe-style `x-webhook-*` headers with `sha256=` hex, wasting the author's time on a wire-format-name finding.
- **Guardrail**: Name the *property* (raw-body HMAC + timestamp window + constant-time compare), not the *spec*. The security properties that actually matter are all present and tested; a finding that demands literal Standard Webhooks header names would be a false positive. The implementation is Stripe-style HMAC under `x-webhook-*` headers with `sha256=` hex, no `id` in the signed material — that meets the security bar under a different wire format.
- **Kill / keep / refine**: KEEP-WITH-GUARDRAIL

### A-38: S11 P-11-1 — A DB-backed test that skips when its env var is unset must have CI that sets the env var
- **FP risk**: 4 — A skip-on-unset test is *correct* local-dev ergonomics (a contributor without Docker should not see 81 failures from `cargo test`); the defect is the *missing CI*, not the skip macro itself. An agent that flags `require_pool!` as a bug rather than flagging the absent workflow produces a false positive.
- **Over-application risk**: 3 — An agent that flags the skip macro as the defect over-applies; the macro is the documented, intentional pattern (`testdb.rs:1-9` module doc).
- **Grounding fragility**: 5 — The intended CI anchor `.github/workflows/test.yaml` was **NOT present on disk at verification time**; the gateway worktree under audit contains only `build.yaml` (tag-only). The fix the audit records as ADDRESSED is, on this machine, not yet landed. This is the single most important grounding fact for this paradigm.
- **Sector confusion**: 3 — P-11-1 shares MAJOR-5 evidence with S07 (the CI applies migrations V1..V44) and S09 (the cross-repo `gateway-db` checkout + PAT).
- **Worst-case agent behavior**: An agent flags `require_pool!` as a bug (the documented local-dev ergonomics pattern), or marks the CI "fixed" because `test.yaml` is cited in the audit, missing that the workflow was not present on disk at verification time.
- **Guardrail**: The defect is the *missing CI workflow* that sets `TEST_DATABASE_URL`, not the `require_pool!` skip macro (the macro is correct local-dev ergonomics). Before marking the CI "fixed", confirm `.github/workflows/test.yaml` exists on disk and sets `TEST_DATABASE_URL` — the audit's "ADDRESSED" verdict was, at verification time, not yet landed. Name the backend: `glob "**/.github/workflows/*.y*ml"` in the gateway worktree and read each trigger — if no workflow sets `TEST_DATABASE_URL` and runs `cargo test`, the paradigm fires.
- **Kill / keep / refine**: KEEP-WITH-GUARDRAIL

### A-39: S11 P-11-2 — A fix PR must ship a test that loses the race before the fix and passes after
- **FP risk**: 3 — Not every fix admits a deterministic before/after test: a fix to a deploy-ordering hazard (S09) or a one-line `Utc::now()` injection (MINOR-4, DECIDED-NOT-ACTIONED) may be verified by inspection or a live spike rather than a unit test. Demanding a reproduce-the-bug test for a fix that is itself a test-infrastructure addition is circular.
- **Over-application risk**: 4 — An agent that demands a reproduce-the-bug test for pure plumbing or deploy-ordering fixes over-applies; the paradigm fires on *behavioral* fixes (race, idempotence, state-machine, contract), not on pure plumbing.
- **Grounding fragility**: 3 — The `finalize_success_second_call_is_noop_and_never_double_bills` / `billing.rs:594` anchor is live.
- **Sector confusion**: 2 — The reproduce-the-bug test concern is uniquely S11.
- **Worst-case agent behavior**: An agent demands a reproduce-the-bug test for a deploy-ordering fix (S09) or a one-line clock injection (MINOR-4, DECIDED-NOT-ACTIONED), which may be verified by inspection or a live spike; or demands a test for a fix that is itself a test-infrastructure addition (circular).
- **Guardrail**: The paradigm fires on *behavioral* fixes (race, idempotence, state-machine, contract), not on pure plumbing, deploy-ordering hazards, or test-infrastructure additions. A fix to a deploy-ordering hazard or a one-line `Utc::now()` injection may be verified by inspection or a live spike rather than a unit test. A deferral with a recorded rationale (MINOR-4) is DECIDED-NOT-ACTIONED, not a finding.
- **Kill / keep / refine**: KEEP-WITH-GUARDRAIL

### A-40: S11 P-11-3 — A security reject path must be exercised with a real reject, not stubbed to always resolve
- **FP risk**: 3 — Forcing a mock to reject tests the *call site's reaction* to a reject, not the *guard's* reject logic itself — the real `validateAndPinUrl` resolve/pin/deny decision is only truly exercised by a test that calls the real guard with a hostile URL. A mock-reject test guards against "guard silently dropped from the call site," not against "guard logic inverted."
- **Over-application risk**: 3 — An agent that treats a mock-reject test as full SSRF coverage over-claims; the live guard's own unit tests (or a live hostile-URL test) are a separate, necessary coverage.
- **Grounding fragility**: 3 — The `trainingWebhook.job.test.ts:408` anchor (in the `training-webhooks` worktree) is live.
- **Sector confusion**: 4 — P-11-3 and S10 P-10-1 share the SSRF reject-path test (S10 owns the guard, S11 owns whether the test forces a reject). The dedup pass may fold the test-exercise half into S10.
- **Worst-case agent behavior**: An agent treats a mock-reject test as full SSRF coverage, over-claiming; the real guard's resolve/pin/deny logic is only truly exercised by a test that calls the real guard with a hostile URL (10.0.0.5, 169.254.169.254, `[::1]`).
- **Guardrail**: A mock-reject test guards against "guard silently dropped from the call site", not against "guard logic inverted". The real guard's own unit tests (or a live hostile-URL test) are a separate, necessary coverage. Distinguish "call site tested against a double" from "real guard's own paths tested".
- **Kill / keep / refine**: KEEP-WITH-GUARDRAIL

### A-41: S11 P-11-4 — A new external client must have unit tests for its real signing, range, and error-mapping paths
- **FP risk**: 3 — SigV4 signing and range headers are partly determined by the SDK (`aws-sdk-s3`); if `RealS3::put` is a thin wrapper over the SDK, unit-testing the wrapper's signing may be testing the SDK, which is low-value.
- **Over-application risk**: 4 — An agent that demands "test the SigV4 signature bytes" when the code never touches them over-asks; the bar is "test what this code owns" (error-mapping, range-header construction).
- **Grounding fragility**: 3 — The `s3_client.rs` (246 lines, 0 `#[test]`) / `mock_s3.rs` anchors are live.
- **Sector confusion**: 3 — P-11-4 arguably overlaps S12 "233 lines no tests" reading, but the lens differs (S12 = maintainability smell; S11 = untested behavioral paths).
- **Worst-case agent behavior**: An agent demands "test the SigV4 signature bytes" when `RealS3::put` is a thin wrapper over `aws-sdk-s3` and never touches the signature, over-asking; the high-value, ownable tests are the *error-mapping* (status → `S3Error` variant, incl. the 403 classification Andrea flagged) and any *range-header construction* this code performs.
- **Guardrail**: The bar is "test what this code owns". If `RealS3::put` is a thin wrapper over the SDK, unit-testing the wrapper's signing is testing the SDK (low-value). The high-value, ownable tests are the *error-mapping* (status → `S3Error` variant, incl. the 403 classification Andrea flagged) and any *range-header construction* this code performs. Do not demand "test the SigV4 signature bytes" when the code never touches them.
- **Kill / keep / refine**: KEEP-WITH-GUARDRAIL

### A-42: S11 P-11-5 — Stateful failure modes must be covered by a failure-matrix test set, not happy-path-only
- **FP risk**: 3 — A "failure matrix" can balloon: every state × every event × every ordering is combinatorial. Andrea's bar is the *four named hazards* specific to this system (restart/budget/cancel/expiry), not an exhaustive cross-product.
- **Over-application risk**: 4 — An agent that demands a test for every state-transition pair over-applies; the bar is the hazards Andrea listed, expanded only when a new stateful path introduces a new hazard class.
- **Grounding fragility**: 3 — The four E-tests (`e7`/`e8`/`e9`/`e10`) in `billing.rs` / `store.rs` are live but DB-gated (use `require_pool!`), so they only run when `TEST_DATABASE_URL` is set — tying this paradigm to P-11-1.
- **Sector confusion**: 3 — P-11-5 shares the `e7`/`e8`/`e9`/`e10` E-tests with S05 (S05 owns the invariant; S11 owns whether a test pins it and whether CI runs it).
- **Worst-case agent behavior**: An agent demands a test for every state-transition pair (combinatorial cross-product), ballooning the matrix; the bar is the four named hazards (restart/budget/cancel/expiry), expanded only when a new stateful path introduces a new hazard class.
- **Guardrail**: The bar is the *four named hazards* specific to this system (restart/budget/cancel/expiry), not an exhaustive state × event × ordering cross-product. Expand only when a new stateful path introduces a new hazard class. If the hazard's test is DB-gated but no CI sets `TEST_DATABASE_URL`, chain the finding to P-11-1.
- **Kill / keep / refine**: KEEP-WITH-GUARDRAIL

### A-43: S11 P-11-6 — A live spike against a real external dependency is a merge prerequisite, not a follow-up
- **FP risk**: 3 — A live spike is genuinely blocked on infra the reviewer cannot supply (dev S3 bucket, creds, GPU priority endpoint); it is a legitimate *gate*, not something a code reviewer can merge.
- **Over-application risk**: 3 — An agent that treats "spike not run" as a code defect over-claims; the defect is the *deferral framing* (calling a prerequisite a follow-up), not the absence of a spike in the diff.
- **Grounding fragility**: 3 — The conformance matrix NOT-RUN markers and `RealS3` (`s3_client.rs:150-221`) anchors are live.
- **Sector confusion**: 4 — P-11-6 shares the live-S3 spike with S06 (S06 owns the substrate decision; S11 owns whether the real client + live endpoint were exercised) and S09 P-09-7 (the ops-prereq owner-naming lens).
- **Worst-case agent behavior**: An agent treats "spike not run" as a code defect to fix in the diff, or sees `test.yaml` (when it lands) and marks the spike closed, missing that the spike is a *process gate* on a live endpoint the reviewer cannot supply — closing it requires running the spike and recording the result, not editing code.
- **Guardrail**: The spike is a *process gate* on a live endpoint the reviewer cannot supply, not a code defect. The correct finding is "this PR must not merge until the spike is run and recorded", which is a process gate, not a code change. Confusing the gate with the code fix produces a wrong finding. Record the gate in `agentmemory` so a future session can verify it passed before the PR merges.
- **Kill / keep / refine**: KEEP-WITH-GUARDRAIL

### A-44: S12 P-12-1 — Rename a constant whose name lies about what it caps
- **FP risk**: 3 — The constant is module-private and the doc-comment at `worker.rs:37-40` already explains the cap keying; a reviewer could legitimately argue the comment is sufficient and the rename is cosmetic diff noise on a PR already carrying 26 review items.
- **Over-application risk**: 3 — The paradigm is strongest when the misleading name has *no* redeeming doc-comment and weakest when, as here, the comment partially compensates.
- **Grounding fragility**: 3 — The `MAX_ATTEMPTS` / `worker.rs:41` anchor is live.
- **Sector confusion**: 4 — P-12-1 shares NIT-1 evidence with S01 (the `MAX_ATTEMPTS`/`det_failures` naming is the detail angle; the correctness angle — the cap must key on deterministic failures — is S01/02's).
- **Worst-case agent behavior**: An agent flags the rename as a blocker on a PR already carrying 26 review items, missing that the doc-comment partially compensates and the rename is cosmetic diff noise; or opens two findings (S01 correctness + S12 naming) on the same `MAX_ATTEMPTS` constant.
- **Guardrail**: The paradigm is strongest when the misleading name has *no* redeeming doc-comment and weakest when, as here, the comment partially compensates. "Partially compensates" is still not "renamed", and a future reader who greps `MAX_ATTEMPTS` expecting attempt semantics will still be misled — but weigh the diff noise against the PR's existing load. Merge the S01 correctness and S12 naming findings where they share the `MAX_ATTEMPTS`/`det_failures` evidence.
- **Kill / keep / refine**: KEEP-WITH-GUARDRAIL

### A-45: S12 P-12-2 — Add a partial index for every hot-path predicate a re-cut introduces
- **FP risk**: 3 — The exhaustion sweep is a *backstop* ("the worker normally terminalizes a capped row inline"); with small per-org fleets the heap scan over queued rows may be cheaper than an extra index's write amplification on every `bump_transient_failure`.
- **Over-application risk**: 3 — The paradigm is right *in principle* (index your hot-path predicates) but this specific instance is the marginal case where the index could be premature — which is exactly why the decision should be *recorded*, not silently dropped.
- **Grounding fragility**: 4 — The index lives in `gateway-db` (DDL, not code symbols); same fragility as A-19.
- **Sector confusion**: 5 — P-12-2 is the explicit twin of P-07-1. S12 owns the code-smell lens; S07 owns the migration/index lens.
- **Worst-case agent behavior**: An agent demands the partial index on a backstop sweep where the heap scan may be cheaper (premature optimization), or opens two findings (S07 + S12) on the same missing index; or greps `~/<provider>/gateway/` for `CREATE INDEX det_failures` and files a false positive by looking in the wrong repo.
- **Guardrail**: The paradigm is right *in principle* but this specific instance is the marginal case where the index could be premature — the decision should be *recorded*, not silently dropped. Target `gateway-db/migrations/` (or its worktree), not the gateway checkout. Merge P-12-2 and P-07-1 into one finding; keep the migration lens in S07, the code-smell lens in S12.
- **Kill / keep / refine**: REFINED (merge with P-07-1; require the decision be recorded, not silently dropped)

### A-46: S12 P-12-5 — Inject the clock into every route that stamps lifecycle or money timestamps
- **FP risk**: 4 — The deferral is genuinely defensible: the *money* decision (expiry → `finalize_failure` / sweep) is in the reaper, which IS clock-injected and tested; the route's `expires_at` is a create-time write of `now + 24h` that is never re-evaluated against the clock, so a `ManualClock` at the route would only test the arithmetic, not a race.
- **Over-application risk**: 5 — The route layer is rife with *other* `Utc::now()` calls that are NOT smells — `usage.rs` lookback defaults (read-only query bounds), `admin.rs:825` key-expiry comparison (read-only), `models.rs:128` model-allow timestamp. The paradigm must be scoped to **writes that stamp lifecycle/money timestamps**, not "any `Utc::now()` in a route" — over-applying it produces a pile of false positives on read-only defaults.
- **Grounding fragility**: 3 — The `batches.rs:238` / `batches.rs:518` anchors are live.
- **Sector confusion**: 3 — P-12-5 shares MINOR-4 evidence with S11 (the testing angle — a `ManualClock`-driven lifecycle integration test can't exist until the clock reaches the route).
- **Worst-case agent behavior**: An agent purges every `Utc::now()` from the route layer, including read-only query bounds (`usage.rs` lookback defaults), read-only comparisons (`admin.rs:825` key-expiry), and model-allow timestamps (`models.rs:128`), producing a pile of false positives that bury the two real lifecycle-stamping smells (create's `expires_at`, cancel's `cancelling_at`/`cancelled_at`).
- **Guardrail**: The paradigm is scoped to **writes that stamp lifecycle/money timestamps** (create's `expires_at`, cancel's `cancelling_at`/`cancelled_at`), not "any `Utc::now()` in a route". Read-only query bounds, read-only comparisons, and model-allow timestamps are NOT smells. The deferral is genuinely defensible (the money decision is in the reaper, which IS clock-injected); a deferral with a recorded rationale (MINOR-4) is DECIDED-NOT-ACTIONED, not a finding.
- **Kill / keep / refine**: KEEP-WITH-GUARDRAIL

### A-47: S12 P-12-6 — Don't flag a latency stopwatch as a missing-clock smell
- **FP risk**: 3 — The paradigm is a *negative* one (don't flag X); the only way it can be wrong is if a future refactor makes the `Instant::now()` value *also* feed a wall-clock decision.
- **Over-application risk**: 2 — The paradigm is itself a restraint on P-12-5; over-application would be flagging a real wall-clock `Instant::now()` as a stopwatch.
- **Grounding fragility**: 4 — The paradigm must be re-verified (re-trace the data flow) on every refactor of `preflight::route`'s signature, not assumed stable forever.
- **Sector confusion**: 3 — P-12-6 is the explicit restraint on P-12-5; the two are paired.
- **Worst-case agent behavior**: An agent applying P-12-5 broadly flags `Instant::now()` at `worker.rs:398` as "mixed clock usage", and the "fix" (replace `Instant::now()` with `clock.now()`) *breaks* the latency stopwatch (wall-clock isn't monotonic) and introduces a real bug while "fixing" a non-issue.
- **Guardrail**: `Instant::now()` used as a *latency stopwatch* (consumed only via `.elapsed()`, a duration) is NOT a clock-injection smell; the injectable `Clock` exists for *wall-clock* decisions (expiry, cancel, lease boundaries). Trace the data flow: if the `Instant` is consumed only via `.elapsed()`, it's a stopwatch, not a clock decision. The paradigm must be re-verified (re-trace the data flow via `codebase-memory trace_path mode=data_flow`) on every refactor of `preflight::route`'s signature.
- **Kill / keep / refine**: KEEP-WITH-GUARDRAIL

### A-48: S12 P-12-7 — Don't call a multi-file behavior change a "one-line fix"
- **FP risk**: 3 — The paradigm can be over-applied into "never call anything one line", which is pedantic — a truly one-line fix (e.g. `MAX_ATTEMPTS` → `MAX_DET_FAILURES` in P-12-1, a module-private rename with one call site) *is* one line and should be called that.
- **Over-application risk**: 4 — An agent that runs the `find_referencing_symbols` blast-radius query on every fix and inflates every one-line rename into a "cross-cutting change" generates noise. The discipline is to size *after* the query returns, not to assume the query will always return >1.
- **Grounding fragility**: 2 — The paradigm is a review-discipline note, not a code anchor.
- **Sector confusion**: 3 — P-12-7 shares MAJOR-7 "one-line" evidence with S08 (the recoverability contract of the 403 mapping) and S11 (the test coverage of the three new match arms).
- **Worst-case agent behavior**: An agent runs the blast-radius query on every fix and inflates every one-line rename (e.g. `MAX_ATTEMPTS` → `MAX_DET_FAILURES`, one in-file call site) into a "multi-site fix", generating noise on genuinely trivial ones.
- **Guardrail**: The discipline is "verify the blast radius *before* sizing", not "always inflate size estimates". Run `find_referencing_symbols` on the symbol the fix touches (a new enum variant, a changed function signature, a renamed column) and itemize the sites; *then* size the claim. If the itemization shows N>1 sites, the claim is "N sites across M files", not "one line"; if N=1, the claim IS "one line". Size *after* the query returns, not before.
- **Kill / keep / refine**: KEEP-WITH-GUARDRAIL

## Robust paradigms (score <= 2 on all axes)

These pass through to the final playbook unchanged with high confidence:

- S01 P-01-1: Require a finalize idempotence guard pinned to the claim generation — *(scores 2/2/3/4; confusion only, merge with P-05-3/P-01-7 per A-13)*
- S01 P-01-2: Make every transient-failure counter re-arm-aware, not just the terminal writes — (2/2/2/2)
- S01 P-01-6: Make re-claim a status flip, not a re-run — and prove it with a crash→reclaim→bill-once test — (2/2/2/2)
- S01 P-01-7: Symmetrize the re-arm gate across every finalize sibling — *(scores 2/2/3/4; merge with P-05-3/P-01-1 per A-13)*
- S02 P-02-3: Name the advisory-lock class — session vs xact — and match it to the failure mode — (2/2/2/2)
- S02 P-02-6: Atomic multi-org claims are a cross-pod race, not a docs gap — fold them into the singleton finding — (2/2/2/2)
- S03 P-03-1: Thread a stop flag into every new worker or async loop — (2/2/2/2)
- S03 P-03-2: Await the worker handle with a bounded timeout — never drop it — (2/2/2/2)
- S03 P-03-3: No double-run on SIGTERM — drain in-flight, don't abort mid-PUT — (2/2/2/2)
- S03 P-03-4: Forward the abort signal to the upstream call — (2/2/2/3)
- S03 P-03-5: Prefer stdlib `AtomicBool` over a new cancellation abstraction — (2/2/2/2)
- S03 P-03-6: Order the drain — metering before worker, worker before brute abort of reaper/sweep — (2/2/2/2)
- S04 P-04-3: Partition the claim queue by org so no org starves another to expiry — *(merge with P-02-5 per A-6)*
- S04 P-04-5: Resolve the org before the concurrency semaphore — no unauthenticated queue pre-fill — (2/2/2/2)
- S04 P-04-6: A queue-depth gate must 429 immediately when full — (2/2/2/2)
- S06 P-06-2: `delete_idempotent` must treat `NotFound` as success and `Forbidden` as terminal-skip — (2/2/2/2)
- S06 P-06-3: Content lives in S3, Postgres holds metadata + object keys only — (2/2/2/2)
- S06 P-06-4: One immutable input object per upload, read by per-line ranged GET — (2/2/2/2)
- S06 P-06-5: Retention is terminal-anchored at 29 days with explicit DeleteObject — (2/2/2/2)
- S06 P-06-6: Expired batches must produce a synthetic error file — *(merge with P-08-2/P-05-6 per A-23)*
- S07 P-07-3: Drop-and-re-add CHECK constraints with the full expanded enum list on any enum change — (2/2/2/2)
- S07 P-07-5: When renumbering or squashing, document the superseded pair and preserve the end state — (2/2/2/2)
- S08 P-08-3: Split the `canceled`/`cancelled` dialect deliberately — (2/2/2/2)
- S08 P-08-6: The JSONL byte-cursor parser must round-trip byte-identical, including CRLF — and must strip a leading UTF-8 BOM — (2/2/2/2)
- S08 P-08-7: A ranged GET must accept 200 *and* 206 — the Range guard is stronger than a literal 206 check — (2/2/2/2)
- S09 P-09-4: helm catalog model additions need compatible gateway route + app SDK — (2/2/2/2)
- S12 P-12-3: Stamp-once — guard idempotent timestamp writes against re-stamp — (2/2/2/2)
- S12 P-12-4: Strip the UTF-8 BOM at every byte-cursor parser boundary — (2/2/2/2)

(Note: paradigms marked "merge with ..." above are robust on their own axes
but appear in the high-risk table only because of sector-confusion twins;
their *content* is sound and they pass through after the merge.)

## Cross-cutting guardrails

These apply to MANY paradigms, not one. They become global rules in the
final playbook.

1. **Before citing a canonical sibling, confirm it still exists at the cited
   path.** The playbook has known drift: `trainingJob.controller.ts:540`
   (moved to `automation.controller.ts:1329-1403`),
   `trainingWebhook.job.ts:51` (file gone), `executeTool.ts:470` (slid to
   `:545-559`). The canonical re-ground tool is `semble_search` (embedding +
   BM25, indexes on first query) followed by `Serena find_symbol` to confirm
   the symbol exists. Citing a playbook line number verbatim without
   re-grounding produces wrong file:line evidence. This guardrail applies to
   at least A-1, A-2, A-3, A-7, A-13.

2. **Distinguish row-disjoint locks (`FOR UPDATE SKIP LOCKED`) from
   count-disjoint locks (`pg_advisory_xact_lock`); do not demand one when the
   other suffices.** The classic MVCC race is a *count-based* cap guarded
   only by a CTE read; a row-disjoint claim guarded by SKIP LOCKED is a hard
   cap on double-claim of the same row and does NOT need an advisory lock.
   The right pattern depends on whether the cap gates *creation* (rare,
   serialize with xact lock) or *claiming* (frequent, disjoint with SKIP
   LOCKED). This guardrail applies to A-5, A-10 (and merges P-02-2 + P-04-4).
   Confirm via `codegraph explore -p ~/<provider>/gateway "FOR UPDATE SKIP
   LOCKED claim_requests"` (row-disjoint) and `Serena find_symbol on
   create_batch_capped` (xact-lock-inside-tx).

3. **A paradigm anchored in a worktree branch (`feat-batch-api-*`) must note
   the worktree; the main-checkout CodeGraph index will not see it.**
   `~/<provider>/gateway/.codegraph` is the *main*-branch index, which has
   no batch module; the batch code lives in
   `~/<provider>/worktrees/batch-api/feat-batch-api-gateway/`. An agent
   grepping the main checkout for `CREATE INDEX det_failures` concludes "no
   index" by looking in the wrong repo. The gateway-db migration DDL is not
   a code symbol — Serena/codebase-memory/graphify do not index it; use
   `grep`/`glob` on `gateway-db/migrations/` (or its worktree). This
   guardrail applies to A-19, A-45 and to every paradigm whose anchor is in
   the `feat-batch-api-*` worktrees.

4. **A deferral with a recorded rationale (MINOR-4) is DECIDED-NOT-ACTIONED,
   not a finding; do not re-raise it as a defect.** A silent NIT drop
   (NIT-1/2/3) IS a finding — re-open it with a recorded decision request.
   The distinguishing test: did the author record a rationale? If yes
   (MINOR-4: "Deferred — AppState has no clock field; plumbing costs ~10
   lines across 6 files; the money path is in the reaper, already
   clock-injected"), it's DECIDED-NOT-ACTIONED; if no (the three NITs), the
   author didn't engage and the finding stays open. This guardrail applies
   to A-39, A-46 and to every paradigm that touches a deferral.

5. **Twin paradigms across sectors must be merged into one finding with both
   lenses preserved; do not open two findings on the same evidence.** The
   playbook has at least seven explicit twins:
   - P-01-1 / P-01-7 / P-05-3 (the `AND attempt = $N` guard, `billing.rs:127`)
   - P-01-4 / P-02-4 (`expectedVersion` on retry, `executeTool.ts:545-586`)
   - P-02-1 / P-04-7 (per-process QoS counter, `interactive_in_flight`)
   - P-02-2 / P-04-4 (MVCC count-race, `create_batch_capped`)
   - P-02-5 / P-04-3 (global FIFO starvation, `claim_requests`)
   - P-05-4 / P-10-5 (terminal status on state-machine swap,
     `reviewActions.ts:69`)
   - P-05-6 / P-08-2 / P-06-6 (`request_counts` fold + expired error file,
     MAJOR-4)
   - P-07-1 / P-12-2 (partial index on `det_failures`, NIT-2)
   The dedup pass owns the merge; the adversarial pass's contribution is
   naming the lenses to preserve (e.g. S05 = no-double-bill consequence,
   S01 = gate-key-shape mechanism; S10 = security-adjacent leak, S05 =
   correctness leak).

6. **Treat "owner named" as NOT-RUN, not DONE, for infra prerequisites; and
   treat "spike not run" as a process gate, not a code defect.** Naming an
   owner (P-09-7) is not the same as the owner having done the work; the
   only real closure is the owner's NOT-RUN→DONE flip, which the graph
   cannot observe. A live spike (P-11-6) is a process gate on a live
   endpoint the reviewer cannot supply; the correct finding is "this PR
   must not merge until the spike is run and recorded", not a code change.
   Record both in `agentmemory` so a future session can verify closure
   before the PR merges. This guardrail applies to A-31, A-43.

## Net recommendation

Of 77 paradigms: **~52 KEEP-WITH-GUARDRAIL**, **~12 REFINED** (the eight
explicit twin-merges: P-01-4↔P-02-4, P-02-1↔P-04-7, P-02-2↔P-04-4,
P-02-5↔P-04-3, P-05-4↔P-10-5, P-07-1↔P-12-2, P-05-6↔P-08-2↔P-06-6, plus
P-01-1↔P-01-7↔P-05-3; and the scope-narrowings: P-01-3 cross-window-only,
P-01-5 outbound-only, P-04-7 enforced-invariant-only, P-08-2 flag-the-stretch),
**0 KILL** (every paradigm has a sound core; the worst cases are
over-application, not wrongness, and a guardrail fixes each). The three most
important guardrails the final playbook must state up front:

1. **Re-ground before citing** (guardrail 1) — the playbook has three known
   stale anchors; an agent that cites them verbatim produces wrong evidence
   on its first run. `semble_search` then `Serena find_symbol` is the
   canonical re-ground sequence.

2. **Row-disjoint vs count-disjoint locks** (guardrail 2) — the single
   highest-FP paradigm in the set is "demand an advisory lock where SKIP
   LOCKED already provides row disjointness"; this guardrail prevents the
   most common wrong finding an automated agent would produce.

3. **Worktree-aware anchoring** (guardrail 3) — every paradigm whose anchor
   is in `feat-batch-api-*` will produce a false negative ("no index", "no
   edge") if the agent greps the main checkout or queries the main-branch
   CodeGraph index; the worktree is where the code is, and `gateway-db` DDL
   is grep-only, not symbol-indexed.

# Synthesis — Dedup Pass

## Method

I read `_CONTEXT.md` and all 12 `sector-*.md` extracts in full, then detected overlaps
four ways: (1) every worker's `## Cross-sector links` section was treated as a primary
input — those name the overlaps the workers themselves saw; (2) I compared paradigm
*statements* semantically across sectors, not just titles, to catch restatements of the
same check under different wording (e.g. "global FIFO starves" vs "partition the claim
queue by org"); (3) I cross-referenced the `Source evidence` and `<Provider> infra
anchor` fields — paradigms citing the *same* gateway.md item (BLOCKER-2, MAJOR-4,
MAJOR-7, Rebuttal (f), NIT-2) AND the *same* file:line anchor are merge candidates even
when no worker flagged them; (4) I diffed anchors across sectors to surface *drift*
(two sectors naming the same symbol at different file:line, or a sector's anchor
disagreeing with the shared `_CONTEXT.md`/playbook example). For each merge group I name
the codebase-intelligence backend that validates the decision. I did NOT modify any
sector file; this is the only file I wrote.

The 12 sectors produced 73 paradigms total (S01:7, S02:6, S03:6, S04:7, S05:7,
S06:6, S07:5, S08:7, S09:7, S10:6, S11:6, S12:7 — note S12 lists 7 in its header but
ships 7 bodies). The dedup lens finds **15 merge groups**: 3 true MERGEs (fold a
duplicate into its owning sector), 4 KEEP-ASPECTS (split overlapping core from
non-overlapping parts), and 8 KEEP-SEPARATEs (genuinely distinct lenses on shared
evidence — these stay, cross-referenced). One unflagged near-duplicate (M-2) and one
unflagged cross-sector overlap (M-14) were detected beyond what the workers flagged.

## Merge groups (15 entries)

### M-1: Finalize idempotence guard `AND attempt = $N` — the canonical multi-lens case

- **Members**: S01 P-01-1, S01 P-01-7, S02 P-02-4, S03 P-03-3, S05 P-05-3, S10 P-10-5
- **Shared evidence**: `gateway.md` MINOR-1 + "Notes on the review" BLOCKER-2
  no-double-billing rebuttal; `playbook` paradigm #6 (re-arm gate); the
  `finalize_success_second_call_is_noop_and_never_double_bills` test
- **Shared anchor**: `src/batch/billing.rs:127` (`AND attempt = $9`) and
  `billing.rs:263` (`AND attempt = $7`), the symmetric pair; both sectors cite the same
  two UPDATE statements and the `AlreadyFinal` no-op branch
- **Lens difference**: S01 = the *gate-key shape* (deterministic claim-generation
  counter, re-arm semantics); S02 = the *optimistic-concurrency mechanism* (does the
  version guard travel to the retry handler?); S03 = the *drain-safety consequence*
  (a missed SIGTERM drain is made harmless by the guard); S05 = the *no-double-bill
  invariant* (the guard is what makes a re-run no-op, the txn is what makes the first
  finalize atomic); S10 = the *security boundary* (a non-terminal row a user can still
  act on is an IDOR-adjacent leak). Five genuinely distinct lenses on one guard.
- **Disposition**: KEEP-SEPARATE — all five sectors explicitly asked for this in their
  cross-links; the guard is load-bearing for all five concerns and no lens subsumes
  another. The orchestrator should keep all five with explicit back-references to
  `billing.rs:127` as the shared anchor.
- **Owning sector**: S01 owns the gate-key *shape*; S05 owns the *billing consequence*
  (the two core concerns). S02/S03/S10 cite the guard for their lens.
- **Backend**: `semble_find_related` on `finalize_success` confirms all five sectors
  point at the same symbol cluster; Serena `find_referencing_symbols` on
  `finalize_success` confirms the guard is one site, not five.

### M-2: `ROW_NUMBER() OVER (PARTITION BY b.org)` claim-fairness query — UNFLAGGED near-duplicate

- **Members**: S02 P-02-5, S04 P-04-3
- **Shared evidence**: `gateway.md` MAJOR-1 (global FIFO starves org B to expiry) +
  the "Notes on the review" correction ("a single window-function query, not a
  cursor/round-robin state machine")
- **Shared anchor**: `src/batch/store.rs:448-451` (`ROW_NUMBER() OVER (PARTITION BY
  b.org ORDER BY b.created_at, br2.line_no) AS rn`) and `store.rs:472` (`ORDER BY
  r.rn`) — both sectors cite the *identical* CTE lines and the *identical* `ponytail:`
  comment at `:470-471`
- **Lens difference**: S02 frames it as "global FIFO starves; partition the claim by
  the fairness key" (a concurrency/queueing lens); S04 frames it as "partition the
  claim queue by org so no org starves another to expiry" (a rate-limiting/fairness
  lens). The statements are paraphrases; the fix, the anchor, and the evidence are
  byte-identical. S02's cross-link names S04 only for the per-process counter and the
  `create_batch_capped` xact lock — it does NOT flag this query as shared, so this is
  an overlap the workers missed.
- **Disposition**: MERGE — true duplicate. Fold into S04 (fairness is S04's named core
  concern per `_CONTEXT.md` row 04 "Rate limiting & per-org fairness"); S02 cites it
  in its cross-link rather than restating the paradigm.
- **Owning sector**: 04
- **Backend**: `codebase-memory trace_path mode=calls` from `worker::tick` →
  `claim_requests` confirms there is exactly one fairness query (both sectors cite
  the same node); `semble_search "ORDER BY created_at line_no no org partition"`
  confirms no second claim-shaped query exists to justify two paradigms.

### M-3: A count-based CTE is not a hard cap under MVCC — use a per-xact advisory lock

- **Members**: S02 P-02-2, S04 P-04-4
- **Shared evidence**: `gateway.md` BLOCKER-3 (Mateo's rebuttal, verified true) +
  the "Notes on the review" rebuttal naming `create_batch_capped`'s
  `pg_advisory_xact_lock` as the true hard cap
- **Shared anchor**: `src/batch/store.rs:211` (`pg_advisory_xact_lock` inside
  `create_batch_capped`) vs `src/batch/worker.rs:693` (`pg_try_advisory_lock`,
  session-level). Both sectors cite both lock sites and the `ponytail:` upgrade-path
  comment at `worker.rs:684-685`.
- **Lens difference**: S02 owns the *MVCC disjointness distinction* (row-disjoint via
  SKIP LOCKED vs count-disjoint via advisory xact lock — the broader concurrency
  mechanism); S04 owns the narrower *fairness-cap-bounds-anything* framing (does the
  cap the fairness tier relies on actually hold under concurrency). S04's own
  cross-link says: "the dedup pass may merge the MVCC counter-point into Sector 02
  and keep the fairness framing here."
- **Disposition**: KEEP-ASPECTS — the MVCC/advisory-lock *mechanism* belongs in S02
  (it is S02's core concurrency lens); S04 keeps only the *fairness-cap-reliability*
  framing and cites S02 for the mechanism. Extract the non-overlapping fairness
  framing into S04, merge the MVCC mechanics into S02.
- **Owning sector**: 02 (mechanism); 04 (fairness framing)
- **Backend**: Serena `find_symbol` on `create_batch_capped` confirms the xact lock
  is inside the `pool.begin()…tx.commit()` span (the mechanism S02 owns); the worker
  session lock at `worker.rs:693` is a distinct symbol S04 references for the
  singleton invariant.

### M-4: `request_counts` fold + expired-batch error file (MAJOR-4)

- **Members**: S05 P-05-6, S06 P-06-6, S08 P-08-2
- **Shared evidence**: `gateway.md` MAJOR-4 (expired batch produces no error file;
  `total != completed + failed` breaks the OpenAI SDK contract) +
  `feedback-divergences` "`request_counts.failed` must not fold canceled/expired"
- **Shared anchor**: `src/batch/store.rs:805` (`SET status = 'expired',
  error_code = 'batch_expired'`), `src/routes/files.rs:288`
  (`SyntheticKind::Error => &["errored", "expired"]`), `src/routes/batches.rs:95`
  (the `failed > 0 || expired > 0` gate). All three sectors cite the same three sites.
- **Lens difference**: S05 = the *lifecycle fold rule* (errored→failed only;
  canceled/expired count toward total); S06 = the *residency footprint* (every
  terminal batch has a deletable result/error footprint so the sweep has something to
  enumerate); S08 = the *wire reconciliation* (the SDK's `total == completed + failed`
  arithmetic invariant + error-file presence). Three genuinely distinct lenses on
  one fix.
- **Disposition**: KEEP-SEPARATE — all three workers explicitly asked for this; the
  same `batch_expired` fix serves three different review questions and no lens
  subsumes another.
- **Owning sector**: 05 (lifecycle fold), 06 (residency), 08 (wire). Each owns its
  lens; cross-reference the shared `store.rs:805`/`files.rs:288`/`batches.rs:95` trio.
- **Backend**: `codebase-memory trace_path mode=data_flow` from `expire_batches`
  (`store.rs:791`) → `SyntheticKind::Error` (`files.rs:286`) confirms the single fix
  path all three cite; `semble_search "request_counts failed expired canceled fold
  error_file_id"` confirms no sibling re-derives the fold outside the canonical sites.

### M-5: Terminal-status-always-written — no non-terminal leak

- **Members**: S05 P-05-4, S05 P-05-7 (409 while in-flight), S10 P-10-5
- **Shared evidence**: `playbook` convention "State-machine terminal status" +
  `gateway.md` MINOR-3 (synthetic files served for non-terminal batches) + BLOCKER-2
  notes
- **Shared anchor**: `src/batch/types.rs:48-54` (`BatchStatus::is_terminal`),
  `src/routes/files.rs:216-220` (the 409 gate), and the app-side
  `backend/src/controllers/<provider>Chat.libs/userMemory/dream/reviewActions.ts:69-74`
  (the "terminal + swap in one txn" sibling S10 cites)
- **Lens difference**: S05 = the *state-machine correctness* invariant (no function
  that advances the state machine may return leaving a row non-terminal when its
  intent was terminal); S10 = the *security boundary* (a non-terminal row a user can
  still act on — approve/reject/cancel — after the state has effectively moved is an
  IDOR-adjacent surface). S05 P-05-7 is the 409-while-in-flight *gate contract* (a
  sub-aspect of the same invariant, intra-sector).
- **Disposition**: KEEP-SEPARATE — S05 owns correctness, S10 owns the security-leak
  angle. S10's own cross-link says "the dedup pass should merge the shared anchor and
  keep both lenses." The 409 gate (S05 P-05-7) stays in S05.
- **Owning sector**: 05 (state-machine invariant); 10 (security lens) cites it
- **Backend**: `semble_find_related` on `BatchStatus::is_terminal` confirms S05 and
  S10 cite the same predicate; Serena `find_referencing_symbols` on `is_terminal`
  confirms the 409 gate routes through the single shared predicate (no hand-rolled
  `matches!` drift).

### M-6: JSONL byte-cursor parser must strip a leading UTF-8 BOM

- **Members**: S08 P-08-6, S12 P-12-4
- **Shared evidence**: `gateway.md` Rebuttal (f) ("JSONL byte-cursor rewrite holds
  (CRLF, no trailing newline, multibyte round-trip) with one gap: a leading UTF-8 BOM
  fails line 1 … worth a targeted fix")
- **Shared anchor**: `src/batch/jsonl.rs:49-85` (`parse_input`) — both sectors cite
  the identical function and the identical gap (no `strip_prefix('\u{FEFF}')` before
  the `cursor = 0` loop). Both propose the same one-line fix.
- **Lens difference**: S08 frames it as *wire/parser-conformance* (the byte-cursor
  parser is the ADR 0004 byte-identity ranged-GET contract; a BOM in line 1 breaks
  the byte-identical read); S12 frames it as a *byte-cursor parser edge* (a
  code-smell/detail lens). The fix, the anchor, and the evidence are identical; the
  S08 framing is strictly more load-bearing (the parser IS the residency contract).
- **Disposition**: MERGE — true duplicate. Fold into S08 (the parser is the wire/
  residency contract; the BOM is a conformance hole in byte-identity, which is S08's
  core lens). S12 cites it in its cross-link rather than restating. S08's own
  cross-link says "the two are the same finding through different lenses; the dedup
  pass should merge or cross-reference."
- **Owning sector**: 08
- **Backend**: Serena `find_symbol` on `parse_input` confirms S08 and S12 cite the
  same single parser entry point; `grep -rn "BOM|0xEF|\\\\ufeff|strip_prefix"
  src/batch/jsonl.rs` re-confirms the gap is observable as one missing symbol.

### M-7: Missing partial index on `det_failures` for the hot-path exhaustion query

- **Members**: S07 P-07-1, S12 P-12-2
- **Shared evidence**: `gateway.md` NIT-2 (UNADDRESSED — "no partial index on
  `det_failures`; cheap to add while re-cutting")
- **Shared anchor**: `src/batch/store.rs:538-552` (`select_exhausted_queued`, the
  every-tick query with `WHERE br.status = 'queued' AND br.det_failures >= $1`) +
  the `V44__batch_api.sql` migration (defines `idx_batch_request_claim` /
  `idx_batch_request_lease` but zero indexes on `det_failures`). Both sectors cite
  the same query and the same migration gap.
- **Lens difference**: S07 = the *migration/index* lens (the fix is a `CREATE INDEX`
  in the gateway-db migration; `CONCURRENTLY` judgment, re-cut-above-head); S12 = the
  *hot-path predicate / cheap-while-re-cutting* code-smell lens. Both workers
  explicitly said: "keep the index in Sector 07, the rename in Sector 12, and
  cross-link" (S07 cross-link verbatim). The fix lives in one migration file.
- **Disposition**: MERGE — the *index* paradigm belongs in S07 (the fix is DDL in a
  migration, which is S07's domain); S12 retains the *rename* (P-12-1, a different
  paradigm) and cites the index. S12's own cross-link concedes "the dedup pass may
  merge it into Sector 07 if that framing is stronger."
- **Owning sector**: 07
- **Backend**: `codebase-memory query_graph` Cypher
  `MATCH (f:Function {name:'select_exhausted_queued'})-[:CALLS|:REFERENCES]->(n)
  RETURN n` confirms S07 and S12 cite the same query node with no
  `CREATE INDEX … det_failures` neighbor; `grep -rn "det_failures"
  ~/<provider>/gateway-db/migrations/` is the byte-for-byte confirmation.

### M-8: Webhook HMAC signing vs deterministic gate key — split the signing site two ways

- **Members**: S01 P-01-3, S10 P-10-6
- **Shared evidence**: `playbook` convention "Standard Webhooks signing"
  (`webhook-id` / `webhook-timestamp` / `webhook-signature: v1,<b64>` over
  `id.timestamp.body`) + the live `verifyWebhookSignature` implementation
- **Shared anchor**: `backend/src/controllers/automation.controller.ts:1373-1403`
  (`verifyWebhookSignature`) — both sectors cite the same function. S01 reads the
  HMAC-over-`timestamp.body` as the *deterministic fingerprint* (gate key); S10 reads
  the raw-body + `timingSafeEqual` + tolerance window as the *signing security*.
- **Lens difference**: S01 = *gate-key determinism* (the key must be a deterministic
  function of stable inputs — HMAC, hash, UID — never non-deterministic ciphertext);
  S10 = *signing security* (raw-body HMAC, timestamp replay window, constant-time
  compare, reject-path test coverage). The two read different properties of the same
  function. S01's cross-link says "the dedup pass may fold P-01-3's signing detail
  into Sector 08 and keep only the deterministic-not-ciphertext half here."
- **Disposition**: KEEP-ASPECTS — S01 keeps the *deterministic-not-ciphertext* half
  (gate-key shape, its core concern); S10 keeps the *raw-body + timing-safe + replay-
  window* half (signing security, its core concern). Extract the non-overlapping
  parts; both cite `automation.controller.ts:1373` for their respective aspect. Do
  NOT fold into S08 — neither S01 nor S10's lens is a wire-shape concern.
- **Owning sector**: 01 (gate-key determinism), 10 (signing security)
- **Backend**: Serena `find_symbol` on `verifyWebhookSignature` confirms both
  sectors cite the same function; `find_referencing_symbols` confirms every webhook
  trigger routes through it (no parallel unverified path) — the property both
  sectors depend on.

### M-9: `expectedVersion` optimistic-concurrency guard must travel to the retry handler

- **Members**: S01 P-01-4, S02 P-02-4
- **Shared evidence**: `playbook` paradigm #7/#8 (retries must carry the
  optimistic-concurrency guard) + the `executeTool.ts` retry site
- **Shared anchor**: `backend/src/controllers/<provider>Chat.libs/agenticLoop/
  executeTool.ts:545-587` (the retry re-asserts `expectedVersion: 0`),
  `backend/src/tools/DraftTextTool.ts:83,104` (the sibling),
  `backend/src/services/insertNextArtifactVersion.ts:86-90` (the primitive). Both
  cite the same three sites. Both also flag the playbook's stale `executeTool.ts:470`
  anchor (now `:545-559`).
- **Lens difference**: S01 owns the *what* (is the re-arm gate key deterministic and
  does it travel to the retry); S02 owns the *how* (does the optimistic-concurrency
  version guard survive the conflict handler's re-invocation). S02's cross-link:
  "Sector 01 owns the what; this sector owns the how. Same evidence, different lens."
- **Disposition**: KEEP-SEPARATE — workers explicitly split this; the two lenses
  produce different findings on the same PR (a webhook re-delivery that re-fires
  correctly but drops `expectedVersion` on retry is one PR with two findings).
- **Owning sector**: 01 (the what), 02 (the how) — cross-reference
- **Backend**: Serena `find_referencing_symbols` on `insertNextArtifactVersion`
  confirms both sectors cite the same retry site; `semble_search "expectedVersion 0
  retry conflict first create"` confirms no sibling insert swallows the conflict.

### M-10: Per-process counter is not a fleet-wide QoS / fairness signal

- **Members**: S02 P-02-1, S04 P-04-7
- **Shared evidence**: `gateway.md` BLOCKER-3 (`AppState.interactive_in_flight` is
  per-process; two pods each read 'quiet' and oversubscribe) + Rebuttal (a)
  (co-location doesn't make QoS correct; singleton-ness does, unenforced) +
  `feedback-divergences` "Deployment topology" / "Summary matrix"
- **Shared anchor**: `src/batch/slots.rs:6-14` (`allowed_batch_slots`),
  `AppState.interactive_in_flight` (`main.rs:86-87`, the `DashMap`),
  `src/batch/worker.rs:693` (`pg_try_advisory_lock(42)`, the singleton guard),
  `worker.rs:684-685` (the `ponytail:` upgrade-path comment). Both cite the same
  signal path and the same singleton lock.
- **Lens difference**: S02 = *counter fleet-consistency* (what keeps a per-process
  counter correct across replicas; the unenforced `replicas: 1` invariant); S04 =
  *QoS-tier fairness semantics* (does the two-tier cap actually enforce fairness
  under the deployment topology). S02's cross-link: "the per-process-counter finding
  likely belongs here, the fairness-tier semantics there."
- **Disposition**: KEEP-ASPECTS — the *counter-correctness* mechanism belongs in S02
  (concurrency); the *QoS-tier-fairness* framing belongs in S04 (rate-limiting). Both
  cite `slots.rs:6` and `worker.rs:693`; extract the non-overlapping fairness framing
  into S04, merge the counter-correctness core into S02.
- **Owning sector**: 02 (counter consistency), 04 (fairness-tier semantics)
- **Backend**: `semble_search "interactive_in_flight per-process DashMap singleton
  replicas 1"` confirms both sectors cite the same DashMap field;
  `codebase-memory trace_path mode=data_flow` from `InFlightGuard::enter` to
  `allowed_batch_slots` confirms the counter is the only input to the cap (no
  cross-process source) — the property both sectors depend on.

### M-11: Live-S3 spike as merge prerequisite, not follow-up

- **Members**: S09 P-09-7, S11 P-11-6
- **Shared evidence**: `gateway.md` MAJOR-7 + Rebuttal (g) ("live S3 spike is a
  merge prerequisite, not a follow-up"; Mateo's "infra validation gate" reframing
  contradicts Andrea's bar) + `feedback-divergences` "Process / ops" (spike marked
  ◻ NOT RUN)
- **Shared anchor**: the conformance matrix NOT-RUN marker
  (`docs/prd-conformance.md`), the ADR 0004 bucket table, and the absence of any
  live-S3 test in `feat-batch-api-gateway` (`RealS3` exercised only via `MockS3`).
  Both sectors cite the same process gate.
- **Lens difference**: S09 = *multi-repo/owner* (name the owner of each infra
  prerequisite; mark NOT-RUN until the owner confirms); S11 = *test-coverage/spike*
  (a new external dependency load-bearing for correctness must be exercised against
  the live service before merge). Different framings of the same process gate.
- **Disposition**: KEEP-SEPARATE — S09 owns the *owner-naming/coordination* framing;
  S11 owns the *test/spike* framing. Both cite the same NOT-RUN marker; the
  orchestrator should cross-reference so a single PR finding cites both lenses.
- **Owning sector**: 09 (coordination/owner), 11 (test/spike gate)
- **Backend**: `agentmemory memory_recall` on "S3 spike merge prerequisite live dev"
  confirms both sectors cite the same process decision and lets a future session
  verify whether the spike was since run (the only way to close the gate, since the
  graph cannot observe a live-endpoint run).

### M-12: S3 `403 → Forbidden` classification + the "one-line fix" honesty

- **Members**: S06 P-06-2, S11 P-11-4, S12 P-12-7
- **Shared evidence**: `gateway.md` MAJOR-7 (403/AccessDenied classified transient;
  the fix is `S3Error::Forbidden` + sweep logs-and-skips) + Rebuttal (g) + the
  "Notes on the review" "one-line 403 fix is ~15 lines across 3 files" finding
- **Shared anchor**: `src/batch/s3_client.rs:34` (`Forbidden(String)` variant),
  `s3_client.rs:143`/`:193`/`:214` (the three match arms), `src/batch/sweep.rs:20-22`
  (the sweep caller). All three sectors cite the same variant and its blast radius.
- **Lens difference**: S06 = *residency correctness* (`delete_idempotent` must treat
  `NotFound` as `Ok` and `Forbidden` as terminal-skip, not retry); S11 = *test
  coverage* (`s3_client.rs` has no unit tests; the 403→Forbidden mapping is exercised
  only by `MockS3` doubles, so a regression ships green); S12 = *review-honesty*
  (calling a 15-line, 3-file, N-match-arm fix "one line" under-estimates the diff and
  leaves match arms un-fixed). Three distinct lenses on one MAJOR-7 fix. (S08 P-08-4
  is the *image-service* 403 classifier at `generateCosmosImage.ts:439-460`, a
  different anchor — not part of this group.)
- **Disposition**: KEEP-SEPARATE — three genuinely distinct lenses; each produces a
  different finding on a PR that touches the S3 error path.
- **Owning sector**: 06 (residency), 11 (test coverage), 12 (review honesty) —
  cross-reference the shared `s3_client.rs:34` variant
- **Backend**: Serena `find_referencing_symbols` on `S3Error::Forbidden` confirms
  all three sectors cite the same variant's blast radius (the three match arms +
  the sweep caller); `codebase-memory trace_path mode=calls` from `s3_client.rs::put`
  /`get_range`/`delete` confirms no match arm was missed (the property S12's
  fix-size check depends on).

### M-13: V-number re-cut above Flyway head / collision across concurrent PRs

- **Members**: S07 P-07-2, S07 P-07-5, S09 P-09-3
- **Shared evidence**: `feedback-divergences` "Schema and migrations" (V39 unusable
  → renumbered to V43 + V44; Andreas wanted single V44 re-cut, local split batch
  tables vs S3 columns) + `playbook` Migration PR path step 1
- **Shared anchor**: `~/<provider>/gateway-db/flyway.conf` (`outOfOrder=false`,
  `validateOnMigrate=true`), the `V44__batch_api.sql` supersession header, and the
  missing V39/V43 gap in the migration dir. All three cite the same re-cut event.
- **Lens difference**: S07 P-07-2 = the *rule* (V-numbers globally unique per DB;
  re-cut above main's head); S07 P-07-5 = the *squash shape* (document the superseded
  pair, preserve end-state in one step); S09 P-09-3 = the *coordination* (two
  concurrent PRs both claiming V44; migration-before-app ordering). S07 owns the
  schema-internal correctness; S09 owns the cross-repo ordering.
- **Disposition**: KEEP-SEPARATE — workers explicitly split this (S07 cross-link:
  "Sector 07 owns the rule; Sector 09 owns the coordination"). The re-cut rule and
  the cross-PR collision are different review questions on the same evidence.
- **Owning sector**: 07 (rule + squash shape), 09 (cross-PR coordination)
- **Backend**: `glob ~/<provider>/gateway-db/migrations/V*.sql` + `bash`
  `git -C gateway-db log --oneline main..<branch> -- migrations/` confirms all three
  cite the same re-cut event (the V39/V43 gap + the V44 supersession header);
  `read ~/<provider>/gateway-db/flyway.conf` confirms `outOfOrder=false` (the
  precondition all three depend on).

### M-14: Abort-signal forwarding — UNFLAGGED cross-sector overlap

- **Members**: S01 P-01-5 (jittered, abort-signal-carrying retry backoff), S03 P-03-4
  (forward the abort signal to the upstream call)
- **Shared evidence**: `playbook` convention "Retry backoff" ("jittered,
  abort-signal-carrying; deterministic formula is a bug") + Webhook path step 2 +
  Image-generation path step 5
- **Shared anchor**: S01 P-01-5's anchor is *stale/ungrounded* (the playbook's
  `src/jobs/trainingWebhook.job.ts:51` does not exist; S01 could not ground a live
  jittered-retry implementation). S03 P-03-4's anchor is live:
  `app/backend/src/controllers/<provider>Chat.libs/agenticLoop/generateCosmosImage.ts:215`
  (`if ctx.abortSignal?.aborted …`) and `:225` (`chat(..., ctx.abortSignal, true)`).
  Different anchors, but the same "abort-signal-carrying" convention.
- **Lens difference**: S01 = the *retry loop's* abort-signal (jitter + signal in the
  backoff scaffolding around the upstream call); S03 = *forwarding the signal into
  the upstream I/O call itself* (so a cancelled request stops the upstream inference,
  not just the retry loop around it). S03's cross-link names S08 (recoverability
  classification of `ABORTED`), but does NOT name S01 — so the overlap with S01
  P-01-5's abort-signal half is unflagged.
- **Disposition**: KEEP-ASPECTS — S01 owns *jitter + retry-loop abort-signal*; S03
  owns *forwarding the signal to the leaf I/O*. Extract the non-overlapping parts
  (S01's jitter half is unique; S03's leaf-forwarding half is unique); the
  abort-signal-carrying convention is shared and should be cross-referenced. S01's
  stale anchor (`trainingWebhook.job.ts:51`) should be re-grounded via
  `semble_search` or dropped in favor of S03's live `generateCosmosImage.ts:215`
  anchor (see Drift findings).
- **Owning sector**: 01 (jitter + retry-loop signal), 03 (leaf-forwarding)
- **Backend**: `semble_search "abortSignal forwarded chat upstream inference"`
  confirms S03's live anchor; `semble_search "jitter backoff retry abort signal
  Math.random setTimeout"` across the full app tree is the only way to locate a live
  jittered-retry implementation for S01 (S01 concedes its playbook anchor is gone).

### M-15: `validateAndPinUrl` SSRF guard vs reject-path test

- **Members**: S10 P-10-1, S11 P-11-3
- **Shared evidence**: `playbook` paradigm #4 + Webhook path step 5 ("Does the test
  exercise the SSRF reject path, or does it stub `validateAndPinUrl` to always
  resolve?")
- **Shared anchor**: `backend/src/libs/ssrfGuard.ts:166` (`validateAndPinUrl`) +
  the `trainingWebhook.job.test.ts:408` `#14` reject test. S10 owns the guard; S11
  owns whether a test forces the guard to reject. (Note: the shared `_CONTEXT.md`
  and playbook cite a *stale* `src/services/clientEgress.ts:103` anchor — see Drift
  findings; S10 grounded the canonical `ssrfGuard.ts:166`.)
- **Lens difference**: S10 = *does the call site route through the shared guard*
  (security boundary); S11 = *does a test force the guard to reject and assert the
  downstream effect* (test coverage). Different review questions on the same guard.
- **Disposition**: KEEP-SEPARATE — S10 owns the guard, S11 owns the test. S11's
  cross-link says "the orchestrator may fold the test-exercise half into Sector 10
  and keep the mock-vs-real-client half here"; I recommend keeping both — the
  guard-presence finding (S10) and the reject-path-test finding (S11) are
  independently actionable.
- **Owning sector**: 10 (guard), 11 (test)
- **Backend**: Serena `find_referencing_symbols` on `validateAndPinUrl` confirms S10
  (guard) and S11 (test) cite the same symbol; `semble_search "validateAndPinUrl
  mock reject SSRF internal network no egress"` locates the `#14` reject test S11
  depends on.

## Orphans

Paradigms with NO overlap with any other sector (no shared evidence, anchor, or
cross-link flagged) — these pass through to the final playbook unchanged:

- `S03 P-03-1`: Thread a stop flag into every new worker or async loop
- `S03 P-03-2`: Await the worker handle with a bounded timeout — never drop it
- `S03 P-03-5`: Prefer stdlib `AtomicBool` over a new cancellation abstraction
- `S03 P-03-6`: Order the drain — metering before worker, worker before brute abort
- `S04 P-04-1`: Enforce per-key RPM on every new public route, after auth
- `S04 P-04-2`: Bound concurrent uploads with a fail-fast permit, not a body limit
- `S04 P-04-5`: Resolve the org before the concurrency semaphore — no unauthenticated queue pre-fill
- `S04 P-04-6`: A queue-depth gate must 429 immediately when full, not park waiters unbounded
- `S05 P-05-1`: Book cost and terminal-state flip in one transaction
- `S05 P-05-2`: Apply the half-rate discount at exactly one site
- `S05 P-05-5`: Enforce budget at admission (fresh re-check), not at finalize-time grace
- `S06 P-06-1`: Sweep must delete every generation up to the claim high-water mark
- `S06 P-06-3`: Content lives in S3, Postgres holds metadata + object keys only
- `S06 P-06-4`: One immutable input object per upload, read by per-line ranged GET
- `S06 P-06-5`: Retention is terminal-anchored at 29 days with explicit DeleteObject
- `S07 P-07-3`: Drop-and-re-add CHECK constraints with the full expanded enum list on any enum change
- `S07 P-07-4`: Use CREATE INDEX CONCURRENTLY for indexes on existing large tables; plain on fresh
- `S08 P-08-1`: Emit OpenAI-exact wire shapes the official SDK parses unchanged
- `S08 P-08-3`: Split the `canceled`/`cancelled` dialect deliberately — batch double-L, request single-L
- `S08 P-08-4`: Classify 4xx as non-recoverable and 5xx per-semantic, never blanket "retry everything ≥400"
- `S08 P-08-5`: Pin the endpoint vocabulary now; widen deliberately, never by accident
- `S08 P-08-7`: A ranged GET must accept 200 *and* 206 — the Range guard is stronger than a literal 206 check
- `S09 P-09-1`: Land companion PRs as a set — none ready until all open and approved
- `S09 P-09-2`: Migration-before-app — the DB PR lands first, the code PR behind it
- `S09 P-09-4`: helm catalog model additions need compatible gateway route + app SDK
- `S09 P-09-5`: Cross-repo HTTP edges (gateway→app) must be confirmed via cross_service trace, not graphify union
- `S09 P-09-6`: ArgoCD auto-deploys on image-yaml bump — the deploy is the merge, review gate is CODEOWNERS
- `S10 P-10-2`: Redact sensitive headers from every log path by name — allowlist, not denylist
- `S10 P-10-4`: Enforce tenant isolation — cross-org returns 404, no `scopedOrgId == null` sentinel hole
- `S11 P-11-1`: A DB-backed test that skips when its env var is unset must have CI that sets the env var
- `S11 P-11-2`: A fix PR must ship a test that loses the race before the fix and passes after
- `S11 P-11-5`: Stateful failure modes (restart, budget exhaustion, cancel race, expiry) must be covered by a failure-matrix test set
- `S12 P-12-1`: Rename a constant whose name lies about what it caps
- `S12 P-12-3`: Stamp-once — guard idempotent timestamp writes against re-stamp
- `S12 P-12-5`: Inject the clock into every route that stamps lifecycle or money timestamps
- `S12 P-12-6`: Don't flag a latency stopwatch as a missing-clock smell

(36 orphans of 73 paradigms. The remaining 37 participate in the 15 merge groups
above. Note: a few "orphans" share an anchor with another sector through a different
lens — e.g. S10 P-10-4 shares `cancel_batch`'s `FOR UPDATE` with S02 — but no worker
flagged a paradigm-level overlap and the review concern is distinct, so they are
listed here as orphans of the *dedup* pass while remaining cross-reference candidates
for the final playbook.)

## Drift findings

Infra anchors cited by 2+ sectors (or by a sector + the shared `_CONTEXT.md`/
playbook) with DIFFERENT file:line. Canonical = verified path; the stale one feeds
the validation pass.

### D-1: `validateAndPinUrl` — canonical `ssrfGuard.ts:166`, stale `clientEgress.ts:103`
- **Canonical (verified)**: `app/backend/src/libs/ssrfGuard.ts:166`
  (`export async function validateAndPinUrl`) — confirmed live via `grep`.
- **Stale**: `src/services/clientEgress.ts:103` — cited as the `validateAndPinUrl`
  anchor in `_CONTEXT.md:130` (the shared example all workers were told to ground
  against) and in the playbook. `app/backend/src/services/clientEgress.ts` does NOT
  exist at that path (read returned "Path not found").
- **Who has it right**: S10 P-10-1 grounded the canonical `ssrfGuard.ts:166`.
- **Who has it stale**: `_CONTEXT.md:130` and the playbook. S11 P-11-3 cites
  `src/services/clientEgress.ts:103` as the "egress boundary" in its anchor text —
  that line is stale; the egress boundary is the `validateAndPinUrl` callers, not a
  `clientEgress.ts` file.
- **Backend to verify**: Serena `find_symbol` on `validateAndPinUrl` resolves to
  `ssrfGuard.ts:166`; `glob app/backend/src/services/clientEgress.ts` returns
  nothing.

### D-2: Webhook signing site — canonical `automation.controller.ts:1373-1403`, stale `trainingJob.controller.ts:540`
- **Canonical (verified)**: `backend/src/controllers/automation.controller.ts:1373-1403`
  (`verifyWebhookSignature`) — cited by both S01 P-01-3 and S10 P-10-6.
- **Stale**: `src/controllers/trainingJob.controller.ts:540` — cited in the playbook
  (Webhook path step 3) and the playbook's "Deterministic idempotency fingerprint"
  convention. S01 P-01-3 explicitly flagged this: "the playbook's
  `trainingJob.controller.ts:540` anchor is **stale** — the webhook signing path now
  lives in `automation.controller.ts:1329-1403`."
- **Who has it right**: S01 and S10.
- **Who has it stale**: the playbook.
- **Backend to verify**: `semble_search "webhook signature HMAC timestamp body
  deterministic"` returns `automation.controller.ts`, not `trainingJob.controller.ts`.

### D-3: `expectedVersion` retry site — canonical `executeTool.ts:545-587`, stale `executeTool.ts:470`
- **Canonical (verified)**: `backend/src/controllers/<provider>Chat.libs/agenticLoop/
  executeTool.ts:545-587` (the retry re-asserts `expectedVersion: 0`) — cited by
  both S01 P-01-4 and S02 P-02-4.
- **Stale**: `executeTool.ts:470` — cited in the playbook (Agentic-tool path step 4)
  and the playbook's "Optimistic concurrency" convention. S01 P-01-4 explicitly
  flagged this: "the playbook's `executeTool.ts:470` anchor is **stale by ~75
  lines** — the expectedVersion forwarding now lives at `:545-559` (file grew)."
- **Who has it right**: S01 and S02.
- **Who has it stale**: the playbook.
- **Backend to verify**: Serena `find_symbol` on `insertNextArtifactVersion` and
  `find_referencing_symbols` resolves the retry to `:545-587`, not `:470`.

### D-4: Jittered-retry anchor — playbook's `trainingWebhook.job.ts:51` does NOT exist
- **Canonical**: none found. S01 P-01-5 concedes: "the playbook's
  `src/jobs/trainingWebhook.job.ts:51` anchor is **stale** — that file does not exist
  in the current app tree." No sector grounded a live jittered-retry implementation;
  the gateway batch path deliberately spaces by lease (reaper), not per-retry jitter.
- **Stale**: `src/jobs/trainingWebhook.job.ts:51` — cited in the playbook (Webhook
  path step 2) and the "Retry backoff" convention.
- **Who has it right**: S01 (honestly flagged the anchor as ungroundable).
- **Who has it stale**: the playbook.
- **Backend to verify**: `semble_search "jitter backoff retry abort signal
  Math.random setTimeout"` across `~/<provider>/app` is the only way to locate a
  live implementation; if no hit, the convention is currently unenforced in app
  code (the gateway relies on the reaper's lease-spacing, per S01 P-01-5 caveat and
  S03 P-03-4).

### D-5: `e7` test file:line — `reaper.rs:521` vs conformance-matrix-only citation
- **Canonical (verified)**: `feat-batch-api-gateway/src/batch/reaper.rs:521`
  (`async fn e7_worker_restart_reclaims_lease_and_bills_exactly_once`) — confirmed
  live via `grep`. Cited by S01 P-01-6 as `reaper.rs:521-592`.
- **Weaker citation**: S11 P-11-2 and S11 P-11-5 cite the e7 test by *conformance-
  matrix row* (`prd-conformance.md:134`) and by name, not by `reaper.rs:521` file:line.
  Not a hard contradiction, but S11's grounding of the e7 invariant is weaker (matrix
  row) than S01's (file:line). S05 P-05-3 cites `billing.rs:594` — that is the
  *different* `finalize_success_second_call_is_noop` test, correctly (not e7).
- **Who has it right**: S01 (file:line for e7); S05 (correctly distinguishes the
  second-call test at `billing.rs:594` from e7 at `reaper.rs:521`).
- **Who has the weaker anchor**: S11 (matrix-row citation for e7).
- **Backend to verify**: `grep` for `e7_worker_restart_reclaims_lease` in the
  gateway worktree resolves to `reaper.rs:521`; `semble_search` confirms the same.

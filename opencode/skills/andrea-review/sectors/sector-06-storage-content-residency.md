# Sector 06 — Storage & content residency

## Scope

This sector owns the **where-does-content-live** question: which substrate
holds bytes (Postgres vs object storage), which layer encrypts them (bucket-side
SSE-S3 vs application AES), how long they may survive, and whether every
generation of every object is actually reclaimed. It asks of every batch/content
PR: *is content out of the row-store, is encryption delegated to the storage
layer, is retention terminal-anchored and bounded, and does the sweep cover the
orphan generations a reclaim race leaves behind?* It deliberately does NOT own
the OpenAI wire-shape of the synthesized error file (that is Sector 08
Wire/contract — MAJOR-4's `total != completed+failed` contract lives there);
the migration V-number / CHECK-constraint mechanics of the `error_code`
column (Sector 07 Schema); or the live-S3-spike-as-merge-gate process decision
(Sector 09 Multi-repo / Sector 11 Testing own the spike gating). It touches the
same `sweep.rs` / `store.rs` files as Sector 03 (shutdown) and Sector 05
(billing), but only through the *residency* lens — does a SIGTERM-dropped
worker or a double-finalize leave an object stranded past retention.

## Paradigms (6 entries)

### P-06-1: Sweep must delete every generation up to the claim high-water mark, not only the committed one

**Paradigm statement** — A lease-reclaim race can leave a superseded result
object in S3: generation 1's PUT succeeded but its finalize lost, then
generation 2 wrote and committed with `result_attempt = 2`. Deleting only the
committed generation strands generation 1 past retention — a residency
violation. The sweep must walk `1..=attempt` for every line, where `attempt`
is the claim high-water mark (bumped on claim, never reset), so no object
survives under the batch's `results/` prefix. Selecting only rows where
`result_attempt IS NOT NULL` skips the orphans the loop exists to reclaim.

**Source evidence** — `gateway.md BLOCKER-1`: Andrea flags
`src/batch/sweep.rs:43-44` selecting `WHERE result_attempt IS NOT NULL`,
"skipping the orphaned objects the `1..=attempt` loop exists to delete."
Mateo's fix: `attempt > 0` (claim high-water mark) + `delete_idempotent`
treats `NotFound` as `Ok`. Verdict: ADDRESSED.

**<Provider> infra anchor** —
`src/batch/sweep.rs:47-48` — `SELECT line_no, attempt FROM batch_request \
WHERE batch_id = $1 AND attempt > 0`;
`src/batch/sweep.rs:60-61` — `for (line_no, attempt) in result_rows {
for gen in 1..=attempt {`;
`src/batch/sweep.rs:54-59` — the comment that documents the orphan-reclaim
rationale ("A reclaim race can leave an orphaned result object under any
earlier generation whose finalize lost. S3 has no LIST, so delete every
generation 1..=attempt");
`src/batch/reaper.rs:1241` — test `sweep_tick_deletes_superseded_result_generations`
pins the invariant.

**Codebase-intelligence backend** —
> `semble_search "sweep orphan reclaim superseded result generation attempt"` against `~/<provider>/worktrees/batch-api/feat-batch-api-gateway` → returns `src/batch/sweep.rs:17-32` (`delete_idempotent`) and `src/batch/reaper.rs:1241` (the covering test) in one pass.
> Confirm the high-water-mark semantics: `codegraph explore -p <gateway-worktree> "trace claim_requests attempt bump reclaim"` → `store.rs` claim path bumps `attempt` on every claim; `finalize_*` stamps `result_attempt` only on commit. The gap between them is exactly the orphan window.

**Fix-suggestion policy** —
> SUGGEST ONLY: if a PR narrows the sweep selector to `result_attempt IS NOT NULL` (or any predicate that excludes rows that claimed but never finalized), open a finding citing BLOCKER-1 and the canonical `attempt > 0` + `1..=attempt` reclaim loop. Do NOT commit a patch. The PR author owns the fix.

**Adversarial caveat** — On a batch with `attempt = 1000` (a pathological
reclaim storm), the `1..=attempt` loop issues up to 1000 idempotent deletes
per line per sweep tick; the absence of S3 LIST forces this brute-force
scan. An agent flagging the loop as "O(n²) overkill" would be wrong — S3
has no LIST in the gatekeeper posture, and under-deleting is a residency
violation while over-deleting is a cheap idempotent 404.

### P-06-2: `delete_idempotent` must treat `NotFound` as success and `Forbidden` as terminal-skip, not retry

**Paradigm statement** — A retention sweep that retries `404` will hot-loop
a missing object every tick; one that retries `403` will hot-loop a
permanently-forbidden credential forever, pinning the sweep on a config
defect. The delete wrapper must fold `NotFound` into `Ok` (the object is
already gone — the sweep's goal) and fold `Forbidden` into a logged `Ok`
(the item is unswept but the sweep advances; a credential defect is an
ops alert, not a retry target). Only `Unavailable` (transient) propagates
to retry the item next tick.

**Source evidence** — `gateway.md BLOCKER-1`: Mateo's fix makes
`delete_idempotent` treat `NotFound` as `Ok`. `gateway.md MAJOR-7`:
"403/AccessDenied classified transient (sweep DeleteObject retries it)"
is the defect Andrea caught; fix is `S3Error::Forbidden`, "sweep logs and
skips."

**<Provider> infra anchor** —
`src/batch/sweep.rs:17-26` —
`match s3.delete(key).await { Ok(()) | Err(S3Error::NotFound) => Ok(()), \
Err(S3Error::Forbidden(e)) => { tracing::error!(...); Ok(()) }, \
Err(e) => Err(e.to_string()) }`;
`src/batch/s3_client.rs:26-39` — the `S3Error` enum with `NotFound`
(deterministic), `Forbidden(String)` (deterministic, "the worker
terminalizes the row; the sweep skips the delete"), `Unavailable(String)`
(transient).

**Codebase-intelligence backend** —
> `semble_search "delete_idempotent NotFound Forbidden sweep skip retry"` against the gateway worktree → returns `src/batch/sweep.rs:17-26` and the `S3Error` enum at `s3_client.rs:26-39` in one query.
> Cross-check the three `map_status` sites all classify 403 as `Forbidden` (not `Unavailable`): `codegraph explore -p <gateway-worktree> "S3 client put get_range delete map_status 403 forbidden"` → confirms `s3_client.rs:143` (put), `:193` (get_range), `:214` (delete).

**Fix-suggestion policy** —
> SUGGEST ONLY: if a PR's delete path maps `403` to a transient/retryable error (or omits the `NotFound => Ok` fold), open a finding citing MAJOR-7 and the `delete_idempotent` canonical wrapper. Do NOT commit a patch.

**Adversarial caveat** — Folding `Forbidden` to a logged skip means a
mis-scoped credential silently leaks the affected objects past 29 days
(the sweep advances but the object stays). The counter is that the
alternative — retrying forever — pins the entire sweep on one bad object;
the chosen posture favors sweep progress and relies on the `tracing::error!`
to alert ops. An agent should flag a *silent* skip (no log) as a regression,
not the logged-skip design itself.

### P-06-3: Content lives in S3, Postgres holds metadata + object keys only — no base64 TEXT, no app crypto, no courier hop

**Paradigm statement** — Batch content (the uploaded input JSONL and the
per-line result/error bodies) resides in object storage with bucket-side
encryption; the gateway-DB row holds the object key and metadata, never the
bytes. Application-layer AES-256-GCM over base64 TEXT columns, per-org client
databases reached through an HTTP courier, and any TS↔Rust crypto interop
gate are all *rejected* substrates — they re-introduce the row-store blob
problem Andrea targeted directly ("base64 TEXT columns in the same DB that
auths and meters"). The correct posture is one immutable input object +
per-line result objects keyed by generation, SSE-S3 at rest, no app
involvement.

**Source evidence** — `feedback-divergences` ADR evolution table:
ADR 0002 (gateway Postgres `TEXT`/base64 + gateway AES-256-GCM, 503 launch
gate) → ADR 0003 (per-org client DBs via app `/internal/batch-content/*`
courier, app platform key) → ADR 0004 (FlashBlade S3, SSE-S3 bucket-side,
app batch content subsystem *deleted*). "Content moves to FlashBlade S3;
Postgres holds metadata + object keys only." "SSE-S3 at rest; drop app-side
crypto / TS↔Rust interop." `gateway.md` Rebuttal (f): "SSE-S3 claimed but
unverified (see MAJOR-7)."

**<Provider> infra anchor** —
`src/batch/s3_client.rs:1-9` — module doc: "Batch CONTENT … resides in
FlashBlade S3 (SSE-S3, per-env bucket) … The gateway holds the S3 object
keys in Postgres and no content key (encryption is bucket-side SSE-S3)."
`src/batch/s3_client.rs:132-134` — `bucket.add_header("x-amz-server-side-encryption", "AES256")` ("SSE-S3 at rest. Belt-and-suspenders alongside bucket default encryption").
`src/batch/s3_client.rs:67-76` — `input_key` / `result_key` shape
(`inputs/{org}/{file_id}`, `results/{org}/{batch_id}/{line_no}/{attempt}`).
No `*_enc` content columns, no `content_client.rs`, no `x-admin-secret`
courier in the batch module (ADR 0003 app-side deleted per `feedback-divergences`).

**Codebase-intelligence backend** —
> `semble_search "batch content FlashBlade S3 SSE-S3 object key Postgres metadata no app crypto courier"` against the gateway worktree → returns the `s3_client.rs` module doc and key helpers; absence of `content_client` / `*_enc` columns is the negative-space confirmation.
> For the ADR decision chain: `memory_recall "ADR 0004 batch content FlashBlade S3 supersede per-org client DB"` → returns the prior-session decision record; if absent, the `feedback-divergences` ADR table is the source of record.

**Fix-suggestion policy** —
> SUGGEST ONLY: if a PR re-introduces a content column on a gateway-DB table, an app-side encrypt/decrypt call in the batch path, or an HTTP courier hop to fetch body bytes, open a finding citing the ADR 0002→0003→0004 evolution and the `s3_client.rs:1-9` residency invariant. Do NOT commit a patch. (Note: the live-S3 *spike* to verify SSE-S3 PUT/ranged-GET/path-style/SigV4 is a Sector 09/11 process gate, not a residency finding — flag it there, not here.)

**Adversarial caveat** — SSE-S3 means the bucket operator (not the app)
holds the encryption keys; if the threat model requires the app to hold keys
(cross-tenant operator isolation, legal-hold guarantees), SSE-S3 alone is
insufficient and SSE-KMS with app-managed keys would be needed. Andrea's
review accepted SSE-S3 explicitly, so the threat model here trusts the
storage boundary — an agent should not relitigate that without a new
threat-model input.

### P-06-4: One immutable input object per upload, read by per-line ranged GET — never materialize the whole blob

**Paradigm statement** — The input is a single immutable S3 object written
once at upload and never rewritten; the worker reads individual lines by
`(offset, len)` ranged GET, so a 50 MB JSONL file is never fully loaded into
worker memory after parse-time. Mutating the input (appending, re-writing,
line-by-line re-PUT) breaks the byte-offset addressing the ranged GETs
depend on and must be rejected. The Range read must tolerate a server that
ignores the `Range` header and returns `200` with the full body — the
guard is "accept 2xx, verify byte length, reject short reads," not "require
exactly 206."

**Source evidence** — `feedback-divergences`: "Input = one immutable S3
object; per-line `(offset, len)` + ranged GET." `gateway.md` Rebuttal (f):
"Range-ignoring-200 guard holds (stronger than literal 206)" — Andrea
endorses the length-verifying guard over a strict 206 check.

**<Provider> infra anchor** —
`src/batch/s3_client.rs:59-61` — `get_range(key, offset, len)` trait method
("the per-line input read; the blob is never materialised whole after
upload").
`src/batch/s3_client.rs:170-203` — `RealS3::get_range` impl: `if len == 0
return Ok(empty)`, `end = offset + len - 1`, `get_object_range(key, offset,
Some(end))`, then `match r.status_code() { 200..=299 => verify bytes.len()
== len else Unavailable, 403 => Forbidden, 404 => NotFound }`.
`src/batch/worker.rs:300-319` — the per-line call site:
`state.s3.get_range(&s3_client::input_key(&row.org, &row.input_file_id),
row.input_offset as u64, row.input_len as u64)`.
`src/batch/s3_client.rs:67-70` — `input_key(org, file_id)` = one object per
`file_id`, org-prefixed.

**Codebase-intelligence backend** —
> `semble_search "get_range input object per-line offset len ranged GET worker"` against the gateway worktree → returns `s3_client.rs:54-65` (trait), `s3_client.rs:170-203` (impl with the 200-tolerant + length-verifying guard), and `worker.rs:300-319` (call site) in one pass.
> To confirm immutability (no rewrite path): `codegraph explore -p <gateway-worktree> "trace input object put rewrite append"` → the only `put` on an `input_key` is at upload; no subsequent write exists.

**Fix-suggestion policy** —
> SUGGEST ONLY: if a PR adds a whole-blob `get` on the input path (materializing 50 MB into worker RAM), a rewrite/mutation of an input object after upload, or a strict `status == 206` guard that would break against a Range-ignoring server, open a finding citing the ranged-GET invariant and the 200-tolerant length-verifying guard. Do NOT commit a patch.

**Adversarial caveat** — A leading UTF-8 BOM in the input object is a
known gap (`gateway.md` Rebuttal (f): "a leading UTF-8 BOM fails line 1";
`jsonl.rs:49-85` strips CRLF and blanks but has no BOM strip). That is a
*parser* defect (Sector 12 Code-smell owns the BOM), not a residency defect —
the immutable-object + ranged-GET invariant is intact; the BOM just means
line 1's bytes include `\u{FEFF}` and fail JSON parse. Flag the BOM in
Sector 12, not here.

### P-06-5: Retention is terminal-anchored at 29 days with explicit DeleteObject — no object-age lifecycle rule

**Paradigm statement** — Retention is bounded and enforced in the
application: a batch terminal for 29+ days gets its S3 content explicitly
deleted, then the gateway-side sweep marker is stamped — in that order,
per item, so a failed delete leaves the marker unset and the next tick
retries. Metadata is kept forever. There is deliberately *no* S3
object-age lifecycle rule: the gateway owns the delete so it controls the
ordering (content-delete-before-marker) and so a credential/permission
failure is observable in app logs rather than silently applied by the
bucket. The sweep cadence is hourly (generous for a 29-day boundary) with
a 60 s floor to prevent a fat-fingered env busy-looping the DB.

**Source evidence** — `feedback-divergences`: "Terminal-anchored 29-day
retention; explicit `DeleteObject`; no object-age lifecycle." `gateway.md`
BLOCKER-1 context: the sweep is the retention mechanism; its correctness
(or leak, per BLOCKER-1) is the residency concern.

**<Provider> infra anchor** —
`src/batch/sweep.rs:1-7` — module doc: "batches terminal for 29+ days get
their S3 content deleted, then the gateway-side sweep marker stamped — in
that order, per item, so a failed delete leaves the marker unset and the
next tick retries (delete is idempotent; a missing object counts as
success). Metadata is kept forever."
`src/batch/sweep.rs:142-146` — `DEFAULT_SWEEP_MS = 3_600_000` (hourly),
`MIN_SWEEP_MS = 60_000` (floor); `sweep.rs:148-149` — `INITIAL_WARMUP_SECS
= 5` (key_reaper precedent).
`src/batch/sweep.rs:175-180` — `BATCH_SWEEP_DISABLED` kill-switch.
`src/batch/s3_client.rs:62-64` — `delete` trait method ("Idempotent
DELETE (retention sweep); deleting a missing object is success, not
NotFound"). No S3 lifecycle rule is configured anywhere in the batch module
(negative space — the doc explicitly says "no object-age lifecycle").

**Codebase-intelligence backend** —
> `semble_search "retention sweep 29 day terminal anchored DeleteObject sweep marker idempotent"` against the gateway worktree → returns `sweep.rs:1-7` (the ordering invariant) and the cadence constants.
> To confirm no lifecycle rule exists: `codegraph explore -p <gateway-worktree> "S3 lifecycle rule object age expiration configuration"` → returns no lifecycle-config path; the `s3_client.rs` config (`S3Config::from_env` at `:90-106`) reads only endpoint/region/bucket/creds, no lifecycle field.

**Fix-suggestion policy** —
> SUGGEST ONLY: if a PR adds an S3 object-age lifecycle rule (deferring retention to the bucket), reorders content-delete-after-marker, or removes the `MIN_SWEEP_MS` floor, open a finding citing the terminal-anchored-delete invariant and the explicit-DeleteObject design choice. Do NOT commit a patch.

**Adversarial caveat** — A 29-day boundary with hourly sweeps means an
object can survive up to ~29 days + 1 hour before deletion; an agent
demanding exact 29-day precision would be over-reading — the boundary is
"terminal for 29+ days," and the hourly cadence is explicitly "already
generous." Conversely, relying solely on the app sweep (no lifecycle
backstop) means a sweep bug (e.g. BLOCKER-1's selector regression) leaks
content indefinitely with no bucket-side safety net — the trade-off is
app-observability vs bucket-side guarantees, and Andrea chose the former.

### P-06-6: Expired batches must produce a synthetic error file so the residency invariant (every terminal batch has a deletable result/error footprint) holds

**Paradigm statement** — An expired batch that produces neither a result
file nor an error file leaves its rows without a deletable residency
footprint and, downstream, breaks the OpenAI SDK's `total == completed +
failed` contract. The expiry path must stamp `error_code = 'batch_expired'`
and the error-file synthesis must include `expired` rows (`status = ANY([
'errored', 'expired'])`), gated so an `error_file_id` is emitted whenever
`failed > 0 || expired > 0`. Without this, expired content is synthesized
as " vanished" — the residency sweep has nothing to enumerate and the wire
contract reports a phantom delta.

**Source evidence** — `gateway.md MAJOR-4`: Andrea flags
`files.rs:232-235` synthesizing the error file from `status='errored'` only
— "expired rows never appear; `total != completed + failed` breaks the
OpenAI SDK contract." Mateo's fix: `expire_batches` sets
`error_code = 'batch_expired'`; synthesis uses
`status = ANY($2::text[])` bound to `["errored", "expired"]`;
`error_file_id` gate widened to `failed > 0 || expired > 0`. Verdict:
ADDRESSED.

**<Provider> infra anchor** —
`src/batch/store.rs:805` — `SET status = 'expired', error_code =
'batch_expired'` (the expiry stamp, inside `expire_batches`'s
`FOR UPDATE SKIP LOCKED` transaction over non-terminal batches at
`:787-794`).
`src/routes/files.rs:288` — `SyntheticKind::Error => &["errored",
"expired"]`; `files.rs:313` — `WHERE batch_id = $1 AND status = ANY($2::text[])`.
`src/routes/batches.rs:95` — `(counts.failed > 0 || tallies.expired >
0).then(|| error_file_id_for(&row.id))` (the widened gate).
`src/batch/store.rs:819-835` — `expire_batches` flips `batch.status =
'expired'`, `expired_at`, `terminal_at` (the terminal anchoring the
29-day retention clock in P-06-5).

**Codebase-intelligence backend** —
> `semble_search "expire batch error_code batch_expired synthetic error file errored expired status ANY"` against the gateway worktree → returns `store.rs:805` (the stamp), `files.rs:288/313` (synthesis), and `batches.rs:95` (the gate) in one pass.
> To confirm the expiry stamp feeds retention: `codegraph explore -p <gateway-worktree> "trace expire_batches terminal_at sweepable_batches retention"` → `store.rs:819-835` sets `terminal_at = $1`; `sweepable_batches` (called by `sweep_tick`) selects on `terminal_at < now - 29d`.

**Fix-suggestion policy** —
> SUGGEST ONLY: if a PR narrows the error-file synthesis back to `status = 'errored'` only, removes the `batch_expired` error code, or tightens the `error_file_id` gate to `failed > 0` (dropping `expired`), open a finding citing MAJOR-4 and the `["errored", "expired"]` synthesis set. Do NOT commit a patch. (The `total != completed + failed` *wire* consequence is Sector 08's to enforce; here the residency concern is that expired rows have a synthesized, deletable footprint.)

**Adversarial caveat** — This paradigm's residency framing overlaps
heavily with Sector 08 (wire contract) — the *same* MAJOR-4 fix serves both
lenses. An agent applying this sector should focus on the *residency*
consequence (expired rows have no deletable footprint / the sweep has
nothing to enumerate for them) and defer the wire-contract consequence
(`total != completed + failed`) to Sector 08; the dedup pass will merge
the shared evidence.

## Cross-sector links

- **Shares BLOCKER-1 evidence with Sector 03 (Graceful shutdown) and Sector 05 (Billing).** The same `1..=attempt` orphan window a SIGTERM-dropped worker creates (Sector 03) and a double-finalize creates (Sector 05) is the residency leak this sector's sweep must reclaim. The *lens* differs: Sector 03 asks "did the worker drain?", Sector 05 asks "did it double-bill?", this sector asks "did the object survive past 29d?".
- **Shares MAJOR-4 evidence with Sector 08 (Wire/contract).** The `batch_expired` stamp + `["errored", "expired"]` synthesis fix the residency footprint (this sector) AND the `total != completed + failed` OpenAI SDK contract (Sector 08). Flagged for the dedup pass; the residency framing above is the sector-06-specific cut.
- **Shares MAJOR-7 evidence with Sector 11 (Testing).** The `S3Error::Forbidden` + timeout + `delete_idempotent`-skip fixes are residency-correctness (this sector); the *missing unit tests for `s3_client.rs`* and the *deferred live-S3 spike as merge gate* are Sector 11's. The spike-as-merge-prerequisite process decision is Sector 09 (Multi-repo / deploy ordering).
- **Shares the `error_code` column with Sector 07 (Schema).** Adding `error_code = 'batch_expired'` is a residency/data concern (this sector); the migration that introduces the `error_code` column, its CHECK constraint, and its V-number are Sector 07.
- **Shares the BOM gap with Sector 12 (Code-smell).** The BOM defect is a parser gap on the immutable input object; the *immutability + ranged-GET* residency invariant (P-06-4) is intact, so the BOM is flagged to Sector 12, not here.

## Sector-specific failure modes

- **Flagging the `1..=attempt` loop as O(n²) overkill.** S3 has no LIST in the gatekeeper posture; the brute-force per-generation delete is the *correct* response to the no-LIST constraint. An agent that "optimizes" it to delete only the committed generation re-introduces BLOCKER-1.
- **Treating the logged `Forbidden`-skip as a bug.** The skip advances the sweep and emits `tracing::error!`; retrying `403` forever (the pre-fix behavior) pins the sweep on a config defect. An agent should flag a *silent* skip (no log), not the logged-skip design.
- **Demanding exact 29-day retention precision.** The boundary is "terminal for 29+ days" with an hourly sweep; ~29d+1h survival is by design ("already generous"). An agent flagging the +1h as a leak over-reads the invariant.
- **Re-opening the SSE-S3 vs app-crypto decision without a new threat-model input.** Andrea explicitly accepted SSE-S3 and the ADR 0002→0003→0004 chain is settled; an agent proposing app-managed KMS keys must cite a new threat-model requirement, not preference.
- **Confusing residency with wire contract on MAJOR-4.** The `batch_expired` fix serves two sectors; an agent applying this sector should report the residency consequence (expired rows have a deletable footprint) and let Sector 08 report the `total != completed + failed` consequence, not duplicate it.

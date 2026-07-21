# Sector 11 — Test coverage & CI gates

## Scope

This sector owns the question Andrea asks of every PR that ships a fix, a new
public surface, or an external dependency: **does the test suite actually
exercise the code path the PR changes, under the conditions the PR claims to
be safe, and does CI make that exercise mandatory?** It covers four failure
shapes Andrea repeatedly catches: (1) DB-backed tests that are opt-in with no
way to turn on, so they skip to green in CI and never run; (2) a fix that
ships without a test that reproduces the bug it fixes (loses before, passes
after); (3) a security/contract reject path "tested" only by stubbing the
guard to always resolve; (4) a new external client whose real signing / range
/ error-mapping paths are exercised only by mock doubles, never by the real
implementation or a live spike. It deliberately does NOT own the *content* of
state-machine terminal-status (Sector 05), the *correctness* of SSRF routing
itself (Sector 10), or the *V-number / deploy-ordering* of migrations
(Sector 07 / 09) — those sectors own the behavior; this sector owns whether a
test proves it and whether CI enforces the proof.

## Paradigms (6 entries)

### P-11-1: A DB-backed test that skips when its env var is unset must have CI that sets the env var, or it is a no-op masquerading as coverage

**Paradigm statement** — When a test module gates itself on an environment
variable (`if TEST_DATABASE_URL unset → skip/return`), the reviewer must
verify that *some* CI workflow actually sets that variable and runs the
tests. A test that early-returns green when its prerequisite is missing is,
in a CI run that never supplies the prerequisite, indistinguishable from no
test at all. The presence of the `require_pool!` / `Option::None → return`
pattern is a red flag that demands the complementary CI workflow, not a sign
of graceful test design. Andrea's bar: if there is no workflow that stands
up the database, applies the migrations, sets the URL, and runs `cargo test
--locked`, then every DB-gated test is dead coverage and the PR's "tested"
claim is unfounded.

**Source evidence** — `gateway.md MAJOR-5`:
> "`testdb.rs:17` returns `None` when `TEST_DATABASE_URL` unset;
> `require_pool!` makes 81 DB-gated tests early-return green; tag-only CI
> exercises none of store/billing/reaper/sweep."
The fix described is "new `.github/workflows/test.yaml` triggers on
pull_request/push, stands up postgres via `gateway-db/docker-compose.yml`,
applies V1..V44, sets `TEST_DATABASE_URL`, `cargo check --tests --locked`
then `cargo test --locked`." The audit's own "Notes" flags the PAT caveat for
cross-repo checkout of `gateway-db`.

**<Provider> infra anchor** — `feat-batch-api-gateway/src/batch/testdb.rs:17`
(`pub async fn pool() -> Option<PgPool>` — `let url =
std::env::var("TEST_DATABASE_URL").ok()?;` returns `None` on unset); the
`require_pool!` macro defined at `billing.rs:314-324` (and duplicated in
`store.rs:1121`, `routes/files.rs:465`, `routes/batches.rs:533`,
`metering.rs`) expands to `match testdb::pool().await { None => {
eprintln!("skipping: TEST_DATABASE_URL unset"); return; } }`. The intended
CI anchor is `.github/workflows/test.yaml` in the gateway repo (triggers
`on: pull_request` + `push: branches: [main]`, `docker compose up -d --wait
postgres-gateway` from `feat-batch-api-gateway-db/docker-compose.yml`, `docker
compose run --rm flyway-gateway` applying V1..V44, `TEST_DATABASE_URL:
postgres://...@localhost:2350/<provider>_gateway`, `cargo test --locked`).
**Grounding note:** the gateway worktree under audit
(`feat-batch-api-gateway`) contains only `.github/workflows/build.yaml` (a
tag-only image-push workflow); the `test.yaml` the audit cites as evidence
was NOT present on disk at verification time. The `build.yaml` that exists
triggers `on: push: tags: ["[0-9]*"]` — tag-only, exactly the "no CI exercises
the tests" state MAJOR-5 describes. This is the single most important
grounding fact for this paradigm: the fix the audit records as ADDRESSED is,
on this machine, not yet landed.

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/gateway "testdb require_pool TEST_DATABASE_URL"`
> → confirms `pool()` returns `Option` and the `require_pool!` blast radius
> (57 call sites across the batch module). CAVEAT: the codegraph index points
> at a different worktree (`$HOME/<provider>/gateway`); run
> `codegraph init -i` in `feat-batch-api-gateway` for a worktree-local index,
> or verify with direct reads.
> `semble_search "require_pool testdb TEST_DATABASE_URL skip DB-backed tests"`
> (repo = `feat-batch-api-gateway`) → returns the `testdb.rs:1` module doc,
> the `require_pool!` macro in `store.rs:1121`, the `db.rs:268` schema-verify
> test, and the `routes/files.rs:465` / `routes/batches.rs:533` duplicates —
> proving the skip pattern is repo-wide, not one file.
> To confirm the CI gap: `glob "**/.github/workflows/*.y*ml"` in the gateway
> worktree and read each trigger — if no workflow sets `TEST_DATABASE_URL`
> and runs `cargo test`, the paradigm fires.

**Fix-suggestion policy** —
> SUGGEST ONLY: open a finding citing MAJOR-5 — "DB-gated tests skip green
> without `TEST_DATABASE_URL`; no gateway workflow sets it." Reference the
> canonical `testdb.rs:17` + `require_pool!` pattern and the missing
> `test.yaml`. Do NOT commit the workflow; the PR author owns adding
> `.github/workflows/test.yaml` (postgres + flyway + `TEST_DATABASE_URL` +
> `cargo test --locked`). Flag the cross-repo `gateway-db` checkout PAT risk
> as an ops follow-up, not a code defect.

**Adversarial caveat** — A skip-on-unset test is *correct* local-dev
ergonomics (a contributor without Docker should not see 81 failures from
`cargo test`); the defect is the *missing CI*, not the skip macro itself.
An agent that flags `require_pool!` as a bug rather than flagging the absent
workflow produces a false positive — the macro is the documented,
intentional pattern (see the `testdb.rs:1-9` module doc).

### P-11-2: A fix PR must ship a test that loses the race before the fix and passes after

**Paradigm statement** — When a PR claims to fix a race, an idempotency gap,
or a state-machine leak, the reviewer must verify the diff contains a test
that *would have failed* against the pre-fix code and *passes* against the
post-fix code. A test added after the fix that only asserts the happy
post-fix behavior proves nothing — it cannot distinguish the fix from a
no-op. Andrea's canonical phrasing (playbook paradigm #2): "If the PR fixes
a race, write a test that loses the race before the fix, then passes after.
If the PR adds a new gate, run the gate-open and gate-closed paths." The
test must name the bug it pins, ideally in a comment that says "#14: the
suite used to always stub X to resolve, so the reject branch never ran."

**Source evidence** — `andrea-review-playbook.md` paradigm #2:
> "Reproduce the bug. If the PR fixes a race, write a test that loses the
> race before the fix, then passes after. If the PR adds a new gate, run the
> gate-open and gate-closed paths."
`gateway.md` "Notes on the review — BLOCKER-2 severity" documents the
exemplar: the `finalize_success_second_call_is_noop_and_never_double_bills`
test at `billing.rs:594` "pins this" — the double-billing rebuttal is
backed by a test that exercises the stale-finalize path and asserts no
double-bill, the canonical reproduce-the-bug shape for an idempotence fix.

**<Provider> infra anchor** — `feat-batch-api-gateway/src/batch/billing.rs:594`
(`async fn finalize_success_second_call_is_noop_and_never_double_bills`) —
drives a second `finalize_success` call against an already-finalized row and
asserts the `AND attempt = $9` guard (billing.rs:127) makes it a no-op, so
the reclaim path bills exactly once. The conformance matrix at
`docs/prd-conformance.md:134` records the restart-race pin:
`e7_worker_restart_reclaims_lease_and_bills_exactly_once` ("Restart mid-batch
→ exactly one usage_log row"). The `testdb.rs:37` `REAPER_LOCK` and `:42`
`SWEEP_LOCK` process-wide mutexes exist precisely so a failure-matrix test
can drive a global reaper/sweep job without a concurrent test in another
module consuming its fixtures — the test harness is built to *reproduce*
the cross-module race, not avoid it.

**Codebase-intelligence backend** —
> `semble_search "finalize_success_second_call noop never double bills
> attempt guard"` (repo = `feat-batch-api-gateway`) → locates the
> reproduce-the-bug test and the `AND attempt = $9` guard it pins.
> `codegraph explore -p ~/<provider>/gateway "trace finalize_success
> idempotence attempt guard"` → confirms the WHERE clause and that the test
> is the only caller asserting the no-op outcome.
> `memory_smart_search "reproduce the bug test loses race before fix"` →
> recall whether a prior session already verified a given fix-test pair,
> avoiding re-derivation.

**Fix-suggestion policy** —
> SUGGEST ONLY: if a fix PR lacks a before/after test, open a finding citing
> playbook paradigm #2 — "no test reproduces the bug this fix addresses;
> add one that fails on the pre-fix path." Point at the canonical sibling
> (`finalize_success_second_call_is_noop_and_never_double_bills`,
> `e7_worker_restart_reclaims_lease_and_bills_exactly_once`). Do NOT write
> the test for the author.

**Adversarial caveat** — Not every fix admits a deterministic before/after
test: a fix to a deploy-ordering hazard (Sector 09) or a one-line
`Utc::now()` injection (MINOR-4, DECIDED-NOT-ACTIONED) may be verified by
inspection or a live spike rather than a unit test. Demanding a
reproduce-the-bug test for a fix that is itself a test-infrastructure
addition is circular. The paradigm fires on *behavioral* fixes (race,
idempotence, state-machine, contract), not on pure plumbing.

### P-11-3: A security reject path must be exercised with a real reject, not stubbed to always resolve

**Paradigm statement** — When a test suite mocks a security guard (SSRF
`validateAndPinUrl`, ownership check, auth), the reviewer must verify at
least one test forces the mock to *reject* and asserts the downstream effect
(no egress call, row marked failed, 403 returned). A suite where the guard
mock always resolves exercises only the happy path; the reject branch — the
one that actually prevents the vulnerability — never runs, and a regression
that drops or inverts the guard ships green. Andrea's webhook path step 5
(playbook) asks: "Does the test exercise the SSRF reject path, or does it
stub `validateAndPinUrl` to always resolve?"

**Source evidence** — `andrea-review-playbook.md` webhook path step 5:
> "Test coverage. Does the test exercise the SSRF reject path, or does it
> stub `validateAndPinUrl` to always resolve? `src/jobs/__tests__/
> trainingWebhook.job.test.ts:35`"
The test file itself documents the hazard it was written to close
(`trainingWebhook.job.test.ts:409-412`):
> "#14: the suite used to always stub validateAndPinUrl to resolve, so the
> SSRF reject branch in deliver() never ran. A regression that dropped or
> inverted the guard would ship green. Force a reject and assert no POST
> and the row going to failed."

**<Provider> infra anchor** —
`worktrees/training-webhooks/app/backend/src/jobs/__tests__/
trainingWebhook.job.test.ts:21` (`vi.mock('../../libs/ssrfGuard', () => ({
validateAndPinUrl: mockValidate }))` — the guard is mocked, so a
default-resolve mock would hide the reject branch); `:408` the test
`an SSRF-rejected URL does not POST and fails the row (#14)`; `:414`
`mockValidate.mockRejectedValueOnce(new Error('URL resolves to
internal/private network address: 10.0.0.5'))`; `:442`
`expect(mockSend).not.toHaveBeenCalled()`; `:444`
`expect(r).toEqual({ attempted: 1, delivered: 0, failed: 1 })`. The real
guard the test must exercise the reject of lives at
`app/backend/src/libs/ssrfGuard.ts` (`validateAndPinUrl`) and the egress
boundary at `src/services/clientEgress.ts:103`. This is the canonical
"force the mock to reject" sibling for every SSRF / ownership / auth-guard
test in the codebase.

**Codebase-intelligence backend** —
> `semble_search "validateAndPinUrl mock reject SSRF internal network no
> egress"` (repo = `training-webhooks/app/backend`) → locates the
> `#14` reject test and any sibling tests that still default-resolve the
> guard (candidates for the same finding).
> `codegraph explore -p ~/<provider>/gateway "validateAndPinUrl
> reject path"` → for gateway-side SSRF, trace the real guard's reject
> branch and confirm a test drives it.
> Serena `find_referencing_symbols` on `validateAndPinUrl` → enumerate every
> caller; for each caller, check whether its test forces a reject. A caller
> whose only test resolves the guard is a gap.

**Fix-suggestion policy** —
> SUGGEST ONLY: open a finding citing playbook webhook-path step 5 — "the
> SSRF/ownership/auth guard is mocked; no test forces a reject, so the
> reject branch is unexercised." Reference the canonical `#14` sibling
> (`trainingWebhook.job.test.ts:408`). Do NOT write the reject test; the PR
> author owns adding `mockValidate.mockRejectedValueOnce(...)` + asserting
> no egress + failed terminal.

**Adversarial caveat** — Forcing a mock to reject tests the *call site's
reaction* to a reject, not the *guard's* reject logic itself — the real
`validateAndPinUrl` resolve/pin/deny decision is only truly exercised by a
test that calls the real guard with a hostile URL (10.0.0.5,
169.254.169.254, `[::1]`). A mock-reject test guards against "guard silently
dropped from the call site," not against "guard logic inverted." An agent
that treats a mock-reject test as full SSRF coverage over-claims; the live
guard's own unit tests (if any) are a separate, necessary coverage.

### P-11-4: A new external client must have unit tests for its real signing, range, and error-mapping paths — mock doubles are not coverage of the real client

**Paradigm statement** — When a PR introduces a new external-client
implementation (S3, HTTP upstream, vault), the reviewer must verify the
*real* client's signing, range-request, and error-mapping code paths are
exercised by tests, not only by an in-memory mock double that implements the
same trait. A `MockS3` that implements `S3Store` exercises the *caller's*
logic (worker, sweep) against a fake, but the `RealS3` path — SigV4 signing,
range-header construction, `403 => Forbidden` mapping — runs zero times in
the suite. Andrea's MAJOR-7 sub-point: "real signing/range/error-mapping
paths exercised only by mock doubles." The bar is either real-client unit
tests (SigV4 canonicalization, range byte-offset, status→error mapping) or
a live spike that exercises the real client against the real service.

**Source evidence** — `gateway.md MAJOR-7` (sub-point 1, PARTIALLY-ADDRESSED):
> "`s3_client.rs` (233 lines) has no tests … the grep shows the real
> signing/range/error-mapping paths in `RealS3` remain exercised only by
> `mock_s3.rs` doubles."
`gateway.md Rebuttal (g)`:
> "No live-S3 test exists in the gateway codebase (the `RealS3` path at
> `s3_client.rs:150-221` is only exercised via `MockS3` doubles in tests)."

**<Provider> infra anchor** —
`feat-batch-api-gateway/src/batch/s3_client.rs` (246 lines, 0 `#[test]` /
`#[tokio::test]` attributes — verified by grep); the `RealS3` implementation
(`put` at `:143`, `get_range` at `:193`, `delete` at `:214`, each mapping
`403 => Err(S3Error::Forbidden(...))` per the MAJOR-7 fix). The double is
`feat-batch-api-gateway/src/batch/mock_s3.rs` (`MockS3` implementing
`S3Store`, 0 tests — it is the *fixture*, not a test of the real client).
`mock_s3.rs:1-3` is explicit: "In-memory `S3Store` test double … there is
no app backend in the content path any more." So the test matrix exercises
the worker/sweep *callers* of `S3Store` against `MockS3`, while `RealS3`'s
signing/range/error-mapping runs only in production. The 403-classification
fix (a real behavioral change) shipped with no test pinning it.

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/gateway "s3_client mock_s3 test
> coverage"` → confirms `s3_client.rs` has no `#[test]` and `RealS3` is only
> referenced by production callers, not by a test module.
> `semble_search "RealS3 put get_range delete Forbidden SigV4 signing
> range header"` (repo = `feat-batch-api-gateway`) → if it returns only
> production call sites and no `#[cfg(test)]` block, the real client is
> untested.
> Serena `find_symbol` (`name_path_pattern="RealS3"`,
> `relative_path="src/batch/s3_client.rs"`) → confirm the struct and its
> method bodies; `find_referencing_symbols` on `RealS3::put` → if every
> reference is in `src/batch/worker.rs` / `sweep.rs` (non-test), there is no
> unit test.

**Fix-suggestion policy** —
> SUGGEST ONLY: open a finding citing MAJOR-7 — "`s3_client.rs` has no unit
> tests; the 403→Forbidden mapping and range-header construction are
> exercised only by `MockS3` doubles, so a regression in `RealS3` ships
> green." Suggest real-client unit tests for: (a) SigV4 canonicalization
> (fixed-input → expected signature), (b) range header byte-offset
> construction, (c) status→`S3Error` mapping incl. 403. Do NOT write the
> tests; the PR author owns them. Separately flag the live-S3 spike (see
> P-11-6).

**Adversarial caveat** — SigV4 signing and range headers are partly
determined by the SDK (`aws-sdk-s3`) rather than this code; if
`RealS3::put` is a thin wrapper over the SDK, unit-testing the wrapper's
signing may be testing the SDK, which is low-value. The high-value, ownable
tests are the *error-mapping* (status → `S3Error` variant, incl. the 403
classification Andrea flagged) and any *range-header construction* this code
performs. An agent that demands "test the SigV4 signature bytes" when the
code never touches them over-asks; the bar is "test what this code owns."

### P-11-5: Stateful failure modes (restart, budget exhaustion, cancel race, expiry) must be covered by a failure-matrix test set, not happy-path-only

**Paradigm statement** — For a stateful system (worker, reaper, billing),
happy-path tests are necessary but not sufficient. The reviewer must verify a
failure matrix that exercises each stateful hazard: restart mid-batch,
budget exhaustion, cancel racing in-flight, and expiry of in-flight rows.
Each hazard must be a named test that drives the system into the failure
state and asserts the post-failure invariant (exactly one bill, no orphan,
correct terminal status, no upstream send). Andrea's feedback-divergences
row records this as the bar: "Stateful failure-matrix testing (restart,
budget exhaustion, cancel race, expiry) ✅ Conformance matrix E-tests."

**Source evidence** — `feedback-divergences.md` (Andreas's original plan,
adopted):
> "Stateful failure-matrix testing (restart, budget exhaustion, cancel
> race, expiry) ✅ Conformance matrix E-tests"
`gateway.md` repeatedly ties verdicts to named tests that pin stateful
invariants: BLOCKER-2 notes the `finalize_success_second_call...` test pins
the no-double-bill; the conformance matrix at `prd-conformance.md` records
`e7` (restart), `e8` (budget), `e9` (cancel race), `e10` (expiry).

**<Provider> infra anchor** — The four E-tests in
`feat-batch-api-gateway/src/batch/billing.rs` (test module at `:290`,
`mod tests`) and `store.rs`, recorded in `docs/prd-conformance.md`:
- `e7_worker_restart_reclaims_lease_and_bills_exactly_once`
  (`prd-conformance.md:134` — "Restart mid-batch → exactly one usage_log
  row");
- `e8_budget_exhaustion_errors_whole_batch_without_upstream_sends`
  (`prd-conformance.md:93` — "failing row + queued siblings →
  errored/insufficient_budget, batch completed, zero bills, zero upstream
  sends");
- `e9_cancel_racing_in_flight_drains_bills_once_and_lands_cancelled`
  (`prd-conformance.md:81` — "cancel keeps succeeded rows, output file
  still downloadable");
- `e10_expiry_drains_in_flight_and_lands_expired_never_completed`
  (`prd-conformance.md:82` — "expired rows write no usage_log row").
All four are DB-gated (use `require_pool!`), so they only run when
`TEST_DATABASE_URL` is set — tying this paradigm to P-11-1: the failure
matrix is dead coverage without the CI workflow that turns it on.

**Codebase-intelligence backend** —
> `semble_search "e7 worker restart reclaims lease bills once e8 budget
> exhaustion e9 cancel racing e10 expiry"` (repo =
> `feat-batch-api-gateway`) → locates the four named E-tests and confirms
> the matrix is complete vs. Andrea's four hazards; a missing hazard (e.g.,
> no `e_*_cancel_race`) is the finding.
> `codegraph explore -p ~/<provider>/gateway "trace worker restart reclaim
> lease finalize idempotence"` → confirms the restart path the E7 test
> drives, and whether a new stateful path added by the PR has a
> corresponding E-test.
> `memory_smart_search "stateful failure matrix restart budget cancel
> expiry E-tests"` → recall prior session decisions on which hazards are
> in-scope.

**Fix-suggestion policy** —
> SUGGEST ONLY: open a finding listing the stateful hazards Andrea names
> (restart, budget exhaustion, cancel race, expiry) and which have a
> corresponding E-test; for any hazard with no test, cite the missing one
> and the canonical sibling shape (`e7_...`). Do NOT write the test; the PR
> author owns adding the missing E-test. If the hazard's test is DB-gated
> but no CI sets `TEST_DATABASE_URL`, chain the finding to P-11-1.

**Adversarial caveat** — A "failure matrix" can balloon: every state × every
event × every ordering is combinatorial. Andrea's bar is the *four named
hazards* specific to this system (restart/budget/cancel/expiry), not an
exhaustive cross-product. An agent that demands a test for every
state-transition pair over-applies the paradigm; the bar is the hazards
Andrea listed, expanded only when a new stateful path introduces a new
hazard class.

### P-11-6: A live spike against a real external dependency is a merge prerequisite, not a follow-up, when the dependency is load-bearing and unverified

**Paradigm statement** — When a PR introduces a new external dependency that
is load-bearing for correctness (a new storage substrate, a new SSE
encryption mode, a new SigV4 path-style endpoint), unit tests and mock
doubles are insufficient: the real dependency's behavior (SSE-S3 PUT,
ranged GET on SSE-S3, path-style + SigV4, scoped-key-with-delete-denied)
must be exercised against the *live* service before merge. Andrea's bar on
the S3 spike (MAJOR-7 / Rebuttal g): "a merge prerequisite, not a
follow-up." A spike marked NOT RUN in the conformance matrix is an open
hazard, not a closed item; deferring it to an "infra validation gate"
contradicts the stated bar and leaves the load-bearing unknown in the diff.

**Source evidence** — `gateway.md MAJOR-7`:
> "live S3 spike is a merge prerequisite, not a follow-up."
`gateway.md Rebuttal (g)`:
> "No live-S3 test exists in the gateway codebase … Mateo's framing reframes
> Andrea's 'merge prerequisite' as 'infra validation gate' — a decision to
> defer the spike out of the code diff. … it contradicts Andrea's stated
> bar ('merge prerequisite, not a follow-up')."
`feedback-divergences.md` (Process / ops):
> "Week-1 spike against live dev S3 + dev GPU priority verification before
> calling storage settled — Spike marked ◻ NOT RUN in conformance matrix
> (no live endpoint contact in build)."

**<Provider> infra anchor** — No live-S3 test exists in
`feat-batch-api-gateway`: `RealS3` (`s3_client.rs:150-221`) is exercised
only via `MockS3` doubles (`mock_s3.rs`); `grep` for a live-S3 integration
test in the gateway returns nothing. The conformance matrix at
`docs/prd-conformance.md` marks the SSE-S3 / ranged-GET spike as ⚠/◻ NOT
RUN (row 12 "Interactive preempts on GPU" is the sibling ⚠ row; the S3
spike is the NOT-RUN ops prereq at `feedback-divergences.md:54`:
"Andreas handles infra: buckets, ranged-GET spike, lifecycle assumptions
— ◻ Ops prereq; spike marked NOT RUN"). The infra the spike would
exercise: `feat-batch-api-gateway-db` buckets/creds (ADR 0004 bucket
table), the `RealS3` SSE-S3 PUT path, and ranged GET on an SSE-S3 object.

**Codebase-intelligence backend** —
> `semble_search "RealS3 live S3 integration test SSE-S3 ranged GET
> path-style SigV4"` (repo = `feat-batch-api-gateway`) → if no
> `#[ignore]` live-integration test or spike script returns, the spike is
> NOT RUN.
> `codegraph explore -p ~/<provider>/gateway "RealS3 put get_range delete
> live integration test"` → confirms no test exercises the real client
> against a live endpoint.
> `memory_smart_search "S3 spike NOT RUN merge prerequisite live dev"` →
> recall whether the spike was since run in a prior session; if a session
> recorded it passing, the paradigm is satisfied and the finding closes.
> `memory_recall "FlashBlade S3 SSE-S3 ranged GET spike"` → same, with
> session-narrative detail.

**Fix-suggestion policy** —
> SUGGEST ONLY: open a finding citing MAJOR-7 / Rebuttal (g) — "the live-S3
> spike (SSE-S3 PUT, ranged GET on SSE-S3, path-style + SigV4,
> scoped-key-with-delete-denied) is marked NOT RUN; Andrea's bar is
> merge-prerequisite, not follow-up." Do NOT run the spike (it needs live
> creds/endpoint); flag it as a pre-merge gate the PR author + ops must
> close. Record the gate in agentmemory so a future session can verify it
> passed before the PR merges.

**Adversarial caveat** — A live spike is genuinely blocked on infra the
reviewer cannot supply (dev S3 bucket, creds, GPU priority endpoint); it is
a legitimate *gate*, not something a code reviewer can merge. An agent that
treats "spike not run" as a code defect over-claims — the defect is the
*deferral framing* (calling a prerequisite a follow-up), not the absence of
a spike in the diff. The correct finding is "this PR must not merge until
the spike is run and recorded," which is a process gate, not a code change.

## Cross-sector links

- **Shares MAJOR-5 evidence with Sector 07 (Schema/migrations) and Sector 09
  (Multi-repo/deploy ordering):** the CI workflow that turns on the
  DB-backed tests must apply migrations V1..V44 (Sector 07 owns the V-number
  correctness; Sector 09 owns the cross-repo `gateway-db` checkout + PAT).
  This sector owns only "does CI set `TEST_DATABASE_URL` and run the
  tests"; the *content* of what the migrations apply is Sector 07.
- **Shares the `e7`/`e8`/`e9`/`e10` E-tests with Sector 05 (Billing &
  state-machine integrity):** Sector 05 owns the *invariant* (same-txn
  finalize, terminal status, no double-bill); this sector owns whether a
  *test* pins it and whether CI runs the test. The
  `finalize_success_second_call_is_noop_and_never_double_bills` test is the
  shared evidence.
- **Shares the SSRF reject-path test with Sector 10 (SSRF, redaction &
  security boundaries):** Sector 10 owns whether the call site routes
  through `validateAndPinUrl`; this sector owns whether a test forces the
  guard to *reject* and asserts the downstream effect. P-11-3 is the test
  lens on Sector 10's routing lens — flag for dedup; the orchestrator may
  fold the test-exercise half into Sector 10 and keep the
  mock-vs-real-client half here.
- **Shares the live-S3 spike with Sector 06 (Storage & content residency):**
  Sector 06 owns the *decision* (SSE-S3, FlashBlade, ADR 0004); this sector
  owns whether the real client + live endpoint were exercised before merge.
  P-11-6 is the test/spike lens on Sector 06's substrate lens.
- **P-11-4 (real-client unit tests) arguably overlaps a Sector 12 (code
  smell) "233 lines no tests" reading, but the lens differs: Sector 12
  would call it a maintainability smell; this sector calls it untested
  behavioral paths (signing/range/error-mapping). Flag for dedup.

## Sector-specific failure modes

- **Treating the skip macro as the defect.** An agent flags
  `require_pool!` / `testdb::pool() → None → return` as a bug. It is not —
  it is the documented local-dev ergonomics pattern (`testdb.rs:1-9`). The
  defect is the *missing CI workflow* that sets `TEST_DATABASE_URL`; the
  macro is correct. The finding must name the absent workflow, not the
  macro.
- **Treating a mock-double test as real-client coverage.** An agent sees
  `MockS3` exercising the worker/sweep and declares `s3_client.rs` tested.
  It is not — `MockS3` tests the *callers*, not `RealS3`'s signing/range/
  error-mapping. The finding must distinguish "caller tested against a
  double" from "real client's own paths tested."
- **Treating a mock-reject test as full SSRF coverage.** An agent sees
  `mockValidate.mockRejectedValueOnce(...)` and declares SSRF covered. It
  covers the call site's *reaction* to a reject, not the guard's own
  resolve/pin/deny logic. The finding must name both layers; the real
  guard's unit tests (or a live hostile-URL test) are a separate necessity.
- **Treating a NOT-RUN spike as a code defect or as satisfied by the
  workflow existing.** An agent flags "no live-S3 test" as a code change to
  make, or sees `test.yaml` (when it lands) and marks the spike closed. The
  spike is a *process gate* on a live endpoint the reviewer cannot supply;
  closing it requires running the spike and recording the result, not
  editing code. Confusing the gate with the code fix produces a wrong
  finding.

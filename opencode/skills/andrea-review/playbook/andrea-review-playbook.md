# Andrea Review Playbook — Agent-Swarm PR Review Methodology v2

Refined from `docs/andrea-review-playbook.md` (v1) by a 12-worker paradigm
extraction over three source documents — the v1 playbook, the
`worktrees/batch-api/docs/resolve-code-review/gateway.md` PR-#94 audit (26
Andrea items: 3 BLOCKERs, 7 MAJORs, 4 MINORs, 3 NITs, 7 rebuttal items), and
`worktrees/batch-api/docs/feedback-divergences.md` (Andrea's #973 design
review) — followed by parallel dedup, validation, and adversarial passes.
All 12 sector extracts live at `docs/andrea-review-sectors/sector-*.md`; the
three synthesis artifacts at `docs/andrea-review-sectors/_synthesis-*.md`.

**What changed from v1.** v1 was a reviewer's checklist for a human. v2 is a
sector-partitioned methodology an agent swarm can execute: 12 sectors, each
a self-contained lens with its own paradigms, infra anchors, codebase-
intelligence backend bindings, guardrails, and fix-suggestion policy. The v1
playbook's 9 paradigms, 4 critical code paths, and 13 conventions are
absorbed and grounded; 8 stale anchors corrected; 6 cross-cutting guardrails
added; a never-auto-commit policy enforced throughout.

---

## How to run this as an agent swarm

A review is a fan-out over the 12 sectors. Each sector is an independent
agent; the orchestrator dispatches them in parallel, one `tasks[]` batch,
then merges, dedups, and adversarially triages the findings.

```
┌─────────────────────────────────────────────────────────────────┐
│  Orchestrator (Main)                                            │
│  1. Preflight: resolve PR diff, comparison ref, file list       │
│  2. Fan out 12 sector agents in ONE tasks[] batch               │
│  3. Each agent: read its sector below + apply to the diff       │
│  4. Merge: dedup across sectors (M-1..M-15 merge groups)        │
│  5. Validate: re-ground every cited anchor (see Drift table)    │
│  6. Adversarial triage: apply the 6 cross-cutting guardrails    │
│  7. Report: FIX / SKIP-NOW / FALSE-POSITIVE buckets             │
│  8. NEVER auto-commit fixes; the PR author owns every fix       │
└─────────────────────────────────────────────────────────────────┘
```

**Dispatch contract.** Each sector agent receives:
- The PR diff + comparison ref + reviewed-files list.
- Its sector section below (paradigms, anchors, backends, guardrails).
- The cross-cutting rules (this doc's top section).
- The fix-suggestion-only policy.
- Output contract: one finding per paradigm that fires, shaped as
  `{sector, paradigm_id, file, line, claim, severity, suggested_fix, backend_used, anchor_verified}`.
  Severity: BLOCKER / MAJOR / MINOR / NIT, anchored to Andrea's #94 severity
  bar (a BLOCKER leaks money/data or breaks the contract; a NIT is naming or
  a missing index).

**Why 12, not one.** A single-pass review misses the lenses. The #94 audit
shows Andrea applies 12 distinct concerns simultaneously — idempotency,
concurrency, shutdown, rate-limiting, billing, storage, schema, wire,
multi-repo, security, testing, code-smell. A 12-agent fan-out with dedup
reproduces that depth; a single agent flattens it. Token budget is not the
binding constraint — thoroughness is.

---

## Cross-cutting rules (apply to every sector agent)

These six rules are global. Every sector agent must honor them; the
adversarial pass grades findings against them.

### CR-1: Re-ground before citing any playbook anchor

The v1 playbook has **8 stale anchors** (see Drift table below). Before
citing any `file:line` from v1, re-ground it. Canonical re-grounding path:
1. `semble_search "<symbol name> <distinctive feature>"` — locates the
   symbol by semantic match even after a rename/move.
2. Serena `find_symbol` with `relative_path` scoped to the likely file/dir
   (unscoped `find_symbol` on the large `app/` tree times out at 30s).
3. `read` the resolved `file:line` to byte-confirm the anchor text.

Never cite a v1 anchor verbatim without re-grounding. A stale anchor in a
finding erodes trust faster than a missed finding.

### CR-2: Distinguish row-disjoint from count-disjoint locks

`FOR UPDATE SKIP LOCKED` provides **row-disjoint** claims: each txn locks a
different row by PK, so no two txns claim the same row. It does NOT provide a
**count-disjoint** cap: two concurrent txns can read the same `count(*)` and
both proceed. A count-based cap guarded only by a CTE read is NOT a hard cap
under MVCC; `pg_advisory_xact_lock` inside the transaction is the true hard
cap. **Do not demand an advisory lock where `SKIP LOCKED` already provides
row disjointness** — that adds contention for no correctness gain. The smell
fires only on a *count-based* cap guarded only by a CTE read.

Backend: `codegraph explore -p ~/<provider>/gateway "FOR UPDATE SKIP LOCKED claim_requests"` confirms row-disjoint; Serena `find_symbol` on
`create_batch_capped` confirms the xact-lock is inside `pool.begin()…tx.commit()`.

### CR-3: Worktree-aware anchoring for `feat-batch-api-*` branches

The batch module lives in `~/<provider>/worktrees/batch-api/feat-batch-api-gateway/src/batch/`, NOT in the main `~/<provider>/gateway/` checkout. Two consequences:

- **CodeGraph on `~/<provider>/gateway` is the main-branch index** (dated Jul 9, pre-batch). `codegraph explore -p ~/<provider>/gateway "<batch symbol>"` will surface main-branch code (`images.rs`, `preflight.rs`) tangentially, NOT the batch module. Every batch anchor must be verified by `read` of the worktree path, or by `semble_search` with `repo=~/<provider>/worktrees/batch-api/feat-batch-api-gateway` (semble indexes on first query and caches).
- **codebase-memory has NO `gateway` project indexed.** The 7 indexed projects are `helm`, `app` (87.5k nodes), `app-backend`, `operator`, `<provider>-python`, `app-client`, `e2e`. Any `codebase-memory search_graph` / `trace_path` / `query_graph` for a gateway Rust symbol (`finalize_success`, `create_batch_capped`, `claim_requests`, `apply_usage_writes`, `MAX_ATTEMPTS`, `S3Error::Forbidden`) returns zero rows. Use `read` or `semble` instead. For app-side symbols (`executeTool`, `validateAndPinUrl`, `expectedVersion`, `enforceChatLimits`), codebase-memory on `app` / `app-backend` works.

The batch feature spans **three worktrees**: (1) `feat-batch-api-gateway/` (gateway Rust), (2) `feat-batch-api-gateway-db/` (migrations), (3) `worktrees/training-webhooks/app/backend/` (the SSRF-reject test). Plus the main `app/` checkout (TS controllers, SSRF guard). A bare `src/...` path is ambiguous across these trees — name the worktree path explicitly in every finding.

### CR-4: A deferral with a recorded rationale is not a finding

Andrea's #94 audit distinguishes **ADDRESSED**, **DECIDED-NOT-ACTIONED**,
**UNADDRESSED**, and **PARTIALLY-ADDRESSED**. A DECIDED-NOT-ACTIONED item
(MINOR-4: clock injection deferred because the money path is already
clock-injected in the reaper) is a decision, not a defect. Do not re-raise it
as a finding unless you can show the rationale no longer holds (e.g. a new
route stamps a lifecycle timestamp that feeds a money calculation).

UNADDRESSED items (the 3 silent NIT drops: MAX_ATTEMPTS rename,
det_failures index, cancel re-stamp) ARE findings — they were dropped
without rationale, not decided. The distinction is the presence of a stated
rationale, not the severity.

Backend: `agentmemory memory_recall "<topic>"` — the canonical way to check
whether a deferral or infra prereq was already decided in a prior session.

### CR-5: Confirm the `replicas: 1` invariant before flagging a per-process counter

The in-process `interactive_in_flight` DashMap is a correct QoS signal **if
and only if** the deployment is durably pinned to one replica. The finding is
the *gap* between the asserted `replicas: 1` and its enforcement, not the
counter itself. Before flagging a per-process counter as a fleet-wide race,
confirm the invariant is unenforced (no PodDisruptionBudget
min-available=1, no helm CEL admission gate, no NetworkPolicy making a second
pod unschedulable). If enforced, the in-process signal is the *better* QoS
source (lower latency than a vLLM `/metrics` scrape).

### CR-6: Fixes are suggested, never auto-committed

This is the non-negotiable constraint. A sector agent that finds a defect:
1. Writes a finding to its output with `suggested_fix` (the patch shape, not
   the patch) and `anchor_verified: true|false`.
2. Does NOT call `edit` / `write` on any source file.
3. Does NOT run `git add` / `git commit` / `git push`.
4. Does NOT dispatch a fix sub-agent.
5. Cites the canonical sibling (the code that does it right) so the PR
   author can pattern-match, not copy-paste.

The PR author owns every fix. The codebase-intelligence backends are
read-only suggestion engines: they locate the defect, confirm the
convention, and name the sibling — they never apply the patch. This holds
even when the fix is one line; the one-line judgment is the author's, and a
"one-line fix" that is actually 15 lines across 3 files (MAJOR-7's 403
reclassification) is a sign the reviewer under-estimated the diff.

### CR-7: Findings must be scoped to the PR — class out pre-existing code

Andrea's #94 audit reviewed a diff, not the whole codebase. The sector
paradigms carry **infra anchors** baked from a prior review (the batch-API
audit); re-grounding them via `semble_search` / `find_symbol` / `read` (CR-1)
pulls the agent into surrounding code that may be 20 cuts old. A finding on
code the PR did not touch is out of scope and must be routed to the
PRE-EXISTING bucket, not the FIX bucket, regardless of severity.

Every finding carries an `origin` classification:
- **`introduced_by_pr`** (default) — the implicated code is modified by this
  diff, OR pre-existing-looking code became wrong because of new code this
  PR adds elsewhere (a stale comment now contradicted by a new code path; a
  function missing a field a new caller needs; a guard a new route lacks).
  The PR is causally responsible, even when the cited lines are old. These
  are in scope.
- **`pre_existing`** — the implicated code is **unchanged by this diff AND**
  the bug exists independently of this PR: reverting this PR would not close
  the finding. These go to the PRE-EXISTING bucket, not FIX.
- **`unknown`** — the agent cannot tell. Default to `introduced_by_pr` only
  if the cited file appears in `reviewed_files_all`; otherwise mark
  `pre_existing` and let the orchestrator adjudicate (Step 7).

**The file-membership test is the fast filter.** If the finding's `file` is
NOT in `reviewed_files_all` (the `git diff --name-only $comparison_ref` list
captured at Step 1), the cited code was not modified by this PR — it is
`pre_existing` unless the PR's new code in *another* file made it wrong
(the "became wrong because of new code" case above, which keeps
`introduced_by_pr` because the PR is the cause).

**This is the rule deep-review does not have trouble with** because
adamsreview (its track A) tags every candidate with `origin` and
force-routes `pre_existing`/`high` to a non-actionable footnote regardless
of score. Andrea-review lacked that gate; CR-7 adds it. The PRD exception
from Step 1.5 still holds: a finding that contradicts the PRD is in scope
even in untouched code, because the PRD defines what "correct" means for
this change — such a finding keeps `introduced_by_pr` and carries
`prd_contradiction: true`.

---

## Drift table — 8 stale v1 anchors, corrected

Every v1 anchor below was shown stale by the 12-worker extraction and
re-verified by the validation pass. The refined playbook uses the canonical
path in every paradigm.

| # | v1 anchor (stale) | Canonical (verified) | Why it drifted |
|---|---|---|---|
| D-1 | `src/services/clientEgress.ts:103` (`validateAndPinUrl`) | `app/backend/src/libs/ssrfGuard.ts:166` | File moved/renamed; `clientEgress.ts` does not exist in `app/backend/src` |
| D-2 | `src/controllers/trainingJob.controller.ts:540` (webhook idempotency fingerprint) | `app/backend/src/controllers/automation.controller.ts:1373-1403` (`verifyWebhookSignature`) | Webhook signing moved; `trainingJob.controller.ts:540` is now a K8s `deleteNamespacedCustomObject` |
| D-3 | `src/jobs/trainingWebhook.job.ts:51` (jittered retry) | **No live anchor** — file does not exist | Convention documented but unimplemented in audited batch code; gateway uses lease-spacing, not per-retry jitter |
| D-4 | `executeTool.ts:470` (`expectedVersion`) | `backend/src/controllers/<provider>Chat.libs/agenticLoop/executeTool.ts:545-587` | File grew ~75 lines; pattern intact, line number drifted |
| D-5 | `generateCosmosImage.ts` (bare path, Image-gen step 3/5) | `backend/src/controllers/<provider>Chat.libs/agenticLoop/generateCosmosImage.ts` | Moved under `agenticLoop/` |
| D-6 | `test.yaml` cited as ADDRESSED (gateway CI, MAJOR-5) | **Absent on disk** — only `build.yaml` (tag-only) exists in the worktree | The "ADDRESSED" verdict in the audit is not landed; the fix is an open action |
| D-7 | `gateway-db main head V42` (S09 V-number collision) | **Main head is V37** (`V37__org_default_budget.sql`); V40-V42 are worktree-only | The concurrent-collision narrative describes a prior state, not current main |
| D-8 | `reviewActions.ts:74` (playbook User-memory path step 2) | `backend/src/controllers/<provider>Chat.libs/userMemory/dream/reviewActions.ts:69-74` | Moved under `userMemory/dream/` |

**Re-grounding rule.** Before citing any of these in a finding, re-verify
via `semble_search "<symbol> <feature>"` or Serena `find_symbol` with
`relative_path`. A finding with a stale anchor is a false-positive risk.

---

## The 12 sectors

Each sector is a self-contained review lens. An agent assigned a sector
reads its paradigms, applies them to the PR diff, and emits findings. The
orchestrator merges across sectors using the dedup merge groups (M-1..M-15)
and applies the adversarial guardrails.

Sector map:

| # | Sector | Core question | Paradigms | Confidence |
|---:|---|---|---:|---|
| 01 | Idempotency & re-arm gates | Does every retry/re-run/webhook re-delivery re-fire when it should and not duplicate when it shouldn't? | 7 | HIGH |
| 02 | Concurrency & race conditions | Do concurrent txns/claims/pods race? MVCC, SKIP LOCKED, advisory locks, optimistic-concurrency. | 6 | HIGH |
| 03 | Graceful shutdown & drain | Does a new worker/async loop drain on SIGTERM? No orphan, no double-run. | 6 | MEDIUM |
| 04 | Rate limiting & per-org fairness | Per-key RPM on every new route? Per-org fairness? QoS signals correct? | 7 | HIGH |
| 05 | Billing & state-machine integrity | Same-txn finalize? No double-bill? Terminal status always written? | 7 | HIGH |
| 06 | Storage & content residency | Where does content live? Encryption correct? Sweep covers orphan generations? | 6 | MEDIUM |
| 07 | Schema, migrations & CHECK constraints | V-number collision? CHECK re-added on enum change? CONCURRENTLY? | 5 | HIGH |
| 08 | Wire/contract conformance | OpenAI-exact wire? total==completed+failed? 4xx vs 5xx? BOM gap? | 7 | MEDIUM |
| 09 | Multi-repo & deploy ordering | Companion PRs land as a set? Migration-before-app? V-number collision? | 7 | MEDIUM |
| 10 | SSRF, redaction & security boundaries | URLs through validateAndPinUrl? Headers redacted? Ownership-before-discard? | 6 | HIGH |
| 11 | Test coverage & CI gates | DB-backed tests not opt-in? Reproduce-the-bug test? Live-S3 spike a merge prereq? | 6 | HIGH |
| 12 | Code smell, naming & correctness-detail | Misleading const name? Missing index? Re-stamp? BOM gap? Utc::now() vs injected clock? | 7 | HIGH |

**Confidence** is the validation pass's per-sector grounding verdict (HIGH =
anchors byte-verified; MEDIUM = anchors plausible but not all byte-verified
this pass; the orchestrator weights HIGH sectors more heavily in the merge).

---

### Sector 01 — Idempotency & re-arm gates

**Scope.** The reviewer asks: does every retry, re-run, or webhook
re-delivery re-fire exactly when it should, and not duplicate when it
shouldn't? Is the re-arm gate key deterministic (HMAC/hash/UID, never
non-deterministic ciphertext)? Does the optimistic-concurrency guard travel
to the retry handler, not just the happy path? Boundaries: the *mechanism*
of optimistic concurrency (expectedVersion plumbing) is shared with Sector
02; the *billing consequence* of a missed guard is Sector 05; the *drain
safety* that makes a missed guard harmless is Sector 03.

**Paradigms.**

#### P-01-1: Pin every finalize to the claim generation with `AND attempt = $N`

A finalize (success or failure) that does not guard on the claim generation
counter can stamp a stale result onto a reclaimed row — double-bill or
orphan. The guard `WHERE … AND attempt = $N` makes a stale finalize a no-op
(`rows_affected == 0 → AlreadyFinal`).

- **Source**: `gateway.md` MINOR-1 + "Notes on the review" BLOCKER-2 no-double-billing rebuttal; playbook paradigm #6.
- **Anchor (verified)**: `feat-batch-api-gateway/src/batch/billing.rs:127` (`AND attempt = $9` in `finalize_success`); `:263` (`AND attempt = $7` in `finalize_failure`); `:140-142` / `:274-276` (`AlreadyFinal` no-op); `:594` (`finalize_success_second_call_is_noop_and_never_double_bills` test).
- **Backend**: `read ~/<provider>/worktrees/batch-api/feat-batch-api-gateway/src/batch/billing.rs:113-142` (worktree — CodeGraph main index lacks batch module); `semble_search "finalize_success AND attempt AlreadyFinal no-op"` against the gateway worktree.
- **Fix-suggestion policy**: cite `billing.rs:127` as the canonical sibling; the fix is adding `AND attempt = $N` to the unguarded UPDATE. SUGGEST ONLY.
- **Adversarial caveat**: the `0` re-assert pattern is first-create-specific; on an update-retry, the correct re-assert is the *new* version after re-read, not `0` (see P-01-4 guardrail).
- **Shared with**: S02 P-02-4 (mechanism), S03 P-03-3 (drain consequence), S05 P-05-3 (billing consequence), S10 P-10-5 (security consequence) — see M-1 (KEEP-SEPARATE, five lenses on one guard).

#### P-01-3: Key re-arm / re-delivery gates on a deterministic fingerprint, never on ciphertext

A re-arm gate keyed on non-deterministic ciphertext (random IV) will never
re-fire correctly because the key differs per call. Key on `HMAC(secret,
url)`, a hash, or an entity UID. **Guardrail (CR-1, A-1)**: before flagging
a missing dedup nonce, confirm the caller's contract requires cross-window
exactly-once (not just per-window tolerance). `triggerWebhook` deliberately
bounds replays by HMAC timestamp tolerance (±300s) + per-workflow rate limit
with no stored nonce — that is at-most-once-per-window, a valid design, not a
defect.

- **Source**: playbook convention "Deterministic idempotency fingerprint" + "Non-deterministic encryption".
- **Anchor (verified, D-2 corrected)**: `app/backend/src/controllers/automation.controller.ts:1373-1403` (`verifyWebhookSignature`, HMAC over `timestamp.body` + `timingSafeEqual`). v1's `trainingJob.controller.ts:540` is stale (now a K8s delete). `app/backend/src/libs/stringEncryption.ts:29-30` (random IV — never compare ciphertext).
- **Backend**: `semble_search "webhook signature HMAC timestamp body deterministic"` (locates the moved symbol); Serena `find_symbol` on `verifyWebhookSignature` with `relative_path="backend/src/controllers/automation.controller.ts"`; codebase-memory `search_graph name_pattern=".*encrypt.*"` on `app-backend`.
- **Fix-suggestion policy**: cite `automation.controller.ts:1373` as the canonical signing site; if a gate keys on ciphertext, suggest re-keying on `HMAC(secret, stable_input)`. SUGGEST ONLY.
- **Adversarial caveat (A-1)**: a gate is correctly absent when the contract is per-window, not cross-window. Naive application produces false positives on `triggerWebhook`.
- **Shared with**: S10 P-10-6 (signing security lens) — see M-8 (KEEP-ASPECTS: S01 keeps the deterministic-not-ciphertext half, S10 keeps the raw-body + timing-safe + replay-window half).

#### P-01-4: Carry `expectedVersion` into the retry handler, not just the happy path

A retry or edit that drops `expectedVersion` races a concurrent first-create
or update. The retry must re-assert the version that makes its intent
correct: `0` on a first-create conflict (no prior row); the *new* version
after a re-read on an update conflict. **Guardrail (A-2)**: the `0` pattern
is first-create-specific; copying it onto an update-retry creates a new bug.

- **Source**: playbook paradigm #7/#8, Agentic-tool path step 4.
- **Anchor (verified, D-4 corrected)**: `app/backend/src/controllers/<provider>Chat.libs/agenticLoop/executeTool.ts:545-587` (read `:545`, forward `:559`, re-assert `0` at `:586`); `backend/src/tools/DraftTextTool.ts:83,104` (sibling); `backend/src/services/insertNextArtifactVersion.ts:86-90` (the `ArtifactVersionConflictError` primitive). v1's `executeTool.ts:470` is stale by ~75 lines.
- **Backend**: Serena `find_symbol` on `insertNextArtifactVersion` + `find_referencing_symbols` (resolves the retry to `:545-587`, not `:470`); codebase-memory `search_graph` on `app-backend`; `semble_search "expectedVersion 0 retry conflict first create"`.
- **Fix-suggestion policy**: cite `executeTool.ts:586` as the canonical retry-re-assert; the fix is forwarding `expectedVersion` into the retry. SUGGEST ONLY.
- **Adversarial caveat (A-2)**: over-applies if the agent copies the `0` pattern onto an update-retry path; twin with S02 P-02-4 (see M-9, KEEP-SEPARATE: S01 owns the *what*, S02 owns the *how*).

#### P-01-5: Make outbound client-delivery retry backoff jittered and abort-signal-carrying

A deterministic retry formula (no jitter) produces thundering herds on
outbound webhooks. **Guardrail (A-3)**: this applies to *concurrent
client-delivery* retry (webhooks outbound), NOT to *inbound lease reclaim*
(batch re-run). The batch path deliberately spaces by lease (reaper
interval, minute-scale), which is a legitimate alternative to per-retry
jitter. Do not flag the reaper for missing `Math.random`.

- **Source**: playbook convention "Retry backoff", Webhook path step 2.
- **Anchor (verified, D-3 corrected)**: **no live anchor** — `src/jobs/trainingWebhook.job.ts:51` does not exist; no jittered client-delivery retry implementation found in `app/backend/src/jobs/` or `services/`. The convention is documented but currently unenforced in audited app code. The abort-signal-carrying half is live at `app/backend/src/controllers/<provider>Chat.libs/agenticLoop/generateCosmosImage.ts:215,225` (shared with S03 P-03-4).
- **Backend**: `semble_search "jitter backoff retry abort signal Math.random setTimeout"` across `~/<provider>/app` (the only way to locate a live implementation if one exists).
- **Fix-suggestion policy**: if an outbound retry loop lacks jitter, cite the Standard Webhooks backoff spec; do NOT cite `trainingWebhook.job.ts:51` (gone). SUGGEST ONLY.
- **Adversarial caveat (A-3)**: the reaper's lease-spacing is a valid alternative; flagging "no jitter" on lease-spaced reclaim is a false positive.
- **Shared with**: S03 P-03-4 (abort-signal leaf-forwarding) — see M-14 (KEEP-ASPECTS: S01 owns jitter + retry-loop signal, S03 owns leaf-forwarding).

#### P-01-6: A re-claim must bump `attempt` and a stale finalize must no-op

The re-arm mechanism: `claim_requests` does `attempt = br.attempt + 1` in
the `RETURNING`; `bump_transient_failure` guards `AND attempt = $4`; a stale
worker whose `attempt` doesn't match the current claim generation no-ops
because the `WHERE` matches zero rows. The `e7` test pins the crash→reclaim→
bill-once path.

- **Source**: gateway.md "Notes on the review" BLOCKER-3 MVCC rebuttal; feedback-divergences "Crash-safe exactly-once finalize".
- **Anchor (verified)**: `feat-batch-api-gateway/src/batch/store.rs:460-474` (`claim_requests` `FOR UPDATE SKIP LOCKED` + `attempt = br.attempt + 1`); `store.rs:505-524` (`bump_transient_failure` `AND attempt = $4`); `store.rs:564-580` (`reclaim_expired_leases` pure status flip); `reaper.rs:521-592` (`e7_worker_restart_reclaims_lease_and_bills_exactly_once`).
- **Backend**: `read store.rs:455-480` (worktree); `semble_search "claim_requests FOR UPDATE SKIP LOCKED attempt bump reclaim"`.
- **Fix-suggestion policy**: cite `store.rs:460-474` as the canonical re-arm increment; a re-claim that doesn't bump `attempt` is a defect. SUGGEST ONLY.
- **Adversarial caveat**: the bump is correct only if `attempt` is monotonic per claim generation; a non-monotonic counter reintroduces the race.

#### P-01-7: A symmetric pair (success + failure) must both carry the guard

`finalize_failure` originally lacked the `AND attempt` guard `finalize_success`
had (MINOR-1) — a double-reclaim could stamp `result_attempt` at the wrong
generation. The fix added `attempt: i32` param + `AND attempt = $7`,
symmetric with `finalize_success`.

- **Source**: gateway.md MINOR-1.
- **Anchor (verified)**: `billing.rs:262-263` (`AND attempt = $7`); `:127` (`AND attempt = $9` sibling); `store.rs:538` (`select_exhausted_queued` returns `attempt`).
- **Backend**: `read billing.rs:113-142` and `:255-280`; Serena `find_referencing_symbols` on `finalize_failure` (scope with `relative_path`).
- **Fix-suggestion policy**: cite the symmetric pair; a failure path without the guard its success sibling has is a defect. SUGGEST ONLY.
- **Adversarial caveat**: symmetry is the goal, not the line count; a guard that's present but wrong-shaped (e.g. `AND attempt = $N` where `$N` isn't the claim generation) is worse than missing.
- **Shared with**: M-1 (the finalize guard is the canonical multi-lens case).

*(Full S01 extract: `docs/andrea-review-sectors/sector-01-idempotency-rearm.md`)*

---

### Sector 02 — Concurrency & race conditions

**Scope.** Do concurrent transactions, claims, or pods race? MVCC count-
race vs row-disjoint claims, `FOR UPDATE SKIP LOCKED` semantics, advisory
locks (session vs xact), optimistic-concurrency guards, multi-pod
oversubscription. Boundaries: the *billing consequence* of a race is
Sector 05; the *shutdown double-run* is Sector 03; the *fairness* framing of
the per-process counter is Sector 04.

**Paradigms.**

#### P-02-1: A per-process counter is not a fleet-wide QoS signal (guardrail CR-5)

`AppState.interactive_in_flight` (a `DashMap`) is per-process; two pods each
read "quiet" and oversubscribe. The finding is the *gap* between asserted
`replicas: 1` and its enforcement, not the counter. **Guardrail (CR-5)**:
confirm the invariant is unenforced (no PDB, no CEL gate, no NetworkPolicy)
before flagging; if enforced, the in-process signal is the better QoS source.

- **Source**: gateway.md BLOCKER-3 + Rebuttal (a).
- **Anchor (verified)**: `feat-batch-api-gateway/src/batch/slots.rs:6-14` (`allowed_batch_slots` pure fn of caller counter); `worker.rs:166-171` (reads `interactive_in_flight`); `main.rs:86-87` (DashMap decl); `worker.rs:693` (`pg_try_advisory_lock(42)` session-level singleton guard).
- **Backend**: `semble_search "interactive_in_flight per-process DashMap singleton replicas 1"` (worktree); `codebase-memory trace_path mode=data_flow` from `InFlightGuard::enter` to `allowed_batch_slots` (app-backend project works; gateway does NOT — see CR-3).
- **Fix-suggestion policy**: cite `worker.rs:693` as the singleton-enforcement fix; the fix is either enforce `replicas: 1` (PDB/CEL) or add a SQL fleet clamp. SUGGEST ONLY.
- **Adversarial caveat (A-4)**: if `replicas: 1` is durably enforced, the counter is correct and a SQL clamp is dead weight.
- **Shared with**: S04 P-04-7 — see M-10 (KEEP-ASPECTS: S02 owns counter-consistency mechanism, S04 owns QoS-tier-fairness framing).

#### P-02-2: A CTE-inlined `count(*)` is not a hard cap under MVCC (guardrail CR-2)

Two concurrent transactions can read the same `count(*)` and both proceed. A
true hard cap needs `pg_advisory_xact_lock` per-deployment (the
`create_batch_capped` pattern). **Guardrail (CR-2)**: do NOT demand an
advisory lock where `FOR UPDATE SKIP LOCKED` already provides row
disjointness — that adds contention for no gain. The smell fires only on a
*count-based* cap guarded only by a CTE read.

- **Source**: gateway.md BLOCKER-3 MVCC rebuttal (verified true) + "Notes on the review" `create_batch_capped` rebuttal.
- **Anchor (verified)**: `feat-batch-api-gateway/src/batch/store.rs:201-230` (`create_batch_capped`: `pool.begin()` at `:209`, `SELECT pg_advisory_xact_lock($1, hashtext($2))` at `:211`, commit at `:228`); `store.rs:460-475` (`claim_requests` `FOR UPDATE OF br3 SKIP LOCKED` — row-disjoint, not count-disjoint).
- **Backend**: Serena `find_symbol` on `create_batch_capped` (confirms xact-lock inside `pool.begin()…tx.commit()`); `read store.rs:201-230` (worktree).
- **Fix-suggestion policy**: cite `store.rs:211` as the true-hard-cap pattern; a count-based CTE cap should be replaced with `pg_advisory_xact_lock` inside the txn. SUGGEST ONLY.
- **Adversarial caveat (A-5)**: for row-disjoint workloads, `SKIP LOCKED` IS a hard cap on double-claim of the same row; demanding an advisory lock there is a false positive.
- **Shared with**: S04 P-04-4 — see M-3 (KEEP-ASPECTS: S02 owns MVCC mechanism, S04 owns fairness-cap-reliability framing).

#### P-02-3: Name the advisory-lock class — session vs xact — and match it to the failure mode

A session-level `pg_try_advisory_lock` holds until the session ends (or
explicit release); a xact-level `pg_advisory_xact_lock` auto-releases at
commit/rollback. The session lock is correct for "only one worker runs at a
time" (singleton guard); the xact lock is correct for "this check-then-
insert is atomic" (hard cap). Mismatch produces either a busy-spin (session
lock held too long) or a non-atomic check (xact lock released too early).

- **Source**: gateway.md BLOCKER-3 (session lock fix) + `store.rs:211` (xact lock sibling).
- **Anchor (verified)**: `worker.rs:693-701` (`pg_try_advisory_lock(42)`, loser logs + returns — the no-op-not-retry that makes the session lock safe); `ponytail:` comment at `:684-685`; `store.rs:211` (xact lock).
- **Backend**: `read worker.rs:672-713` (worktree); Serena `find_symbol` on `create_batch_capped`.
- **Fix-suggestion policy**: cite the two lock classes; the fix is matching the class to the failure mode. SUGGEST ONLY.
- **Adversarial caveat**: `pg_try_advisory_lock` returns false silently; if the loser retries in a tight loop it becomes a busy-spin. The worker's `return` (not `continue`) at `:700` is what makes the session lock safe — a reviewer must confirm the loser returns, not loops.

#### P-02-4: The optimistic-concurrency guard must travel to the retry handler (twin of P-01-4)

S02 owns the *how*: does the version guard survive the conflict handler's
re-invocation? S01 owns the *what* (P-01-4: is the re-arm gate key
deterministic). Both produce different findings on the same PR. See M-9
(KEEP-SEPARATE).

- **Source**: playbook paradigm #8; gateway.md BLOCKER-3 notes.
- **Anchor (verified)**: `executeTool.ts:545-586` (retry re-asserts `expectedVersion: 0` on concurrent first-create); `insertNextArtifactVersion.ts:86-92` (the `ArtifactVersionConflictError` primitive).
- **Backend**: Serena `find_referencing_symbols` on `insertNextArtifactVersion`; `semble_search "expectedVersion 0 retry conflict first create"`.
- **Fix-suggestion policy**: cite `executeTool.ts:586`; the fix is forwarding the guard into the retry. SUGGEST ONLY.
- **Adversarial caveat**: some retries are intentionally unguarded because idempotent by construction (P-01-1 re-arm key); re-asserting a version there can dead-loop a legitimate retry.

#### P-02-5: Global FIFO starves; partition the claim by the fairness key (merged into S04)

A global `ORDER BY created_at, line_no` lets org A's 50k batch starve org B's
small batch to expiry. The fix is `ROW_NUMBER() OVER (PARTITION BY b.org
ORDER BY …)` and ordering claims by the row number. **This paradigm is
owned by Sector 04** (fairness is S04's core concern); S02 cites it, does
not restate it. See M-2 (MERGE into S04 P-04-3).

- **Source**: gateway.md MAJOR-1.
- **Anchor (verified)**: `store.rs:448-451` (`ROW_NUMBER() OVER (PARTITION BY b.org ORDER BY b.created_at, br2.line_no) AS rn`); `:472` (`ORDER BY r.rn`); `:470-471` (`ponytail:` comment).
- **Backend**: `codebase-memory trace_path mode=calls` from `worker::tick` → `claim_requests` (confirms one fairness query); `semble_search "ORDER BY created_at line_no no org partition"`.
- **Adversarial caveat**: per-org fairness is within one deployment; if one org has multiple deployments, a per-org rank can still starve across deployments; with `replicas: 1` + one org, global FIFO is correct.

#### P-02-6: Atomic multi-org claims are a cross-pod race, not a docs gap

Andrea self-flagged "atomic multi-org claim" as a docs gap, then corrected it
to BLOCKER-3 (atomicity holds within one process; across pods it's the
singleton-oversubscription race). Fold into P-02-1 / CR-5.

- **Source**: gateway.md Rebuttal (d) + Rebuttal (a).
- **Anchor**: `worker.rs:693` (advisory lock bounds oversubscription to one claimer across pods).
- **Backend**: same as P-02-1.
- **Adversarial caveat**: folding is correct only when both concerns key on the SAME physical resource; if one keys on worker process and the other on shared GPU upstream, folding hides a real second race.

*(Full S02 extract: `docs/andrea-review-sectors/sector-02-concurrency-races.md`)*

---

### Sector 03 — Graceful shutdown & drain

**Scope.** Does a new worker or async loop participate in SIGTERM drain? No
orphaned in-flight work, no double-GPU-run, abort-signal forwarded to
upstream, stop-flag threaded, handle joined with timeout. Boundaries: the
*billing consequence* of a missed drain (orphan + double-bill) is shared
with S05; the *abort-signal leaf-forwarding* is shared with S01 P-01-5.

**Paradigms.**

#### P-03-1: Thread a stop flag into every new worker or async loop

A worker spawned and bound to a `_handle` (never awaited/aborted) is dropped
mid-S3-PUT-to-finalize on SIGTERM → orphan leak + double GPU run. Thread an
`Arc<AtomicBool>` stop flag into `spawn → tick → drain_deployment`; gate
claim and loop-top on `stop.load(Ordering::SeqCst)`.

- **Source**: gateway.md BLOCKER-2.
- **Anchor (verified)**: `feat-batch-api-gateway/src/batch/worker.rs:672` (`spawn(state, clock, stop: Arc<AtomicBool>)` signature); `:77-82` (`tick` takes `stop`); `:704` (loop-top `stop.load` break); `:175` (claim gate `!stop.load` before `claim_requests`); `main.rs:329` (`batch_worker_stop = Arc::new(AtomicBool::new(false))`).
- **Backend**: `read worker.rs:672-713` (worktree); `semble_search "AtomicBool stop flag worker drain"` (worktree).
- **Fix-suggestion policy**: cite `worker.rs:672` as the canonical stop-flag-threading; the fix is adding the `stop` param + gating the loop. SUGGEST ONLY.
- **Adversarial caveat**: a stop flag that's checked only at loop-top (not inside the per-row future) still drops a row mid-PUT; the check must be at the claim gate AND the loop-top AND forwarded into the upstream I/O (P-03-4).

#### P-03-2: Await the worker handle with a bounded timeout — never drop it

After signaling stop, `tokio::time::timeout(Duration::from_secs(30), handle).await` — never let the handle go un-awaited. The timeout must be ≤ helm `terminationGracePeriodSeconds` (Sector 09 cross-link).

- **Source**: gateway.md BLOCKER-2.
- **Anchor (verified, not byte-confirmed this pass)**: `feat-batch-api-gateway/src/main.rs:378-380` (`batch_worker_stop.store(true, …); if let Some(handle) = batch_worker_handle { let _ = tokio::time::timeout(Duration::from_secs(30), handle).await; }`); `main.rs:357` (`with_graceful_shutdown(shutdown_signal())`); `:374` (`timeout(5s, metering_drain)`); `:508-517` (`shutdown_signal` handles SIGINT+SIGTERM).
- **Backend**: `read ~/<provider>/worktrees/batch-api/feat-batch-api-gateway/src/main.rs:370-385` (worktree); Serena `find_referencing_symbols` on `batch_worker_handle`.
- **Fix-suggestion policy**: cite `main.rs:378-380`; the fix is awaiting the handle with a bounded timeout. SUGGEST ONLY.
- **Adversarial caveat**: a 30s timeout that exceeds `terminationGracePeriodSeconds` (K8s default 30s) gets SIGKILLed mid-drain anyway; the timeout must be strictly less than the grace period.

#### P-03-3: No double-run on SIGTERM — drain in-flight, don't abort mid-PUT

A SIGTERM that brute-aborts a worker mid-S3-PUT-to-finalize orphans the S3
object AND re-runs the GPU on reclaim. The drain must complete the in-flight
finalize before exit. This is the drain-safety *consequence* of the
`AND attempt` guard (P-01-1): even if drain is missed, the guard makes the
stale finalize a no-op. See M-1.

- **Source**: gateway.md BLOCKER-2.
- **Anchor**: `worker.rs:66-68` (ADR 0004 PUT-before-finalize ordering invariant); `billing.rs:127` (the `AND attempt` guard that makes a missed drain harmless).
- **Backend**: `read worker.rs:60-70` + `billing.rs:113-142` (worktree).
- **Fix-suggestion policy**: cite the PUT-before-finalize ordering; the fix is draining in-flight before abort. SUGGEST ONLY.
- **Adversarial caveat**: the guard makes a missed drain harmless for billing, but the orphan S3 object still leaks until the sweep reclaims it (P-06-1) — drain is still required, not optional.

#### P-03-4: Forward the abort signal to the upstream call (shared with P-01-5)

A cancelled request should stop the upstream inference, not just the retry
loop around it. Forward `ctx.abortSignal` into the upstream `chat(…)` call.
S01 P-01-5 owns the *retry-loop* abort-signal; S03 owns the *leaf-forwarding*.
See M-14 (KEEP-ASPECTS).

- **Source**: playbook Image-generation path step 5; gateway.md Reutal (f).
- **Anchor (verified, D-5 corrected)**: `app/backend/src/controllers/<provider>Chat.libs/agenticLoop/generateCosmosImage.ts:215` (`if ctx.abortSignal?.aborted …`); `:225` (`chat(…, ctx.abortSignal, true)`); `:240-241` (retry-sleep `onAbort` clears timer); `agentAbortRegistry.ts:15-26` (`abortAgent → controller.abort()`); `saveStoppedMessage.ts:32` (`abortAll(conversation_id)`).
- **Backend**: `codegraph explore -p ~/<provider>/app "abortSignal forwarded chat upstream inference"` (app IS indexed); `semble_search "abortSignal forwarded chat upstream inference"`.
- **Fix-suggestion policy**: cite `generateCosmosImage.ts:225`; the fix is forwarding the signal into the upstream call. SUGGEST ONLY.
- **Adversarial caveat**: forwarding an abort signal into an idempotent upstream that already committed (e.g. a finalized billing row) is a no-op at best and a race at worst; the signal is for in-flight I/O only.

#### P-03-5: Prefer stdlib `AtomicBool` over a new cancellation abstraction

`tokio_util::CancellationToken` was deliberately NOT added; stdlib `AtomicBool`
is already in the codebase and sufficient for a boolean stop flag. Adding a
new abstraction for one use is YAGNI.

- **Source**: gateway.md BLOCKER-2 notes (Mateo used stdlib `AtomicBool`, already in the codebase).
- **Anchor**: `worker.rs:11` (`use std::sync::atomic::{AtomicBool, Ordering};` — no `tokio_util` import).
- **Backend**: `grep -rn "tokio_util::CancellationToken" ~/<provider>/worktrees/batch-api/feat-batch-api-gateway/src/` (confirms absence).
- **Fix-suggestion policy**: do NOT suggest `CancellationToken` unless there are ≥2 distinct cancellation scopes; cite `AtomicBool` as sufficient. SUGGEST ONLY.
- **Adversarial caveat**: if a future feature needs hierarchical cancellation (cancel this subtree but not that one), `AtomicBool` is insufficient and `CancellationToken` is justified; the paradigm is "prefer stdlib now", not "never upgrade".

#### P-03-6: Order the drain — metering before worker, worker before brute abort of reaper/sweep

Drain in dependency order: metering (5s) first, then worker (30s), then
brute-abort reaper/sweep (no stop param, `_handle` bound). Out-of-order drain
drops the worker before its metering records, losing the last billing
write.

- **Source**: gateway.md BLOCKER-2 (the `_batch_sweep_handle` brute-abort tier contrast at `main.rs:326`).
- **Anchor**: `main.rs:374` (metering 5s drain), `:378-380` (worker 30s), `:326` (`_batch_sweep_handle` — brute-abort, no stop); `reaper.rs:77` (`spawn(pool, clock)` — NO stop param).
- **Backend**: `read main.rs:320-385` (worktree).
- **Fix-suggestion policy**: cite the drain ordering; the fix is sequencing the drains. SUGGEST ONLY.
- **Adversarial caveat**: the reaper/sweep are SQL-only and idempotent (reclaim is a pure status flip); brute-aborting them is safe IF their idempotence holds. A non-idempotent reaper would need the stop flag too.

*(Full S03 extract: `docs/andrea-review-sectors/sector-03-graceful-shutdown.md`)*

---

### Sector 04 — Rate limiting & per-org fairness

**Scope.** Per-key RPM enforced on every new public route, unbounded-upload
concurrency permits, per-org queue fairness (no starvation), QoS signals
correct, two-tier slot caps, resolve-org-before-semaphore. Boundaries: the
MVCC *mechanism* of the cap is Sector 02; the *counter-correctness* is
shared with S02 P-02-1.

**Paradigms.**

#### P-04-1: Enforce per-key RPM on every new public route, after auth

`key.rate_limit_rpm` is unenforceable if a new route doesn't call
`state.rate_limiter.check(&key.id, key.rate_limit_rpm)` after auth. The
check goes AFTER auth (so unauthenticated callers don't pre-fill) and BEFORE
the work. Reuse the existing limiter; don't hand-roll.

- **Source**: gateway.md MAJOR-3.
- **Anchor (verified)**: `feat-batch-api-gateway/src/routes/batches.rs:50` (`state.rate_limiter.check(&key.id, key.rate_limit_rpm).await?` in `gate_and_auth`, covering create/list/retrieve/cancel); `files.rs:59` (upload) + `:205` (content); `rate_limit.rs:39` (`pub async fn check(&self, key_id: &str, limit_rpm: i32)`); `preflight.rs:324` (canonical sibling). App-side analog: `backend/src/services/enforceChatLimits.ts:34`.
- **Backend**: `semble_search "rate_limiter check key_id limit_rpm"` (worktree); Serena `find_referencing_symbols` on `RateLimiter::check`.
- **Fix-suggestion policy**: cite `batches.rs:50` as the canonical per-route check; a new route without it is a defect. SUGGEST ONLY.
- **Adversarial caveat**: a route that's internal-only (no public API key) doesn't need per-key RPM; over-applying to internal routes adds latency for no gain.

#### P-04-2: Bound concurrent uploads with a fail-fast permit, not a body limit

A `/v1/files` upload with no concurrency permit lets N×50MB resident with
only 64MB `DefaultBodyLimit` per request. The fix is a `Semaphore` with
`try_acquire` that fail-fast 429s after auth, before the body is read. A
body limit alone doesn't bound concurrency.

- **Source**: gateway.md MAJOR-2.
- **Anchor (verified)**: `files.rs:28` (`pub const FILE_UPLOAD_MAX_CONCURRENCY: usize = 6;`); `:53-57` (`.try_acquire().map_err(|_| GatewayError::TooManyRequests("file upload at capacity, retry later"))`); `reaper.rs:229` + `worker.rs:887` (AppState wires `file_upload_concurrency: Arc::new(Semaphore::new(FILE_UPLOAD_MAX_CONCURRENCY))`); `batches.rs:39` (`BATCH_CREATE_MAX_CONCURRENCY` sibling).
- **Backend**: `semble_search "try_acquire Semaphore file upload concurrency 429"` (worktree); Serena `find_referencing_symbols` on `FILE_UPLOAD_MAX_CONCURRENCY`.
- **Fix-suggestion policy**: cite `files.rs:53-57`; the fix is a fail-fast permit after auth. SUGGEST ONLY.
- **Adversarial caveat**: a `try_acquire` that 429s without a `Retry-After` header leaves the client to guess the backoff; the 429 should carry `Retry-After`.

#### P-04-3: Partition the claim queue by org so no org starves another to expiry (owns M-2)

A global `ORDER BY created_at` lets org A's 50k batch starve org B's small
batch to expiry on a shared deployment. The fix is `ROW_NUMBER() OVER
(PARTITION BY b.org ORDER BY …)` and ordering claims by the row number —
one query, no new state. S02 P-02-5 is the same paradigm; merged here (M-2).

- **Source**: gateway.md MAJOR-1 + "Notes on the review" correction (single window-function query, not a cursor/round-robin state machine).
- **Anchor (verified)**: `store.rs:448-451` (`ROW_NUMBER() OVER (PARTITION BY b.org ORDER BY b.created_at, br2.line_no) AS rn`); `:472` (`ORDER BY r.rn`); `:470-471` (`ponytail: next-axis` comment).
- **Backend**: `codebase-memory trace_path mode=calls` from `worker::tick` → `claim_requests` (confirms one fairness query); `semble_search "ORDER BY created_at line_no no org partition"`.
- **Fix-suggestion policy**: cite `store.rs:448-472`; the fix is the window-function partition. SUGGEST ONLY.
- **Adversarial caveat**: per-org fairness is within one deployment; if one org has multiple deployments, a per-org rank can still starve across deployments; with `replicas: 1` + one org, global FIFO is correct and the partition is dead weight.

#### P-04-4: A count-based CTE is not a hard cap under MVCC (twin of P-02-2, KEEP-ASPECTS)

S04 owns the *fairness-cap-reliability* framing: does the cap the fairness
tier relies on actually hold under concurrency? S02 P-02-2 owns the MVCC
*mechanism*. See M-3. Apply CR-2.

- **Source**: gateway.md BLOCKER-3 MVCC rebuttal + `create_batch_capped` rebuttal.
- **Anchor**: `store.rs:211` (`pg_advisory_xact_lock` in `create_batch_capped`); `worker.rs:693` (`pg_try_advisory_lock` session-level singleton); `store.rs:460-475` (`FOR UPDATE SKIP LOCKED` row-disjoint claim).
- **Backend**: Serena `find_symbol` on `create_batch_capped`; `read store.rs:201-230` (worktree).
- **Fix-suggestion policy**: cite `store.rs:211` as the true-hard-cap; a fairness cap that relies on a count-based CTE is a defect. SUGGEST ONLY.
- **Adversarial caveat**: see P-02-2 / CR-2 — do not demand an advisory lock where `SKIP LOCKED` provides row disjointness.

#### P-04-5: Resolve the org before the concurrency semaphore — no unauthenticated queue pre-fill

`resolve()` the org (auth) BEFORE the concurrency semaphore so an
unauthenticated caller cannot pre-fill the queue. The ordering is
load-bearing: resolve → semaphore → work.

- **Source**: playbook Image-generation path step 1.
- **Anchor (verified)**: `feat-batch-api-gateway/src/routes/images.rs:169` (`let resolved = resolve(&state, &headers, &request.model, start).await?` with the `:164-168` comment "Runs before the concurrency gate so unauthenticated callers can't fill the queue"); `:180` (`try_acquire_image_gen_slot` AFTER resolve); `main.rs:81` (`image_gen_pending AtomicUsize`); `config.rs:104,185` (`image_gen_max_queue_depth` default 50). Note: `images.rs` IS in the main gateway CodeGraph index (pre-existed batch), so `codegraph explore -p ~/<provider>/gateway "try_acquire_image_gen_slot"` works here.
- **Backend**: `codegraph explore -p ~/<provider>/gateway "try_acquire_image_gen_slot resolve before semaphore"` (works — `images.rs` is main-branch); `semble_search "resolve org before concurrency semaphore unauthenticated queue"`.
- **Fix-suggestion policy**: cite `images.rs:169`; the fix is moving `resolve()` before the semaphore. SUGGEST ONLY.
- **Adversarial caveat**: a route with no auth (public health check) has no org to resolve; the paradigm applies only to auth-gated routes.

#### P-04-6: A queue-depth gate must 429 immediately when full, not park waiters unbounded

A concurrency permit that parks waiters (await on the semaphore) lets the
queue grow unbounded under load. The gate should `try_acquire` and 429
immediately when full, so the client retries with backoff.

- **Source**: playbook Image-generation path step 2.
- **Anchor (verified)**: `images.rs:71` (`try_acquire_image_gen_slot` fn); `:42-55` (`PendingGuard` RAII); `:180-202` (gate + 429 arm); `config.rs:185` (`image_gen_max_queue_depth` default 50).
- **Backend**: `semble_search "try_acquire 429 queue depth full image gen slot"` (worktree); `read images.rs:42-202`.
- **Fix-suggestion policy**: cite `images.rs:180-202`; the fix is `try_acquire` + 429, not `acquire` + park. SUGGEST ONLY.
- **Adversarial caveat**: a 429 without `Retry-After` and without a `limit` header in the response violates the OpenAI rate-limit contract; the 429 should carry both.

#### P-04-7: Two-tier slot caps must account for the singleton invariant (twin of P-02-1, KEEP-ASPECTS)

S04 owns the *QoS-tier-fairness semantics*: does the two-tier cap actually
enforce fairness under the deployment topology? S02 P-02-1 owns the
*counter-consistency mechanism*. See M-10. Apply CR-5.

- **Source**: gateway.md BLOCKER-3 + Reutal (a); feedback-divergences QoS rows.
- **Anchor**: `slots.rs:6-14` (`allowed_batch_slots` two-tier); `slots.rs:17-71` (unit tests pinning the arithmetic); `worker.rs:166-170` (worker reads the counter); `worker.rs:693` (advisory lock enforces `replicas: 1`).
- **Backend**: `semble_search "allowed_batch_slots two-tier slot cap interactive_in_flight"` (worktree); `read slots.rs:1-71`.
- **Fix-suggestion policy**: cite `slots.rs:6`; the fix is either enforce `replicas: 1` or move the cap to a fleet-wide signal. SUGGEST ONLY.
- **Adversarial caveat**: see P-02-1 / CR-5 — if `replicas: 1` is durably enforced, the two-tier cap is correct.

*(Full S04 extract: `docs/andrea-review-sectors/sector-04-rate-limiting-fairness.md`)*

---

### Sector 05 — Billing & state-machine integrity

**Scope.** Same-transaction finalize (cost booked with terminal state
flip), no double-bill, terminal status always written, state-machine swap
completeness, `request_counts` serializers, half-rate metering exactly
once. Boundaries: the *idempotence guard mechanism* is shared with S01; the
*wire contract* of `request_counts` is shared with S08; the *security* of a
non-terminal row is shared with S10.

**Paradigms.**

#### P-05-1: Book cost and terminal-state flip in one transaction

`finalize_success` opens `pool.begin()`, flips the row to terminal, calls
`apply_usage_writes` (the usage_log INSERT) and `complete_batch_if_drained`,
all on the same `tx`, then `tx.commit()`. A finalize that books cost in a
separate txn from the state flip can double-bill on a crash between the two.

- **Source**: feedback-divergences "Billing conflict resolution" + "Restart-safe billing"; gateway.md BLOCKER-2 notes.
- **Anchor (verified)**: `feat-batch-api-gateway/src/batch/billing.rs:109` (`pool.begin()`); `:113-139` (flip); `:146` (`apply_usage_writes(&mut tx, …)`); `:148` (`complete_batch_if_drained(&mut tx, …)`); `:149` (`tx.commit()`); `:110` (`lock_batch`).
- **Backend**: `read billing.rs:109-149` (worktree); `codebase-memory trace_path mode=data_flow` on `apply_usage_writes` (app-backend project works; gateway does NOT — see CR-3).
- **Fix-suggestion policy**: cite `billing.rs:109-149`; the fix is moving the cost INSERT into the same txn as the state flip. SUGGEST ONLY.
- **Adversarial caveat**: a same-txn finalize that holds a `lock_batch` row lock for the whole span serializes finalize throughput; if the usage_log INSERT is slow, the lock duration becomes the bottleneck. The trade-off is correctness (same-txn) vs throughput (separate-txn + idempotence guard).

#### P-05-2: Apply the half-rate discount at exactly one site

The half-rate discount is applied exactly once, at one site
(`finalize_success`), landing identically on `batch_request.cost_usd` and
`usage_log.cost_usd`. A second application site double-discounts; a missing
site charges full price. The unit test `discount_is_exactly_half` pins it.

- **Source**: feedback-divergences "half-rate applied exactly once at one site"; gateway.md "Where you're right — half-rate applied once".
- **Anchor (verified)**: `billing.rs:112` (single discount site); `:300` (`discount_is_exactly_half` unit pin); `metering.rs:240-296` (`apply_usage_writes` shared INSERT records `usage_log.cost_usd` on the same discounted basis).
- **Backend**: `semble_search "half rate discount cost_usd usage_log finalize"` (worktree); `read billing.rs:108-135` + `metering.rs:240-296`.
- **Fix-suggestion policy**: cite `billing.rs:112`; the fix is consolidating to one discount site. SUGGEST ONLY.
- **Adversarial caveat**: a "second site" that's actually a re-derivation for display (not persistence) is not a double-discount; the paradigm fires only on persistent cost fields.

#### P-05-3: Pin every finalize to the claim generation with `AND attempt = $N` (twin of P-01-1)

S05 owns the *billing consequence*: the guard is what makes a re-run no-op,
the txn is what makes the first finalize atomic. S01 P-01-1 owns the
*gate-key shape*. See M-1 (KEEP-SEPARATE, five lenses).

- **Source**: gateway.md MINOR-1 + "Notes on the review" no-double-billing rebuttal.
- **Anchor (verified)**: `billing.rs:127` (`AND attempt = $9`); `:263` (`AND attempt = $7`); `:140-142` / `:274-276` (`AlreadyFinal` no-op); `:594` (`finalize_success_second_call_is_noop_and_never_double_bills` test); `store.rs:538` (`select_exhausted_queued` returns `attempt`).
- **Backend**: `read billing.rs:113-142` + `:255-280` (worktree); Serena `find_symbol` on `finalize_success` (scope with `relative_path="src/batch/billing.rs"`).
- **Fix-suggestion policy**: cite `billing.rs:127`; a finalize without the `AND attempt` guard can double-bill. SUGGEST ONLY.
- **Adversarial caveat**: the guard makes a stale finalize a no-op, but the orphan S3 object still leaks (P-06-1); the guard is necessary, not sufficient.

#### P-05-4: Every terminalization writes a terminal status — no non-terminal leak (twin of P-10-5)

A function that advances the state machine must write a terminal status if
its intent was terminal; a swap that leaves the row in a non-terminal state
is a leak. S10 P-10-5 owns the *security* lens (a non-terminal row a user can
act on is IDOR-adjacent). See M-5.

- **Source**: playbook convention "State-machine terminal status"; gateway.md MINOR-3.
- **Anchor (verified)**: `store.rs:805` (`SET status = 'expired', error_code = 'batch_expired'`); `store.rs:819-830` (batch-level `status='expired', expired_at, terminal_at`); `billing.rs:196-200` (`complete_batch_if_drained`); `types.rs:48-54` (`BatchStatus::is_terminal`). App sibling: `backend/src/controllers/<provider>Chat.libs/userMemory/dream/reviewActions.ts:69-74` (D-8 corrected).
- **Backend**: `read store.rs:799-835` (worktree); `semble_search "UPDATE batch SET status terminal terminal_at"`.
- **Fix-suggestion policy**: cite `store.rs:805` / `types.rs:48-54`; a state-machine swap without a terminal status is a leak. SUGGEST ONLY.
- **Adversarial caveat**: a terminal status that's written but not committed (crash before `tx.commit()`) is not a leak — the txn rolls back; the paradigm fires only on committed non-terminal rows.

#### P-05-5: Enforce budget at admission (fresh re-check), not at finalize-time grace

Budget is enforced at worker admission (`route()` fresh re-check per
row), not at finalize-time grace. A finalize-time grace lets an over-budget
batch complete and bill; admission-time enforcement rejects before the GPU
run. Post-#1347: `spent_usd` bump is unconditional (not gated on finalize
success).

- **Source**: feedback-divergences "Billing conflict resolution" (unconditional `spent_usd` bump toward #1347; budget at admission not finalize-time grace).
- **Anchor (verified)**: `feat-batch-api-gateway/src/batch/worker.rs:339-422` (fresh key + `route()` budget admission, `insufficient_budget` terminalization); `:492-517` (worker passes FULL cost, finalize applies discount); `metering.rs:240-296` (unconditional `spent_usd` bump).
- **Backend**: `semble_search "route budget admission insufficient_budget terminalization"` (worktree); `read worker.rs:339-422`.
- **Fix-suggestion policy**: cite `worker.rs:339`; the fix is moving the budget check to admission. SUGGEST ONLY.
- **Adversarial caveat**: admission-time enforcement that re-checks per row adds a DB round-trip per row; if the batch is 50k rows, that's 50k re-checks. The trade-off is correctness (no over-budget completion) vs throughput (one check per row).

#### P-05-6: `request_counts.failed` must not fold canceled/expired (twin of P-08-2, P-06-6)

`RequestCounts::from_tallies` maps `failed = errored only`; canceled/expired
count toward `total` but not `failed`. An error file is synthesized when
`failed > 0 || expired > 0`. Folding canceled/expired into `failed` breaks
the OpenAI SDK contract (`total != completed + failed`). S08 owns the
*wire* lens, S06 owns the *residency* lens. See M-4 (KEEP-SEPARATE, three
lenses).

- **Source**: gateway.md MAJOR-4; feedback-divergences "`request_counts.failed` must not fold canceled/expired".
- **Anchor (verified)**: `types.rs:99-113` (`RequestCounts::from_tallies`, `failed = errored only`); `store.rs:805` (`SET status='expired', error_code='batch_expired'`); `files.rs:288` (`SyntheticKind::Error => &["errored", "expired"]`); `batches.rs:95` (`failed > 0 || expired > 0` gate).
- **Backend**: `codebase-memory trace_path mode=data_flow` from `expire_batches` → `SyntheticKind::Error` (app-backend); `semble_search "request_counts failed expired canceled fold error_file_id"`.
- **Fix-suggestion policy**: cite `types.rs:99-113`; a fold that includes canceled/expired in `failed` is a defect. SUGGEST ONLY.
- **Adversarial caveat**: a client that displays `failed` as "anything that didn't succeed" would expect canceled/expired folded in; the OpenAI contract is the authority, not the client's display preference.

#### P-05-7: A non-terminal batch must 409 on result/error-file download (sub-aspect of P-05-4)

`file_content_inner` returns 409 Conflict if `!status.is_terminal()`. A
caller pulling a partial output file mid-run gets inconsistent state. This
is the *gate contract* sub-aspect of P-05-4.

- **Source**: gateway.md MINOR-3.
- **Anchor (verified)**: `feat-batch-api-gateway/src/routes/files.rs:216-220` (`if !status.is_terminal() { return Err(GatewayError::Conflict(…)); }`); `batches.rs:92` (`is_terminal` file-id gate, shared predicate).
- **Backend**: `semble_search "is_terminal 409 Conflict file_content_inner"` (worktree); Serena `find_referencing_symbols` on `BatchStatus::is_terminal`.
- **Fix-suggestion policy**: cite `files.rs:216-220`; a download without the `is_terminal` gate is a defect. SUGGEST ONLY.
- **Adversarial caveat**: a 409 on a batch that's `finalizing` (between last row finalize and `complete_batch_if_drained`) may be too strict; the file is complete but the batch isn't terminal. The trade-off is consistency (409) vs availability (serve the complete file).

*(Full S05 extract: `docs/andrea-review-sectors/sector-05-billing-statemachine.md`)*

---

### Sector 06 — Storage & content residency

**Scope.** Where content lives (Postgres vs S3), encryption correctness
(SSE-S3 vs app crypto), retention bounded + sweep covers orphan generations,
immutable input object + per-line ranged GET, per-env buckets + creds.
Boundaries: the *wire contract* of the error file is S08; the *billing* of
an expired batch is S05.

**Paradigms.**

#### P-06-1: Sweep must delete every generation up to the claim high-water mark, not only the committed one

A sweep that selects `WHERE result_attempt IS NOT NULL` skips the orphaned
objects the `1..=attempt` loop exists to delete — a reclaim race leaves an
orphan under an earlier generation whose finalize lost. The fix: `SELECT …
WHERE attempt > 0` (the claim high-water mark) and `for gen in 1..=attempt`
delete each generation.

- **Source**: gateway.md BLOCKER-1.
- **Anchor (verified, partial)**: `feat-batch-api-gateway/src/batch/sweep.rs:47-48` (`SELECT line_no, attempt FROM batch_request WHERE batch_id = $1 AND attempt > 0`); `:60-61` (`for (line_no, attempt) in result_rows { for gen in 1..=attempt {`); `:54-59` (rationale comment); `reaper.rs:1241` (covering test). Note: not byte-verified this pass; files confirmed to exist in worktree.
- **Backend**: `semble_search` against `~/<provider>/worktrees/batch-api/feat-batch-api-gateway` (sembles indexes on first query); `read sweep.rs:40-65` (worktree). `codegraph explore -p <worktree>` needs `codegraph init -i` first (no `.codegraph` in worktree).
- **Fix-suggestion policy**: cite `sweep.rs:47-48`; a sweep that selects only committed attempts orphans reclaim-lost generations. SUGGEST ONLY.
- **Adversarial caveat**: a `1..=attempt` loop that deletes a generation still in use (a concurrent finalize racing the sweep) can delete a live object; the sweep must run after the retention window (29d) so in-flight finalize is long-done.

#### P-06-2: `delete_idempotent` must treat `NotFound` as success and `Forbidden` as terminal-skip, not retry

A sweep `DeleteObject` that retries on `NotFound` wastes calls; one that
retries on `Forbidden` (403) loops forever on a permission it can't fix. The
fix: `Ok(()) | Err(S3Error::NotFound) => Ok(())`; `Err(S3Error::Forbidden(e))
=> { tracing::error!(…); Ok(()) }` (skip, not retry). See M-12 (shared with
S11 P-11-4 test lens, S12 P-12-7 honesty lens).

- **Source**: gateway.md BLOCKER-1 + MAJOR-7.
- **Anchor (verified, partial)**: `sweep.rs:17-26` (`delete_idempotent` match); `s3_client.rs:26-39` (`S3Error` enum: `NotFound` / `Forbidden` / `Unavailable`); `:143` / `:193` / `:214` (three `403 => Forbidden` sites); `:34` (`Forbidden(String)` variant).
- **Backend**: `read sweep.rs:10-30` + `s3_client.rs:26-40` (worktree); Serena `find_referencing_symbols` on `S3Error::Forbidden` (confirms all three match arms + sweep caller).
- **Fix-suggestion policy**: cite `sweep.rs:17-26`; a sweep that retries `Forbidden` is a defect. SUGGEST ONLY.
- **Adversarial caveat**: treating `Forbidden` as terminal-skip means a real permission regression (bucket policy revoked mid-sweep) is silently swallowed; the `tracing::error!` is the only signal. A sweep that alerts on `Forbidden` rate (not just logs) is safer.

#### P-06-3: Content lives in S3, Postgres holds metadata + object keys only

No base64 TEXT columns, no app-side crypto, no app courier hop. ADR 0004
supersedes 0002 (gateway-Postgres base64 + AES-256-GCM) and 0003 (per-org
client DBs + app courier). The gateway `s3_client.rs` module doc states the
residency invariant; SSE-S3 (`x-amz-server-side-encryption: AES256`) is the
at-rest encryption.

- **Source**: feedback-divergences ADR 0002→0003→0004; gateway.md Reutal (f).
- **Anchor (verified, partial)**: `s3_client.rs:1-9` (module doc residency invariant); `:132-134` (`x-amz-server-side-encryption: AES256`); `:67-76` (`input_key` / `result_key` shape). ADR docs: `worktrees/batch-api/docs/adr/0004-batch-content-resides-in-flashblade-s3.md`.
- **Backend**: `read s3_client.rs:1-10` (worktree); `semble_search "SSE-S3 x-amz-server-side-encryption AES256 bucket"`.
- **Fix-suggestion policy**: cite `s3_client.rs:132-134`; a new content path that stores bytes in Postgres or app-encrypts is a defect. SUGGEST ONLY.
- **Adversarial caveat**: a content path that's genuinely small (<1KB, e.g. a config blob) may be fine in Postgres; the paradigm fires on *batch content* (request/response bodies), not all bytes.

#### P-06-4: One immutable input object per upload, read by per-line ranged GET

The input is one immutable S3 object per upload; the worker reads it by
per-line `(offset, len)` ranged GET, never materializing the whole blob. A
mutability violation (appending to the input object) breaks the byte-identity
contract; a whole-blob read OOMs on large inputs.

- **Source**: feedback-divergences "one immutable S3 object + per-line (offset,len) + ranged GET"; gateway.md Reutal (f) Range guard.
- **Anchor (verified, partial)**: `s3_client.rs:59-61` (`get_range` trait); `:170-203` (impl: `len==0` short-circuit, `end=offset+len-1`, `200..=299` length-verify, `403=>Forbidden`, `404=>NotFound`); `:67-70` (`input_key` immutable per `file_id`); `worker.rs:300-319` (per-line call site).
- **Backend**: `read s3_client.rs:150-210` (worktree); `semble_search "get_range offset len ranged GET immutable input"`.
- **Fix-suggestion policy**: cite `s3_client.rs:170-203`; a content path that materializes the whole blob or mutates the input is a defect. SUGGEST ONLY.
- **Adversarial caveat**: a ranged GET that accepts only `206` (not `200..=299`) breaks on S3 implementations that return `200` for the full object on a range request; the `200..=299` guard is stronger than a literal `206` check (P-08-7).

#### P-06-5: Retention is terminal-anchored at 29 days with explicit `DeleteObject` — no object-age lifecycle

A `DeleteObject` is called explicitly for each terminal batch's objects 29
days after terminalization. No S3 object-age lifecycle rule — the sweep is
the only deletion path, so it must cover every generation (P-06-1).

- **Source**: feedback-divergences "Terminal-anchored 29-day retention; explicit DeleteObject; no object-age lifecycle".
- **Anchor (verified, partial)**: `sweep.rs:1-7` (ordering invariant + metadata-forever); `:142-146` (`DEFAULT_SWEEP_MS = 3_600_000` / `MIN_SWEEP_MS = 60_000`); `:175-180` (`BATCH_SWEEP_DISABLED` kill-switch); `s3_client.rs:62-64` (`delete` trait, idempotent); `S3Config:90-106` has no lifecycle field.
- **Backend**: `read sweep.rs:1-10, 140-185` (worktree); `semble_search "DEFAULT_SWEEP_MS BATCH_SWEEP_DISABLED DeleteObject retention"`.
- **Fix-suggestion policy**: cite `sweep.rs:1-7`; a content path that relies on an S3 lifecycle rule instead of explicit `DeleteObject` is a defect (the sweep is the auditable deletion path). SUGGEST ONLY.
- **Adversarial caveat**: an S3 lifecycle rule as a *backstop* (in case the sweep fails) is defensible; the paradigm fires only when the lifecycle rule is the *primary* deletion path, replacing the sweep.

#### P-06-6: Expired batches must produce a synthetic error file (twin of P-05-6, P-08-2)

An expired batch with no error file breaks the OpenAI SDK contract (`total
!= completed + failed` — expired rows never appear). The fix: `expire_batches`
sets `error_code = 'batch_expired'`; error-file synthesis uses `status =
ANY(['errored', 'expired'])`; `error_file_id` gate is `failed > 0 || expired
> 0`. S05 owns the lifecycle fold, S08 owns the wire reconciliation. See
M-4.

- **Source**: gateway.md MAJOR-4.
- **Anchor (verified)**: `store.rs:805` (`SET status='expired', error_code='batch_expired'`); `files.rs:288` (`SyntheticKind::Error => &["errored", "expired"]`); `files.rs:313` (`WHERE batch_id = $1 AND status = ANY($2::text[])`); `batches.rs:95` (`(counts.failed > 0 || tallies.expired > 0).then(|| error_file_id_for(&row.id))`).
- **Backend**: `codebase-memory trace_path mode=data_flow` from `expire_batches` (`store.rs:791`) → `SyntheticKind::Error` (`files.rs:286`) (app-backend project); `semble_search "batch_expired synthetic error file expired"`.
- **Fix-suggestion policy**: cite `store.rs:805` + `files.rs:288`; an expired batch with no error file is a defect. SUGGEST ONLY.
- **Adversarial caveat**: a synthetic error file for an expired batch that had zero failures (all rows canceled before expiry) may confuse the SDK client; the gate `failed > 0 || expired > 0` correctly includes pure-expiry batches.

*(Full S06 extract: `docs/andrea-review-sectors/sector-06-storage-content-residency.md`)*

---

### Sector 07 — Schema, migrations & CHECK constraints

**Scope.** V-number collision with main (Flyway `outOfOrder=false`), CHECK
constraint drop-and-re-add on enum change, `CONCURRENTLY` for indexes on
large tables, re-cut above Flyway head, partial indexes for hot paths.
Boundaries: the *cross-PR coordination* of V-number collision is S09;
S07 owns the schema-internal rule.

**Paradigms.**

#### P-07-1: Ship a partial index for every hot per-tick query predicate (owns M-7)

A query that runs every tick (`select_exhausted_queued`, every worker tick)
with a predicate on `det_failures` needs a partial index on that predicate.
The `V44__batch_api.sql` migration ships 7 partial indexes but none on
`det_failures` — a hot-path scan. S12 P-12-2 is the same paradigm; merged
here (M-7). S12 retains the `MAX_ATTEMPTS` rename (P-12-1).

- **Source**: gateway.md NIT-2 (UNADDRESSED — "no partial index on `det_failures`; cheap to add while re-cutting").
- **Anchor (verified)**: `feat-batch-api-gateway/src/batch/store.rs:538-552` (`select_exhausted_queued`: `WHERE br.status = 'queued' AND br.det_failures >= $1`); `worker.rs:93` (caller, every tick); migration `~/<provider>/worktrees/batch-api/feat-batch-api-gateway-db/migrations/V44__batch_api.sql` (defines `idx_batch_request_claim` / `idx_batch_request_lease`, zero indexes on `det_failures` — confirmed via `grep -c det_failures` = 3, all in column def + comments, no `CREATE INDEX det_failures`).
- **Backend**: `grep` / `glob` the gateway-db migrations (DDL is text, not symbol-indexed — CodeGraph/Serena/codebase-memory don't index DDL); `semble_search "CREATE INDEX det_failures"` scoped to gateway-db; `codegraph explore -p ~/<provider>/gateway` locates the query (but WORKTREE-MISMATCH — see CR-3), not the index.
- **Fix-suggestion policy**: cite `store.rs:538-552`; the fix is a `CREATE INDEX … WHERE status='queued' AND det_failures >= …` in the next migration. SUGGEST ONLY.
- **Adversarial caveat**: a partial index on a predicate that's rarely hit (most rows are not `queued`) is cheap; one on a hot predicate that's always hit is as expensive as a full index. The `queued` filter makes this a true partial index.

#### P-07-2: Re-cut migrations above main's Flyway head; V-numbers are globally unique per DB (twin of P-09-3)

V-numbers are globally unique per DB; Flyway runs `outOfOrder=false`, so a
V-number that collides with main or a concurrent PR blocks deploy. Re-cut
above main's head. S09 P-09-3 owns the *cross-PR coordination*. See M-13.

- **Source**: playbook Migration PR path step 1 + convention "Migration V-number uniqueness"; feedback-divergences "V39 unusable → V43+V44".
- **Anchor (verified)**: `~/<provider>/gateway-db/flyway.conf:5-6` (`flyway.outOfOrder=false`, `flyway.validateOnMigrate=true`); main `~/<provider>/gateway-db/migrations/` highest = `V37__org_default_budget.sql` (D-7 corrected — NOT V42); worktree `feat-batch-api-gateway-db/migrations/` highest = `V44__batch_api.sql`, with V38/V40/V41/V42/V44 present and V39/V43 missing (re-cut gaps). `git log` confirms renumber commits (`59af680`, `32fda04`).
- **Backend**: `glob ~/<provider>/gateway-db/migrations/V*.sql` + `bash git -C gateway-db log --oneline main..<branch> -- migrations/` (filesystem/git is the correct tool for DDL); `semble_search "V44 batch_api migration"`.
- **Fix-suggestion policy**: cite `flyway.conf:5`; a V-number that collides with main or a concurrent PR is a defect. SUGGEST ONLY.
- **Adversarial caveat**: re-cutting above main's head when main is advancing fast (multiple concurrent PRs) can race again; the re-cut should pick a head-room V-number (e.g. main is V37, cut at V44, not V38).

#### P-07-3: Drop-and-re-add CHECK constraints with the full expanded enum list on any enum change

A Postgres `chk_*` CHECK constraint encodes enum validity as `type IN
(ARRAY[...])`. Changing the enum without dropping and re-adding the
constraint with the full expanded list leaves the constraint validating
the old enum. `V44__skills_custom.sql:16-17` confirms the DROP+ADD pattern.

- **Source**: playbook convention "CHECK-constraint enum encoding" + Migration PR path step 2.
- **Anchor (verified)**: `app-db/migrations/V1__baseline.sql:1037` (`chk_source_type` full `ARRAY[...]` enum list); `V44__skills_custom.sql:16-17` (`DROP CONSTRAINT IF EXISTS` + `ADD CONSTRAINT`); canonical sibling `app/backend/src/controllers/<provider>Chat.libs/sharedUpload.ts:114` (`createSource` relies on `chk_source_type`).
- **Backend**: `grep "CHECK.*IN.*ARRAY" ~/<provider>/app-db/migrations/` (DDL is text); `semble_search "chk_source_type CHECK constraint ARRAY enum"`.
- **Fix-suggestion policy**: cite `V44__skills_custom.sql:16-17`; an enum change without the CHECK constraint re-add is a defect. SUGGEST ONLY.
- **Adversarial caveat`: adding a new enum value without the CHECK re-add is silently accepted by Postgres (the constraint is stale, not enforced at write time for the new value); the defect manifests only when a row with the new value fails a read-time validation. Test coverage (S11) is the backstop.

#### P-07-4: `CREATE INDEX CONCURRENTLY` for indexes on existing large tables; plain `CREATE INDEX` on fresh tables

A plain `CREATE INDEX` on a large existing table locks writes for the
duration. `CONCURRENTLY` avoids the lock but takes longer and can't run
inside a txn. On a fresh table (no rows), plain `CREATE INDEX` is correct
(no rows to lock). `V17/V19/V26/V28/V31` use `CONCURRENTLY` on populated
tables; `V44` uses plain `CREATE INDEX` on fresh batch tables (correct).

- **Source**: playbook Migration PR path step 4.
- **Anchor (verified)**: `app-db/migrations/V17/V19/V26/V28/V31` (`CONCURRENTLY` on populated tables); `V44__batch_api.sql` (plain `CREATE INDEX` on fresh batch tables — correct, no rows).
- **Backend**: `grep "CREATE INDEX CONCURRENTLY" ~/<provider>/app-db/migrations/` (DDL text); `semble_search "CREATE INDEX CONCURRENTLY populated table"`.
- **Fix-suggestion policy**: cite the V17/V19 pattern; a plain `CREATE INDEX` on a large existing table is a defect. SUGGEST ONLY.
- **Adversarial caveat**: `CONCURRENTLY` can fail and leave an invalid index (`CREATE INDEX CONCURRENTLY` is not atomic); the migration must include a `DROP INDEX IF EXISTS` before the `CONCURRENTLY` to recover from a prior failed run.

#### P-07-5: When renumbering or squashing, document the superseded pair and preserve the end state in one step

A squash that silently replaces V43+V44 with a single V44 leaves no audit
trail. The `V44__batch_api.sql:1-7` supersession header documents "Supersedes
former V43+V44 pair". Preserve the end state (the final schema) in one step;
document what was superseded.

- **Source**: feedback-divergences schema section (Andreas wanted single V44 re-cut; local split V43+V44 then squashed).
- **Anchor (verified)**: `V44__batch_api.sql:1-7` (supersession header); `git log` (`59af680` "renumber batch migrations to V43/V44", `32fda04` "squash V43/V44 into single V44").
- **Backend**: `read V44__batch_api.sql:1-10`; `bash git -C gateway-db log --oneline`.
- **Fix-suggestion policy**: cite `V44__batch_api.sql:1-7`; a squash without the supersession header is a defect. SUGGEST ONLY.
- **Adversarial caveat**: a supersession header that references a V-number that never existed on main (only on a concurrent branch) is confusing; the header should name the branch-internal V-numbers it supersedes explicitly.

*(Full S07 extract: `docs/andrea-review-sectors/sector-07-schema-migrations.md`)*

---

### Sector 08 — Wire/contract conformance

**Scope.** OpenAI-exact wire shape, `total == completed + failed` invariant,
`canceled`/`cancelled` spelling split, 4xx vs 5xx recoverability,
`request_counts.failed` folding, JSONL byte-cursor parser (CRLF, multibyte,
BOM gap), Range-ignoring-200 guard. Boundaries: the *lifecycle fold* is
shared with S05; the *residency footprint* is shared with S06; the
*non-deterministic encryption* gate-key is S01.

**Paradigms.**

#### P-08-1: Emit OpenAI-exact wire shapes the official SDK parses unchanged

The `BatchStatus` enum is the 8-term OpenAI vocab (`validating, in_progress,
finalizing, completed, failed, expired, cancelling, canceled`); the wire
types reject `json!(canceled)` for `BatchStatus` and round-trip-test the
shape. A deviation from the OpenAI wire breaks the official SDK.

- **Source**: feedback-divergences OpenAI vocab table; gateway.md MAJOR-4.
- **Anchor (verified, partial)**: `feat-batch-api-gateway/src/batch/types.rs:1-3` (file header "OpenAI-exact"); `:11-20` (`BatchStatus` 8-term enum); `:286-316` (round-trip tests); `:315` (reject `json!(canceled)`); `:8-23` (`cancelled`/`canceled` dialect docs).
- **Backend**: `read types.rs:1-23` + `:286-316` (worktree); Serena `find_symbol` on `BatchStatus`; `semble_search "BatchStatus OpenAI validating in_progress finalizing"`.
- **Fix-suggestion policy**: cite `types.rs:11-20`; a wire shape that deviates from OpenAI is a defect. SUGGEST ONLY.
- **Adversarial caveat`: a wire shape that's "better than OpenAI" (e.g. adds a field the SDK ignores) is not a defect; the paradigm fires only on shapes the SDK rejects or misparses.

#### P-08-2: An expired batch must produce an error file so `total == completed + failed` (twin of P-05-6, P-06-6)

The OpenAI SDK contract is `total == completed + failed`. An expired batch
with no error file breaks this (expired rows never appear). S05 owns the
lifecycle fold, S06 owns the residency. See M-4.

- **Source**: gateway.md MAJOR-4; feedback-divergences "`request_counts.failed` must not fold canceled/expired".
- **Anchor**: `store.rs:805`; `files.rs:288` (`SyntheticKind::Error => &["errored", "expired"]`); `files.rs:313` (`status = ANY($2::text[])`); `batches.rs:95` (`failed > 0 || expired > 0` gate).
- **Backend**: `codebase-memory trace_path mode=data_flow` from `expire_batches` → `SyntheticKind::Error` (app-backend); `semble_search "request_counts failed expired canceled fold error_file_id"`.
- **Fix-suggestion policy**: cite `batches.rs:95`; a gate that excludes expired batches from the error file is a defect. SUGGEST ONLY.
- **Adversarial caveat**: see P-05-6.

#### P-08-3: Split the `canceled`/`cancelled` dialect deliberately — batch double-L, request single-L

OpenAI uses `canceled` (single-L) for batch status and `cancelled`
(double-L) for request status. The wire types encode both deliberately;
the dialect docs at `types.rs:8-23` record the split. A "fix" that
normalizes to one spelling breaks the SDK.

- **Source**: feedback-divergences OpenAI vocab; gateway.md "First-build items Andreas praised" (OpenAI wire types including `canceled`/`cancelled` spelling split).
- **Anchor (verified, partial)**: `types.rs:8-23` (dialect docs); `:315` (reject `json!(canceled)` for `BatchStatus`).
- **Backend**: `read types.rs:8-23` (worktree); `semble_search "canceled cancelled dialect batch request status"`.
- **Fix-suggestion policy`: cite `types.rs:8-23`; a normalization that collapses the dialect is a defect. SUGGEST ONLY.
- **Adversarial caveat**: a new status value that uses the wrong dialect (e.g. `canceling` for batch when OpenAI uses `cancelling`) is a defect the paradigm should catch; confirm against the OpenAI API spec, not the codebase's current spelling.

#### P-08-4: Classify 4xx as non-recoverable and 5xx per-semantic, never blanket "retry everything ≥400"

A blanket "retry on ≥400" retries 4xx (auth failures, bad requests) that
will never succeed and wastes quota. `generateCosmosImage.ts:404-468`
classifies: 404 non-recoverable, 429 recoverable, 4xx non-recoverable, 5xx
non-recoverable with a content-safety rationale.

- **Source`: playbook Image-generation path step 3; gateway.md Reutal (f).
- **Anchor (verified, partial)**: `app/backend/src/controllers/<provider>Chat.libs/agenticLoop/generateCosmosImage.ts:404-468` (D-5 corrected — now under `agenticLoop/`).
- **Backend**: `codegraph explore -p ~/<provider>/app "generateCosmosImage 4xx 5xx recoverable"` (app IS indexed); `semble_search "4xx 5xx recoverable retry classification"`.
- **Fix-suggestion policy`: cite `generateCosmosImage.ts:404-468`; a blanket retry-on-≥400 is a defect. SUGGEST ONLY.
- **Adversarial caveat: a 429 (rate limit) is 4xx but recoverable; a 408 (timeout) is 4xx but may be recoverable; the classification is per-status, not per-class. Over-applying "all 4xx non-recoverable" misclassifies 429.

#### P-08-5: Pin the endpoint vocabulary now; widen deliberately, never by accident

The batch endpoint is `/v1/batches` (OpenAI-exact); `BATCH_ENDPOINT` const
at `batches.rs:26`; a request to a different endpoint is rejected
(`batches.rs:224-226`). Widening to `/v1/chat/batches` (Andrea's thin-v1
plan) is a deliberate scope decision, not an accident. S09 owns the
*companion-PR ordering* of endpoint vocab changes.

- **Source**: feedback-divergences "endpoint vocab widenable for embeddings later".
- **Anchor (verified, partial)**: `batches.rs:26` (`BATCH_ENDPOINT` const); `:224-226` (`endpoint != BATCH_ENDPOINT` reject).
- **Backend**: `read batches.rs:26` + `:224-226` (worktree); `semble_search "BATCH_ENDPOINT v1/batches reject"`.
- **Fix-suggestion policy`: cite `batches.rs:26`; an endpoint that accepts non-`/v1/batches` paths is a defect. SUGGEST ONLY.
- **Adversarial caveat: a new endpoint (e.g. `/v1/embeddings/batches`) is a deliberate widening, not a defect; the paradigm fires on accidental drift, not intentional extension.

#### P-08-6: A byte-cursor JSONL parser must strip a leading UTF-8 BOM (owns M-6)

A JSONL parser that strips CRLF and skips blanks but doesn't strip a
leading `\u{FEFF}` (BOM) fails line 1's JSON parse. The `parse_input`
byte-cursor at `jsonl.rs:49-85` strips CRLF (`:75-78`) and skips blanks
(`:82-84`) but has NO BOM strip (`grep` for `BOM|0xEF|\ufeff|strip_prefix`
= no matches). S12 P-12-4 is the same paradigm; merged here (M-6). S12
retains the broader "byte-cursor parser edge" framing in its cross-link.

- **Source`: gateway.md Reutal (f) ("JSONL byte-cursor rewrite holds with one gap: a leading UTF-8 BOM fails line 1 … worth a targeted fix").
- **Anchor (verified, partial)**: `feat-batch-api-gateway/src/batch/jsonl.rs:49-85` (`parse_input`); `:75-78` (CRLF strip); `:82-84` (blank skip); NO BOM strip (grep exit=1).
- **Backend`: Serena `find_symbol` on `parse_input` (confirms single parser entry point); `grep -rn "BOM|0xEF|\\\\ufeff|strip_prefix" src/batch/jsonl.rs` (confirms gap is one missing symbol).
- **Fix-suggestion policy`: cite `jsonl.rs:49-85`; the fix is `bytes.strip_prefix(b"\\xEF\\xBB\\xBF")` before the cursor loop + a test with a BOM'd input. SUGGEST ONLY.
- **Adversarial caveat: BOM'd API inputs are rare (most clients send no BOM); the cost is 1 line + 1 test; Andrea's own bar is "worth a targeted fix", not a BLOCKER. Don't over-state the severity.

#### P-08-7: A ranged GET must accept 200 AND 206 — the Range guard is stronger than a literal 206 check

An S3 ranged GET that accepts only `206` breaks on implementations that
return `200` for the full object on a range request. The `get_range` impl
accepts `200..=299` and verifies the byte-length, which is stronger than a
literal `206` check.

- **Source`: gateway.md Reutal (f) ("Range-ignoring-200 guard holds, stronger than literal 206").
- **Anchor (verified, partial)**: `s3_client.rs:182-183` (`200..=299` range guard); `:185-189` (byte-length check).
- **Backend`: `read s3_client.rs:170-210` (worktree); `semble_search "ranged GET 200 206 byte-length verify"`.
- **Fix-suggestion policy`: cite `s3_client.rs:182-183`; a ranged GET that accepts only `206` is a defect. SUGGEST ONLY.
- **Adversarial caveat: accepting `200..=299` on a ranged GET that returns `200` for a *partial* object (not the requested range) would silently serve the wrong bytes; the byte-length check at `:185-189` is the real guard, not the status range.

*(Full S08 extract: `docs/andrea-review-sectors/sector-08-wire-contract.md`)*

---

### Sector 09 — Multi-repo & deploy ordering

**Scope.** Companion PRs land as a set, migration-before-app ordering,
V-number collision across concurrent PRs, helm catalog model additions
needing compatible gateway route + app SDK, cross-repo HTTP edges, ArgoCD
deploy sequencing, CODEOWNERS gating. Boundaries: the *V-number rule* is
shared with S07; S09 owns the *coordination*.

**Paradigms.**

#### P-09-1: Land companion PRs as a set — none ready until all open and approved

A multi-repo change (app + app-db + gateway + gateway-db + helm) lands as a
set. No single PR is ready until every companion is open and approved. The
batch feature was a 5-repo coordinated set.

- **Source`: playbook Dependency Cross-Checks; `worktrees/batch-api/` 5-repo layout + `HANDOFF-sdk-backend-compat.md`.
- **Anchor (verified)**: `~/<provider>/worktrees/batch-api/` (5-repo layout: `feat-batch-api-gateway`, `feat-batch-api-gateway-db`, `feat-batch-api-app`, `feat-batch-api-app-db`, `helm`); `AGENTS.md` ("umbrella checkout, not a monorepo … separate git repos, cloned in place").
- **Backend`: `glob ~/<provider>/worktrees/batch-api/*/` (filesystem); `bash git -C <each> rev-parse --abbrev-ref HEAD` (confirms branch names).
- **Fix-suggestion policy`: cite the 5-repo set; a PR that calls itself ready while a companion is still draft is a defect. SUGGEST ONLY.
- **Adversarial caveat: a companion PR that's blocked on an unrelated issue (e.g. a CODEOWNERS vacation) shouldn't block the whole set indefinitely; the set rule is a default, not a hard gate, when one companion is genuinely independent.

#### P-09-2: Migration-before-app — the DB PR lands first, the code PR behind it

Client Flyway runs `outOfOrder=false`; a code PR that expects a new column
deployed before its migration fails at startup (`verify_schema` probe). The
DB PR lands first, the code PR behind it.

- **Source`: playbook Dependency Cross-Checks; gateway.md MAJOR-5.
- **Anchor (verified)**: `feat-batch-api-gateway/src/db.rs:54` (`verify_schema` called unconditionally at `main.rs:143`); `BATCH_PROBE_TABLES=[batch, batch_request, file]`, `BATCH_PROBE_COLUMNS=[(usage_log, batch_id)]` (the migration→code ordering contract).
- **Backend`: `codegraph explore -p ~/<provider>/gateway "verify_schema probe BATCH_PROBE_TABLES"` (worktree — WORKTREE-MISMATCH, use `read`); `semble_search "verify_schema probe migration code ordering"`.
- **Fix-suggestion policy`: cite `db.rs:54`; a code PR that lands before its migration is a defect. SUGGEST ONLY.
- **Adversarial caveat: a code PR that's backward-compatible with both the old and new schema (e.g. reads an optional column) can land before the migration; the probe is a hard gate only for required columns.

#### P-09-3: V-number collision across concurrent PRs — renumber above main's head (twin of P-07-2)

S09 owns the *coordination*: two concurrent PRs both claiming V44 collide.
S07 P-07-2 owns the *rule*. See M-13. Note D-7: main head is V37, NOT V42;
the V40-V42 collision narrative describes a prior concurrent-PR state.

- **Source`: feedback-divergences V43/V44 renumbering; app-db commit `c5a3703` (Andrea-authored renumber V49-51→V52-54).
- **Anchor (verified, D-7 corrected)**: `~/<provider>/gateway-db/migrations/` main head = `V37__org_default_budget.sql`; worktree ships V38-V44 (V39/V43 gaps); `app-db` commit `c5a3703` (2026-06-29, Andrea Moccia, "renumber SSH migrations V49-51 -> V52-54") — a live Andrea-authored V-collision renumber.
- **Backend`: `glob ~/<provider>/gateway-db/migrations/V*.sql` + `bash git -C gateway-db log --oneline`; `bash git -C app-db log --oneline | grep -i renumber`.
- **Fix-suggestion policy`: cite `app-db c5a3703` as the canonical renumber; a V-number that collides with a concurrent PR is a defect. SUGGEST ONLY.
- **Adversarial caveat: a renumber that picks a V-number too close to main's head (e.g. main V37, cut V38) races main's next merge; pick head-room (V44+).

#### P-09-4: helm catalog model additions need compatible gateway route + app SDK — opt-in-by-presence, fail-closed at render

A new helm catalog model (`helm/charts/.../<model>.yaml`) with `batch:
opt-in` requires a compatible gateway route and app SDK. The helm
`_helpers.tpl:119-165` render-time `{{- fail}}` gates couple `batch: opt-in`
with `scheduling-policy:priority` + `max-num-seqs`, so a partial opt-in
fails at render, not at runtime.

- **Source`: playbook Dependency Cross-Checks (helm↔app/gateway); AGENTS.md ("Adding a gateway model route = a helm catalog YAML entry, not gateway code. ArgoCD auto-deploys").
- **Anchor (verified)**: `helm/charts/<chart>/templates/_helpers.tpl:152,155` (render-time `{{- fail}}` gates); `helm/charts/<chart>/values.yaml` (`glm-5-2-nvfp4.yaml:36` `batch: opt-in` with `inputCap 262144`).
- **Backend`: `glob ~/<provider>/helm/charts/**/*.yaml`; `grep "batch: opt-in" ~/<provider>/helm/` (YAML — not symbol-indexed); `semble_search "helm batch opt-in scheduling-policy priority max-num-seqs"`.
- **Fix-suggestion policy`: cite `_helpers.tpl:152`; a catalog model with `batch: opt-in` but no compatible gateway route is a defect. SUGGEST ONLY.
- **Adversarial caveat: a model that's intentionally not batch-enabled (`batch: opt-in` absent) doesn't need the gateway route; the paradigm fires on opt-in models, not all models.

#### P-09-5: Cross-repo HTTP edges (gateway→app) must be confirmed via `cross_service` trace, NOT graphify union

Graphify's merged graph is a union with `repo` tags — it does NOT infer
gateway→app HTTP edges. The only backend that synthesizes real cross-repo
HTTP edges is codebase-memory's `cross-repo-intelligence` mode
(`index_repository` with `mode: "cross-repo-intelligence"`). The
gateway→app edge is `BACKEND_URL` (`config.rs:30`) → `/internal/*`
(`validate_backend_url` at `config.rs:258`); the deleted
`/internal/batch-content` courier (ADR 0004) was both a security surface and
a cross-repo dependency.

- **Source`: `_CONTEXT.md` backend 5 (graphify union-only); `AGENTS.md` codebase-intelligence section.
- **Anchor (verified)**: `feat-batch-api-gateway/src/config.rs:30` (`backend_url`); `:258` (`validate_backend_url`); `s3_client.rs:6-9` (documents deleted `/internal/batch-content` courier). codebase-memory project list confirmed: gateway NOT indexed.
- **Backend`: codebase-memory `trace_path mode=cross_service` (the ONLY backend that synthesizes cross-repo HTTP edges); NOT `graphify query` (union-only). For gateway symbols not in codebase-memory, `read config.rs:30` + `semble_search "BACKEND_URL internal batch-content courier"`.
- **Fix-suggestion policy`: cite `config.rs:30`; a new gateway→app HTTP call not confirmed via `cross_service` trace is a review gap. SUGGEST ONLY.
- **Adversarial caveat: a gateway→app edge that's internal-only (no public API) may not need the full cross-repo trace; the paradigm fires on public-surface edges, not all internal calls.

#### P-09-6: ArgoCD auto-deploys on image-yaml bump — the deploy IS the merge, review gate is CODEOWNERS

`release.sh <svc>` bumps the dev image tag; ArgoCD auto-deploys. The review
gate is CODEOWNERS: dev image files are unowned (auto-merge); UAT/prod
image files are owned by Andrea+Michael (catch-all). A promotion PR
(`release.sh promote uat|prod`) touches owned paths, so CODEOWNERS review
is required.

- **Source`: AGENTS.md; release-strategy docs; `helm/.github/CODEOWNERS`.
- **Anchor (verified)**: `helm/.github/CODEOWNERS` (dev image files unowned: `environments/dev/*-images.yaml # no owner — auto-merges`; catch-all `* @andrea-moccia_options @michael-mcmahon_options`); `docs/model-deployment.md:519` (branch protection).
- **Backend`: `read helm/.github/CODEOWNERS` (text); `bash git -C helm log --oneline -- environments/dev/` (confirms auto-merge history).
- **Fix-suggestion policy`: cite `CODEOWNERS`; a prod image bump that bypasses CODEOWNERS review is a defect. SUGGEST ONLY.
- **Adversarial caveat: a dev image bump that's unowned (auto-merge) is by design; flagging it as "needs review" misunderstands the release strategy. The paradigm fires on UAT/prod, not dev.

#### P-09-7: Ops/infra prerequisites are review-blockers, not follow-ups — name the owner (twin of P-11-6)

An infra prerequisite (live-S3 spike, bucket provisioning, per-env creds)
that's load-bearing for correctness is a merge prerequisite, not a
follow-up. Name the owner (Andrea handles infra: buckets, ranged-GET
spike). S11 P-11-6 owns the *test/spike* framing. See M-11.

- **Source`: feedback-divergences "Andreas handles infra" NOT-RUN; gateway.md Reutal (g) ("merge prerequisite, not a follow-up"); ADR 0004 bucket table.
- **Anchor (verified)**: `worktrees/batch-api/docs/prd-conformance.md` (spike marked ◻ NOT RUN); `worktrees/batch-api/docs/adr/0004-batch-content-resides-in-flashblade-s3.md` (bucket table); no live-S3 test in `feat-batch-api-gateway` (`RealS3` exercised only via `MockS3`).
- **Backend`: `agentmemory memory_recall "S3 spike merge prerequisite live dev"` (the only way to close the gate — the graph can't observe a live-endpoint run); `read prd-conformance.md` (NOT-RUN marker).
- **Fix-suggestion policy`: cite the NOT-RUN marker; an infra prereq marked NOT-RUN is a defect that blocks merge. SUGGEST ONLY.
- **Adversarial caveat: an infra prereq that's genuinely orthogonal to the code diff (e.g. bucket provisioning that's already done for dev) is not a blocker; the paradigm fires on load-bearing unverified prereqs, not all infra.

*(Full S09 extract: `docs/andrea-review-sectors/sector-09-multirepo-deploy-order.md`)*

---

### Sector 10 — SSRF, redaction & security boundaries

**Scope.** Client URLs through `validateAndPinUrl` (resolve before connect,
shared blocklist), sensitive headers in redaction allowlist, ownership-
before-discard (no IDOR), tenant isolation (cross-org → 404, no sentinel
hole), Standard Webhooks signing (Stripe-style HMAC). Boundaries: the
*terminal-status security* lens is shared with S05; the *reject-path test*
is shared with S11.

**Paradigms.**

#### P-10-1: Route every client URL through `validateAndPinUrl` (D-1 corrected)

Every client-supplied URL must route through `validateAndPinUrl` with
`resolve()` before `connect()` and a shared blocklist (so the blocklist
cannot drift). **D-1 correction**: the canonical anchor is
`app/backend/src/libs/ssrfGuard.ts:166`, NOT the playbook's stale
`clientEgress.ts:103` (that file does not exist).

- **Source`: playbook paradigm #4 + Webhook path step 4.
- **Anchor (verified)**: `app/backend/src/libs/ssrfGuard.ts:166` (`export async function validateAndPinUrl(url, opts)`); `:95-119` (`resolveAndAssertPublic`); `:32-65` (`isBlockedIP`); `:197-202` (pinned-lookup return). `find ~/<provider>/app/backend/src -name "clientEgress*"` returns NOTHING.
- **Backend`: `codegraph explore -p ~/<provider>/app "validateAndPinUrl SSRF resolve before connect"` (app IS indexed); Serena `find_symbol` on `validateAndPinUrl` with `relative_path="backend/src/libs/ssrfGuard.ts"`; `semble_search "validateAndPinUrl SSRF internal network blocklist"`.
- **Fix-suggestion policy`: cite `ssrfGuard.ts:166`; a client URL that bypasses `validateAndPinUrl` is a defect. SUGGEST ONLY.
- **Adversarial caveat: a URL that's internal-only (e.g. a health check to `localhost`) may legitimately bypass the SSRF guard if it's hardcoded, not client-supplied; the paradigm fires on client-supplied URLs, not all URLs.

#### P-10-2: Redact sensitive headers from every log path by name — allowlist, not denylist

Header logging redacts `authorization`, `cookie`, and `x-auth`-key-shaped
names via an allowlist (inbound, `app.ts:201-213`) and a regex (outbound
API calls, `apiHandler.ts:40-54`). **Two surfaces, not one.** A new
sensitive header must be added to the allowlist; a denylist drifts.

- **Source`: playbook paradigm #5 + convention "Header redaction allowlist".
- **Anchor (verified, corrected)**: `app/backend/src/app.ts:201-213` (explicit inbound allowlist); `app/backend/src/apiHandler.ts:40-54` (regex for outbound API calls). Caveat: bare `x-auth` is in NEITHER surface — only `x-.*-key`-shaped names are redacted by the regex; the playbook's "x-auth is redacted" claim is only true for `x-auth-key`-shaped names.
- **Backend`: `semble_search "header redaction authorization cookie x-auth allowlist"`; `codegraph explore -p ~/<provider>/app "logHeaderInfo redaction allowlist"`.
- **Fix-suggestion policy`: cite `app.ts:201-213`; a new sensitive header not in the allowlist is a defect. SUGGEST ONLY.
- **Adversarial caveat: a header that's sensitive in one context (e.g. `x-request-id` in a multi-tenant log) may be fine in another; the allowlist is global, so over-redaction can hide debugging signal.

#### P-10-4: Enforce tenant isolation — cross-org returns 404, no `scopedOrgId == null` sentinel hole

Every org-scoped query must return 404 (not 403) for cross-org access, and
must not have a `scopedOrgId == null` sentinel that matches all orgs. The
batch routes are tenant-isolated across all six (`cancel_batch` returns
`NotFound` for cross-org; `list_batches` scopes `WHERE b.org = $1`).

- **Source`: gateway.md "Where you're right — tenant isolation correct across all six routes".
- **Anchor (verified)**: `feat-batch-api-gateway/src/batch/store.rs:631-639` (`cancel_batch` returns `NotFound` for cross-org); `store.rs:845-873` (`list_batches` scopes `WHERE b.org = $1`); all claim/store functions take `org` parameters.
- **Backend`: `semble_search "cancel_batch NotFound cross-org tenant isolation"` (worktree); `read store.rs:625-640` (worktree).
- **Fix-suggestion policy`: cite `store.rs:631`; a cross-org query that returns 403 (not 404) or has a null-org sentinel is a defect. SUGGEST ONLY.
- **Adversarial caveat: a 403 (not 404) for cross-org is a UX choice (tells the user the resource exists but is forbidden), not a security defect; the 404 is defense-in-depth (doesn't confirm existence). The paradigm fires on the null-org sentinel, not the 403-vs-404 choice.

#### P-10-5: Ownership-before-discard — no IDOR on user-scoped rows (twin of P-05-4)

A discard/delete of a user-scoped row must check ownership first; a
discard without ownership is an IDOR. S05 owns the *state-machine*
terminal-status lens. See M-5.

- **Source`: playbook convention "Ownership-before-discard".
- **Anchor (verified, D-8 corrected)**: `app/backend/src/controllers/userMemory.controller.ts:340` (ownership before discard); `app/backend/src/controllers/<provider>Chat.libs/userMemory/dream/reviewActions.ts:69-74` (terminal + swap in one txn).
- **Backend`: `semble_search "ownership check before discard userMemory"`; Serena `find_symbol` on `discard` with `relative_path="backend/src/controllers/userMemory.controller.ts"`.
- **Fix-suggestion policy`: cite `userMemory.controller.ts:340`; a discard without an ownership check is a defect. SUGGEST ONLY.
- **Adversarial caveat: a discard that's admin-only (not user-scoped) doesn't need a user ownership check; the paradigm fires on user-scoped rows, not admin operations.

#### P-10-6: Webhook signing is Stripe-style HMAC, not literal Standard Webhooks spec (D-2 corrected, twin of P-01-3)

The live `verifyWebhookSignature` is Stripe-style HMAC
(`x-webhook-timestamp` / `x-webhook-signature: sha256=<hex>` over
`timestamp.rawBody`), NOT the literal Standard Webhooks spec
(`webhook-id`/`webhook-signature: v1,<b64>` over `id.timestamp.body`). The
security properties (raw-body HMAC, timestamp replay window, constant-time
compare) are all present and tested. **The playbook's "Standard Webhooks"
convention is aspirational, not the live implementation.** S01 P-01-3 owns
the *deterministic-not-ciphertext* half. See M-8.

- **Source`: playbook convention "Standard Webhooks signing" (aspirational); live `verifyWebhookSignature` (Stripe-style).
- **Anchor (verified, corrected)**: `app/backend/src/controllers/automation.controller.ts:1373-1403` (`verifyWebhookSignature`: `crypto.createHmac('sha256', signingSecret).update(`${timestamp}.${rawBody}`)` at `:1396`, `timingSafeEqual` at `:1366`).
- **Backend`: Serena `find_symbol` on `verifyWebhookSignature` with `relative_path`; `semble_search "webhook signature HMAC timestamp body timingSafeEqual"`.
- **Fix-suggestion policy`: cite `automation.controller.ts:1373`; a webhook trigger without signature verification is a defect. Do NOT cite the Standard Webhooks spec as the canonical shape — the live code is Stripe-style. SUGGEST ONLY.
- **Adversarial caveat: a webhook that's internal-only (no external sender) may not need signature verification; the paradigm fires on externally-triggered webhooks.

*(Full S10 extract: `docs/andrea-review-sectors/sector-10-ssrf-redaction-security.md`)*

---

### Sector 11 — Test coverage & CI gates

**Scope.** DB-backed tests must not be opt-in with no way to turn on,
reproduce-the-bug test (loses race before fix, passes after), SSRF reject
path exercised (not stubbed), workflow stands up real postgres + flyway,
unit tests for external clients (not just mock doubles), stateful failure-
matrix testing, live-S3 spike as merge prerequisite. Boundaries: the
*SSRF guard* is S10; the *residency substrate* is S06; the *billing/state-
machine invariants* the tests pin are S05.

**Paradigms.**

#### P-11-1: A DB-backed test that skips when its env var is unset must have CI that sets the env var (D-6 corrected)

A test that early-returns green when `TEST_DATABASE_URL` is unset (via
`require_pool!` → `None`) is a no-op in tag-only CI. The fix is a CI
workflow that stands up postgres + flyway + sets `TEST_DATABASE_URL` +
runs `cargo test --locked`. **D-6 correction**: the audit cites `test.yaml`
as ADDRESSED, but `test.yaml` is **absent on disk** — only `build.yaml`
(tag-only) exists in the worktree. The fix is an open action, not a
completed one.

- **Source`: gateway.md MAJOR-5.
- **Anchor (verified, D-6 corrected)**: `feat-batch-api-gateway/src/batch/testdb.rs:17` (`pool() -> Option<PgPool>`, returns `None` on unset `TEST_DATABASE_URL`); `require_pool!` macro (defined at `billing.rs:314-324`, duplicated in `store.rs:1121`, `files.rs:465`, `batches.rs:533`, `metering.rs`; 57 call sites). `~/<provider>/worktrees/batch-api/feat-batch-api-gateway/.github/workflows/` contains ONLY `build.yaml` (triggers `on: push: tags: ["[0-9]*"]` — tag-only, no `pull_request`, no `TEST_DATABASE_URL`, no `cargo test`). `test.yaml` does NOT exist.
- **Backend`: `glob "**/.github/workflows/*.y*ml"` (the decisive check); `semble_search "require_pool TEST_DATABASE_URL testdb None"` (worktree).
- **Fix-suggestion policy`: cite `testdb.rs:17` + the absent `test.yaml`; a DB-backed test suite with no CI to run it is a defect. SUGGEST ONLY.
- **Adversarial caveat: a test that's genuinely unit-only (no DB) doesn't need the workflow; the paradigm fires on DB-backed tests, not all tests. Over-applying to unit tests adds CI cost for no gain.

#### P-11-2: A fix PR must ship a test that loses the race before the fix, passes after

A fix without a test that reproduces the bug is unverifiable; a regression
ships green. The `e7_worker_restart_reclaims_lease_and_bills_exactly_once`
test at `reaper.rs:521` pins the crash→reclaim→bill-once path. (D-5: S11
cites e7 by conformance-matrix row; S01 cites it by `reaper.rs:521`
file:line — the file:line is stronger.)

- **Source`: playbook paradigm #2; gateway.md MAJOR-5.
- **Anchor (verified, D-5 strengthened)**: `feat-batch-api-gateway/src/batch/reaper.rs:521-592` (`e7_worker_restart_reclaims_lease_and_bills_exactly_once`); `billing.rs:594` (`finalize_success_second_call_is_noop_and_never_double_bills` — a different test, correctly cited by S05).
- **Backend`: `grep` for `e7_worker_restart_reclaims_lease` in the gateway worktree (resolves to `reaper.rs:521`); `semble_search "e7 worker restart reclaims lease bills once"`.
- **Fix-suggestion policy`: cite `reaper.rs:521`; a fix PR without a reproduce-the-bug test is a defect. SUGGEST ONLY.
- **Adversarial caveat: a fix for a flaky race that can't be deterministically reproduced (e.g. a timing-dependent OS race) may ship with a stress-test instead of a deterministic one; the paradigm fires on deterministically-reproducible bugs, not all bugs.

#### P-11-3: A security reject path must be exercised with a real reject, not stubbed to always resolve (D-1 corrected)

A test that stubs `validateAndPinUrl` to always resolve doesn't exercise the
SSRF reject path. The `trainingWebhook.job.test.ts:408` test #14
(`'an SSRF-rejected URL does not POST'`) uses
`mockValidate.mockRejectedValueOnce` + asserts `mockSend` was NOT called.
**D-1 correction**: the SSRF guard is `ssrfGuard.ts:166`, not `clientEgress.ts:103`. The test file is in a SEPARATE worktree (`worktrees/training-webhooks/app/backend/`), not the batch-api worktree.

- **Source`: playbook Webhook path step 5.
- **Anchor (verified, corrected)**: `~/<provider>/worktrees/training-webhooks/app/backend/src/jobs/__tests__/trainingWebhook.job.test.ts:408` (`'an SSRF-rejected URL does not POST'`, `mockValidate.mockRejectedValueOnce` + `expect(mockSend).not.toHaveBeenCalled`); real guard at `app/backend/src/libs/ssrfGuard.ts:166`.
- **Backend`: `semble_search repo=~/<provider>/worktrees/training-webhooks/app/backend "SSRF reject mockValidate mockRejectedValueOnce"`; Serena `find_referencing_symbols` on `validateAndPinUrl` (confirms S10 guard and S11 test cite the same symbol).
- **Fix-suggestion policy`: cite `trainingWebhook.job.test.ts:408`; a security reject path test that stubs the guard to always resolve is a defect. SUGGEST ONLY.
- **Adversarial caveat: a test that mocks the guard to reject doesn't exercise the real guard's blocklist; a stronger test uses a real blocked IP. The paradigm fires on "stubbed to always resolve", not on "mocked to reject" (the latter is weaker but not wrong).

#### P-11-4: A new external client needs unit tests for real signing/range/error-mapping, not just mock doubles (twin of P-06-2, P-12-7)

`s3_client.rs` (246 lines) has 0 `#[test]`/`#[tokio::test]`; the real
signing/range/error-mapping paths in `RealS3` are exercised only by
`MockS3` doubles. A regression in the real client ships green. S06 owns the
*residency* lens, S12 owns the *honesty* lens. See M-12.

- **Source`: gateway.md MAJOR-7.
- **Anchor (verified)**: `feat-batch-api-gateway/src/batch/s3_client.rs` (246 lines, 0 tests); `mock_s3.rs` (the only exerciser).
- **Backend`: `grep -c "#\\[test\\]\\|#\\[tokio::test\\]" src/batch/s3_client.rs` (confirms 0); `semble_search "s3_client RealS3 signing range error mapping test"`.
- **Fix-suggestion policy`: cite `s3_client.rs`; a new external client with only mock-double tests is a defect. SUGGEST ONLY.
- **Adversarial caveat: a real-S3 unit test needs S3 credentials in CI (or a local S3 emulator like `minio`); the cost is CI complexity. The trade-off is test fidelity (real S3) vs CI simplicity (mock only).

#### P-11-5: Stateful failure modes (restart, budget exhaustion, cancel race, expiry) must be a failure-matrix test set

A happy-path-only test suite misses the stateful failure modes. The
conformance matrix E-tests (`e7` restart, `e8` budget, `e9` cancel race,
`e10` expiry) are the named failure-matrix set.

- **Source`: feedback-divergences "Stateful failure-matrix testing (restart, budget exhaustion, cancel race, expiry) ✅ Conformance matrix E-tests".
- **Anchor (verified)**: `~/<provider>/worktrees/batch-api/docs/prd-conformance.md:134` (e7/e8/e9/e10 E-tests confirmed).
- **Backend`: `read prd-conformance.md` (the matrix); `grep "e7\\|e8\\|e9\\|e10" ~/<provider>/worktrees/batch-api/feat-batch-api-gateway/src/batch/`.
- **Fix-suggestion policy`: cite the conformance matrix; a new stateful feature without a failure-matrix test is a defect. SUGGEST ONLY.
- **Adversarial caveat: a failure-matrix test that's marked "expected to fail" (xtest) is not a real test; it's a documented gap. The paradigm fires on missing tests, not xtests.

#### P-11-6: A live spike against a real external dependency is a merge prerequisite, not a follow-up (twin of P-09-7)

A new external dependency load-bearing for correctness must be exercised
against the live service before merge. The S3 spike (SSE-S3 PUT, ranged GET
on SSE-S3, path-style + SigV4, scoped-key-with-delete-denied) is a merge
prerequisite; deferring it contradicts Andrea's stated bar. S09 owns the
*owner-naming* framing. See M-11.

- **Source`: gateway.md MAJOR-7 + Reutal (g).
- **Anchor (verified)**: `worktrees/batch-api/docs/prd-conformance.md` (spike marked ◻ NOT RUN); no live-S3 test in `feat-batch-api-gateway` (`RealS3` only via `MockS3`).
- **Backend`: `agentmemory memory_recall "S3 spike merge prerequisite live dev"`; `read prd-conformance.md` (NOT-RUN marker).
- **Fix-suggestion policy`: cite the NOT-RUN marker; a load-bearing external dependency without a live spike is a merge-blocking defect. SUGGEST ONLY.
- **Adversarial caveat: a spike that's genuinely exploratory (not load-bearing) can be a follow-up; the paradigm fires on load-bearing dependencies, not all external calls.

*(Full S11 extract: `docs/andrea-review-sectors/sector-11-testing-ci-gates.md`)*

---

### Sector 12 — Code smell, naming & correctness-detail

**Scope.** Misleading constant names, missing partial indexes, repeated
re-stamp, BOM gap, `Utc::now()` vs injected clock, `Instant::now()` as
stopwatch (fine) vs decision input (not fine), silent NIT drops, misleading
"one-line fix" claims. Boundaries: the *partial index* is shared with S07
(owns the DDL); the *BOM gap* is shared with S08 (owns the wire/parser
contract); the *403 "one-line fix" honesty* is shared with S06/S11.

**Paradigms.**

#### P-12-1: Rename a constant whose name lies about what it caps

`MAX_ATTEMPTS` is compared against `det_failures`, not `attempt` — the name
reads like it caps `attempt`. Rename to `MAX_DET_FAILURES`. (UNADDRESSED —
silently dropped without rationale; a finding, not a decision.)

- **Source`: gateway.md NIT-1.
- **Anchor (verified)**: `feat-batch-api-gateway/src/batch/worker.rs:41` (`const MAX_ATTEMPTS: i32 = 3;` with doc comment `:37-40` explaining it keys on `det_failures`); `:93` (`select_exhausted_queued(&state.pool, MAX_ATTEMPTS, …)`); `store.rs:549` (`WHERE br.det_failures >= $1`); `V44__batch_api.sql:143-150` (schema doc confirms cap keys on `det_failures`).
- **Backend`: `read worker.rs:37-41` + `:93` (worktree); `read store.rs:545-555`; Serena `find_referencing_symbols` on `MAX_ATTEMPTS` (scope with `relative_path`).
- **Fix-suggestion policy`: cite `worker.rs:41`; a constant name that lies about what it caps is a defect. SUGGEST ONLY.
- **Adversarial caveat: the rename is module-private; the doc comment partially compensates. Over-inflating a one-line rename to a MAJOR is severity inflation; it's a NIT.

#### P-12-2: Partial index for hot-path predicate — owned by S07 (M-7)

S12 retains the *hot-path predicate / cheap-while-re-cutting* framing; S07
P-07-1 owns the *migration/DDL* paradigm. See M-7.

- **Source`: gateway.md NIT-2.
- **Anchor**: `store.rs:538-552`; `V44__batch_api.sql` (no `det_failures` index).
- **Backend`: `grep`/`glob` the gateway-db migrations.
- **Adversarial caveat: the backstop query is rarely hit in steady state; the index could be premature on small fleets — exactly why the decision should be RECORDED, not silently dropped.

#### P-12-3: Stamp-once — guard idempotent timestamp writes against re-stamp

A repeated `cancel` re-stamps `cancelling_at` on every call; harmless (no
reader) but stamp-once is more correct. The canonical sibling is the
`AND attempt` guard in `finalize_success`/`finalize_failure`. (UNADDRESSED —
silently dropped.)

- **Source`: gateway.md NIT-3.
- **Anchor (verified)**: `feat-batch-api-gateway/src/batch/store.rs:668-671` (`UPDATE batch SET status = 'cancelling', cancelling_at = $2 WHERE id = $1` — no guard against an already-`cancelling` batch re-stamping); `store.rs:608-640` (`cancel_batch` checks `AlreadyTerminal` but a second cancel on a `cancelling` batch re-stamps); canonical sibling `billing.rs:127`/`:263` (`AND attempt` guard).
- **Backend`: `read store.rs:608-671` (worktree); `semble_search "cancel_batch cancelling_at re-stamp idempotent"`.
- **Fix-suggestion policy`: cite `store.rs:668-671`; an idempotent timestamp write without a re-stamp guard is a NIT. SUGGEST ONLY.
- **Adversarial caveat: the reaper keys on `status`, not `cancelling_at`, so the re-stamp is harmless; over-stating as a MAJOR is severity inflation. It's a NIT.

#### P-12-4: BOM gap — owned by S08 (M-6)

S12 retains the broader "byte-cursor parser edge" framing in its cross-link;
S08 P-08-6 owns the wire/parser-conformance paradigm. See M-6.

#### P-12-5: Inject the clock into every route that stamps lifecycle or money timestamps (DECIDED-NOT-ACTIONED — CR-4)

A route that stamps `expires_at` or `cancelling_at` via `Utc::now()` can't
be driven on a `ManualClock`, so the create-to-expire path can't be tested.
The money path (expiry decision) is in the reaper, already clock-injected.
**CR-4**: this is DECIDED-NOT-ACTIONED with a rationale (AppState has no
clock field; plumbing is ~10 lines across 6 files for a trivial calc) — a
decision, not a finding. Do not re-raise unless the rationale no longer
holds.

- **Source`: gateway.md MINOR-4.
- **Anchor (verified)**: `feat-batch-api-gateway/src/routes/batches.rs:238` (`let now = Utc::now().trunc_subsecs(6);` in create → feeds `expires_at`); `:518` (cancel → feeds `cancelling_at`); `src/main.rs:48-101` (AppState has NO clock field); `worker.rs:672`/`reaper.rs:77`/`sweep.rs:154` (clock is a separate spawn param, not an AppState field); `clock.rs` (`Clock` trait, `ManualClock`).
- **Backend`: `grep -rn "Utc::now()" ~/<provider>/worktrees/batch-api/feat-batch-api-gateway/src/routes/` (the smell); `read worker.rs:672` (clock-as-spawn-param shape).
- **Fix-suggestion policy`: cite `batches.rs:238`; the fix is plumbing a clock field into AppState. **Do NOT raise as a finding** (CR-4 — DECIDED-NOT-ACTIONED with rationale) unless a new route stamps a lifecycle/money timestamp. SUGGEST ONLY on re-raise.
- **Adversarial caveat (over-application)**: the paradigm MUST scope to lifecycle/money WRITE timestamps, not read-only `Utc::now()` defaults. Over-application to read-only uses produces a false-positive pile.

#### P-12-6: Don't flag a latency stopwatch as a missing-clock smell (negative paradigm)

`Instant::now()` at `worker.rs:382` is a latency stopwatch feeding
`preflight::route`, not a decision input; it doesn't need the injected
clock. Andrea retracted the mixed-clock-usage flag here. **Negative
paradigm**: only wrong if a future refactor makes the `Instant` also feed a
wall-clock decision — must re-trace on every `preflight::route` signature
change.

- **Source`: gateway.md "Where you're right — worker.rs:382 Instant::now() is fine".
- **Anchor (verified)**: `worker.rs:398` (`Instant::now()` feeds `preflight::route`); `:377` (`clock.now()` is the decision input); `preflight.rs:57-59` (`ms()` consumes via `.elapsed()` only).
- **Backend`: `read worker.rs:377-400` + `preflight.rs:57-59` (worktree).
- **Fix-suggestion policy`: do NOT flag `Instant::now()` as a missing-clock smell when it's a latency stopwatch. SUGGEST ONLY on re-trace if the signature changes.
- **Adversarial caveat: a negative paradigm is fragile — a refactor that feeds the `Instant` into a wall-clock decision silently invalidates it; the re-trace rule is the guard.

#### P-12-7: Don't call a multi-file behavior change a "one-line fix" (twin of P-06-2, P-11-4)

The "one-line 403 fix" was ~15 lines across 3 files (`s3_client.rs:34`
variant + `:143`/`:193`/`:214` three match arms + `sweep.rs:20-22` caller +
worker/route caller updates). Calling it "one line" under-estimates the diff
and leaves match arms un-fixed. S06 owns the *residency* lens, S11 owns the
*test* lens. See M-12.

- **Source`: gateway.md "Notes on the review — MAJOR-7 one-line 403 fix is ~15 lines across 3 files".
- **Anchor (verified, partial)**: `s3_client.rs:34` (variant) + `:143`/`:193`/`:214` (three match arms) + `sweep.rs:20-22` (sweep caller) + worker/route caller updates.
- **Backend`: `read s3_client.rs:26-40` + `:140-220` + `sweep.rs:17-26` (worktree); Serena `find_implementations` on `S3Error::Forbidden` (confirms all match arms).
- **Fix-suggestion policy`: cite the full blast radius; a "one-line fix" that's multi-file is a review-honesty defect. SUGGEST ONLY.
- **Adversarial caveat: a fix that's genuinely one line (e.g. a missing `?` on a `Result`) IS one line; the paradigm fires on under-estimated multi-file changes, not all small fixes.

*(Full S12 extract: `docs/andrea-review-sectors/sector-12-codesmell-naming.md`)*

---

## Dependency Cross-Checks (companion PRs) — retained from v1, grounded

Andrea cross-references these pairs on almost every multi-repo change
(see Sector 09 for the full paradigm set):

- `app-db` ↔ `app` — migration lands first; client Flyway `outOfOrder=false` enforces order. Anchor: `flyway.conf:5`; `verify_schema` probe at `feat-batch-api-gateway/src/db.rs:54`.
- `gateway-db` ↔ `gateway` — same pattern, enforce sequence. Anchor: `gateway-db/flyway.conf:5`; main head `V37` (D-7 corrected).
- `helm` ↔ `app` / `gateway` — catalog model additions need compatible gateway route + app SDK. Anchor: `helm/charts/<chart>/templates/_helpers.tpl:152,155` (render-time `{{- fail}}` gates); `docs/model-deployment.md`.
- Multi-repo PRs land as a set; verify every companion PR is open and approved before calling any one ready. Anchor: `worktrees/batch-api/` 5-repo layout.

Cross-repo HTTP edges (gateway→app) must be confirmed via codebase-memory
`trace_path mode=cross_service`, NOT graphify union (which is union-only,
no inferred edges). The gateway project is NOT in codebase-memory's default
index — use `read` + `semble` for gateway symbols (CR-3).

---

## Codebase-intelligence backend binding (summary)

Every paradigm names its backend. This is the consolidated binding; the
per-paradigm entries above have the exact query shapes.

| Backend | When | Canonical query | Worktree caveat |
|---|---|---|---|
| **CodeGraph** (CLI) | Verbatim source + call paths, "show me the sibling that does X right" | `codegraph explore -p ~/<provider>/<repo> "<question>"` | `~/<provider>/gateway/.codegraph` is main-branch (no batch module); batch code lives in `worktrees/batch-api/feat-batch-api-gateway/` which has no `.codegraph` — use `read` or `semble` for batch symbols (CR-3) |
| **Semble** (MCP) | Vague natural-language lookup, "where is X done?", finding code similar to a location | `semble_search "<description>"` or `semble_find_related` | For worktree code, `semble_search repo=~/<provider>/worktrees/batch-api/feat-batch-api-gateway`; semble indexes on first query and caches |
| **Serena** (MCP) | Symbol-level: confirm a symbol exists, find references, safe rename/delete, diagnostics | `find_symbol` (scope with `relative_path` to avoid 30s timeout on large trees), `find_referencing_symbols`, `find_implementations` | Unscoped `find_symbol` on `app/` times out; always scope with `relative_path` |
| **codebase-memory** (MCP) | Multi-hop call chains, cross-service HTTP edges, complexity metrics, Cypher queries | `search_graph` (BM25/name_pattern/semantic), `trace_path` (calls/data_flow/**cross_service**), `query_graph` (Cypher) | **gateway project NOT indexed** — only `app`, `app-backend`, `app-client`, `helm`, `operator`, `<provider>-python`, `e2e`. For gateway symbols, use `read`/`semble`. `cross_service` is the ONLY way to get real cross-repo HTTP edges (graphify union doesn't infer them) |
| **graphify** (CLI) | Community detection, god nodes, broad "what's in this codebase" map, semantic doc↔code hyperedges | `graphify query "<q>"` (merged at root) or `--graph ./<repo>/graphify-out/graph.json` (per-repo) | Merge is union-only with `repo` tags — does NOT infer cross-repo edges. For cross-repo, use codebase-memory `cross-repo-intelligence` |
| **agentmemory** (MCP) | Past-session decisions, "did we already decide X", deferral rationales | `memory_smart_search` (preferred), `memory_recall` | Search before re-deriving; dedup before saving. The canonical way to check whether a deferral (CR-4) or infra prereq (P-09-7) was already decided |

**Re-grounding order for a stale anchor (CR-1):** `semble_search "<symbol> <feature>"` → Serena `find_symbol` with `relative_path` → `read` the resolved `file:line`.

**Never auto-commit (CR-6).** The backends locate defects, confirm
conventions, and name siblings — they never apply patches. Every finding's
`suggested_fix` is the patch *shape*, not the patch. The PR author owns
every fix. This holds even for one-line fixes (which are often 15-line
multi-file changes — P-12-7).

---

## Appendices

- **12 sector extracts**: `docs/andrea-review-sectors/sector-01-*.md` … `sector-12-*.md` (~330KB total; 77 paradigms before dedup).
- **3 synthesis artifacts**: `docs/andrea-review-sectors/_synthesis-dedup.md` (15 merge groups, 36 orphans, 5 drift findings), `_synthesis-validation.md` (27 paradigms re-verified, 14 YES / 9 PARTIAL / 4 NO-or-STALE, 4 systemic gaps), `_synthesis-adversarial.md` (77 paradigms scored on 4 axes, 48 high-risk, 29 robust, 0 KILL, 6 cross-cutting guardrails).
- **Source documents**: `docs/andrea-review-playbook.md` (v1), `worktrees/batch-api/docs/resolve-code-review/gateway.md` (PR #94 audit), `worktrees/batch-api/docs/feedback-divergences.md` (#973 design review).
- **Shared worker context**: `docs/andrea-review-sectors/_CONTEXT.md` (the 12-sector partition, 6 backends, output contract, hard rules — the dispatch contract for the agent swarm).

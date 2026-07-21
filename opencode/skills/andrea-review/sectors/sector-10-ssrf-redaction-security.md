# Sector 10 — SSRF, redaction & security boundaries

## Scope

This sector owns the security *boundaries* Andrea checks at every trust
frontier: outbound egress from user-supplied URLs, secrets in logs, the
ownership gate that turns a row delete from an IDOR into a 404, tenant
isolation across orgs (no `scopedOrgId == null` sentinel hole), and the
webhook signature that separates an authenticated delivery from a forged
one. The question it asks of every PR: **does every new code path that
crosses a trust boundary route through the shared guard, or did the
author hand-roll a thinner one?** It deliberately does NOT own the
*correctness* of the state machine (double-billing, same-txn finalize —
Sector 05), the *migration* shape of CHECK constraints (Sector 07), or the
*test* coverage gate (Sector 11). Where a terminal-status write is both a
correctness and a security boundary, this sector owns the security lens
(a non-terminal row a user can still act on is an IDOR-adjacent leak) and
flags the Sector 05 overlap.

## Paradigms

### P-10-1: Route every client-supplied URL through `validateAndPinUrl` — resolve before pin, pin before connect

**Paradigm statement** — Any code path that issues an outbound HTTP
request to a user-configured URL (automation HTTP steps, `api` chat
sources, webhook delivery targets, web-fetch tools) MUST route through
the shared `validateAndPinUrl` guard. The guard resolves DNS once,
asserts every resolved record is public, and returns a pinned `lookup`
callback that axios connects to — closing the DNS-rebinding TOCTOU race
where a record flips between validate-time and connect-time. A caller
that validates-then-lets-axios-re-resolve, or that hand-rolls its own
blocklist, is an open proxy.

**Source evidence** — `playbook` paradigm #4 ("SSRF. Do client-supplied
URLs route through `clientEgress` with `validateAndPinUrl`?") and
convention "SSRF isolation": *"Client URLs route through `clientEgress`
`validateAndPinUrl` with `resolve()` before `connect()`; shared guard so
the blocklist cannot drift."* Critical path Webhook step 4 names the same
file. `playbook` line 11 also names `validateAndPinUrl` as the canonical
sibling ("Find sibling code that does it right").

**<Provider> infra anchor** — `backend/src/libs/ssrfGuard.ts:166`
(`validateAndPinUrl`), with `resolveAndAssertPublic` at `:95-119`
(resolve-once, assert-all-records-public, return vetted records),
`isBlockedIP` at `:32-65` (RFC1918/loopback/link-local/CGNAT/0.x/ULA +
cloud-metadata 169.254.169.254 + Alibaba ECS 100.100.100.200), and the
pinned-`lookup` return at `:197-202` (`const lookup: PinnedLookup =
async () => pinned`). The DNS-rebinding race is documented inline at
`:158-163`: *"validateUrlNotInternal resolves once and axios would
resolve again at connect time, so a record that flips between the two
lookups could still reach a private IP."* Callers confirmed:
`WebFetchTool.ts:46` (`await validateAndPinUrl(url)`),
`AutomationExecutor.ts:459` and `:554` (`const { lookup } = await
validateAndPinUrl(resolvedUrl)`), and the `apiHandler` chat-source path
referenced in the codegraph blast-radius. The blocklist is shared
across all callers — `isBlockedIP` / `isLoopbackOrLinkLocal` are the
single implementation, so the blocklist cannot drift between callers
(the file header at `:3-7` states this invariant: *"Keep this the single
implementation so the blocklist can't drift between callers."*).
`allowPrivate` (`:172-193`) is the operator-allowlist escape hatch for
legitimate internal egress, but loopback/metadata/0.0.0.0/8 stay blocked
even there.

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/app "validateAndPinUrl SSRF resolve before connect"`
> → blast-radius lists all 8 callers; confirm a new egress path is among
> them or is missing the guard.
> Serena `find_symbol` on `validateAndPinUrl` to locate the def; then
> `find_referencing_symbols` to enumerate every caller — a new outbound
> HTTP path NOT in this set is the finding.
> `semble_search "axios.get user url outbound egress"` to catch a
> hand-rolled fetch that bypassed the named-symbol search.

**Fix-suggestion policy** —
> SUGGEST ONLY: open a finding on the PR naming the unguarded egress
> path; cite the canonical sibling (`validateAndPinUrl` at
> `ssrfGuard.ts:166`) and show the one-line wiring (`axios({ url, lookup:
> (await validateAndPinUrl(url)).lookup })`). Do NOT commit a patch —
> the PR author owns the fix and must decide whether `allowPrivate` is
> warranted (operator-allowlisted internal host).

**Adversarial caveat** — The guard validates the *hostname's* resolved
records, not the redirect chain. A public host that 302s to an internal
IP is caught only if the caller re-validates after each redirect
(`WebFetchTool.ts:5-8` notes websearchmcp "re-checks and handles
redirect re-validation server-side" — but `AutomationExecutor`'s axios
call has no documented redirect re-validation). A finding that demands
`validateAndPinUrl` on the initial URL only is necessary but not
sufficient if the upstream follows redirects.

### P-10-2: Redact sensitive headers from every log path by name — allowlist, not denylist

**Paradigm statement** — Any code path that dumps request headers to a
log (debug request logging, outbound API-call logging, service-alert
middleware) MUST redact by name before emission. Two complementary
shapes exist: an explicit header allowlist for the inbound request log,
and a name-regex redactor for outbound API-call headers/params. A new
sensitive header added to a log without joining either redaction surface
leaks a credential to the central pipeline. Andrea's rule: the redaction
list is an allowlist of *what to redact*, extended whenever a new secret
header appears — never a "log everything, filter later" posture.

**Source evidence** — `playbook` review paradigm "Check redaction. New
sensitive headers added to logs must be in the redaction allowlist."
Convention "Header redaction allowlist": *"Debug request-header logging
redacts `authorization`, `cookie`, `x-auth`; new sensitive headers must
be added to the allowlist."*

**<Provider> infra anchor** — Two redaction surfaces:
(1) `backend/src/app.ts:201-213` — the inbound request-log redaction
allowlist, an explicit array: `['x-admin-secret', 'authorization',
'proxy-authorization', 'cookie', 'portal-access', 'portal-access-token',
'portal-token']`, each overwritten to `'[redacted]'` when
`DEBUG === 'true'`. The comment at `:197-199` names the threat model:
*"Redact high-value shared secrets before dumping request headers. The
pmSession cookie and the Olympus portal tokens are the app's real
session credentials."*
(2) `backend/src/controllers/<provider>Chat.libs/apiHandler.ts:40-54`
— `SECRET_KEY_RE = /(authorization|api[-_]?key|token|secret|cookie|password|x-.*-key)/i`
applied by `redactSecretKeys` to outbound API-call headers AND params
before they reach the request log. The comment at `:37-39`: *"Redact by
NAME so the request log can't leak any of them to the central pipeline,
not just the one auth field this handler configured."* A third surface,
`insertServiceAlertMiddleware.ts:58-67`, redacts via
`SENSITIVE_KEY_PATTERN` for service-alert payloads. The test at
`apiHandler.test.ts:503-506` pins the contract: `Authorization`,
`X-Custom-Key`, `Cookie`, and `params.api_key` all surface as
`'<redacted>'`.

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/app "header redaction allowlist authorization cookie x-auth log"`
> → blast-radius names `logHeaderInfo`, `redactSecretKeys`,
> `RestEgressAllowlist`; a new header-logging path NOT routing through
> one of these is the finding.
> `semble_search "console.info headers request log debug"` to catch an
> ad-hoc `console.info(req.headers)` that bypassed the named redactor.
> Serena `find_referencing_symbols` on `redactSecretKeys` to enumerate
> every caller — a new API-call logger missing it leaks secrets.

**Fix-suggestion policy** —
> SUGGEST ONLY: open a finding naming the unredacted header-logging
> site; cite the canonical sibling (`app.ts:201` for inbound request
> logs, `apiHandler.ts:43` for outbound API-call logs) and the exact
> header to add. If the new secret header is `x-auth`-shaped, note it is
> caught by the `x-.*-key` regex in `apiHandler` but is NOT in the
> `app.ts` explicit list — the author must add it to both surfaces or
> confirm the path only logs via one. Do NOT commit a patch.

**Adversarial caveat** — The `app.ts` allowlist is explicit (enumerates
exact header names); the `apiHandler` redactor is a regex. A header like
`x-auth` is caught by the regex (`x-.*-key` matches `x-auth-key` but NOT
bare `x-auth`) — so the playbook's claim that `x-auth` is redacted is
true only for `x-auth-key`-shaped names. A bare `x-auth` header in an
inbound request log (the `app.ts` path) is NOT in the explicit list and
would leak. The reviewer must check the *exact* header name against the
*exact* redaction surface, not assume "x-auth is covered."

### P-10-3: Check ownership before any discard of user-scoped rows — no IDOR

**Paradigm statement** — Any handler that discards, deletes, or
mutates a user-scoped row MUST verify the caller owns that row (or is
org-admin) before the write, and MUST return 404 (not 403) for a
not-owned row so the existence of another user's row is not leaked. A
discard without an ownership check is an IDOR: user A passes user B's
`id` and deletes B's memory. The ownership predicate must travel into
the SQL `WHERE` clause (or the row lookup), not be a separate
post-hoc check that races. Hand-rolled source creation that skips the
ownership-map INSERT is the IDOR precursor: an unowned row has no
ownership to check.

**Source evidence** — `playbook` convention "Ownership-before-discard":
*"User-scoped rows require an ownership check before any discard/delete;
a discard without ownership is an IDOR."* User-memory/dream critical
path step 1: *"Ownership before discard. Is ownership checked before
any `discard`/`delete` of user-scoped rows?"* `playbook` line 45 also
names `createSource` as the canonical path that a hand-rolled INSERT
drifts from ("NOT a hand-rolled `INSERT`" — misses `11` fields and
ownership bookkeeping).

**<Provider> infra anchor** —
`backend/src/controllers/userMemory.controller.ts:88-111`
(`deleteMyMemory`): parses `id`, calls `deleteMemory(pool,
req.user.user_id, id)`, returns 404 when `forgottenHash` is falsy
(`:102-104`) — the `user_id` travels into the delete so a cross-user
`id` yields no row → 404, not a leak. `:320-341`
(`rejectDreamProposalHandler`): passes `userId: req.user.user_id`
into `rejectDreamProposal` (`:333`), returns 404 when
`!result.revertedToPassthrough` (`:335-338`). The canonical
source-creation sibling:
`backend/src/controllers/<provider>Chat.libs/sharedUpload.ts:114-215`
(`createSource`): the ownership record is written at `:180-187`
(`INSERT INTO tbl_chat_sources_user_owner_map (source_id, user_id,
access_level, created_by, ...) VALUES ($1, $2, 'owner', $2, ...)`)
inside the same transaction as the source INSERT — a hand-rolled
INSERT that skips this creates an unowned row with no ownership to
check downstream. The whole block is wrapped in `BEGIN`/`COMMIT`/`ROLLBACK`
(`:134`, `:203`, `:207`) so the source and its ownership record land
together.

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/app "ownership check before discard userMemory"`
> → blast-radius names the dream/memory handlers; confirm a new
> delete/discard handler passes `userId` into the SQL, not just `id`.
> Serena `find_symbol` on `createSource`; `find_referencing_symbols`
> to confirm every source-creating path routes through it (not a
> hand-rolled INSERT).
> `semble_search "DELETE FROM tbl_user_memory WHERE id"` to catch a
> delete that keys on `id` alone without `AND user_id = $2`.

**Fix-suggestion policy** —
> SUGGEST ONLY: open a finding naming the unguarded discard; cite the
> canonical sibling (`deleteMyMemory` at `userMemory.controller.ts:101`
> for the 404-on-not-owned shape, `createSource` at
> `sharedUpload.ts:180` for the ownership-record INSERT a hand-rolled
> path skips). Do NOT commit a patch — the author must decide whether
> the 404-vs-403 distinction matters for their threat model.

**Adversarial caveat** — A 404 on not-owned hides existence from an
outsider, but an *org-admin* legitimately sees cross-user rows within
their org. A finding that demands `user_id` in every `WHERE` clause
would break org-admin oversight paths. The reviewer must distinguish
user-scoped (must carry `user_id`) from org-scoped (must carry `org`,
see P-10-4) deletes — conflating them produces a false positive on
org-admin routes.

### P-10-4: Enforce tenant isolation — cross-org returns 404, no `scopedOrgId == null` sentinel hole

**Paradigm statement** — Every multi-tenant query MUST scope by `org`
in the `WHERE` clause, and cross-org access MUST return 404
(indistinguishable from "doesn't exist"), never 200-with-data and never
a 500 from a NULL-org sentinel. The specific footgun Andrea hunts: a
query that builds `WHERE org = $1` but lets `$1` be NULL (e.g. an
unauthenticated path, a missing default, a `scopedOrgId` that falls
back to `null`), because `WHERE org = NULL` matches nothing in
three-valued logic — which is *safe* (empty result) — but
`WHERE org = $1 OR $1 IS NULL` matches *everything*, an instant
cross-org leak. Andrea looked specifically for this sentinel hole and
endorsed the batch routes because they don't have it.

**Source evidence** — `gateway.md` "Where you're right — tenant
isolation correct across all six routes": *"Cross-org returns 404, no
scopedOrgId==null sentinel hole; looked specifically for the sentinel
footgun."* Verdict ADDRESSED (Andrea endorsed). `feedback-divergences`
"From the original implementation plan": *"Org-scoped batches; cross-org
→ 404 ✅"*.

**<Provider> infra anchor** —
`worktrees/batch-api/feat-batch-api-gateway/src/batch/store.rs:608-628`
(`cancel_batch`): the lookup is `SELECT status FROM batch WHERE org =
$1 AND id = $2 FOR UPDATE` (`:617-619`), bound `org` then `batch_id`
(`:622-623`); `None` → `CancelOutcome::NotFound` (`:627-628`) —
cross-org and unknown are indistinguishable, both 404, no writes. The
doc comment at `:600-607` states the contract: *"org-scoped lookup;
cross-org/unknown → NotFound, no writes."*
`store.rs:845-875` (`list_batches`): `WHERE org = $1` (`:862`) with a
row-wise cursor subquery at `:863-866` that is itself org-scoped
(`WHERE b2.org = $1 AND b2.id = $2`) — a cursor id that doesn't resolve
*within the org* makes the subquery return zero rows, the comparison
NULL, the page empty (the comment at `:851-853` documents this
deliberately: *"a cursor id that doesn't resolve within the org makes
the subquery return zero rows, the comparison NULL, and the page
empty"*) — there is no `OR $2 IS NULL` fallback that would leak
cross-org. All store functions take `org: &str` parameters throughout
(per the gateway.md evidence summary). The app-side analog:
`userMemory.controller.ts:100` (`getClientPool(req.user.org_id)`) —
the org is resolved from auth before any query, never passed as a
nullable sentinel.

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/gateway "cancel_batch cross org NotFound"`
> → confirm the `WHERE org = $1` shape; grep the same repo for
> `OR $1 IS NULL` or `OR org IS NULL` to catch a sentinel fallback.
> codebase-memory `search_graph` with `name_pattern="list_batches|cancel_batch|retrieve_batch"`
> to enumerate every batch route's store function and confirm each
> binds `org`.
> `semble_search "WHERE org = NULL OR org IS NULL"` to catch the
> sentinel-hole anti-pattern directly.

**Fix-suggestion policy** —
> SUGGEST ONLY: open a finding naming the unscoped or sentinel-fallback
> query; cite the canonical sibling (`cancel_batch` at
> `store.rs:608` for the `WHERE org = $1 AND id = $2` → NotFound shape,
> `list_batches` at `store.rs:862` for the within-org cursor that
> returns empty rather than leaking). Do NOT commit a patch.

**Adversarial caveat** — `WHERE org = $1` with a non-nullable `org` is
safe, but a caller that derives `org` from an unauthenticated or
default-null context still produces the sentinel hole at the *binding*
site, not the SQL. The reviewer must trace `org` back to its source
(auth middleware, not request body) — a SQL-only check gives a false
clean on a route that binds `org = req.body.org_id`.

### P-10-5: Write a terminal status on every state-machine swap — a non-terminal row is a leak

**Paradigm statement** — Every state-machine transition that swaps,
reverts, or finalizes a row MUST write a terminal status in the same
transaction as the swap. A swap that leaves the row in a non-terminal
state is a leak: downstream consumers (nightly extractors, reapers,
billing reconcilers) key on `status IN ('terminal-states')` to advance
watermarks, and a row stuck in `awaiting_review` or `in_flight` after
the work is done re-fires the whole pipeline every cycle. The terminal
write is the security boundary too — a row a user can still act on
(approve/reject/cancel) after the state has effectively moved is an
IDOR-adjacent surface.

**Source evidence** — `playbook` convention "State-machine terminal
status": *"Every state-machine swap must write a terminal status; a
swap that leaves the row in a non-terminal state is a leak."*
User-memory/dream critical path step 2: *"Terminal status. Does every
state-machine swap write a terminal status (not leave the row in a
non-terminal state)?"* `gateway.md` "Notes on the review" BLOCKER-2
notes: the no-double-billing rebuttal keys on `finalize_success`'s
`AND attempt = $9` terminal-flip guard.

**<Provider> infra anchor** —
`backend/src/controllers/<provider>Chat.libs/userMemory/dream/reviewActions.ts:69-74`:
the comment names the exact failure mode — *"Revert + swap + terminal
status in one transaction: without a terminal status the extraction
watermark (status IN ('complete','approved')) never advances, so a
review-gate org re-extracts the user's whole history every night.
Atomic with the swap so an approve can't leave a half-applied run
stuck in 'awaiting_review'."* The `UPDATE tbl_user_memory_staging ...
WHERE ... r.status = 'awaiting_review'` at `:82-94` and the swap at
`:95+` run inside one `BEGIN` (`:77`), so the terminal status and the
row swap land together — a crash between them rolls both back. The
gateway-side terminal-flip analog:
`worktrees/batch-api/feat-batch-api-gateway/src/batch/store.rs:631`
(`cancel_batch` returns `AlreadyTerminal` for
`completed|failed|expired|cancelled`) and `billing.rs:127`
(`finalize_success` ... `AND attempt = $9` — the idempotence guard
that makes a stale terminal flip a no-op, per gateway.md BLOCKER-2
notes).

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/app "terminal status state machine swap reviewActions"`
> → confirm the `BEGIN`/terminal-`UPDATE`/swap/`COMMIT` block is
> atomic.
> Serena `find_symbol` on `applyApprovedDreamProposals` /
> `rejectDreamProposal`; `find_referencing_symbols` to confirm every
> state-machine swap site writes a terminal status in the same txn.
> codebase-memory `trace_path` mode `data_flow` from the swap to the
> status column to confirm no swap path omits the terminal write.

**Fix-suggestion policy** —
> SUGGEST ONLY: open a finding naming the swap-without-terminal-status
> site; cite the canonical sibling (`reviewActions.ts:69` for the
> "terminal + swap in one txn" invariant and its documented
> re-extraction-watermark consequence; `billing.rs:127` for the
> terminal-flip idempotence guard). Do NOT commit a patch.

**Adversarial caveat** — This paradigm overlaps Sector 05 (Billing &
state-machine integrity), which owns the *correctness* lens (no
double-bill, same-txn finalize). The security lens here is narrower: a
non-terminal row is a leak a user can still act on. A reviewer applying
this paradigm must not duplicate a Sector 05 finding — flag the overlap
in Cross-sector links and let the dedup pass merge. Also: not every
state machine has a terminal status (some are cyclical); demanding one
on a cycle is a false positive.

### P-10-6: Sign webhooks with a timing-safe HMAC over the raw body — reject replay and tamper

**Paradigm statement** — Every inbound webhook delivery MUST be
verified against an HMAC signature computed over the exact bytes
received (never a re-serialized body), with a timestamp window to
reject replay and a constant-time comparison to reject timing oracle
attacks. A re-serialization-based signature verification is a bug:
re-serializing `req.body` reorders keys and drops whitespace,
producing a digest the caller never computed. The signature must
cover the raw body; the timestamp must be within a tolerance window;
the comparison must be timing-safe. The test suite must exercise the
reject paths: wrong secret, tampered body, stale timestamp,
timestamp/signature mismatch, and the SSRF-payload-swap case.

**Source evidence** — `playbook` convention "Standard Webhooks
signing": *"`webhook-id` / `webhook-timestamp` / `webhook-signature:
v1,<b64>` over `id.timestamp.body`."* Critical path Webhook step 1:
*"Signing. Does the signer match Standard Webhooks (`webhook-id` /
`webhook-timestamp` / `webhook-signature: v1,<b64>` over
`id.timestamp.body`)? "*

**<Provider> infra anchor** —
`backend/src/controllers/automation.controller.ts:1373-1403`
(`verifyWebhookSignature`): reads `x-webhook-timestamp` and
`x-webhook-signature` headers (`:1374-1375`); rejects missing headers
(`:1377-1379`); parses timestamp as integer (`:1381-1384`); enforces
`WEBHOOK_TIMESTAMP_TOLERANCE_SEC` replay window (`:1386-1389`); signs
the *exact raw bytes* (`:1391-1396`: *"Sign the exact bytes received.
Re-serialising req.body would reorder keys and drop whitespace,
producing a digest the caller never computed."* → `expected =
'sha256=' + crypto.createHmac('sha256', signingSecret).update(\`${timestamp}.${rawBody}\`).digest('hex')`);
compares with `timingSafeStringEqual` (`:1398`) — not `===`. The test
suite at `backend/src/routes/__tests__/automationWebhook.e2e.test.ts`
exercises every reject path: valid signature → 200 (`:110-113`);
tampered body (SSRF payload swap to `169.254.169.254`) → 401
(`:154-165`); wrong secret → 401 (`:145-150`); stale timestamp → 401
(`:174-179`); timestamp/signature mismatch → 401 (`:189-194`); the
signing helper at `:80-81` mirrors the verifier
(`'sha256=' + crypto.createHmac('sha256', secret).update(\`${timestamp}.${rawBody}\`).digest('hex')`).

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/app "verifyWebhookSignature HMAC timing safe raw body"`
> → confirm the verifier uses `rawBody` not `req.body` and
> `timingSafeStringEqual` not `===`.
> Serena `find_symbol` on `verifyWebhookSignature`; `find_referencing_symbols`
> to confirm every webhook-trigger entry point routes through it (no
> parallel unverified trigger path).
> `semble_search "crypto.createHmac webhook signature verify"` to catch
> a second, drift-prone verifier hand-rolled elsewhere.

**Fix-suggestion policy** —
> SUGGEST ONLY: open a finding if a new webhook trigger path bypasses
> `verifyWebhookSignature`, or if a verifier re-serializes the body /
> uses `===`; cite the canonical sibling
> (`automation.controller.ts:1373` for the raw-body + timing-safe
> shape, `automationWebhook.e2e.test.ts:154` for the SSRF-payload-swap
> reject test that must accompany any new trigger). Do NOT commit a
> patch.

**Adversarial caveat** — The playbook names this convention "Standard
Webhooks" and cites the spec's header names (`webhook-id` /
`webhook-timestamp` / `webhook-signature: v1,<b64>` over
`id.timestamp.body`). The <Provider> implementation is a **Stripe-style
HMAC**, not the full Standard Webhooks spec: headers are
`x-webhook-timestamp` / `x-webhook-signature` (no `webhook-id`), the
signature prefix is `sha256=` (hex), not `v1,` (base64), and the signed
payload is `${timestamp}.${rawBody}` — **no `id` in the signed
material**. The security properties that actually matter
(tamper-resistance via raw-body signing, replay-rejection via timestamp
window, timing-attack-resistance via constant-time compare) are all
present and tested. A finding that demands literal Standard Webhooks
header names would be a false positive against an implementation that
meets the security bar under a different wire format — name the
*property* (raw-body HMAC + timestamp window + constant-time), not the
*spec*.

## Cross-sector links

- **P-10-5 (terminal status) ↔ Sector 05 (Billing & state-machine
  integrity).** Same evidence (`reviewActions.ts:69`, `billing.rs:127`,
  gateway.md BLOCKER-2 notes), different lens: Sector 05 owns
  correctness (no double-bill, same-txn finalize); this sector owns the
  security boundary (a non-terminal row a user can still act on is a
  leak). The dedup pass should merge the shared anchor and keep both
  lenses.
- **P-10-1 (SSRF) ↔ Sector 11 (Test coverage).** The SSRF reject-path
  test (`ssrfGuard.test.ts:137-161` — DNS-rebinding, mixed public+private
  records, metadata IP) is the Sector 11 "SSRF reject path exercised"
  concern; this sector owns the guard, Sector 11 owns whether the test
  exists. Shared anchor: `ssrfGuard.ts` + `ssrfGuard.test.ts`.
- **P-10-2 (redaction) ↔ Sector 12 (Code smell / naming).** The
  `x-auth`-vs-`x-.*-key`-regex gap (P-10-2 adversarial caveat) is also a
  naming-correctness detail Sector 12 might catch; the lens differs
  (security leak vs. naming precision).
- **P-10-3 (ownership) ↔ Sector 05 (state-machine).** A discard that
  skips ownership and also skips a terminal-status write is one bug
  under two lenses; flag for dedup.
- **P-10-4 (tenant isolation) ↔ Sector 02 (Concurrency).** The
  `FOR UPDATE` in `cancel_batch` (`store.rs:619`) is both a tenant
  boundary (cross-org → NotFound) and a concurrency guard (prevents
  claim/cancel race); the lens differs. Shared anchor: `store.rs:608`.

## Sector-specific failure modes

- **Flagging `validateAndPinUrl` as missing on a path that legitimately
  uses `allowPrivate`.** The `allowPrivate` opt (`ssrfGuard.ts:168,
  172-193`) is the operator-allowlist escape for in-cluster egress; it
  still blocks loopback/metadata. A finding that demands the default
  (no-`allowPrivate`) path on a legitimate internal-egress caller is a
  false positive — confirm the caller's host is in the operator
  `RestEgressAllowlist` before flagging.
- **Demanding literal Standard Webhooks header names (`webhook-id` /
  `v1,<b64>`).** The implementation is Stripe-style HMAC under
  `x-webhook-*` headers with `sha256=` hex. The security properties
  (raw-body, timestamp window, constant-time) are what matter; a
  wire-format-name finding is a false positive that wastes the author's
  time. Name the property, not the spec.
- **Treating `WHERE org = $1` as sufficient without tracing `$1`'s
  source.** The SQL is safe against SQL-level NULL, but a route that
  binds `org = req.body.org_id` (attacker-controlled) or
  `org = scopedOrgId ?? null` (sentinel fallback) leaks at the binding
  site. The reviewer must trace `org` back to auth middleware, not
  stop at the SQL string.
- **Conflating user-scoped and org-scoped deletes.** P-10-3 demands
  `user_id` in the `WHERE` for user-scoped rows; org-scoped rows
  (org-admin oversight) legitimately omit `user_id`. A finding that
  demands `user_id` on an org-admin route breaks oversight —
  distinguish the scope from the handler's role check before flagging.
- **Redaction allowlist assumed complete.** The `app.ts` explicit list
  and the `apiHandler` regex are two *different* surfaces; a header
  caught by one is not necessarily caught by the other (bare `x-auth`
  is in neither). The reviewer must check the *exact* header name
  against the *exact* surface the logging path uses, not assume "it's
  covered."

# Sector 08 — Wire/contract conformance

## Scope

This sector owns the question **"does the response on the wire match the
external contract a real client SDK parses?"** Andrea reviews an API not as
Rust that compiles but as bytes an `openai` SDK (or any base_url-overridden
client) must deserialize unchanged. It covers: OpenAI-exact status vocabulary
and field spelling, the `request_counts` reconciliation invariant
(arithmetic + error-file coverage), the `canceled`/`cancelled` dialect
split, 4xx-vs-5xx recoverability as a client-visible contract, endpoint
vocabulary, and the JSONL input parser that feeds the byte-identity
ranged-GET contract. It does NOT own the state-machine transitions behind
those statuses (Sector 05), the migration that creates the `batch_request`
table (Sector 07), or the multi-repo deploy ordering that ships the wire
change (Sector 09). Where a wire field is also a billing term, Sector 05
owns the money path; this sector owns the shape. The non-deterministic
encryption convention (never compare ciphertext for equality) is owned by
Sector 01 as an idempotency-gate-key concern — see Cross-sector links.

## Paradigms (7 entries)

### P-08-1: Emit OpenAI-exact wire shapes the official SDK parses unchanged

**Paradigm statement** — Every batch/file object the gateway returns must
deserialize in the official `openai` SDK with a `base_url` override and zero
patching. "OpenAI-shaped" is not a vibe — it is a pinned JSON shape with a
round-trip test that asserts the exact serialized bytes, and an unknown
status string must be a hard error, not a silent default.

**Source evidence** — `gateway.md` Rebuttal (f) endorses "OpenAI wire types
(including `canceled`/`cancelled` spelling split)" as part of the
"correctness core … survives untouched"; `feedback-divergences.md` "First-build
items Andreas praised that survived unchanged" lists "OpenAI wire types
(including `canceled`/`cancelled` spelling split)" verbatim. The local build's
own doc records the choice was OpenAI-exact, not thin-v1:
feedback-divergences "Where we diverged" shows thin-v1 proposed
`in_progress | canceling | ended`, the build shipped the full 8-term OpenAI
vocabulary.

**<Provider> infra anchor** — `feat-batch-api-gateway/src/batch/types.rs:1-3`
file header: "Wire types for the Batch API — OpenAI-exact shapes (docs/PRD.md
'API dialect'). The official `openai` SDK with a base_url override must parse
these objects unchanged; the tests below pin the exact JSON." The `BatchStatus`
enum at `types.rs:11-20` (`Validating, Failed, InProgress, Finalizing,
Completed, Expired, Cancelling, Cancelled`) is the 8-term OpenAI vocabulary.
Round-trip tests at `types.rs:286-316` pin every status string and
`types.rs:315` asserts `json!("canceled")` is a *deserialize error* for
`BatchStatus`. The full wire shape is pinned by
`batch_object_fully_populated_wire_shape` (`types.rs:360-426`) asserting the
exact JSON including `"object": "batch"` and `"request_counts": {"total": 10,
"completed": 9, "failed": 1}`.

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/gateway "BatchStatus Serialize Deserialize openai vocabulary wire"`
> → Serena `find_symbol` on `BatchStatus` to enumerate variants, then
> `find_referencing_symbols` to confirm every serialization site (the custom
> `Serialize` impl at `types.rs:146-162`) uses the pinned strings.
> `semble_search "openai SDK batch object request_counts completed failed"`
> locates any drift between the wire struct and a caller that re-shapes it.

**Fix-suggestion policy** — SUGGEST ONLY: if a status string drifts from the
OpenAI vocabulary, open a PR finding citing the failing round-trip test
(`types.rs:315` for the spelling, `types.rs:360` for the full shape) and the
SDK contract in the file header. Do NOT commit the enum edit; the PR author
owns the wire change and its SDK-compat re-test.

**Adversarial caveat** — "OpenAI-exact" can be over-applied: OpenAI ships
draft/beta fields (e.g. `metadata`, `completion_window` values beyond `24h`)
the local build intentionally omits as out-of-scope. An agent that flags every
absent OpenAI field as a contract break is wrong — the contract is "the SDK
parses what we send," not "we send every OpenAI field." The test at
`types.rs:360` is the authority, not the OpenAPI spec.

---

### P-08-2: Hold the `request_counts` reconciliation invariant end-to-end — counter arithmetic AND error-file coverage

**Paradigm statement** — Every request the SDK counts in `total` must be
*accountable*: either as `completed` (succeeded), as `failed` (errored only —
never canceled/expired), or via an entry in the error file. Two halves must
hold together. (a) Arithmetic: `failed = errored` only — folding
canceled/expired into `failed` makes an expired batch report `failed > 0`
when it has no real error, breaking the SDK's `total != completed + failed`
reconciliation. (b) Artifact: a batch that ends `expired` must still produce
an error file covering those rows, or the SDK sees rows in `total` it can
neither count as `failed` nor find in the error file.

**Source evidence** —
- Arithmetic half: `feedback-divergences.md:49` — "`request_counts.failed`
  must not fold canceled/expired; gate `error_file_id` on real failures" —
  "Already correct in first build; Andreas said keep."
- Artifact half: `gateway.md` MAJOR-4 (verbatim) — "An expired batch produces
  no result file and no error file… `files.rs:232-235` synthesizes error file
  from `status='errored'` only; expired rows never appear; `total != completed
  + failed` breaks the OpenAI SDK contract." Resolved: "`expire_batches` sets
  `error_code = 'batch_expired'`; error-file synthesis uses
  `status = ANY($2::text[])` bound to `['errored', 'expired']`; `error_file_id`
  gate widened to `failed > 0 || expired > 0`." Verdict ADDRESSED.

**<Provider> infra anchor** —
- Arithmetic: `feat-batch-api-gateway/src/batch/types.rs:99-113`
  `RequestCounts::from_tallies` — `total` sums all 6 internal buckets,
  `completed = succeeded`, `failed = errored`; canceled and expired
  deliberately *excluded* from `failed`. Test `request_counts_roll_up_from_internal_tallies`
  (`types.rs:344-357`) pins it: with `errored:1, canceled:2, expired:1` it
  asserts `failed == 1` with the comment "errored only; canceled/expired
  excluded."
- Artifact: `feat-batch-api-gateway/src/batch/store.rs:805` — `SET status =
  'expired', error_code = 'batch_expired'` (queued rows of an expired batch
  flip with a stable machine code); `feat-batch-api-gateway/src/routes/files.rs:288`
  — `SyntheticKind::Error => &["errored", "expired"]`; `files.rs:313` —
  `WHERE batch_id = $1 AND status = ANY($2::text[])`; `batches.rs:95` —
  `(counts.failed > 0 || tallies.expired > 0).then(|| error_file_id_for(&row.id))`
  (the `error_file_id` field is present iff there are real failures *or*
  expired rows, so the SDK always finds the error file for a non-purely-
  succeeded terminal batch).

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/gateway "RequestCounts from_tallies expire_batches error file synthesis"`
> → codebase-memory `trace_path` mode `data_flow` from `request_tallies`
> (store.rs:371) → `RequestCounts::from_tallies` (types.rs:102) → `batch_object`
> (batches.rs:86) to confirm no caller mutates the rollup after construction,
> and mode `calls` from `expire_batches` (store.rs:791) → `SyntheticKind::Error`
> (files.rs:286) to confirm the expired status reaches the error-file stream.
> `semble_search "request_counts failed expired canceled fold error_file_id"`
> to find any sibling that re-derives `failed` or the gate outside the
> canonical sites.

**Fix-suggestion policy** — SUGGEST ONLY: two distinct failure shapes. If a
change makes `failed` include canceled/expired (e.g. a "simpler"
`failed = total - completed`), open a finding citing `types.rs:111`
(`failed: tallies.errored`) and the test at `types.rs:356`. If a new terminal
status is added (e.g. a future `aborted`) and the error-file synthesis at
`files.rs:288` is not widened to include it, open a finding citing MAJOR-4 and
the `batches.rs:95` gate. Do NOT edit; the author owns both the arithmetic
and the gate, and must add a test that the new terminal status produces an
error file with `failed` unchanged.

**Adversarial caveat** — A reviewer might argue `total - completed - failed`
should always be `0` for a terminal batch, so canceled/expired "belong" in
`failed`. That is the SDK's *reconciliation expectation* for *error files*,
not a reason to fold the counts — the resolution is that canceled and expired
rows *also get error-file entries* (MAJOR-4), so the SDK sees them in the
error file, not in `failed`. Folding them would double-count. Separately,
an `expired` row with `error_code = 'batch_expired'` is arguably *not* a
per-request error (the request was never attempted), so putting it in the
*error* file is a semantic stretch vs OpenAI, where expired batches surface
expiry at the batch level — the local choice trades OpenAI-exactness for SDK
reconciliation completeness; flag the divergence rather than treat it as
obviously correct.

---

### P-08-3: Split the `canceled`/`cancelled` dialect deliberately — batch-level double-L, request-level single-L

**Paradigm statement** — The wire has two different "cancelled" spellings by
design: the batch-level status `cancelled` (double-L) is the OpenAI
caller-visible vocabulary; the per-request status `canceled` (single-L) is
an *internal* lifecycle dialect. A new status that crosses these layers must
choose the right spelling, and a deserializer must *reject* the wrong one
rather than silently coerce — a silent coercion hides a wire bug from the
SDK.

**Source evidence** — `gateway.md` Rebuttal (f) lists "OpenAI wire types
(including `canceled`/`cancelled` spelling split)" among the correctness core
that "survives untouched"; `feedback-divergences.md:145` (praised-survived
list) repeats it verbatim. The thin-v1 proposal used `canceling` (single-L)
for the batch level — the build deliberately rejected that for the OpenAI
double-L `cancelling`/`cancelled` (feedback-divergences "Scope and
sequencing").

**<Provider> infra anchor** — `feat-batch-api-gateway/src/batch/types.rs:8-23`:
`BatchStatus` (caller-visible) doc comment "OpenAI vocabulary, double-L
`cancelled`"; `RequestStatus` (internal) doc comment "Single-L `canceled`
(internal dialect, distinct from the batch-level `cancelled`)." The
deserialization test at `types.rs:315` —
`assert!(serde_json::from_value::<BatchStatus>(json!("canceled")).is_err())` —
makes the single-L form a *hard error* on the batch wire. The serialize tests
at `types.rs:295-296` pin `Cancelling → "cancelling"`, `Cancelled →
"cancelled"`; the request tests at `types.rs:325` pin `Canceled → "canceled"`.

**Codebase-intelligence backend** —
> Serena `find_symbol` on `BatchStatus` and `RequestStatus` to list variants
> and their `#[serde(rename_all)]` attributes, then
> `find_referencing_symbols` on `RequestStatus::Canceled` to confirm it never
> reaches a `BatchStatus` serialization site.
> `grep -rn "canceled|cancelled|canceling|cancelling"` across
> `src/batch/` and `src/routes/` to audit every literal — the dialect split
> must hold at every site, not just the enum.

**Fix-suggestion policy** — SUGGEST ONLY: if a new status is added with the
wrong spelling or a `#[serde(alias = "canceled")]` is proposed to "be lenient,"
open a finding citing `types.rs:315` (the reject-on-wrong-spelling test) and
the dialect doc at `types.rs:22-23`. Do NOT add a permissive alias; the author
owns the strictness decision and must extend the reject-test for any new
status.

**Adversarial caveat** — A lenient deserializer (accepting both spellings) is
more "robust" to typo'd clients — but the contract here is the official SDK,
which sends one spelling. Leniency would mask a server-side wire bug from the
reviewer and from the round-trip test; strictness is the load-bearing choice.
The caveat holds only if all real clients use the official SDK.

---

### P-08-4: Classify 4xx as non-recoverable and 5xx per-semantic, never blanket "retry everything ≥400"

**Paradigm statement** — A tool/model-call error carries a `recoverable`
boolean the agent loop reads to decide whether to retry. The classification
must be by HTTP semantics *and* upstream behavior: null-status infra errors
(S3/DB blips) and 429 are recoverable; 404 and 4xx-rejections are not (the
prompt is the problem, retrying wastes a turn); 5xx is *not* automatically
recoverable when the upstream (e.g. an image service) uses 5xx to signal a
content-safety trip — a blanket "5xx = retry" burns retries on the same
rejected prompt.

**Source evidence** — `andrea-review-playbook.md` Image-generation path step 3:
"4xx vs 5xx recoverability. Is `5xx` marked recoverable and `4xx` not?
`src/backend/src/controllers/<provider>Chat.libs/generateCosmosImage.ts`."
(The playbook's path predates a refactor; the file now lives under
`agenticLoop/`.)

**<Provider> infra anchor** —
`feat-batch-api-app/backend/src/controllers/<provider>Chat.libs/agenticLoop/generateCosmosImage.ts:404-468`:
the catch block extracts `e.response.status` or `$metadata.httpStatusCode`,
then:
- `status === null` (AWS SDK / pg, no HTTP status) → `recoverable: true`
  (`:415-421`, "transient storage / DB blips are exactly what you'd retry")
- `404` → `recoverable: false`, `IMAGE_GEN_MODEL_NOT_FOUND` (`:423-429`)
- `429` → `recoverable: true`, `IMAGE_GEN_REJECTED` (`:431-437`)
- `4xx` (400-499) → `recoverable: false`, `IMAGE_GEN_REJECTED` ("The model
  rejected the request. Try rephrasing") (`:439-447`)
- `5xx` → `recoverable: false`, `IMAGE_GEN_FAILED` (`:449-460`) with the
  explicit comment "5xx from the image service often means the prompt tripped
  a content-safety filter that is not cleanly surfaced as a 4xx. Treat as
  non-recoverable so the LLM stops wasting retries on the same prompt."

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/app "generateCosmosImage 4xx 5xx recoverable"`
> → Serena `find_symbol` on `runGenerateCosmosImage`, then
> `find_referencing_symbols` to find every caller that reads `.recoverable`
> (the agent loop's retry decision).
> `semble_search "recoverable false retry agent loop"` to find sibling error
> classifiers that should match this taxonomy.

**Fix-suggestion policy** — SUGGEST ONLY: if a new model-call error path is
added with `recoverable: true` for a 4xx or a blanket `recoverable: true` for
all 5xx, open a finding citing `generateCosmosImage.ts:439-460` as the
canonical classifier and the content-safety rationale at `:450-452`. Do NOT
edit the new path; the author owns the classification and must justify any
deviation from the 4xx-non-recoverable / 5xx-semantic default.

**Adversarial caveat** — Marking all 5xx non-recoverable is wrong for a
generic LLM text endpoint where 503/504 genuinely means "retry later." The
non-recoverable-5xx choice here is specific to an *image* service known to
abuse 5xx for content-safety. An agent applying this paradigm to a different
upstream must check whether *that* upstream uses 5xx semantically before
copying the classification.

---

### P-08-5: Pin the endpoint vocabulary now; widen deliberately, never by accident

**Paradigm statement** — A batch is created against a single `endpoint`
(e.g. `/v1/chat/completions`), and the input JSONL must carry a matching
`url`. The endpoint is validated at two layers (route + JSONL parser) and the
vocabulary is intentionally narrow now — widenable to `/v1/embeddings` etc.
later, but only as a deliberate change, never by dropping the equality
check.

**Source evidence** — `feedback-divergences.md:53`: "Endpoint vocab widenable
for embeddings later (don't pre-build)" under "What we took from Andreas."
The build rejected thin-v1's broader endpoint surface in favor of the
OpenAI-exact single-endpoint path (feedback-divergences "Scope and
sequencing").

**<Provider> infra anchor** —
- `feat-batch-api-gateway/src/routes/batches.rs:26` — `const BATCH_ENDPOINT:
  &str = "/v1/chat/completions";`
- `feat-batch-api-gateway/src/routes/batches.rs:224-226` — `if req.endpoint !=
  BATCH_ENDPOINT { return Err(... "endpoint must be {BATCH_ENDPOINT}") }`
  (route-layer rejection of any other endpoint).
- `feat-batch-api-gateway/src/batch/jsonl.rs:159-160` — `if value.get("url")
  .and_then(Value::as_str) != Some(endpoint) { return Err(err("invalid_url",
  format!("url must be {endpoint}"))) }` (per-line JSONL rejection; the test
  `url_not_matching_endpoint_rejected` at `jsonl.rs:269-272` uses
  `/v1/embeddings` as the rejected URL — confirming embeddings is the known
  future widening, currently rejected).
- `feat-batch-api-gateway/src/batch/types.rs:121` — `pub endpoint: String`
  on `BatchObject` (the wire field the SDK reads back).

**Codebase-intelligence backend** —
> `grep -rn "BATCH_ENDPOINT|endpoint !=|url must be"` across
> `src/routes/batches.rs` and `src/batch/jsonl.rs` to confirm both gates use
> the same constant (no drift between route-layer and parser-layer
  validation).
> Serena `find_referencing_symbols` on `BATCH_ENDPOINT` to confirm every
> create path routes through the single constant, not a hardcoded literal.
> `semble_search "endpoint embeddings batch url validation"` to find any
> speculative pre-built embeddings path that should be removed.

**Fix-suggestion policy** — SUGGEST ONLY: if a PR widens the endpoint to
embeddings/responses, open a finding requiring (a) the constant becomes a
set/enum, (b) both the route gate (`batches.rs:224`) and the JSONL gate
(`jsonl.rs:159`) use the same source of truth, (c) the JSONL body-shape
validation per endpoint is added. Do NOT implement the widening; the author
owns the vocabulary change and the per-endpoint body schema.

**Adversarial caveat** — A single hard-coded `BATCH_ENDPOINT` constant is
brittle: a future multi-endpoint PR must touch every site or the gates drift.
An agent might flag the hard-code as a smell and propose a `match`/set now.
That pre-builds the widening the design explicitly deferred — the smell is
intentional YAGNI until embeddings is actually in scope.

---

### P-08-6: The JSONL byte-cursor parser must round-trip byte-identical, including CRLF — and must strip a leading UTF-8 BOM

**Paradigm statement** — The input JSONL parser records a per-line
`(offset, len)` byte range so the worker's ranged GET returns *exactly* the
bytes the parser validated — not `str::lines()` semantics that normalize
line endings. The parser must strip CRLF from the recorded range, skip blank
lines while counting them in the 1-based line number, and round-trip
multibyte UTF-8 correctly (split on `\n` bytes, slice on byte indices). A
leading UTF-8 BOM (`\u{FEFF}`) must be stripped before line 1, or it stays in
line 1's `raw` and fails JSON parse — a real gap Andrea flagged as "worth a
targeted fix."

**Source evidence** — `gateway.md` Rebuttal (f) (verbatim): "JSONL
byte-cursor rewrite holds (CRLF, no trailing newline, multibyte round-trip)
with one gap: a leading UTF-8 BOM fails line 1." Verdict PARTIALLY-ADDRESSED;
Notes: "The BOM gap Andrea flagged as 'worth a targeted fix' is not acted on
and not mentioned in Mateo's reply."
`feedback-divergences.md:42`: "Byte-cursor JSONL rewrite + byte-identity test
(not `str::lines()`)" under "What we took from Andreas."

**<Provider> infra anchor** —
`feat-batch-api-gateway/src/batch/jsonl.rs:49-115` `parse_input`:
- `:64-65` "Byte-cursor scan (ADR 0004)… Split on `\n` like `str::lines`,
  strip a trailing `\r` (CRLF) from the recorded range, and count physical
  lines (blanks included) for the 1-based line number."
- `:67-71` `bytes[cursor..].iter().position(|&b| b == b'\n')` — byte-level
  `\n` split (multibyte-safe: `\n` is a single byte never inside a UTF-8
  continuation).
- `:75-78` `if end > cursor && bytes[end - 1] == b'\r' { end -= 1; }` — CRLF
  stripped from the recorded range so a ranged read is byte-identical to the
  JSON the parser saw.
- `:82-84` `if raw.trim().is_empty() { cursor = next; continue; }` — blanks
  skipped but `line_no` already incremented (`:80`), so line numbers stay
  physical.
- **NO BOM strip** — `grep -n "BOM|0xEF|\\ufeff|strip_prefix" src/batch/jsonl.rs`
  returns exit 1 (no matches). A leading `\u{FEFF}` (bytes `EF BB BF`) would
  remain in line 1's `raw` at `:79`, and `validate_line`'s `serde_json` parse
  of `raw` would fail on the BOM prefix.

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/gateway "jsonl parse_input CRLF BOM multibyte byte cursor"`
> → Serena `find_symbol` on `parse_input` and `validate_line`, then
> `get_diagnostics_for_file` on `jsonl.rs` (no BOM-related diagnostic exists,
  confirming the gap).
> `grep -rn "BOM|0xEF|\\ufeff|strip_prefix" src/batch/jsonl.rs` to re-confirm
> the absence at review time — the gap is observable as a missing symbol.

**Fix-suggestion policy** — SUGGEST ONLY: open a finding citing Rebuttal (f)
and `jsonl.rs:64-79` describing the BOM gap: before the `while cursor <
bytes.len()` loop, strip a leading `EF BB BF` byte sequence if present (or
`text.strip_prefix('\u{FEFF}')`). Do NOT commit; the author owns the fix and
must add a test (`bom_stripped_from_line_1`) that a BOM-prefixed input parses
with line 1's `offset` starting after the BOM and the ranged-GET still
byte-identical.

**Adversarial caveat** — A leading BOM in a JSONL file is rare (most
producers write UTF-8 without BOM), and the failure mode is a clean parse
error on line 1, not silent corruption — so the blast radius is "first line
of an unusual file fails," not "data loss." An agent might rate this NIT not
MAJOR; Andrea himself called it "worth a targeted fix," not blocking. The
fix is cheap (one `strip_prefix`) but the severity is genuinely low.

---

### P-08-7: A ranged GET must accept 200 *and* 206 — the Range guard is stronger than a literal 206 check

**Paradigm statement** — When the worker issues a ranged GET against the
input object, the success status is *not* literally `206 Partial Content` —
some S3-compatible stores (and full-object reads where the range covers the
whole object) return `200 OK` with the full body. The client must accept the
whole `2xx` class and validate the returned *byte length* against the
requested range, rather than assert `status == 206`. A literal `206` check
fails silently against a store that returns `200`.

**Source evidence** — `gateway.md` Rebuttal (f) (verbatim): "Range-ignoring-200
guard holds (stronger than literal 206)." Verdict PARTIALLY-ADDRESSED;
Evidence: "the other three sub-points (continuous fill, Range guard, SSE-S3)
are either present in code or covered by MAJOR-7."

**<Provider> infra anchor** —
`feat-batch-api-gateway/src/batch/s3_client.rs:170-203` `get_range`:
- `:175` `let end = offset + len - 1;` (HTTP Range is inclusive).
- `:178` `get_object_range(key, offset, Some(end))`.
- `:182-183` `match r.status_code() { 200..=299 => { ... }` — accepts the
  full 2xx class, not a literal `206`.
- `:185-189` `if bytes.len() as u64 != len { return
  Err(S3Error::Unavailable(... "ranged GET returned {} bytes, expected
  {len}")) }` — the *byte-length* check is the real contract guard, not the
  status code. A 200 that returns the wrong byte count still fails.
- Comment at `:181` "206 Partial Content on success" documents the *expected*
  case while the match arm accepts the wider class.

**Codebase-intelligence backend** —
> `codegraph explore -p ~/<provider>/gateway "get_range 200 206 Partial Content byte length"`
> → Serena `find_symbol` on `get_range` (trait method) and its impl in
  `RealS3`; `find_referencing_symbols` to confirm every caller relies on the
  byte-length contract, not a 206 assumption.
> `semble_search "ranged GET status 200 206 accept 2xx"` to find any sibling
  HTTP-range client that hard-codes `== 206` and should be widened.

**Fix-suggestion policy** — SUGGEST ONLY: if a new ranged-GET client
hard-codes `if status != 206 { return Err(...) }`, open a finding citing
`s3_client.rs:182-189` as the canonical "accept 2xx + validate byte length"
pattern. Do NOT edit the new client; the author owns the fix and must add a
test that a 200-with-correct-length succeeds and a 206-with-wrong-length
fails.

**Adversarial caveat** — Accepting any 2xx and validating only byte length
could mask a store that returns `200` with a *full object* longer than the
requested range but truncated to the right length by coincidence (extremely
unlikely for ranged reads, but possible if the store ignores the Range
header and the object happens to be exactly `len` bytes). The byte-length
check catches the common case; a paranoid client could also verify a
returned `Content-Range` header. The local choice trades that paranoia for
store-compat breadth — defensible, but an agent should note the
`Content-Range` check is the stricter option.

---

## Cross-sector links

- **P-08-2 shares MAJOR-4 evidence with Sector 05 (Billing & state-machine
  integrity)** — the `total != completed + failed` invariant is a wire
  contract *and* a state-machine completeness property; the expired-batch
  error-file fix is both "wire reconciliation" (here) and "terminal status
  always produces a visible artifact" (Sector 05). The dedup pass should
  keep the wire lens here (counter arithmetic + error-file presence) and the
  state-machine lens in 05 (transitions into `expired`).
- **P-08-3 (`canceled`/`cancelled` spelling) shares Rebuttal (f) evidence
  with Sector 12 (Code smell, naming & correctness-detail)** — the spelling
  split is a naming-correctness concern (12) as well as a wire contract
  (08). If 12 claims it, keep the *strict-deserializer-rejects-wrong-spelling*
  angle here (the wire lens) and let 12 own the *naming-convention* angle.
- **P-08-6 (JSONL BOM gap) shares Rebuttal (f) evidence with Sector 12** —
  the BOM gap is filed under NIT/correctness-detail in 12 and under
  wire/parser-conformance here. The two are the same finding through
  different lenses; the dedup pass should merge or cross-reference.
- **Non-deterministic encryption convention → owned by Sector 01
  (Idempotency & re-arm gates), NOT written in full here per hard rule #5.**
  The playbook convention "Non-deterministic encryption" — "`encrypt()` uses
  a random IV — ciphertext differs per call; never compare ciphertext for
  equality or use it as a gate key" — is a *gate-key* concern (Sector 01),
  not a wire-shape concern. Grounded for Sector 01's use at
  `app/backend/src/libs/stringEncryption.ts:29-30`
  (`const iv = crypto.randomBytes(12); crypto.createCipheriv('aes-256-gcm', key, iv)`)
  — a fresh random IV per call, so `encrypt(a) === encrypt(b)` is always
  false; any dedup/gate keyed on ciphertext is a bug, the canonical
  alternative being `HMAC(secret, url)` / entity UID
  (`trainingJob.controller.ts:540`). An agent checking this should use
  `semble_search "encrypt ciphertext compare equality dedup gate"` and
  Serena `find_referencing_symbols` on `encrypt` to audit callers. Flagged
  for adjudication: if 01 does not claim it, it can return here.
- **P-08-5 (endpoint vocabulary) borders Sector 09 (Multi-repo & deploy
  ordering)** — widening the endpoint to embeddings is a deliberate
  vocabulary change that may ship as a companion set (helm catalog + app
  SDK + gateway). The *vocabulary decision* is here; the *companion-PR
  ordering* of that widening is 09.
- **P-08-4 (4xx vs 5xx) overlaps Sector 04 (Rate limiting)** — 429 is the
  rate-limit status and its `recoverable: true` classification lives in the
  image error path reviewed here; 04 owns the *RPM enforcement*, this sector
  owns the *recoverability contract* the agent loop reads.

## Sector-specific failure modes

- **Flagging a missing OpenAI field as a contract break.** The contract is
  "the SDK parses what we send," not "we send every OpenAI field." An agent
  that diffs the local `BatchObject` against the full OpenAI spec and flags
  every absent field (`metadata`, `completion_window` values beyond `24h`)
  as a wire bug is over-applying P-08-1. The round-trip test at
  `types.rs:360` is the authority.
- **Treating `total - completed - failed` as a bug for terminal batches.**
  A terminal batch *can* legitimately have `total != completed + failed`
  when rows are canceled or expired — that is the design (P-08-2). An agent
  that flags every such gap as "invariant violation" is wrong; the invariant
  is reconciled via the error file (P-08-2 artifact half), not by folding
  counts.
- **Demanding a permissive `canceled`/`cancelled` alias for "robustness."**
  The strict deserializer (`types.rs:315` rejects `canceled` for
  `BatchStatus`) is load-bearing — it catches wire bugs. An agent that
  "improves" the API by accepting both spellings silently regresses the
  contract the test pins.
- **Copying the image-service 5xx-non-recoverable classification to a
  generic LLM endpoint.** The non-recoverable-5xx choice at
  `generateCosmosImage.ts:449` is specific to an image service that abuses
  5xx for content-safety. An agent applying it to a text endpoint where 503
  genuinely means "retry later" would kill legitimate retries. Always
  confirm the upstream's 5xx semantics before classifying.
- **Pre-building the embeddings endpoint widening.** P-08-5 says the
  vocabulary is *widenable later* — an agent that refactors `BATCH_ENDPOINT`
  into a `match`/set now, "to be ready," pre-builds the deferred scope and
  violates the explicit YAGNI decision. The single hard-coded constant is
  intentional until embeddings is actually in scope.
- **Conflating "wire reconciliation" with "state-machine terminality."**
  P-08-2's artifact half (expired batches produce error files) looks like a
  Sector 05 state-machine concern. An agent that files it only under 05 loses
  the wire lens (the SDK's `total != completed + failed` reconciliation); an
  agent that files it only here loses the transition lens. The finding has
  two legitimate homes — file both, or pick the lens that matches the PR's
  actual change.

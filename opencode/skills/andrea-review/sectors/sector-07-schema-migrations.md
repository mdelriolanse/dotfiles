# Sector 07 — Schema, migrations & CHECK constraints

## Scope

This sector owns the **database-schema review lens**: does every migration
land safely under Flyway `outOfOrder=false`, do CHECK constraints stay correct
when an enum changes, are indexes added `CONCURRENTLY` where they must be and
plainly where they may be, does every hot query path carry a supporting
(index, often partial) index, and is a re-cut/renumber done above main's
Flyway head with the supersession documented? The question it asks of every
PR that touches SQL is: *will this migration apply cleanly on a live DB, in
sequence, without blocking the table or leaving the schema inconsistent with
the code that depends on it?*

Boundaries — what this sector deliberately does NOT own:
- **Deploy ordering across repos** (migration-before-app, companion-PR sets,
  helm catalog compat) is Sector 09 (Multi-repo & deploy ordering). Sector 07
  owns the *internal* correctness of one migration; Sector 09 owns whether it
  lands before its app PR.
- **The V-number collision across *concurrent PRs*** as a coordination
  problem (two open PRs both claiming V44) is Sector 09; Sector 07 owns the
  *globally-unique-per-DB / re-cut-above-head* rule that makes a collision
  possible in the first place.
- **Idempotency of the *data* a migration writes** (re-arm gates, terminal
  status) is Sector 01/05; Sector 07 owns idempotency of the *DDL* (`IF NOT
  EXISTS`, drop-and-re-add).

## Paradigms (5 entries)

### P-07-1: Ship a partial index for every hot per-tick query predicate

**Paradigm statement** — Any query a worker/reaper/sweep runs on **every
tick** must have a supporting index, and because these queries are uniformly
status-discriminated (`WHERE status = 'queued'`, `WHERE status = 'in_flight'`,
`WHERE terminal_at IS NOT NULL AND content_swept_at IS NULL`) the index should
be a **partial index** scoped to that predicate — not a full-table index that
makes every tick pay for the cold rows. A hot predicate with no index is a
correctness-adjacent finding, not just a perf NIT: the worker tick is the
lowest-frequency, highest-repetition path in the system, and an unindexed
sequential scan there degrades under exactly the load (many queued rows) the
feature exists to serve. Andrea frames the fix as "cheap to add while you're
re-cutting" — i.e. the cost is near-zero if you add the index in the same
migration that introduces the column, and steep if you defer it.

**Source evidence** — `gateway.md NIT-2` (UNADDRESSED): "Andrea:
`store.rs:566` — no partial index on `det_failures`; cheap to add while
re-cutting." Mateo's reply has no entry under NITs for this item — silently
dropped with no rationale. The audit verdict: "Silently dropped with no
rationale. Andrea framed it as 'cheap to add while you're re-cutting' — a
minor perf item, not a correctness issue." Also `playbook` convention
"CHECK-constraint enum encoding" is silent on indexing, but the *Migration PR
path* step 4 ("`CONCURRENTLY` for indexes on large tables") implies Andrea
scrutinizes index strategy on migrations generally.

**<Provider> infra anchor** — The query is
`src/batch/store.rs:538-552` (`select_exhausted_queued`):
```sql
SELECT br.batch_id, br.line_no, br.attempt
FROM batch_request br JOIN batch b ON b.id = br.batch_id
WHERE br.status = 'queued'
  AND br.det_failures >= $1
  AND b.status = 'in_progress'
  AND b.expires_at > $2
ORDER BY b.created_at, br.line_no
```
called every worker tick via `worker.rs:93` (`select_exhausted_queued(&state.pool,
MAX_ATTEMPTS, ...)`). The companion migration
`gateway-db/migrations/V44__batch_api.sql` ships **seven** partial indexes on
`batch`/`batch_request`/`file` — `idx_batch_request_claim` (`ON batch_request
(deployment, batch_id, line_no) WHERE status = 'queued'`, line 180-182),
`idx_batch_request_lease` (`WHERE status = 'in_flight'`, 185-187),
`idx_batch_sweep` (`WHERE terminal_at IS NOT NULL AND content_swept_at IS
NULL`, 118-120), `idx_batch_expiry` (113-115), `idx_file_sweep` (`WHERE
content_swept_at IS NULL`, 60-62) — but **zero** indexes reference
`det_failures` (the column is defined at line 162 and mentioned only in
comments at 143/149). The partial-index convention was applied to claim,
lease, sweep, and expiry — and stopped one predicate short of
`select_exhausted_queued`. The fix shape is a sibling of
`idx_batch_request_claim`:
`CREATE INDEX IF NOT EXISTS idx_batch_request_det_failures ON batch_request
(det_failures) WHERE status = 'queued';` (partial, matching the query's two
conjuncts).

**Codebase-intelligence backend** — The index lives in the `gateway-db`
repo, whose DDL is **not** indexed by CodeGraph (CodeGraph's
`~/<provider>/gateway/.codegraph` covers the *gateway* Rust crate on `main`,
which has no batch module; the batch code is on the `feat-batch-api-gateway`
worktree). So:
> `grep -rn "det_failures" ~/<provider>/gateway-db/migrations/` (or the
> `feat-batch-api-gateway-db` worktree) — confirms whether any
> `CREATE INDEX ... det_failures` exists. Authoritative, byte-for-byte.
> `semble_search "CREATE INDEX det_failures"` scoped to `gateway-db` —
> semantic fallback if the migration dir is not in the active checkout.
> `codegraph explore -p ~/<provider>/gateway "select_exhausted_queued
> det_failures query"` — locates the *query* (the code that needs the index);
> note the gateway index is main-branch, so the batch query is only visible
> in the worktree, where you'd run `codegraph init -i` for a local index or
> just `read` `src/batch/store.rs:538`.

**Fix-suggestion policy** —
> SUGGEST ONLY: open a finding on the PR citing the missing
> `idx_batch_request_det_failures` partial index; quote the sibling
> `idx_batch_request_claim` (`WHERE status = 'queued'`) as the canonical
> shape and note the column was introduced in the same V44 migration so the
> index is free to add now and a separate migration later. Do NOT commit a
> patch — the PR author owns the fix (and the choice of partial-vs-full,
> though the query's `status = 'queued'` conjunct makes partial the right
> call).

**Adversarial caveat** — `select_exhausted_queued` returns the **exhausted**
rows (rows already at the cap, about to be terminalized); the result set is
expected to be small and the query runs once per tick, not per row. An
adversary could argue the sequential scan over `status='queued'` rows (which
the existing `idx_batch_request_claim` already narrows) plus an in-memory
`det_failures >= $1` filter is fine at fleet scale, and that adding the index
is premature optimization. The counter is that the claim index is keyed
`(deployment, batch_id, line_no)` and does **not** lead with `det_failures`,
so Postgres cannot use it to satisfy `det_failures >= $1` without scanning
all queued rows for the deployment — the index only helps once you've
already paid the scan. Whether that scan is "fine" depends on max queued
rows per deployment, which is capped at 10k/file; the reviewer should state
the cap before deciding the NIT is a non-issue, not assume it.

### P-07-2: Re-cut migrations above main's Flyway head; V-numbers are globally unique per DB

**Paradigm statement** — Flyway runs with `outOfOrder=false`, so a migration
V-number is **globally unique per database**, not per-branch. Before
submitting a migration PR, check `main`'s highest applied V-number and
ensure your new V-number sits above it with no collision against any
concurrent PR on `main`. If your branch has fallen behind (an earlier V on
your branch was already taken on `main`, making your number "unusable"),
**re-cut**: renumber the whole migration to a fresh V above main's head
rather than editing the stale one, because Flyway `validateOnMigrate` will
refuse to boot a DB whose `flyway_schema_history` row's checksum no longer
matches the file on disk.

**Source evidence** — `feedback-divergences.md` "Schema and migrations" row
and the stress-test table: "Schema re-cut above main's Flyway head (V39
unusable) → ✅ Renumbered to **V43 + V44** (`batch-api-docs.md`; Andreas said
V44 single re-cut, local splits batch tables vs S3 columns across two
migrations)." `playbook` Migration PR path step 1: "V-number collision. Does
the migration V-number collide with `main`? Flyway runs `outOfOrder=false`;
V-numbers are globally unique per DB." `playbook` convention "Migration
V-number uniqueness": "Flyway `outOfOrder=false`; migration V-numbers are
globally unique per DB; check `main` for collision before submit."

**<Provider> infra anchor** — `~/<provider>/gateway-db/flyway.conf` line 5
(and 8) — `flyway.outOfOrder=false` with `flyway.validateOnMigrate=true`
line 6. Main `gateway-db` head is **V37**
(`~/<provider>/gateway-db/migrations/` — highest is `V37__org_default_budget.sql`).
The batch branch `feat-batch-api-gateway-db` ships **V38, V40, V41, V42, V44**
with **V39 and V43 missing** (gaps) — the visible scar of the re-cut: an
earlier V39 was unusable, the work was renumbered up, and the final squash
landed at V44. The V44 migration header (lines 5-7) records the supersession
explicitly: "Supersedes the former `V43__batch_api.sql` + `V44__batch_s3.sql`
pair, which created `batch_file` then renamed it to `file` and ALTERed
columns in place. This file produces the same end state in one step." Any
concurrent PR that adds `V38__*` on `main` would collide with this branch's
`V38__db_report_view.sql` — exactly the collision the rule prevents.

**Codebase-intelligence backend** — Migration DDL is not a code symbol, so
Serena/codebase-memory/graphify do not index it. The check is filesystem +
git:
> `glob ~/<provider>/gateway-db/migrations/V*.sql` and
> `glob ~/<provider>/worktrees/batch-api/feat-batch-api-gateway-db/migrations/V*.sql`
> — diff the two V-number sets; any V present on both branches is a
> collision, any gap on the branch is a re-cut scar.
> `read ~/<provider>/gateway-db/flyway.conf` — confirm `outOfOrder=false`
> (the rule's precondition).
> `semble_search "V44 batch_api migration"` — locates the migration file by
> semantic match if the path is unknown.
> For the *concurrent-PR* collision (two open PRs both claiming V44), that
> is a Sector 09 cross-repo coordination check, not a single-repo schema
> check.

**Fix-suggestion policy** —
> SUGGEST ONLY: if a V-number collision with `main` (or a concurrent PR) is
> found, open a finding instructing the author to renumber the migration to
> the next free V above `main`'s head and update the `feat-batch-api-gateway-db`
> checkout's Flyway apply order. Do NOT rewrite the author's migration in
> place; the renumber touches the companion app PR's test workflow
> (`.github/workflows/test.yaml` checks out `gateway-db` at a ref and
> applies V1..V44), so the author must coordinate the ref bump.

**Adversarial caveat** — `outOfOrder=false` is a config, not a law of physics;
some teams set `outOfOrder=true` precisely to let long-lived feature branches
land after `main` has moved. The adversary could argue that re-cutting is
unnecessary friction if the team is willing to accept out-of-order applies.
The counter is that `validateOnMigrate=true` (also set in this `flyway.conf`)
still checksum-validates every applied row, so an edited-and-renamed
migration breaks boot on any DB that already applied the old version —
`outOfOrder=true` does not rescue a checksum mismatch. The re-cut rule holds
under this repo's actual config; it would not hold on a repo with
`validateOnMigrate=false`, which would be a different (and worse) problem.

### P-07-3: Drop-and-re-add CHECK constraints with the full expanded enum list on any enum change

**Paradigm statement** — <Provider> encodes enum validity as **Postgres
`CHECK` constraints** (`chk_*`), not native `ENUM` types, so a column's
legal values live in an `ARRAY[...]` literal inside the constraint. Adding
or removing a legal value therefore requires **dropping the existing
`chk_*` constraint and re-adding it with the full expanded type list** —
not `ALTER TYPE ... ADD VALUE` (there is no enum type) and not a partial
edit. A migration that adds a new source type but leaves the old `chk_*`
intact will reject every insert of the new type at the DB layer, silently
turning a "feature shipped" PR into a "feature 500s in prod" PR. The
reviewer's job is to confirm the constraint and the code agree after the
migration, not just that the code compiles.

**Source evidence** — `playbook` convention "CHECK-constraint enum
encoding": "Postgres `chk_*` constraints encode enum validity; changing an
enum requires updating the constraint." `playbook` Migration PR path step 2:
"CHECK constraint. If changing an enum, drop and re-add the `CHECK`
constraint with the full expanded type list. `chk_*` in SQL." `playbook`
convention "Canonical source creation": "`tbl_chat_sources` enforces schema
`CHECK` constraints and ownership via `createSource()` — hand-rolled
`INSERT` misses `11` fields and drift."

**<Provider> infra anchor** — The canonical CHECK-encoding pattern is
`tbl_chat_sources.chk_source_type` in
`~/<provider>/local-dev/schema/app-db/flyway/central/sql/V1__baseline.sql`
(table at line 1037, constraint): `CONSTRAINT chk_source_type CHECK
(((source_type)::text = ANY ((ARRAY['database', 'api', 'mcp', 'mcp_web',
'vectorized', 'tabular', 'mount', 'library', 'custom', 'ocr_image', 'file',
'excel_mcp', 'data_exploration_mcp'])::text[])))` — the **full expanded
list** Andrea's rule is named after. The canonical **drop-and-re-add**
sibling is `~/<provider>/local-dev/schema/app-db/flyway/central/sql/V44__skills_custom.sql:16-17`:
`ALTER TABLE tbl_skill DROP CONSTRAINT IF EXISTS chk_skill_scope_org;` /
`ALTER TABLE tbl_skill ADD CONSTRAINT chk_skill_scope_owner CHECK (...)` —
drop the old-named constraint, add the new one with the revised list, in one
migration. On the gateway side, the app-code counterpart is
`~/<provider>/app/backend/src/controllers/<provider>Chat.libs/sharedUpload.ts:114`
(`createSource`) — the canonical path that **relies on** the `chk_source_type`
constraint being in sync; a hand-rolled `INSERT` (the anti-pattern) would
bypass neither the constraint nor the 11 ownership/bookkeeping fields, but a
migration that adds a source type without updating `chk_source_type` makes
even `createSource` fail at the DB.

**Codebase-intelligence backend** — CHECK constraints are DDL, not code
symbols; Serena `find_symbol` and codebase-memory do not see them. Use text
search over the migration dirs:
> `grep -rn "chk_source_type\|chk_.*CHECK\|ADD CONSTRAINT chk" ~/<provider>/app-db/migrations/ ~/<provider>/local-dev/schema/app-db/flyway/central/sql/`
> — finds the constraint definition and every migration that touches it;
> a PR adding a source type should show a `DROP CONSTRAINT ... ADD CONSTRAINT`
> pair in its diff.
> `grep -rn "source_type" ~/<provider>/app/backend/src/controllers/<provider>Chat.libs/sharedUpload.ts`
> — finds the code-side enum usage to diff against the constraint's
> `ARRAY[...]`.
> `semble_search "chk_source_type CHECK constraint enum source_type"` —
> semantic locator when the constraint name is unknown.
> `codegraph explore -p ~/<provider>/app "createSource CHECK constraint
> enforcement"` — locates the canonical path that *depends on* the
> constraint being correct (the code side of the contract).

**Fix-suggestion policy** —
> SUGGEST ONLY: if a PR adds an enum value but its migration does not
> drop-and-re-add the corresponding `chk_*` constraint, open a finding
> quoting the `V44__skills_custom.sql:16-17` drop-and-re-add sibling and
> the `chk_source_type` full-list shape; the author adds the
> `DROP CONSTRAINT IF EXISTS ... ADD CONSTRAINT ... CHECK (... = ANY
> (ARRAY[<full list including new value>]))` pair. Do NOT write the
> constraint for them — the full list must be transcribed from the current
> constraint plus the new value, and a wrong transcription silently narrows
> the enum.

**Adversarial caveat** — A native `ENUM` type would make this a one-line
`ALTER TYPE ... ADD VALUE` and remove the "full expanded list" footgun
entirely; the adversary could argue the `chk_*` convention is itself the
defect and the fix is to migrate to `ENUM`. The counter is that `ENUM`
changes still need a drop-and-re-add for *removal* (Postgres has no
`ALTER TYPE ... DROP VALUE` without a rewrite), and `chk_*` keeps the legal
values queryable in one place (the constraint body) rather than split across
`pg_type` and the migration history. The convention is a deliberate
trade-off; the reviewer enforces it, doesn't relitigate it.

### P-07-4: Use CREATE INDEX CONCURRENTLY for indexes on existing large tables; plain CREATE INDEX is correct on fresh tables

**Paradigm statement** — Adding an index to a table that already holds
production data must use `CREATE INDEX CONCURRENTLY` to avoid taking an
`ACCESS EXCLUSIVE` lock that blocks writes for the duration of the build.
But `CONCURRENTLY` cannot run inside a transaction, so a migration that
creates a table **and** its indexes in one statement block (the fresh-table
case) must use plain `CREATE INDEX` — there is no existing data to lock
against, and Flyway wraps each migration in a transaction by default. The
reviewer distinguishes the two: a `CREATE INDEX` on a fresh table is
correct; a `CREATE INDEX` (non-concurrent) on `batch_request` *after* it has
been populated by a backfill is a blocker. Andrea's Migration PR path step 4
is explicitly conditional: "Does the migration use `CONCURRENTLY` for indexes
on **large tables**?"

**Source evidence** — `playbook` Migration PR path step 4: "CONCURRENTLY.
Does the migration use `CONCURRENTLY` for indexes on large tables?" (Note the
"large tables" qualifier — Andrea does not demand `CONCURRENTLY`
unconditionally.)

**<Provider> infra anchor** — `~/<provider>/gateway-db/migrations/` uses
`CONCURRENTLY` in **V17__drop_chat_type_column.sql**, **V19__one_default_model_per_org.sql**,
**V26__one_active_internal_user_per_user.sql**, **V28__usage_log_metadata_tags.sql**,
and **V31__internal_user_per_org.sql** — all migrations that touch
**already-populated** tables (`chat`, `models`, `users`, `usage_log`).
Contrast: `feat-batch-api-gateway-db/migrations/V44__batch_api.sql` uses
**plain** `CREATE INDEX IF NOT EXISTS` for all seven batch indexes (lines
57-62, 102-126, 176-191) — and this is **correct**, because V44 creates
`file`, `batch`, and `batch_request` in the same migration (lines 43, 76,
151) with no pre-existing rows; `CONCURRENTLY` would be both impossible
inside the transaction and pointless with zero rows. The convention is
"distinguish fresh from populated," not "always concurrent." A future
migration that adds an index to `batch_request` *after* V44 has run in prod
must switch to `CONCURRENTLY`.

**Codebase-intelligence backend** —
> `grep -rn "CONCURRENTLY" ~/<provider>/gateway-db/migrations/` — lists
> every migration that uses the concurrent pattern (the siblings to
> emulate for a populated-table index).
> `grep -rn "CREATE INDEX" <pr-migration>.sql` — checks whether the PR's
> index additions are concurrent; cross-reference against whether the
> same migration `CREATE TABLE`s the target (fresh → plain is fine) or
> `ALTER`s an existing table (populated → must be `CONCURRENTLY`).
> `read <pr-migration>.sql` — confirms whether the table is created in the
> same migration (the fresh-table exemption) or pre-exists.

**Fix-suggestion policy** —
> SUGGEST ONLY: if a PR adds a non-concurrent `CREATE INDEX` to a table
> that is NOT created in the same migration (i.e. already populated in
> prod), open a finding citing the `V19`/`V26`/`V28` concurrent siblings and
> the prod lock duration risk; the author changes to `CREATE INDEX
> CONCURRENTLY` and splits it into its own migration if needed (Flyway runs
> `CONCURRENTLY` statements outside a transaction only if the migration is
> the only statement or is marked accordingly). Do NOT auto-split the
> migration — the author owns the transaction-boundary decision.

**Adversarial caveat** — `CONCURRENTLY` has a real cost: it can fail and
leave an `INVALID` index that must be found and dropped, and it takes
longer than a locked build, during which the index is unavailable. For a
small table (a few thousand rows) the locked build finishes in
milliseconds and `CONCURRENTLY` adds failure modes for no benefit. The
adversary could argue the reviewer should size the table before demanding
`CONCURRENTLY`. The counter is that "large" is Andrea's own qualifier and
the reviewer's job is to ask "is this table large *or will it grow large
before the next migration window*," not to demand concurrency on a config
table. The `usage_log` case (V28) is genuinely large and concurrent is
load-bearing; the `file`/`batch` case (V44) is genuinely fresh and plain is
correct — the rule is "match the build mode to the table state," and both
directions of mismatch are findings.

### P-07-5: When renumbering or squashing, document the superseded pair and preserve the end state in one step

**Paradigm statement** — A re-cut or squash migration must (a) **preserve
the exact end-state schema** the superseded migrations would have produced —
no drift, no "close enough" — and (b) **record the supersession in a header
comment** naming the old file(s) and why they were replaced. The comment is
the review artifact: it lets a reviewer diff the squash against the
superseded pair's logical effect without digging through git history, and it
tells a future debugger why a V-number is missing from the sequence.
Andrea's specific concern (from `feedback-divergences`) was the *shape* of
the re-cut: he wanted a **single** V44 re-cut, where the local build split
batch tables vs S3 columns across two migrations (V43 + V44) before
squashing. The lesson is that a re-cut should be **one atomic migration to
the final state**, not a chain of rename/ALTER steps that a reviewer must
replay to verify.

**Source evidence** — `feedback-divergences.md` "Schema and migrations"
row: "Single re-cut at **V44** (Andreas) vs **V43** (`batch_api.sql`) +
**V44** (`batch_s3.sql`) — two migrations (`batch-api-docs.md`)." And the
stress-test adoption table: "Schema re-cut above main's Flyway head (V39
unusable) → ✅ Renumbered to **V43 + V44** (`batch-api-docs.md`; Andreas said
V44, local splits batch tables vs S3 columns across two migrations)." The
resolution (visible in the worktree) is the **squash**: a single
`V44__batch_api.sql` whose header records the supersession.

**<Provider> infra anchor** —
`~/<provider>/worktrees/batch-api/feat-batch-api-gateway-db/migrations/V44__batch_api.sql`
header, lines 1-7: "-- Squashed migration: creates the final Batch API
schema directly. (Supersedes the former `V43__batch_api.sql` +
`V44__batch_s3.sql` pair, which created `batch_file` then renamed it to
`file` and ALTERed columns in place. This file produces the same end state
in one step.)" This is the canonical shape: the comment **names the
superseded files**, **describes what they did** (create-then-rename-then-ALTER),
and **asserts the end-state equivalence** ("same end state in one step").
The missing V39 and V43 in the migration directory are the visible scar the
comment explains. The end-state preservation is verifiable: `V44` creates
`file` (not `batch_file`), `batch`, and `batch_request` in their final
shapes with no subsequent `ALTER TABLE ... RENAME` or `ALTER TABLE ... ADD
COLUMN` in the same file — the rename/ALTER chain was eliminated by the
squash.

**Codebase-intelligence backend** —
> `read <pr-migration>.sql:1-10` — check the header for a "Supersedes"
> comment when the migration directory shows a V-number gap (the gap is
> the signal that a re-cut happened).
> `grep -n "Supersedes\|supersedes\|squash" <pr-migration>.sql` — fast
> locator for the supersession note.
> `grep -c "ALTER TABLE .* RENAME\|ALTER TABLE .* ADD COLUMN\|ALTER TABLE
> .* DROP COLUMN" <pr-migration>.sql` — a squash-to-final-state should
> return ~0 rename/ALTER steps on the tables it creates; non-zero means the
> migration is a replayable chain, not a one-step end state, and is a
> finding under this paradigm.
> `glob ~/<provider>/<repo>-db/migrations/V*.sql` then look for V-number
> gaps — a gap with no supersession comment in the surrounding migrations
> is an undocumented re-cut.

**Fix-suggestion policy** —
> SUGGEST ONLY: if a re-cut migration lacks a supersession header, or
> contains create-then-rename-then-ALTER chains instead of a one-step final
> state, open a finding citing the V44 header as the canonical comment and
> the zero-ALTER property as the canonical squash; the author adds the
> header and (if feasible) flattens the chain. Do NOT rewrite the
> migration — the author must confirm the end state matches the superseded
> pair, and that confirmation is theirs to make.

**Adversarial caveat** — A squash throws away migration history, which some
teams treat as an audit trail (every ALTER is a recorded event). The
adversary could argue the V43+V44 chain should be preserved as-is for
traceability and only renumbered, not squashed. The counter is that
`feat-batch-api-gateway-db` has **never applied** V43 to any prod DB (it
was a feature branch above main's V37 head), so there is no audit trail to
preserve — the squash costs nothing and gains a one-step apply. On a branch
that *had* been applied to a shared DB, squashing would be a checksum
break; but that case is caught by P-07-2's `validateOnMigrate` check. The
paradigm applies to pre-merge re-cuts, not post-merge history rewrites.

## Cross-sector links

- **Shares NIT-2 evidence with Sector 12 (Code smell, naming & correctness-detail).**
  The missing `det_failures` index is *also* a Sector 12 "missing partial
  index" code-smell finding. Sector 07 owns the **migration/index** lens
  (the fix is a `CREATE INDEX` in the gateway-db migration); Sector 12 owns
  the **naming/code-smell** lens (the same finding also covers the
  `MAX_ATTEMPTS` → `MAX_DET_FAILURES` rename, which is code, not schema).
  Dedup pass: keep the index in Sector 07, the rename in Sector 12, and
  cross-link.
- **Shares the V-number story with Sector 09 (Multi-repo & deploy ordering).**
  P-07-2 owns the *rule* (globally unique per DB, re-cut above head,
  `outOfOrder=false`); Sector 09 owns the *coordination* (two concurrent
  PRs both claiming V44, migration-before-app deploy order, helm catalog
  compat). The V39-unusable → V43+V44 renumbering is grounded here because
  it is a schema-migration correctness event; the "companion PRs land as a
  set" framing belongs in Sector 09.
- **Shares the CHECK-constraint / `createSource` anchor with Sector 10
  (SSRF, redaction & security boundaries)** and the playbook's "Canonical
  source creation" convention. Sector 07 owns the **DB CHECK constraint**
  (`chk_source_type` staying in sync with the enum); the *ownership* part
  of `createSource` (ownership-before-discard, IDOR) is Sector 10. The
  `sharedUpload.ts:114` anchor is shared; the lens differs.
- **Shares the `CONCURRENTLY`-on-large-tables concern with Sector 11
  (Test coverage & CI gates)** insofar as the DB-backed test workflow
  (`.github/workflows/test.yaml` applies V1..V44 via Flyway in CI) is what
  catches a non-concurrent index build hanging in CI; Sector 07 owns the
  DDL correctness, Sector 11 owns the CI gate that exercises it.
- **Arguable overflow into Sector 07 from Sector 06 (Storage & content
  residency):** the V44 migration's "metadata only, content in S3" column
  design is a storage decision (Sector 06) expressed as schema (Sector 07).
  Flagged here; the dedup pass should keep the *column residency* in
  Sector 06 and the *migration mechanics* (squash, V-number, indexes) in
  Sector 07.

## Sector-specific failure modes

- **Flagging a non-concurrent `CREATE INDEX` as a blocker on a fresh
  table.** The fresh-table exemption (P-07-4) is real: a migration that
  `CREATE TABLE`s and `CREATE INDEX`es in the same transaction cannot use
  `CONCURRENTLY` and has no rows to lock. An agent that demands
  `CONCURRENTLY` on V44's `idx_batch_request_claim` is wrong — it would
  reject a correct migration. The check is "is the table already populated
  in prod," not "is the word CONCURRENTLY present."
- **Treating a V-number gap as a defect.** V39 and V43 are missing from
  `feat-batch-api-gateway-db` — an agent that flags "missing migration V39"
  as a flyway-integrity bug is wrong; the gap is a documented re-cut scar,
  explained by the V44 supersession header. The check is "is there a
  supersession comment explaining the gap," not "is the V-sequence
  contiguous."
- **Demanding a partial index where the predicate is not selective.** A
  partial `WHERE status = 'queued'` index is correct because `queued` is a
  small fraction of `batch_request` rows; a partial `WHERE det_failures >=
  0` index would be a full index in disguise (every row matches) and the
  agent should not pattern-match "Andrea wants partial indexes" onto a
  non-selective predicate. The `det_failures >= $1` predicate in
  `select_exhausted_queued` is selective only because `$1 = MAX_ATTEMPTS =
  3` is a high-water cap; the partial form is `WHERE status = 'queued'`
  (selective), not `WHERE det_failures >= $1` (a bind variable, unusable in
  a partial predicate).
- **Writing the CHECK constraint's full enum list for the author.** The
  drop-and-re-add fix (P-07-3) requires transcribing the *current*
  `ARRAY[...]` plus the new value; an agent that auto-generates the list
  risks silently dropping a legal value (a narrowed enum) or adding a typo.
  The fix-suggestion policy is SUGGEST ONLY for exactly this reason — the
  author owns the transcription, the reviewer owns the diff.
- **Assuming the gateway-db migration is in the gateway checkout.** The
  index/query coupling in P-07-1 spans two repos (`gateway` Rust code ↔
  `gateway-db` SQL DDL). An agent that greps only `~/<provider>/gateway/`
  for `CREATE INDEX det_failures` will conclude "no index" by looking in
  the wrong repo and may file a false positive (or miss the index that
  *does* exist). The check must target `gateway-db/migrations/`
  (or its worktree), and CodeGraph's `~/<provider>/gateway/.codegraph` is
  the *main*-branch gateway index, which has no batch module — a worktree
  query warns about this mismatch. Name the repo before naming the
  finding.

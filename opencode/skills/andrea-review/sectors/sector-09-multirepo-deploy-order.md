# Sector 09 — Multi-repo & deploy ordering

## Scope

This sector owns the **cross-repo coordination lens**: does a change that
spans `app` / `gateway` / `*-db` / `helm` land as a coherent set, in the
right order, with every companion PR open and approved before any one is
called ready? It asks of every PR: *what else has to move with this, and in
what sequence, and who owns the infra prerequisite?* It deliberately does
NOT own the schema/CHECK-constraint internals of a single migration (that is
Sector 07 — `outOfOrder=false` is the *mechanism* this sector relies on, but
the CHECK-constraint re-add is Sector 07's), the wire contract of any one
route (Sector 08), or the S3-storage residency decision (Sector 06). The
boundary is crisp: this sector is about *ordering across repos*, not the
contents of any one repo's diff.

The <Provider> topology that makes this lens load-bearing: this is an
**umbrella checkout, not a monorepo** (`AGENTS.md:5-8`). `app/`, `gateway/`,
`operator/`, `helm/`, `app-db/`, `gateway-db/` are **separate git repos,
cloned in place and gitignored**. Branches, merges, and ArgoCD deploys are
independent per repo, so a "batch API" feature is a **five-repo coordinated
set** (`feat-batch-api-{app,gateway,gateway-db,helm,sdk}` in
`worktrees/batch-api/`), and nothing enforces the set lands together except
reviewer discipline. Andrea Moccia's own commits and review items show he
treats that discipline as a first-class review concern.

## Paradigms (7)

### P-09-1: Land companion PRs as a set — none ready until all open and approved

**Paradigm statement** — A change spanning repos is one logical PR set.
Verify every companion PR is open and approved before calling any one ready.
A merged gateway PR whose `gateway-db` migration hasn't landed, or whose
`helm` catalog opt-in hasn't shipped, is a half-deployed bug, not a win.

**Source evidence** — `andrea-review-playbook.md` "Dependency
Cross-Checks": "Multi-repo PRs land as a set; verify every companion PR is
open and approved before calling any one ready." The batch API concretizes
this: `worktrees/batch-api/` carries
`feat-batch-api-{app,gateway,gateway-db,helm,sdk}` as a coordinated set, and
`HANDOFF-sdk-backend-compat.md` is literally a cross-repo contract audit
("make the SDK fully compatible with the backend before the batch feature
merges").

**<Provider> infra anchor** —
`worktrees/batch-api/feat-batch-api-gateway/src/routes/batches.rs:192`
(`create_batch`), `feat-batch-api-gateway-db/migrations/V44__batch_api.sql`
(the migration the gateway's `verify_schema` probe requires), and
`feat-batch-api-helm/charts/gateway-router-config/templates/_helpers.tpl:120`
(the `batch:` opt-in the gateway worker reads). The five worktrees are the
physical artifact of the set contract.

**Codebase-intelligence backend** — `codebase-memory` is the only backend
that sees across repos. Query shape:
> `search_graph` BM25 `query="batch opt-in catalog route" project="home-mateo.delriolanse-<provider>-helm"` → confirms the helm `batch:` key exists; then `search_graph` on the gateway-equivalent (see P-09-6 caveat) for `create_batch` → confirms the route that consumes it exists. Graphify is union-only and does NOT synthesize the gateway→app or helm→gateway dependency edge (see P-09-6); codebase-memory's per-project indices are the right tool, and the `trace_path cross_service` mode is the only one that materializes real HTTP edges between them.

**Fix-suggestion policy** —
> SUGGEST ONLY: open a finding listing every companion PR (gateway, gateway-db, helm, app, SDK) with links; flag any that are missing, closed, or unapproved. Do NOT merge any one until the set is green. The PR author owns the merge ordering.

**Adversarial caveat** — "Open and approved" is necessary but not sufficient:
a companion PR can be approved on a stale base. The set is only safe if every
companion is rebased on its repo's current `main` at merge time — a V-number
collision (P-09-3) is the failure mode that "approved" doesn't catch.

### P-09-2: Migration-before-app — the DB PR lands first, the code PR behind it

**Paradigm statement** — A code PR that depends on a new/changed schema
column or table MUST land after its migration PR, never before. With Flyway
`outOfOrder=false`, a gateway/app image deployed ahead of its migrations
either fails to boot (if the code probes the schema) or silently 500s on
the first call that touches the missing column.

**Source evidence** — `andrea-review-playbook.md` "Dependency
Cross-Checks": "`app-db` ↔ `app` — migration lands first; client Flyway
`outOfOrder=false` enforces order. `gateway-db` ↔ `gateway` — same pattern,
enforce sequence." `gateway.md` MAJOR-5 evidence shows the gateway CI
standing up `gateway-db` and applying `V1..V44` before `cargo test` — the
test harness itself encodes migration-first.

**<Provider> infra anchor** — The enforcement is real and in-tree:
`worktrees/batch-api/feat-batch-api-gateway/src/db.rs:54` (`verify_schema`)
is called unconditionally at `src/main.rs:143` before any route is wired.
`db.rs:236-238` documents the posture: *"a gateway image deployed ahead of
the batch migrations must CrashLoop, not boot and 500 on the first batch
call / silently skip batch billing's `usage_log.batch_id` write."* The
probe list `BATCH_PROBE_TABLES` / `BATCH_PROBE_COLUMNS` (incl.
`("usage_log", "batch_id")`) is the migration→code contract made
machine-checked (`db.rs:251-262`). On the app side, `app-db` runs two
Flyway chains (`flyway/central/sql/`, `flyway/client/sql/`) each with
`outOfOrder=false` per `app-db/flyway/{central,client}/flyway.conf`.

**Codebase-intelligence backend** — Serena `find_symbol` to confirm
`verify_schema` and its probe list, then `find_referencing_symbols` on
`verify_schema` to confirm it's called from `main`. Query shape:
> Serena `find_symbol name_path="verify_schema"` (gateway) → `find_referencing_symbols` confirms `main.rs:143` caller. `codegraph explore -p ~/<provider>/gateway "verify_schema batch probe"` → reads the probe list verbatim.

**Fix-suggestion policy** —
> SUGGEST ONLY: if a code PR adds a column read by `verify_schema`'s probe list, flag that the probe MUST be extended in the same PR (or the set will CrashLoop on the old image reading new schema — or worse, boot on new image against old schema). Cite `db.rs:236`. Do NOT edit the probe; the author owns it.

**Adversarial caveat** — `verify_schema` only probes the tables/columns
listed; a migration that adds a column the code reads but the probe doesn't
check will boot fine and 500 on first use — the probe is a
defense-in-depth, not a complete contract. A new column needs its own probe
entry (the `db.rs:251` test enforces the list is complete only against the
tables already known, not against new ones).

### P-09-3: V-number collision across concurrent PRs on main — renumber above main's head

**Paradigm statement** — Flyway V-numbers are globally unique per DB and
`outOfOrder=false` rejects lower-numbered migrations applied after higher
ones. Before submit, check `main` (and any concurrent in-review branch) for
the V-number you picked; if it's taken, renumber above the current head, not
into the gap. A V-number shared with main makes Flyway refuse to start on
the next env that pulls both.

**Source evidence** — `feedback-divergences.md` schema section: "Single
re-cut at V44 (later correction to comment 3's V42)" and "V43 (`batch_api.sql`)
+ V44 (`batch_s3.sql`) — two migrations"; the row "Schema re-cut above main's
Flyway head (V39 unusable) ✅ Renumbered to V43 + V44". The full mechanism
is in `worktrees/batch-api/docs/batch-api-docs.md`: "origin/main is at V42…
The batch branch originally shipped V39/V40. That collided with main in two
ways: (1) Version collision — main already owns V40 (`usage_log_auth_org`)…
(2) `outOfOrder=false` — Flyway applies migrations strictly in ascending
version order. A database that has already run main's V40–V42 cannot later
apply a batch migration numbered V39."

**<Provider> infra anchor** — `gateway-db` main head is
`e0ae137 V42: per-org moderation policy` (`V42__org_moderation_policy.sql`).
The batch branch renumbered V39/V40 → V43/V44
(`gateway-db` commit `59af680` "renumber batch migrations to V43/V44 after
main V40–V42"), then squashed to a single `V44__batch_api.sql`
(commit `32fda04`). **Live, fresh, Andrea-authored anchor**: `app-db`
commit `c5a3703` (2026-06-29, author Andrea Moccia) — "app-db: renumber SSH
migrations V49-51 -> V52-54. Avoid collision with the in-review
sources-egress-cleanup, which already owns central V49/V50/V51 (and is
deployed on uat). Mine stack above uat's max (V51) so they apply cleanly
once sources-egress lands on main." This is the paradigm executed by the
paradigm's author, three weeks before the batch review.

**Codebase-intelligence backend** — This is a `bash`/`glob` fact lookup
(list the migration dir, `git log` the branch), not a graph query — `AGENTS.md`
explicitly says "`helm/` and `*-db/` are YAML and SQL — no symbols. Grep is
the correct tool there, not a fallback." Query shape:
> `glob path="gateway-db/migrations/V*.sql"` → sorted-V listing of main's head; `bash`: `git -C gateway-db log --oneline main..<branch> -- migrations/` → branch's added migrations; `git -C gateway-db ls-tree -r --name-only <branch> -- migrations/ | sort -V | tail` → confirm branch renumbers above main's head. For the cross-branch collision check: `git -C <db-repo> branch -a | grep -i <feature>` then `git -C <db-repo> ls-tree -r --name-only <remote-branch> -- migrations/` against every in-review branch.

**Fix-suggestion policy** —
> SUGGEST ONLY: open a finding citing the colliding V-number, the owning branch/commit on main, and the `outOfOrder=false` consequence (Flyway refuse-to-start). Recommend renumbering above main's head (and above any concurrent in-review branch visible on `origin`). Note the ops follow-up: `flyway repair` / baseline / wipe on envs that already applied the old filename (per `batch-api-docs.md` P1/B3 note). The PR author owns the renumber.

**Adversarial caveat** — "Above main's head" is a snapshot; a concurrent
PR can merge between your renumber and your merge, re-colliding. The only
safe check is at-merge-time against `origin/main` HEAD, not at-PR-open-time.
And the `flyway repair` ops step is real: renaming a file does NOT rewrite
`flyway_schema_history` on a DB that already applied the old filename —
envs that ran the old V39 need manual repair, which is invisible to the
graph and easy to miss.

### P-09-4: helm catalog model additions need compatible gateway route + app SDK — opt-in-by-presence, fail-closed at render

**Paradigm statement** — Adding a model to the `helm` catalog is not a
helm-only change: the gateway must know how to route to it and the app SDK
must accept the shape it returns. The `batch:` opt-in is by-presence; the
chart fail-closes at render if the opt-in and its required args don't land
together, so drift fails the deploy instead of silently breaking batch for
that model.

**Source evidence** — `andrea-review-playbook.md` "Dependency
Cross-Checks": "`helm` ↔ `app` / `gateway` — catalog model additions need
compatible gateway route + app SDK changes." `AGENTS.md`: "Adding a gateway
model route = a `helm/` catalog YAML entry, not gateway code. ArgoCD
auto-deploys. Runbook: `docs/model-deployment.md`." The batch concretization:
`worktrees/batch-api/feat-batch-api-helm/charts/gateway-router-config/templates/_helpers.tpl:119-165`
documents the opt-in-by-presence contract and the render-time fail gates.

**<Provider> infra anchor** —
`helm/catalog/gpu-prdc-1/vllm-stack/options-it/glm-5-2-nvfp4.yaml:28-36`
(the `batch:` opt-in with `inputCap: 262144`); the same file's
`args.scheduling-policy: priority` and `args.max-num-seqs` are the coupled
requirements. The chart enforces the coupling at render:
`_helpers.tpl:151-153` `{{- fail (printf "...deployment %q is batch-eligible
(has a `batch:` key) but args.scheduling-policy is %q, not \"priority\" — vLLM
would reject every batch line's priority tag...")}}` and `_helpers.tpl:154-156`
fails on missing/non-numeric `max-num-seqs`. The gateway side that consumes
the rendered ConfigMap: `worktrees/batch-api/feat-batch-api-gateway/src/catalog_routes.rs:77`
(`RoutesFile` parsed from the mounted `routes.yaml`). The app-SDK compat
artifact: `worktrees/batch-api/HANDOFF-sdk-backend-compat.md` (the
`Batch.metadata` `dict[str,str]→dict[str,Any]` widening, commit `d35d000`).

**Codebase-intelligence backend** — `codebase-memory` on the helm index is
the only backend that indexes the chart's Route nodes. Query shape:
> `search_graph project="home-mateo.delriolanse-<provider>-helm" query="batch opt-in scheduling-policy priority"` → the `__route__` nodes for the rendered ConfigMap; `get_code_snippet qualified_name="..."` to read the helper. Then `semble_search` on the gateway for "batch worker reads catalog routes" to locate the consumer. For SDK compat: `semble_search repo=~/<provider>/worktrees/batch-api/feat-batch-sdk "Batch metadata"` → the `_models.py` field that had to widen.

**Fix-suggestion policy** —
> SUGGEST ONLY: if a helm PR adds `batch: {}` to a catalog file, verify (a) the same PR or a companion sets `args.scheduling-policy: priority` + `args.max-num-seqs: <int>` (the chart's `{{- fail }}` will catch this, but only at deploy, not at review), (b) the gateway PR that reads the rendered `routes.yaml` is in the set, (c) the SDK PR that types the new/changed response field is in the set. Cite `_helpers.tpl:151`. The PR author owns the set.

**Adversarial caveat** — The chart's `{{- fail }}` is a render-time gate,
which means a missing `scheduling-policy` only fails at ArgoCD render, not
at PR review — so a reviewer who doesn't check the coupling is relying on a
deploy-time failure to catch a review-time mistake. And the chart gate is
wholly blind to the gateway/SDK side: a `batch:` key with perfect args
still breaks batch if the gateway PR reading the ConfigMap hasn't landed.

### P-09-5: Cross-repo HTTP edges (gateway→app) are real but must be confirmed via cross_service trace, not graphify union

**Paradigm statement** — When a change touches a call that crosses a repo
boundary (gateway→app, app→gateway), confirm the edge actually exists in the
deployed topology and that both endpoints move together. Do NOT trust a
merged-graph query to materialize the edge: graphify merge is union-only and
does not infer cross-repo HTTP calls. The only backend that synthesizes real
cross-repo HTTP edges is codebase-memory `trace_path` mode `cross_service`.

**Source evidence** — `_CONTEXT.md` backend 5: "graphify merge is union-only.
For real gateway→app HTTP edges use codebase-memory
`cross-repo-intelligence`." `andrea-review-playbook.md` paradigm
"Cross-reference companion PRs. Does this land as a set? What's the deploy
order?" The batch API is the worked example: ADR 0003 had a gateway→app
`/internal/batch-content/*` courier (HTTP edge on every body read/write);
ADR 0004 **deleted** that edge and moved content to S3. The edge's
existence/non-existence is itself a cross-repo coordination fact Andrea
stress-tested ("Content must leave Postgres; FlashBlade S3").

**<Provider> infra anchor** —
`worktrees/batch-api/feat-batch-api-gateway/src/config.rs:26-30` (`backend_url:
String`, "Base URL of the <provider>-app backend. Used by /v1/auth/exchange
and the user-data proxy routes to call /internal/* endpoints") and
`config.rs:258` (`validate_backend_url`). The deployed edge is visible in
the helm index as `__route__infra__http://<provider>-app-service:3001`
(from `environments/dev/gateway-values.yaml`). The batch-specific edge is
**absent by design**: `feat-batch-api-gateway/src/batch/s3_client.rs:6-9`
documents the deletion — "ADR 0003 app-backend courier (`content_client.rs`,
deleted): no `/internal/batch-content/*` hop, no `x-admin-secret`, no
client-DB tables." The remaining gateway→app edges (`/v1/auth/exchange`,
user-data proxy) still exist and still require the app PR to be in the set.

**Codebase-intelligence backend** — `codebase-memory` `trace_path` mode
`cross_service` is the canonical tool; graphify is explicitly NOT. Query
shape:
> `trace_path function_name="<gateway-route-handler>" project="home-mateo.delriolanse-<provider>-helm" mode="cross_service" direction="outbound" depth=3` — the helm index carries the infra `__route__` nodes (e.g. `http://<provider>-app-service:3001`) that are the deployed cross-repo edges. Gateway itself is NOT in the indexed project list (only `app`, `app-backend`, `app-client`, `helm`, `operator`, `python`, `e2e`); for gateway→app, query the helm index for the infra route, or run `index_repository repo_path=~/<provider>/gateway mode="fast"` to add it, then `trace_path cross_service` from the gateway route handler. Confirm graphify's limitation: `graphify query "gateway batch route to app"` returns a union BFS over app + worktrees with NO synthesized HTTP edge — the edge is absent from the union.

**Fix-suggestion policy** —
> SUGGEST ONLY: when a PR adds/changes a cross-repo HTTP call, open a finding naming both endpoints (gateway route handler, app `/internal/*` controller) and requiring both PRs in the set. If the edge is being REMOVED (as ADR 0004 removed the courier), require the app-side controller deletion PR in the set too (`feedback-divergences.md`: "app `batchContent` controller + client DB tables (V70) — Delete with S3 move ✅ Dropped"). The PR author owns the set.

**Adversarial caveat** — `trace_path cross_service` only works on indexed
projects; gateway is NOT in the default index list, so a naive query
returns "project not found" (verified live: `create_batch` on the
`gateway` project name errors). The agent must either query the helm index
for the infra route, or index the gateway repo first. Treating "no edge
found" as "no edge exists" is a false negative when the project isn't
indexed.

### P-09-6: ArgoCD auto-deploys on image-yaml bump — the deploy is the merge, review gate is CODEOWNERS

**Paradigm statement** — For `app`/`gateway`/`operator`, ArgoCD auto-sync
is ON for dev; merging the image-tag bump to `helm/environments/dev/` IS the
deploy. The only review gate between "build succeeded" and "pod restarts"
is CODEOWNERS on the image-yaml file. Dev image files are unowned
(auto-merge); UAT/prod image files are owned by Andrea+Michael and require
CODEOWNERS review. A PR that bumps a prod image file without a CODEOWNERS
approval is not a deploy — it's a blocked stage.

**Source evidence** — `AGENTS.md`: "ArgoCD auto-deploys. Runbook:
`docs/model-deployment.md`." `release.sh` header (lines 28-46): dev build
flow step 4 "Open a PR on the helm repo and auto-merge it (dev image files
are unowned in CODEOWNERS so no review is required)"; promote flow:
"promote uat → opens a PR (requires CODEOWNERS review). promote prod →
same shape, source is UAT not dev." `docs/model-deployment.md:519`:
"Branch protection on app/gateway/app-db/gateway-db = 1 approval,
code_owner=true. helm + ansible stay relaxed for direct-push (CODEOWNERS
still applies on the rare PR)."

**<Provider> infra anchor** —
`helm/.github/CODEOWNERS` (the catch-all `* @andrea-moccia_options
@michael-mcmahon_options` then the explicit empty-RHS unown block for
`environments/dev/{app,gateway,mcp,shell-pods,operator-hub}-images.yaml`
"Dev image tag files are bumped by release.sh on every build. Leaving the
RHS empty clears ownership: no CODEOWNERS review required, so the script
can open + auto-merge its own dev-bump PR"). UAT/prod image files are
governed by the catch-all (require CODEOWNERS). The deploy trigger:
`docs/model-deployment.md:223-243` — ArgoCD ApplicationSets poll the catalog
and render on reconcile (~3 min), and per `model-deployment.md:519` the
app/gateway ArgoCD auto-syncs on image bump (with the "ocp-ny5-dev sometimes
needs a hard refresh" gotcha at line 519).

**Codebase-intelligence backend** — This is a CODEOWNERS/YAML fact lookup;
`AGENTS.md` says grep is correct for helm. Query shape:
> `read path="helm/.github/CODEOWNERS"` → the ownership map; `bash`: `git -C helm log --oneline -- environments/dev/app-images.yaml | head` → confirm release.sh auto-merges land without review (commit messages like "ci: bump app dev tag"); `grep pattern="auto-merge|auto-sync" path="helm/"` to find the release-script's self-merge calls. For the ArgoCD topology: `read path="docs/model-deployment.md:519-521"` (branch protection + auto-sync notes).

**Fix-suggestion policy** —
> SUGGEST ONLY: if a PR bumps `environments/prod/<svc>-images.yaml` or `environments/uat/<svc>-images.yaml`, verify a CODEOWNERS approval is present (Andrea or Michael); if the bump is to `environments/dev/`, no review is required but flag that the merge IS the dev deploy (no further gate). If a feature PR is being called "done" but its prod promotion PR is unreviewed, the feature is not in prod. The PR author owns the promotion.

**Adversarial caveat** — "Auto-deploy on dev" means a merged dev image bump
is live in dev within ~3 min with NO human gate — a bad image is only caught
by dev smoke tests, not by review. And the "ocp-ny5-dev sometimes needs a
hard refresh" gotcha means "merged" ≠ "deployed" on that cluster; the
deploy-ordering claim can be true on paper and stale in fact.

### P-09-7: Ops/infra prerequisites are review-blockers, not follow-ups — name the owner

**Paradigm statement** — An infra prerequisite (S3 bucket provisioning,
ranged-GET spike, lifecycle assumption, per-env creds) that the feature
depends on is a **merge prerequisite, not a follow-up**. Review must name
the owner of each infra prerequisite and mark it NOT-RUN until the owner
confirms it; a feature that merges with an un-validated infra assumption
ships a load-bearing unknown.

**Source evidence** — `feedback-divergences.md` "From the stress-test"
table: "Andreas handles infra: buckets, ranged-GET spike, lifecycle
assumptions ◻ Ops prereq; spike marked NOT RUN in conformance matrix."
`gateway.md` Rebuttal (g): "Agreed the spikes are load-bearing unknowns;
treating the S3 spike as a merge prerequisite, not a follow-up (MAJOR-7)."
The verdict on Mateo's deferral: DECIDED-NOT-ACTIONED with the note "This
is a genuine deferral decision… but it contradicts Andrea's stated bar
('merge prerequisite, not a follow-up')."

**<Provider> infra anchor** —
`worktrees/batch-api/feat-batch-api-helm/catalog/gpu-prdc-1/vllm-stack/options-it/glm-5-2-nvfp4.yaml`
(the deployment that needs the S3 bucket + SSE-S3 + ranged GET); the
per-env bucket/creds table is in
`worktrees/batch-api/docs/adr/0004-batch-content-resides-in-flashblade-s3.md`
(the ADR's bucket table: NY //E dev/uat, prod DC, Vault paths). The
"NOT RUN" marker is in `worktrees/batch-api/docs/prd-conformance.md`'s
conformance matrix (the spike row). `docs/model-deployment.md:286` names the
end-to-end prereq: "End-to-end via gateway needs (a) the OCP
`gateway-router-config` chart to have synced… and (b) a valid API key with
this `<deployment>` in its `models` list."

**Codebase-intelligence backend** — `agentmemory` is the canonical backend
for "did we already decide who owns this infra prereq." Query shape:
> `memory_smart_search query="S3 bucket ranged GET spike owner batch"` → prior-session decisions on infra ownership; `memory_recall query="FlashBlade bucket provisioning"` → who provisioned which env. For the infra-as-code state: `read path="worktrees/batch-api/docs/adr/0004-batch-content-resides-in-flashblade-s3.md"` → the bucket table; `grep pattern="NOT RUN|not run|spike" path="worktrees/batch-api/docs/prd-conformance.md"` → the un-validated markers.

**Fix-suggestion policy** —
> SUGGEST ONLY: open a finding listing every infra prerequisite the feature assumes (bucket exists, creds provisioned, SSE-S3 PUT verified, ranged GET on SSE-S3 verified, path-style + SigV4 verified, scoped-key-with-delete-denied verified) and require each to be marked DONE with an owner name, or the PR is blocked. Cite `gateway.md` Rebuttal (g) — "merge prerequisite, not a follow-up." The PR author + named ops owner own the validation.

**Adversarial caveat** — Naming an owner is not the same as the owner
having done the work; "Andreas handles infra" in `feedback-divergences` is
marked ◻ NOT RUN, meaning the owner was named but the work was not
completed at review time — the paradigm can be satisfied (owner named)
while the feature still ships a load-bearing unknown. The only
real closure is the owner's NOT-RUN→DONE flip, which the graph cannot
observe.

## Cross-sector links

- **Shares the `outOfOrder=false` mechanism with Sector 07 (Schema/migrations).**
  Sector 07 owns the CHECK-constraint re-add, `CONCURRENTLY`, and the
  schema-internal correctness of a migration; this sector owns the
  V-number *collision* and *ordering across repos* that the same
  `outOfOrder=false` flag enforces. The V39/V40→V43/V44 renumber is
  Sector 09; what those migrations contain is Sector 07.
- **Shares BLOCKER-2 evidence with Sector 03 (Graceful shutdown) and
  Sector 05 (Billing/state-machine).** The batch worker shutdown drain is
  Sector 03; the same-txn finalize guard is Sector 05; this sector's
  concern is that the *gateway PR + gateway-db migration + helm opt-in*
  land as the set that makes the worker able to run at all.
- **Shares the `BACKEND_URL` / `/internal/*` edge with Sector 10 (SSRF/
  security).** `validate_backend_url` (`config.rs:258`) is a security
  posture (reject plaintext-remote to protect `x-admin-secret`); this
  sector's concern is that the edge exists and both endpoints move
  together. The deleted `/internal/batch-content/*` courier was both a
  security surface (Sector 10) and a cross-repo dependency (Sector 09).
- **Shares the `verify_schema` probe with Sector 11 (Testing/CI).** The
  `verify_schema_passes_against_migrated_test_db` test (`db.rs:269`) is
  Sector 11's CI gate; this sector's concern is that the probe is the
  migration→code ordering contract. A new column without a probe entry
  is a Sector 09 ordering gap AND a Sector 11 test-coverage gap.
- **Arguably belongs in another sector:** P-09-6 (ArgoCD/CODEOWNERS) is
  as much a release-process concern as a review concern; if the
  orchestrator prefers a "release-strategy" sector, this paradigm could
  move there. Flagged for the dedup pass — the *review* lens (CODEOWNERS
  approval as the only gate) is what keeps it here.

## Sector-specific failure modes

- **Treating "all companion PRs open and approved" as sufficient.** A
  companion can be approved on a stale base; a V-number collision
  (P-09-3) or a schema-column drift (P-09-2) appears only at merge/rebase
  time. The set is safe only if every companion is re-checked against its
  repo's `origin/main` HEAD at merge, not at open.
- **Trusting graphify's merged graph for cross-repo HTTP edges.** Graphify
  is union-only and does NOT infer gateway→app HTTP calls; an agent that
  runs `graphify query "gateway to app"` and sees no edge will wrongly
  conclude the edge doesn't exist, or will see app-internal calls and
  mistake them for the cross-repo edge. Only `codebase-memory trace_path
  cross_service` (or the helm index's infra `__route__` nodes) materializes
  the real edge.
- **Querying an un-indexed project.** Gateway is NOT in the default
  `codebase-memory` project list (`home-mateo.delriolanse-<provider>-{app,
  app-backend,app-client,helm,operator,python,e2e}`). A `trace_path` on
  `"gateway"` or `search_graph` on a gateway function returns "project not
  found" / "function not found" — the agent must query the helm index for
  the infra route, or `index_repository` the gateway repo first. Treating
  the error as "no edge" is a false negative.
- **Flagging a helm `batch:` opt-in as a complete batch-enablement.** The
  `batch:` key is one of three coupled requirements (opt-in + `scheduling-
  policy: priority` + `max-num-seqs`); the chart's `{{- fail }}` catches
  the args coupling at render, but is wholly blind to the gateway/SDK
  side. A "helm PR added `batch:`" finding that doesn't check the gateway
  route + SDK PRs in the set is incomplete.
- **Confusing "renamed file" with "applied migration."** Renaming
  `V39__batch_api.sql` → `V43__batch_api.sql` does NOT rewrite
  `flyway_schema_history` on a DB that already applied V39; envs that ran
  the old filename need `flyway repair`/baseline/wipe. An agent that sees
  the renumber commit and marks the ordering "fixed" misses the ops
  follow-up (the P1/B3 note in `batch-api-docs.md`).
- **Treating "owner named" as "prereq done."** P-09-7's infra-prereq
  paradigm is satisfied by naming an owner, but the feature still ships a
  load-bearing unknown until the owner flips NOT-RUN→DONE; the graph
  cannot observe that flip, so an agent that closes the finding on
  "owner assigned" is premature.

# reMarkable tablet → vault course notes: cloud sync facts (researched 2026-08)

Condensed, grounded findings for getting handwritten reMarkable notes INTO the vault's
`cornell/courses/<slug>/` silo automatically. Use this before building or re-deriving
the transport. Spec lives at `raw/inbox/future-work/remarkable-obsidian-course-pipeline.md`.

## What reMarkable actually supports
- **Official cloud integrations** (Google Drive / Dropbox / OneDrive): browse, import,
  export. **Export is MANUAL and per-file** (long-press → Export → saved as PDF). There is
  **no automatic push-to-folder**. So "auto-upsert" cannot be built on the Drive
  integration — it's a fallback/manual path only.
- **Export formats:** PDF (whole notebook), PNG per page, SVG per page, plain text.
  Import: "Convert to Notebook" for .docx/.txt.
- **Native file format (`.rm`):** proprietary binary, but open/parseable (vector pen
  strokes). Cloud returns it packed in a ZIP with `metadata.json`, `.content`, `.pagedata`.
- **Handwriting → text:** built-in "Convert to text" (MyScript) is a Connect feature,
  decent on clean handwriting, poor on cursive/messy. Local tesseract is weak on
  handwriting. Big-provider OCR (user chose **Mistral OCR 4**) is the better nightly-pass
  choice.

## The Linux constraint (decisive)
- The **official reMarkable desktop app supports Windows 10+ and macOS 13+ only — NO
  Linux.** (A community Wine-wrapped snap exists but is unofficial/fragile.)
- That desktop app maintains a readable local sync cache at
  `~/.local/share/remarkable/desktop` (mirrors the tablet's xochitl store) — but since
  there's no Linux app, this "local-dir" route is **not available on a Linux vault box**.
- On Linux the realistic wireless path is the cloud API via a maintained client.

## Unofficial cloud API state (2026)
- Classic documented endpoints (service-manager discovery +
  `document-storage/json/2/docs`) are being **retired/rolled to a new sync protocol**.
  A live probe of the discovery endpoint returned 404 on this account. `rmapi` is
  **archived/unmaintained** (its README documents the breaking "new sync protocol"
  rollout).
- **Use `remarkable-mcp`** (github.com/SamMorrowDrums/remarkable-mcp, actively maintained,
  PyPI) as the engine. It implements the current protocol and covers sync + `.rm`→PNG/SVG
  rendering (rmscene + PyMuPDF) + typed-text/highlight reading + sectioned-Markdown export.
- **`remarkable-mcp` transports** (choose by constraint):
  - *Local directory* — reads the desktop-app cache; read-only; needs the (non-Linux) app.
  - *Cloud* — `uvx remarkable-mcp --register <CODE>`; wireless, headless; **requires a
    Connect subscription**; full document/folder mgmt. ← recommended on Linux.
  - *USB web* — physical cable + tablet USB-web enabled; no subscription, no dev mode;
    needs a cable per sync (fine for desk, not for a carried tablet).
  - *SSH* — requires developer mode on the tablet (modifies it; last resort).
- Registration code is a one-time 8-char code the user generates logged into
  my.remarkable.com; only the user can produce it (and confirm Connect). Not automatable.

## Subscription gating
- Connect: unlimited cloud sync, handwriting search, convert-to-text, full app mgmt.
- Free tier: only files edited in the last ~50 days sync to cloud; limited storage.
- → auto-pull depth is capped by the cloud sync window regardless of client.

## Recommended pipeline (fits raw-in/compiled-out) — superseded 2026-08-22, see the redesign
- **Current architecture: DESTINATION ROUTING** (full design: vault doc
  `raw/inbox/future-work/remarkable-puller-design.md`).
  1. **Poller (deterministic, no LLM/OCR):** walks `/Cornell/FA26` only (hard
     refusal guard for any other root), matches each class subfolder to a
     **registered** course slug in `cornell/courses/_index.md`, exports changed
     notebooks to a single annotated PDF, and drops
     `<YYYY-MM-DD>--<name>.pdf` + sidecar `meta.json` into
     `cornell/courses/<slug>/_inbox/remarkable/`. No centralized staging sink;
     no guess-routing; unmatched classes skipped + logged. Schedule: 18:00 + 03:00 cron.
  2. **Nightly consolidation (Cursor agent, opus tier, `run-agent-task.sh`), 04:00:**
     scans registered courses' `_inbox/remarkable/` for new drops, verifies
     `/Cornell/FA26` scope in `meta.json`, rasterizes pages + **Mistral OCR 4**,
     distills into `cornell/courses/<slug>/notes/` formalized markdown with a
     "what was done in class" summary. Raw PDFs stay in `_inbox/remarkable/` as evidence.
- Secrets (Connect token, Mistral key) live in `~/.hermes/.env` (+ `~/.rmapi` for the
  client token), never in the vault.
- **BUILD GATE (do not build before this):** `cornell/courses/` must be populated
  with the real FA26 course folders (copied from `_template/`) and registered in
  `_index.md`. The puller never invents course folders.
- **Learned gotchas:** `remarkable_export` returns a ResourceLink (read via
  `session.read_resource(uri)`; resolves by name/path, not doc id). reMarkable
  cloud rate-limits (HTTP 429) aggressive clients — pace calls, don't spawn
  debug loops. Phase 0 screening PASSED 2026-08-22 (transport + OCR both legs).
- PRD/companion history: vault doc `remarkable-obsidian-course-pipeline.md`.

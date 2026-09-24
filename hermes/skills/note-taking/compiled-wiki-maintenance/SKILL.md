---
name: compiled-wiki-maintenance
description: Reconcile conflicting vault notes; commit git checkpoints.
---

# Compiled-wiki maintenance (second-brain vault)

The vault at `/home/mdelrio/Documents/second-brain/` is a **compiled wiki**: agents are the compiler,
`raw/` is read-only ground truth, `entities/` and `concepts/` are build output, `INDEX.md` is the front
door, `Todos.md` + `todos/<date>.md` track todo items. Maintenance is **review-driven** (side effect of
code review / on-request), never scheduled. **AGENTS.md in the vault root is authoritative** — the
generic `obsidian` skill is bundled and does not encode these rules.

## Ground rules (from the vault AGENTS.md)
- **Never edit anything under `raw/`** — it is append-only ground truth. Only `raw/inbox/` is writable.
- Update the existing page; don't create a duplicate. Link related pages with `[[wikilinks]]`.
- Every compiled claim carries a source link back to `raw/` (or a URL). Unsourced claims get flagged.
- Write for a future session with zero context: include the *why*, not just the what.
- Research pages carry `expires` frontmatter (~90 days out) so stale intel announces itself.
- Delete/update pages that turn out to be wrong — but never `raw/`.

## Cross-note claim reconciliation (the core workflow)
Notes resolving/clashing on the same fact link each other with `> ⚠️ conflicts with [[page]]` banners
that name the disagreeing page and line numbers. To reconcile:

1. **Read BOTH notes in full** — the banner sits on every page pointing at the other, so both must be
   edited to clear the conflict.
2. **Decide stale-snapshot vs updated claim.** Snapshot lines often say "as of <date>" or
   "not-yet-real" and reference a July/earlier capture. Check `created`/`expires` frontmatter to date
   each page. The newer page usually has the corrected fact.
3. **Verify against PRIMARY sources BEFORE editing:** the cited `raw/digests/<date>.md` file plus the
   external URLs. Use web_search/web_extract to confirm a source actually exists (e.g. an HF repo is a
   real weights repo) before citing it. Watch for **announcement-date vs actual-ship-date** nuance —
   correct a page whose "released <date>" was really just the announcement.
4. **Edit BOTH pages:** drop the `> ⚠️ conflicts with` banner, fix the stale line (mark it e.g. "July
   snapshot — since SHIPPED" rather than deleting the history), and add/refine the reconciled fact with
   its sources. A reconciled fact often *strengthens* the older page's thesis — say so in the edit.
5. **Check off the originating todo** in `todos/<date>.md`, and the durable `Todos.md` if the item
   lives there (check both — the item may only be in one).
6. **Verify zero banners remain:** grep `⚠️ conflicts with` across `concepts/` (search_files skips
   hidden dirs; this path is not hidden).

## Vault git checkpoint commits
- The vault git is **local (no remote)** — "commit checkpoints, no cloud sync." Nothing leaves the
  machine.
- Commit only the files in scope for the task. If unrelated outstanding work shares the tree, group it
  into **logical commits** with descriptive per-group messages (e.g. cornell planning / internships
  tracker / resume variants / references) — never one sweep-all commit.
- **Before committing `references/credentials-and-blocking-info.md`, confirm the diff adds NO raw
  secret values.** It is an index; actual values live in `dotfiles/` and `~/.hermes/.env`, outside the
  repo. Only pointer/deprecation edits are safe.
- After committing, confirm `git status --porcelain` is empty.

## Pitfalls
- Don't trust the generic `obsidian`/`obsidian-vault` skills for vault layout — their paths/naming
  (title-case, `~/Documents/Obsidian Vault`) are stale vs the compiled-wiki (`second-brain/`,
  kebab-case). Follow this skill + the vault's AGENTS.md.
- Don't "fix" both pages to the same wording blindly — the older page's history is legitimately the
  older view; mark it as superseded, don't rewrite the record.
- Don't run a batch/unsupervised wiki compile — corrections happen in the session where the raw source
  is consumed, verified like a review.

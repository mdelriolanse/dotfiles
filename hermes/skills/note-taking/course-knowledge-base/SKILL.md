---
name: course-knowledge-base
description: Build and maintain per-course knowledge bases in the Obsidian vault (the `courses/` silo) and pull course content into them — including LMS (Canvas) ingestion. Use when the user is setting up their class file system, wants to sync/ingest course materials, generate groundable quizzes from a course, track coursework per class, or references "the courses/ skeleton", "the course pipeline", or a "Canvas" integration.
---

# Course Knowledge Base & LMS Ingestion

Builds the user's per-course knowledge base in the Obsidian vault and connects
agents to course content (starting with Canvas at Cornell). This is an active
multi-session project; decisions here are hard-won and should not be re-litigated.

## The courses/ silo (canonical spec lives in the vault)

The `cornell/courses/` silo (canonical spec lives in the vault): path `/home/mdelrio/Documents/second-brain/cornell/courses/`.
**`cornell/courses/_index.md` is the single source of truth** — the skeleton spec, the
ingestion-contract table, and the slug registry. `cornell/courses/_template/` is a
copy-me scaffold per course.

Per-course layout (one folder per slug, kebab-case `<dept>-<number>` e.g. `ece-3150`):
```
cornell/courses/<slug>/
  index.md         # course home
  syllabus.md      # syllabus, kept raw (usually first wave of ingested content)
  schedule.md      # due dates/exams/office hrs — AUTO-POPULATED by sync
  materials/       # RAW source files as delivered, by week-NN/
  notes/           # compiled markdown distilled from materials/   [agent-compiled]
  problem-sets/    # psets + solutions / submission copies
  quizzes/         # generated SRS quizzes + review history        [agent-compiled]
  feedback/        # handwritten-work feedback + mastery (FSRS)    [agent-compiled]
  _inbox/          # unprocessed drops awaiting triage
```

**Core rule — raw-in/compiled-out:** `materials/`, `syllabus.md`, `schedule.md`
are *ingested* (written by the sync/agent pulls). `notes/`, `quizzes/`,
`feedback/` are *agent-compiled* and must NEVER be overwritten by any pull.
Design principle: the layout is **layout-independent** — content lands in the
same local place no matter how a professor structures their Canvas course.
The vault's `AGENTS.md` has a "Resolving course references" rule (slug →
`courses/<slug>/index.md` via the registry), mirroring the projects rule.

## Design decisions (user choices — do not re-open)

- **Open-source & local only.** FSRS for SRS scheduling (not a SaaS, not
  build-your-own scheduler). Local LLM for question generation (citation-grounded,
  never invent facts). Local open VLM (no Mathpix) for handwritten-work feedback.
  No Notion, no Quizlet, no closed third-party services. See the future-work note
  `hermes-course-quiz-pipeline.md` for the full documented rationale.
- **Quiz content is always citation-grounded** in the course corpus — grading
  rubrics derived from the course's own material, not generic answers.

## Canvas ingestion — decision logic (read before building any pull)

**Token route is institutionally gated at Cornell.** Canvas API tokens require an
approval form justifying "AI bot" use, and the token-creation page explicitly
warns against sharing the token with AI bots/third parties. Treat this as
high-friction, not a button-click.

**Browser-automation route (token-free):** valid approach, BUT only build it
**after the user is enrolled in the course and a real Canvas page exists.**
Professors structure Canvas differently (Files vs. Module attachments vs.
external Drive links vs. HTML pages) — the app chrome is standardized but
content placement varies per professor, so selectors **cannot be validated
blind**. Do NOT build a hardcoded scraper before seeing a live course; confidence
in any pre-built sync is low. Instead the agent walks a real course adaptively
(browser/vision read the page like a human), maps where content lives, then
writes the pull.

**Critical coupling:** any Canvas pull MUST write into the exact destinations in
the `courses/_index.md` ingestion-contract table (syllabus→`syllabus.md`,
slides→`materials/week-NN/`, announcements/due-dates→`schedule.md`, ambiguous→`_inbox/`).
Read that spec each run before ingesting. Never write into `notes/`/`quizzes/`/`feedback/`.

**Fallback that always works:** the user dropping files manually into `courses/<slug>/`
is first-class input. The knowledge base must be robust to manual drops, not
dependent on Canvas success.

## Pitfalls

- **Do not build automation against a course layout you can't see yet** — it's
  brittle and untrustworthy. Defer until enrolled.
- **Do not store a Canvas token in `config.yaml` / hand it to a broad MCP binary.**
  If a token is ever used, it belongs in `~/.hermes/.env`, read-only scope, short
  expiry, revocable. Prefer token-free browser automation against the user's own
  session.
- **Never let raw source files and compiled notes mix** — the sync writes only to
  ingested locations; compiled dirs are agent-owned.
- Keep the `courses/_index.md` registry and `AGENTS.md` accurate whenever a course
  is added/renamed.

## See also
- Reproduce the scaffold from `templates/course-scaffold.md` (copy-me folder map / golden rule).
- Vault spec: `courses/_index.md`, `courses/_template/`, and the vault `AGENTS.md`.
- Project genesis & pipeline notes: `raw/inbox/future-work/hermes-course-quiz-pipeline.md`.
- `obsidian-vault` / `obsidian` skills for general vault file mechanics.
- `pull-lecture-notes-to-remarkable` — on-demand Cursor Opus scan → vault + tablet.
- `lecture-study-guide-pipeline` — **mandatory** whenever building a study
  resource (walkthrough, practice set, quiz, flashcards) off a course's
  `materials/`: OCR-first for handwritten/scanned lecture PDFs, LaTeX-typeset
  PDF output via tectonic. Writes to the new `study-guides/` bucket.

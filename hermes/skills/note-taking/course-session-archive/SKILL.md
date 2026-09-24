---
name: course-session-archive
description: Archive a course Q&A chat into the vault's sessions/ folder.
---

# Course session archive

Compiles a course-related tutoring/discussion chat into a durable, exam-ready
review artifact in the Obsidian vault, under the correct course's `sessions/`
bucket. Generic across every registered course — never hardcode a course.

## Trigger phrases

"archive this session", "save this discussion", "log this chat", "file away
what we covered", or any clear equivalent asking to persist a course Q&A.

## Procedure

1. **Resolve the course.** Look at what was actually discussed (terminology,
   problem content, any course explicitly named) and match it against
   `cornell/courses/_index.md`'s Registry table. If more than one registered
   course plausibly fits, or none obviously do, **ask the user** which course
   — never guess a slug (mirrors the vault's registry-first rule).
2. **Read that course's `index.md`** to confirm the slug/path, and check
   whether `sessions/README.md`, `sessions/_index.md`, `sessions/topics.md`,
   and `sessions/tags.md` already exist under `cornell/courses/<slug>/sessions/`.
   If missing, create them (see Scaffolding below) and link `sessions/_index.md`
   from the course's `index.md` Contents list plus an "Invoke: archive a
   discussion" blurb — do this once per course, not every archive.
3. **Compile, don't dump.** Never paste the raw verbatim transcript. Write a
   structured markdown note with:
   - Frontmatter: `type: session`, `course: <slug>`, `date`, `tags`.
   - One-line summary at the top (vault convention).
   - `## Topics covered` — numbered list of concepts/techniques discussed,
     each with enough detail (formulas, worked examples, key distinctions)
     that this note alone is useful without re-reading the chat.
   - `## Specific questions the user asked` — the user's actual questions,
     lightly cleaned up but preserving intent/wording, so review can retrace
     *what confused them* (often more diagnostic than the answers).
   - `## Open threads / good exam-review angles` — anything flagged as worth
     re-practicing, corrections made mid-conversation, or loose ends.
   - `## Source` — session id / date / platform for traceability.
4. **File it**: `cornell/courses/<slug>/sessions/<YYYY-MM-DD>--<topic-slug>.md`.
   Topic-slug = kebab-case, 3-6 words capturing the core topic (not "session-1").
5. **Update `sessions/_index.md`**: add a line under the most fitting `##`
   topic heading (create a new heading if none fits), linking the new file
   with a one-line descriptor. This index — not a raw file listing — is what
   the user scans at midterm/final time, so keep it topic-organized, not just
   chronological.
6. **Update `sessions/topics.md` (the refcount ledger) — mandatory, do this
   for every archive, no exceptions.** Topics are matched by **tag-set
   overlap**, not by title string/semantic similarity — titles drift over a
   semester, tags are a stable, shared, growing vocabulary. Procedure per
   distinct topic/lesson under "Topics covered" in the new session file:

   a. **Generate candidate tags** for the topic (short, kebab-case, atomic —
      e.g. `rref`, `pivots`, `consistency`, not whole phrases).

   b. **Reconcile candidates against `sessions/tags.md`** (the shared tag
      vocabulary for this course) BEFORE using them. For each candidate,
      check if a close existing tag already covers it (e.g. `pivot` vs
      `pivots` vs `pivot-columns` should collapse to one canonical tag).
      Reuse the existing tag. Only add a genuinely new tag to `tags.md` if
      nothing fits — this is where fuzzy judgment happens, on short atomic
      tags (low drift surface), not on whole topic titles (high drift
      surface).

   c. **Match the topic against existing `topics.md` rows by tag overlap**:
      if a row's `Tags` set shares roughly half or more of its tags with
      the new topic's reconciled tag set, treat it as the same topic —
      regardless of how differently the title is worded this time.

   d. **If it matches an existing row:** increment `Count` by 1, append
      today's date to `Dates covered` (comma-separated, newest last), append
      the new session's link to `Sessions` (dedupe per session), and union
      in any newly-surfaced tags from this pass into that row's `Tags` (tags
      only ever accumulate on a row, never get removed here).

   e. **If no row overlaps enough:** add a new row — title, `Count: 1`,
      today's date, link to the new session, and its reconciled tag set.

   f. Keep topic granularity consistent with the existing ledger for that
      course (a real study unit, not so narrow every session mints new
      rows) — tag overlap naturally discourages fragmentation as long as
      step (b) is done honestly.
7. **Report back**: tell the user the file path, what topic heading it was
   filed under in `_index.md`, and a one-line summary of the ledger update
   (e.g. "2 topics bumped to count 2, 3 new topics added").

## Scaffolding a course's sessions/ bucket (first time only)

```
cornell/courses/<slug>/sessions/
  README.md      # one-line purpose + agent-compiled notice
  _index.md      # topic-organized index of archived sessions
  topics.md      # per-topic dated refcount ledger (table: Topic | Tags | Count | Dates covered | Sessions)
  tags.md        # flat, growing list of every tag ever used in this course's ledger — reuse before minting
  <date>--<topic-slug>.md   # one file per archived session
```

Both `topics.md` and `tags.md` start empty (header/blank) when scaffolded for
a new course — they fill in as sessions get archived. See populated examples
at `cornell/courses/math-2940/sessions/topics.md` and `.../tags.md`.

`sessions/` is an agent-compiled bucket, exactly like `notes/`, `quizzes/`,
`feedback/` — it must never be overwritten by any Canvas/reMarkable sync.
This bucket and its routing rule are documented in
`cornell/courses/_index.md` under "Session archiving — mandatory routing";
keep that spec in sync if this procedure changes.

## Pitfalls

- **Don't guess the course.** If the chat covered generic math with no
  explicit course mentioned, ask. Wrong-course filing pollutes another
  class's review material.
- **Don't dump verbatim transcripts.** The value is compilation — a raw dump
  is exactly as hard to review under exam pressure as scrolling the chat.
- **Don't create a new `sessions/_index.md` entry structure per file** — reuse
  the existing topic headings when the new session fits an existing one, so
  the index stays a small number of well-populated topic clusters, not one
  heading per file.
- **Don't touch `notes/`, `quizzes/`, `feedback/`, or any raw/ingested path**
  — sessions are their own bucket, kept separate from lecture-note synthesis.

## Pitfalls (ledger-specific)

- **Don't skip the ledger update.** It's the whole point — without it,
  `course-session-review` has no way to know what's stale or under-covered.
- **Don't skip the tag-reconciliation step.** Minting a new tag for every
  session instead of checking `tags.md` first defeats the entire point of
  using tags — you'd just be trading title-drift for tag-drift.
- **Don't match topics on title text.** Two sessions can describe the exact
  same lesson in completely different words; tag-set overlap is what makes
  matching robust to that. If you catch yourself comparing title strings to
  decide if a topic is "the same," stop and compare tag sets instead.
- **Don't let Count drift from Dates covered.** They must always match in
  length — that's the corruption check `course-session-review` relies on.

## See also
- `cornell/courses/_index.md` — skeleton spec, registry, ingestion contract.
- `course-knowledge-base` skill — the broader per-course KB this bucket lives in.
- `course-session-review` — the companion skill that consumes `topics.md` to
  drive spaced-repetition-style review, then builds LaTeX study guides.
- `lecture-study-guide-pipeline` — for building actual study guides from
  lecture materials (different from session archives — that pipeline compiles
  `materials/`, this one compiles chat discussions).

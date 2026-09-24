# Course template — how to start a new course

Copy this folder to `courses/<slug>/` (e.g. `courses/ece-3150/`) to begin a
course. Then:

1. Rename `index.md`'s title/placeholders to the real course.
2. Register the course in `courses/_index.md` (registry table).
3. When enrolled, drop the syllabus into `syllabus.md` — that's the first wave
   of content the Canvas automation will pull.

Read `../_index.md` (the canonical spec) before ingesting anything.

## Folder map

| Path | What lives here | Who writes |
|------|-----------------|------------|
| `syllabus.md` | The syllabus, kept raw | Canvas sync / you |
| `schedule.md` | Due dates, exams, office hours (structured) | Canvas sync |
| `materials/` | Source files **as delivered** (slides PDFs, readings), by `week-NN/` | Canvas sync |
| `notes/` | Your compiled markdown notes distilled from materials/ | **agent only** |
| `problem-sets/` | Psets + your solutions / submission copies | you |
| `quizzes/` | Generated SRS quizzes + review history | **agent only** |
| `feedback/` | Handwritten-work feedback + per-topic mastery (FSRS) | **agent only** |
| `_inbox/` | Unprocessed drops (photos of work, loose files) awaiting triage | you / sync |

**Golden rule:** `materials/`, `syllabus.md`, `schedule.md` are *ingested*.
`notes/`, `quizzes/`, `feedback/` are *compiled* and must never be overwritten
by any pull.

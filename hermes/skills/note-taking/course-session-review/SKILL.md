---
name: course-session-review
description: Review a course from archived sessions, by staleness.
---

# Course session review

Uses a course's archived `sessions/` (built by `course-session-archive`) to
drive exam review, prioritizing topics that are **stale** (long since last
covered) or **under-covered** (low refcount) — a spaced-repetition-style
emphasis model, but grounded in this student's actual discussion history
instead of a generic curriculum.

## When to use

Trigger on requests like: "help me review from our sessions", "quiz me on
what we've covered for [course]", "what should I focus on for the midterm",
"what have we not talked about in a while", or any request to study using
past chat discussions for a specific course (as opposed to lecture materials
directly — see the handoff note below).

## Procedure

1. **Resolve the course** via `cornell/courses/_index.md`'s registry (same
   rule as `course-session-archive` — ask if ambiguous, never guess).
2. **Read `cornell/courses/<slug>/sessions/topics.md`** (the ledger). If it
   doesn't exist or is empty, tell the user there's no session history yet
   for this course and suggest archiving sessions as they go, or route
   straight to `lecture-study-guide-pipeline` off `materials/` instead.
3. **Sanity-check the ledger**: for each row, `Count` must equal the number
   of dates in `Dates covered`. If any row is inconsistent, reconcile by
   actually reading the linked session files before trusting priorities —
   don't silently propagate a corrupted count.
3a. **Cross-check against `feedback/` (FSRS mastery), if it has data for this
   course.** `feedback/` tracks a *different* signal than `sessions/
   topics.md`: whether the student has actually demonstrated correct
   problem-solving on a topic (graded handwritten work, FSRS-scheduled),
   versus `topics.md`'s "have we discussed it in chat" signal. These can
   diverge — a topic can be chat-fresh but never tested, or FSRS-strong but
   chat-stale. Concretely:
   - Check whether `cornell/courses/<slug>/feedback/` has any per-topic
     mastery records (it may be empty/unbuilt — treat that as "no FSRS
     signal available" and skip straight to the pure `topics.md` ranking
     from step 4, don't block on this).
   - If FSRS mastery data exists for a topic, treat **weak-or-never-tested
     mastery** as an additional priority boost on top of the staleness/
     under-coverage ranking — a topic that's both stale-in-discussion AND
     weak-in-demonstrated-mastery is the true highest priority, ahead of a
     topic that's merely stale in one signal.
   - Do not let a strong FSRS mastery score fully suppress a chat-stale
     topic, and vice versa — the two signals answer different questions
     ("do you understand this" vs. "have we kept it warm in discussion"),
     so combine them as an additive nudge, not a veto in either direction.
4. **Compute priority.** For each topic, combine two signals:
   - **Staleness** — days since the most recent date in `Dates covered`
     (today minus the last entry). Larger = more urgent.
   - **Under-coverage** — low `Count` relative to the rest of the ledger
     (e.g. count of 1 while most topics sit at 3+ is a thin spot).
   Rank topics by a blend of both — a topic that's both old *and*
   low-count is highest priority; a topic covered recently and often is
   lowest. Don't overthink the exact formula (no need for real spaced-
   repetition scheduling math) — a simple sort by
   `(days_since_last, -count)` descending is enough. Surface the top
   handful (not the whole ledger) as what needs attention.
5. **Present the prioritized list to the user first**, plainly: which
   topics are stale/thin and why, before diving into content. Let the user
   confirm or redirect ("actually focus on X instead") — don't just barrel
   into generating material.
6. **Pull the actual content.** For each prioritized topic, go back to the
   linked session file(s) in `Sessions` and re-surface: the compiled
   explanation, the worked examples, and (importantly) the "Open threads /
   good exam-review angles" section — those are often the exact gaps to
   re-drill.
7. **Build the review artifact as a LaTeX-typeset PDF via
   `lecture-study-guide-pipeline`.** This is a hard requirement, not
   optional — the user's existing study guides for this course are LaTeX/
   tectonic PDFs in `study-guides/`, and review material must match that
   format and location. Concretely:
   - Follow `lecture-study-guide-pipeline`'s structure (motivation → boxed
     concept → unpack → worked example → connections), callout box
     conventions, and numeric-verification requirement.
   - Content is now sourced from **archived sessions**, not raw
     `materials/` lecture PDFs — treat the session files as the "source
     material" for Step 1 of that pipeline (already compiled and typo-
     checked, so no OCR step needed).
   - Prioritize section order by the staleness/under-coverage ranking from
     step 4, not the order topics happened to be discussed chronologically.
   - Output path and naming follow that pipeline's own convention:
     `cornell/courses/<slug>/study-guides/study-guide-N-<topic>.pdf` +
     `tex-src/study-guide-N.tex`. Pick the next available N.
8. **After building it, do NOT update `topics.md`** — a review artifact is
   not a new discussion session, so it shouldn't inflate refcounts. Only
   `course-session-archive` writes to the ledger.
9. **Optionally offer** a quick verbal/interactive quiz pass over the
   prioritized topics before or instead of a full PDF, if the user just
   wants a fast gut-check rather than a new artifact.

## Priority formula reference (keep it simple)

```
priority_key = (days_since_last_covered, -count)
# sort descending by days_since_last_covered, break ties by lower count first
```

No need for a real FSRS-style memory-strength model here — `topics.md` is a
coarse signal (dated refcounts), and the goal is "don't let anything go
untouched for too long," not precise recall-probability modeling. FSRS
machinery already exists elsewhere in the vault (`feedback/` buckets) for
finer-grained mastery tracking if that's ever wired to this ledger later.

## Pitfalls

- **Don't skip presenting the priority list before generating content** —
  the user may want to redirect emphasis (e.g. "skip that, midterm doesn't
  cover it").
- **Don't silently trust a corrupted ledger** (Count ≠ len(Dates covered)) —
  reconcile from source session files first.
- **Don't fall back to plain markdown/reportlab output** — matrices and
  multi-line derivations need real LaTeX; that's a hard rule inherited from
  `lecture-study-guide-pipeline`.
- **Don't bump `topics.md` counts from a review pass** — only archiving a
  new discussion session should do that, or the ledger stops reflecting
  actual instruction/discussion frequency.
- **Don't confuse this with `lecture-study-guide-pipeline`'s normal use
  case.** That skill's default source is raw lecture `materials/`; this
  skill's source is compiled `sessions/` content. Reuse its formatting and
  output conventions, but source content from the sessions ledger and
  session files, not by re-reading lecture PDFs from scratch (unless a
  session lacks enough detail and the user wants it cross-checked against
  the original lecture).

## See also
- `course-session-archive` — writes the `sessions/` files, `topics.md` ledger,
  and `tags.md` vocabulary this skill reads. Read that skill's SKILL.md for
  the ledger's exact schema if unclear.
- `lecture-study-guide-pipeline` — the LaTeX/tectonic pipeline this skill
  hands off to for final artifact production; mandatory for the actual
  typesetting step.
- `cornell/courses/_index.md` — registry + routing rules for both session
  skills.
- `cornell/courses/<slug>/feedback/` — the FSRS mastery-tracking bucket this
  skill cross-checks in step 3a, a separate signal from `topics.md`.

---
name: physics-study-guide-pipeline
description: Build physics study guides from unit notes and slides.
license: MIT
metadata:
  hermes:
    tags: [physics, latex, study-guide, tectonic, cornell, intuition, phys-2214]
    category: note-taking
    related_skills: [lecture-study-guide-pipeline, course-knowledge-base, pdf]
---

# Physics Study-Guide Pipeline (Unit Notes + Slides -> intuition-first LaTeX PDF)

Sibling to `lecture-study-guide-pipeline`, specialized for physics courses (e.g.
PHYS 2214) where the course ships **two independent, non-exhaustive sources**:
typed "Unit Notes" (the textbook-style derivations) and lecture slide decks
(in-class framing, clicker questions, worked exam problems, mnemonics). Neither
source alone covers the material — this skill's core discipline is treating
**both as mandatory inputs for every guide**, not just Unit Notes.

The other structural difference from the math-2940 pipeline: physics study
guides must build **physical intuition**, not just mechanical procedure. Every
derivation needs a plain-language "what does this equation mean and why"
layer, not just the algebra.

## When to use

Trigger on any request to build a study resource from PHYS 2214 (or a similar
physics course with Unit Notes + slides) material: "make a study guide for
units/lectures N-M", "build a review sheet for this unit", "summarize this
physics material". Same trigger phrasing as `lecture-study-guide-pipeline`,
but route physics courses here instead — the two-source and intuition
requirements below are physics-specific and would be wrong overhead for a pure
math course.

## Step 0 — Identify both sources, every time

For each lecture/unit number N in range, locate BOTH:
1. **Unit Notes**: `materials/lectures/Unit NN.pdf` — the typed textbook-style
   notes (has a table of contents PDF mapping unit -> topic; check
   `Physics 2214 lecture notes cover page and table of contents.pdf` if unsure
   which Unit number corresponds to which lecture range).
2. **Lecture slides**: `materials/lectures/Lecture_NN_f26 preview.pdf` (pre-class
   version) or `..._annotated.pdf` (in-class annotated version, prefer this one
   if both exist — it has the worked clicker-question answers and any
   in-lecture corrections/additions the preview lacks).

**Never build a guide from only one source.** The Unit Notes are the thorough
derivation but a written text is not the course — the professor's lecture slides
routinely add framing, mnemonics, extra worked exam-style problems, and
emphasis (what to actually remember) that the Unit Notes don't. Conversely,
slides are terse/incomplete without the full Unit Notes derivation behind them.
Cross-reference: if the slides mention something with no unit-notes backing
(or vice versa), include it and note which source it came from in your own
head — don't silently drop content because "only one source has it."

Both PDFs in this vault have real text layers (typed, not scanned) — use
the available PDF/file reader directly, no OCR step needed (unlike the math notes, which were
often scanned handwriting). Skip Step-0-OCR entirely for phys-2214, but if a
future physics course's source PDFs turn out to be scanned/handwritten,
fall back to `lecture-study-guide-pipeline`'s OCR step (Mistral OCR, one-off
consent) before proceeding.

## Step 1 — Extract for BOTH intuition and mechanics

Read every Unit Notes PDF and every corresponding Lecture slide PDF in the
range fully before drafting anything. For each concept/equation, capture three
layers, not just one:

1. **The foundational equation** — the actual equation as derived (e.g. the
   ideal wave equation, the pulse equation, the driven-oscillator amplitude
   formula). Write it exactly as the course does, in the same symbols.
2. **What each term/component physically means** — for every symbol in the
   equation, one clause on what it represents physically (not just "ω is
   angular frequency" — say why it appears squared, why it's a ratio of
   elastic-to-inertial constants, etc.). This is the layer generic math study
   guides skip and physics guides must include.
3. **Why the equation has the form it does / where it comes from** — the
   physical reasoning or derivation path (Newton's 2nd law + small-angle
   approximation, chain rule + wave ansatz, etc.), condensed to the key
   insight, not a full line-by-line rederivation unless the derivation itself
   is the pedagogical point (e.g. deriving wave speed from F=ma is itself the
   lesson in Unit 4).

Also extract, from the slides specifically: clicker questions (L#-# numbered)
and any "exam question" worked examples — these show exactly what the course
considers testable and at what depth. Reuse their structure/difficulty for new
practice problems (fresh numbers, same structure), same rule as the math
pipeline.

**Numerically verify every computed answer** (local Python/NumPy or direct
algebra by hand, checked) before it goes in an answer key — same non-negotiable
rule as `lecture-study-guide-pipeline`.

## Step 2 — Structure each guide section around intuition, not just derivation

For each major equation/concept, use this shape (not a strict template, but the
elements should all appear somewhere):

1. One or two sentences of plain-language motivation ("why do we care" / "what
   physical situation is this").
2. The foundational equation, boxed/highlighted.
3. A short "reading the equation" breakdown: what each symbol/term means and
   why it enters the way it does (ratio, sign, exponent).
4. The key derivation insight in a few lines (not full algebra unless that's
   the point), citing which unit/lecture it's from.
5. A worked example pulled from the actual lecture/unit material.

Callout boxes should be used for: foundational equations (distinct visual
treatment from regular text — e.g. a heavier border / different color than the
generic math guide's `callout` box), and for "physical intuition" asides.
Distinguish these two box types visually (e.g. `eqbox` vs `intuitionbox`) so a
student skimming can tell "formula to memorize" from "concept to understand"
at a glance.

## Step 3 — Typeset as LaTeX (tectonic), not reportlab

Same rationale and setup as `lecture-study-guide-pipeline` Step 2 (matrices/
multi-line derivations/aligned equations need real LaTeX). See that skill's
`references/tectonic-setup.md` for the tectonic install + PNG-render-and-
visual verification steps — reuse them verbatim, this skill doesn't
duplicate that reference.

Extend the math-2940 template (`references/study-guide-template.tex` in the
sibling skill) with an `eqbox` environment (foundational-equation callout,
distinct color, e.g. a warm accent vs the generic guide's cool blue) alongside
the existing `callout`/`answerbox`. Keep one `.tex` per guide, plus the
compiled PDF.

## Step 4 — Output locations

Per-course, under `cornell/courses/<slug>/`, same bucket convention as the math
pipeline:

```
study-guides/
  study-guide-<N>-<slug-topic>.pdf
  tex-src/
    study-guide-<N>.tex
```

Break lecture ranges into guides by topic boundary, not fixed lecture count
(ask if unclear). Never bake "N of M" into a document's own title.

## Pitfalls

- **Dropping one source because the other seems "complete enough."** The whole
  point of this skill vs. the math one is the two-source requirement — a guide
  built from Unit Notes alone reads like a textbook summary and misses what's
  actually taught/tested; a guide built from slides alone is missing derivation
  depth and the "why". Always open both PDFs for every lecture in range.
- **Reducing intuition to a restated definition.** "ω is the angular frequency"
  is not intuition — explain e.g. why ω² = k/m (ratio of restoring-force
  strength to inertia) rather than just naming the symbol.
- **Skipping the mechanical-to-EM (or general) correspondence tables** the
  course draws (e.g. mass-spring <-> series LRC circuit in Unit 2) — these
  cross-domain mappings are a recurring, testable teaching device in this
  course; preserve them when present in the source.
- **Matching terminology to the course, not a textbook** — e.g. use "amplitude
  decay time τ_A" and "energy decay time τ_E" exactly as Prof. Thorne's notes
  and lecture slides do, not generic "time constant."
- **Don't skip numeric verification** of answer-key values — carried over
  directly from the math-2940 pipeline's hard-won lesson.

## See also

- `lecture-study-guide-pipeline` — the math-2940 sibling this skill forked
  from; shares the tectonic/LaTeX toolchain and output-location convention.
  Read its `references/tectonic-setup.md` for the install + render steps.
- `course-knowledge-base` — per-course skeleton and Canvas ingestion rules.

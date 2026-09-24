---
name: lecture-study-guide-pipeline
description: Build study guides from course materials (any course); OCR if needed, LaTeX output.
version: 2.0.0
author: Mateo del Rio Lanse
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [ocr, latex, study-guide, tectonic, cornell, all-courses, unified]
    category: note-taking
    related_skills: [course-knowledge-base, concept-study-guide-pipeline, pdf, ocr-and-documents]
---

# Unified Lecture Study-Guide Pipeline (Any Course → Intuition-First LaTeX PDF)

Builds comprehensive study guides from any course's lecture materials (slides, typed notes, handwritten lecture PDFs, unit notes). Outputs clean LaTeX-typeset PDFs using `tectonic`, with pedagogically sound structure: progressive terminology introduction, worked examples grounded in course material, visual callout boxes for key concepts, and practice problems with verified answers.

**Single pipeline, all courses.** Route any course here (MATH 2940, PHYS 2214, CS 3110, etc.). Course-specific guidance below documents how to handle different source-material types (slides-only, two-source like physics, etc.).

## When to use

Trigger on any request to build a study resource from **course lecture material**:
- "make a study guide for lectures N-M"
- "build a review sheet for this unit"
- "summarize this week's notes"
- "create practice problems from the course material"

Applies to any course with lecture materials (slides, notes, recorded content transcripts).

**Important:** This skill is for **course-scoped material only.** Resources built here go into `cornell/courses/<slug>/study-guides/`. For standalone concepts from external sources (blog posts, papers, textbooks not tied to a course), use `concept-study-guide-pipeline` instead (outputs to `concepts/study-guides/`).

Does NOT apply to: syllabus/schedule ingestion (use `course-knowledge-base`), one-off help questions with no persisted artifact, or non-course standalone concepts.

## Step 0 — Identify source material(s) and OCR if needed

Before drafting, determine what lecture material you're working from:

### Source types and how to handle each:

**Type A: Typed lecture slides (PDF with text layer)**
- Examples: MATH 2940 problem worksheets, official slide decks, typed course notes
- Handling: Extract directly with `read_file` or `web_extract`
- OCR needed? NO

**Type B: Handwritten/scanned lecture notes (image-only PDFs)**
- Examples: Professor's handwritten lecture notes scanned, whiteboard photos, slide photos
- Handling: **Run Mistral OCR** before extracting content
- OCR needed? YES (see below)

**Type C: Two independent sources (common in physics/engineering)**
- Examples: PHYS 2214 (typed Unit Notes + lecture slides), E&M (textbook + lecture annotations)
- Handling: Extract both sources fully and cross-reference throughout
- OCR needed? Only if either source is scanned

**Type D: Recorded lecture transcript or AI-generated transcription**
- Examples: Course videos transcribed, Zoom lecture transcripts
- Handling: Extract as text, treat as equivalent to typed notes
- OCR needed? NO

### If OCR is needed:

1. Check fast: `pdftotext <file>.pdf -` in terminal — if output is gibberish or empty, it's scanned
2. Use **Mistral OCR** (see `references/mistral-ocr.md` for API call, one-time key handling, privacy framing)
   - Per this user's local-first preference: ask for explicit one-off consent every time a **new** key/session is needed
   - Export key → run OCR calls → `unset` key → delete temp files
   - Never persist Mistral key in config/memory/vault
3. If Mistral is unavailable/slow, fall back to `web_extract` on hosted PDFs or use `ocr-and-documents` skill for alternative providers

**Always extract once, reuse everywhere.** Don't re-run OCR per guide — extract all lecture material in the target range in one batch, save to markdown, then build however many resources you need from that markdown.

## Step 1 — Extract and verify content; ground in actual materials

### Read every source in the target range fully

Before drafting a single guide line:
1. If two sources (like PHYS 2214): open **both** Unit Notes PDFs and **both** Lecture slide PDFs side by side
2. For single-source courses: read the entire lecture range start to finish
3. Note which concepts appear where, what the course emphasizes, what's left to context

### Build the guide grounded in what was actually taught

1. **Never invent examples.** Every worked example must trace back to the source material (lecture slides, worked problems in notes, textbook section cited by professor). Fresh numbers with the same structure are fine for practice problems, but the template must be course-provided.

2. **Use the course's exact terminology.** If the professor says "basic variables" instead of "pivot variables," use "basic variables" in the guide. Terminology consistency with what students will hear in lecture is more important than textbook-standard terms.

3. **Progressive terminology introduction.** Define unfamiliar terms the first time they appear, using simple language. Build from concrete to abstract. If the course introduces concepts in a certain order, follow that order in the guide, not a different logical flow.

4. **Numerically verify every answer before finalizing.** Use `execute_code` with `numpy` (for linear algebra, span/rank checks), or by-hand algebra checked twice:
   - Matrix operations: verify with numpy
   - Algebraic manipulations: hand-check or symbolic (SymPy)
   - Numeric solutions: execute and verify against the problem setup
   - **Non-negotiable:** A plausible-looking wrong answer in an answer key is worse than no answer key at all.

5. **When extracting from two sources:** If the slides mention something with no unit-notes backing (or vice versa), include it and note the source in your internal reasoning. Don't silently drop content just because only one source has it.

## Step 2 — Structure for teaching, not just summarizing

A study guide is a **teaching document**, not a reference manual. Structure each section to build understanding progressively.

### Standard section shape (adapt to your course):

For each major topic/equation/concept:

1. **Motivation (1-2 sentences):** Why do we care? What physical/mathematical situation is this? What problem does it solve?

2. **Foundational concept/equation (boxed):** The core claim or formula, exactly as the course presents it. Use a distinct callout box (e.g., `eqbox` for equations, `conceptbox` for non-math concepts).

3. **Unpack the components:** For every symbol, term, or step:
   - What does it represent (in English)?
   - Why does it appear in this form (ratio, exponent, sign)?
   - What changes if you vary it?

4. **Why this form / where it comes from:** The derivation insight or physical reasoning in a few lines. Cite which lecture/section. If the full derivation is the lesson, include it; otherwise, give the key insight.

5. **Worked example from course material:** Pull directly from lectures or assigned problems. Show every step. This is what students should be able to replicate.

6. **Connection to related ideas:** Where does this fit in the bigger picture? How does it relate to the previous/next concept? (E.g., "This is the template for all driven harmonic systems; we'll see the same pattern in Units 5 and 7.")

### Callout box types (define these in your `.tex` preamble):

- **`conceptbox`** (e.g., warm gold/orange): Foundational equations, key definitions, the "memorize this" tier
- **`callout`** (e.g., cool blue): Key insights, conceptual takeaways, "understand why this is true"
- **`intuitionbox`** (e.g., light green): Physical intuition, real-world interpretation, "what does this actually mean"
- **`answerbox`** (e.g., light gray): Practice problem answers, worked solutions

This visual distinction lets students skim and know "formula" vs. "insight" vs. "intuition" vs. "solution" at a glance.

### Tips for teaching-oriented writing:

- **Start concrete, end abstract.** Begin with a specific example, then generalize.
- **Anticipate common confusion.** If students often mix up two related concepts, address it explicitly: "Note: This is NOT the same as [...], because [difference]."
- **Use analogies sparingly but well.** A good analogy bridges two domains the student knows; a bad one adds confusion. Only include analogies from the course material itself.
- **Numbered steps for procedures.** If explaining a method, break into steps (1. Do X, 2. Do Y, 3. Interpret result).
- **One lesson per subsection.** Don't pack multiple independent ideas into one section — use subsections to keep things scannable.

## Step 3 — Typeset as LaTeX with tectonic

LaTeX is mandatory for any guide with equations, matrices, or aligned derivations (reportlab produces garbled math).

### Setup (one-time per machine):

See `references/tectonic-setup.md` (shared with concept pipeline) for installing tectonic (static binary, no root needed) and rendering to PNG for verification.

### LaTeX template and customization:

1. Start from `references/study-guide-template.tex` (extends the standard article class with `amsmath`, `tcolorbox`, house style)
2. Extend it with callout box types for your course (e.g., add `conceptbox`, `intuitionbox` to the default `callout` and `answerbox`)
3. For PHYS/STEM courses: add an `eqbox` environment (warm-colored, used for foundational equations only)
4. Keep the color palette consistent with house style (blues for generic insights, warm tones for equations/key formulas)

### Writing `.tex`:

- Use `\section*{}` for major topics, `\subsection*{}` for subtopics
- Wrap equations/formulas in `\begin{conceptbox}...\end{conceptbox}` (or `\begin{eqbox}...`)
- Use `\begin{quote}...\end{quote}` for worked examples (monospace or indented to visually separate from prose)
- Use `\begin{callout}...\end{callout}` for conceptual insights
- Use `\begin{intuitionbox}...\end{intuitionbox}` for physical/real-world intuition (physics/science courses)
- Matrices: `\left[\begin{array}{ccc|c}...\end{array}\right]` for augmented, `\begin{bmatrix}...\end{bmatrix}` for regular

### Compile and verify:

```bash
tectonic study-guide-N.tex
# Download packages on first use per machine (needs network), then caches locally
```

Render to PNG for visual check:
```bash
uv venv /tmp/latexvenv --clear --quiet
source /tmp/latexvenv/bin/activate
uv pip install pypdfium2 pillow --quiet

python3 << 'EOF'
import pypdfium2 as pdfium
pdf = pdfium.PdfDocument('study-guide-N.pdf')
for i in range(len(pdf)):
    bitmap = pdf[i].render(scale=2.2)
    bitmap.to_pil().save(f'study-guide-N_p{i}.png')
EOF
```

Then `vision_analyze` each PNG to verify:
- Equations render correctly (no garbled LaTeX, no missing math symbols)
- Callout boxes have proper color and borders
- Matrices display cleanly
- Nothing overflows page edges
- Answer key is fully visible

**This verification step is mandatory, not optional.** LaTeX compiles happily even when overflow or bad spacing looks wrong on the printed page.

## Step 4 — Output locations and naming

All study guides go under the **course's** directory:

```
cornell/courses/<slug>/
└── study-guides/
    ├── study-guide-1-<topic>.pdf      # final artifact
    ├── study-guide-2-<topic>.pdf
    ├── study-guide-N-<topic>.pdf
    └── tex-src/
        ├── study-guide-1.tex          # LaTeX source (for future edits)
        ├── study-guide-2.tex
        └── study-guide-N.tex
```

**Naming convention:**
- Prefix with number: `study-guide-1`, `study-guide-2`, etc.
- Add descriptive slug after hyphen: `-triangular-and-echelon-form`, `-oscillations-and-waves`, `-recursion-and-induction`
- PDF name: `study-guide-1-triangular-and-echelon-form.pdf`
- `.tex` source: `study-guide-1.tex` (same number, no slug needed in source file)

**Topic segmentation:** Break lecture ranges by topic boundary, not a fixed lecture count. Ask the user if unclear, but default to natural topic divisions (e.g., "waves" is one guide, "driven oscillations" is another, not "lectures 3-5" as one guide).

**Never bake "N of M" into a document's own title** (e.g., don't write "Study Guide 1 of 3" in the PDF title). The "of 3" context belongs in chat/prose, not the artifact, since guides get reordered/added/removed and a hardcoded total goes stale immediately.

## Special cases by course type

### MATH courses (MATH 2940, MATH 2930, etc.)

**Sources:** Usually typed problem worksheets + typed or scanned lecture notes

**Structure:** 
- Start with a definition/concept
- Build intuition with simple examples (1-2D cases before high-dimensional)
- Worked problem from the lecture material
- Practice problems: fresh numbers, same structure
- Connection to next concept or real-world application if relevant

**Emphasis:** Mechanical procedure + why the procedure works (the "why" layer is what many math students miss). Show both the algorithm and the geometric/algebraic interpretation.

**Example:** MATH 2940 guides should include: definition of RREF, the row-reduction algorithm, why it preserves solutions, worked matrix example, free-variable extraction, practice problems.

### PHYS courses (PHYS 2214, PHYS 2213, etc.)

**Sources:** Typically two independent mandatory sources (typed Unit Notes + lecture slides), both non-negotiable

**Structure:**
- Physical setup / real-world scenario (what are we modeling?)
- Foundational equation(s) (boxed separately with `eqbox`)
- What each term means physically (not just mathematically)
- Derivation insight / where it comes from (Newton's laws, energy conservation, etc.)
- Worked example from course material
- Limits / special cases (what happens when X → 0, when X is very large, etc.)
- Correspondence with related systems (e.g., mass-spring ↔ LRC circuit)

**Emphasis:** Physical intuition + mechanical derivation. Every equation has a physical story. Explain why terms appear in the form they do (ratio of inertia to restoring force, not just "ω is angular frequency").

**Example:** PHYS 2214 oscillations guide: introduce simple harmonic motion with mass-spring, show the derivation from F=ma, unpack why ω² = k/m, worked example, then show the correspondence to LC circuits.

### CS courses (CS 3110, CS 2800, etc.)

**Sources:** Lecture slides, recorded lecture transcripts, provided problem sets with solutions

**Structure:**
- Problem/pattern being solved
- Algorithm or data structure definition (pseudocode or structural diagram)
- Why this approach / when to use it (motivation)
- Worked example: step through the algorithm on a concrete input (trace execution)
- Analysis: time/space complexity, correctness argument
- Practice problems: new instances of the same structure

**Emphasis:** Concrete before abstract. Always trace algorithms on examples before asking students to implement. Connect to previous algorithms/structures.

**Example:** CS 3110 recursion guide: start with factorial (concrete), show the call stack, explain the pattern, worked recursive function, then show list-processing recursion, then tree recursion, then practice problems.

## Pitfalls

- **Dropping a source because the other seems "complete."** If your course has two sources (math + physics), use both. Slides alone are too terse; Unit Notes alone are too textbook-y.
- **Using textbook terminology instead of course terminology.** The guide should match what students hear in lecture. If the professor calls it "rank," use "rank," even if a textbook uses "dimension of the image."
- **Reducing intuition to a restated definition.** "ω is angular frequency" is naming, not intuition. Intuition explains why ω² = k/m (inertia-to-restoring-force ratio).
- **Skipping the numerical verification step.** A wrong answer in the answer key is worse than no answer key.
- **Not rendering to PNG and visually verifying.** LaTeX compiles with overflow that looks fine in the log but breaks on the printed page.
- **Packing multiple independent ideas into one section.** Use subsections liberally. Scannable is better than comprehensive.
- **Starting too abstract.** Begin with a concrete worked example, then generalize. Not the other way around.
- **Forgetting to cite sources within the guide.** Every worked example and every claim should be traceable to a specific lecture/section in the course material.

## Workflow checklist

When building a new guide:

- [ ] Identify source material(s) and check for OCR need
- [ ] Extract all materials in range to markdown (one-time reuse)
- [ ] Read all sources fully before drafting
- [ ] Plan guide segmentation by topic boundary (ask if unclear)
- [ ] Draft guide with progressive terminology, worked examples grounded in course, distinct callout boxes per type
- [ ] Numerically verify every practice problem answer
- [ ] Write LaTeX `.tex` file using extended template
- [ ] Compile with tectonic
- [ ] Render to PNG and visually verify (via `vision_analyze`)
- [ ] Save both `.pdf` and `.tex` to course directory
- [ ] Update course's `INDEX.md` or equivalent to link to the new guide if it exists

## See also

- `concept-study-guide-pipeline` — for standalone external-source concepts (blog posts, papers, standalone ideas), NOT for course material. Outputs to `concepts/study-guides/`, not `cornell/courses/`.
- `course-knowledge-base` — per-course skeleton, Canvas ingestion, quizzes/feedback buckets
- `ocr-and-documents` — general OCR if Mistral unavailable; alternative providers
- `references/tectonic-setup.md` — tectonic install, compile, PNG-render workflow
- `references/mistral-ocr.md` — Mistral OCR API call and key handling

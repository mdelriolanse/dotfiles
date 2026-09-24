---
name: concept-study-guide-pipeline
description: Use when making a study guide PDF for one concepts/ page.
version: 1.0.0
author: Mateo del Rio Lanse
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [latex, study-guide, tectonic, concepts, sources]
    category: note-taking
    related_skills: [lecture-study-guide-pipeline, physics-study-guide-pipeline, obsidian]
---

# Concept Study-Guide Pipeline (concepts/ page -> intuition-first LaTeX PDF)

Sibling to `lecture-study-guide-pipeline` and `physics-study-guide-pipeline`,
but scoped to the vault's `concepts/` silo instead of a course. Where the
course pipelines turn lecture/unit material into exam-prep documents, this
skill turns a **single standalone idea** — a blog post breakdown, a paper
summary, a "how does X actually work" explainer already compiled into
`concepts/<slug>.md` — into a short, dense, intuition-first study guide PDF.
The defining discipline of this skill, more than any other in the family, is
**source discipline**: concepts pages are compiled from external material
(blog posts, papers, articles), not a professor's own lecture, so every claim
in the resulting guide must be traceable back to a real external source link,
not just "the concepts page said so."

## When to use

Trigger on any request to build a study guide/review sheet/explainer PDF
**for a single concept**: "make a study guide for the <X> concept", "explain
this paper/post as a study guide", "turn this concepts page into a PDF I can
review". Distinct from the course pipelines (`lecture-study-guide-pipeline`,
`physics-study-guide-pipeline`), which operate on `cornell/courses/<slug>/`
material across a lecture/unit range — this one operates on exactly one
`concepts/<slug>.md` page (or the raw source that page compiles from) and
produces exactly one guide, not a numbered series.

## Step 0 — Ensure the concept page exists and is sourced

1. Check `concepts/` (via INDEX.md or Grep) for an existing page on this
   topic — **update the existing page instead of creating a duplicate**, per
   the vault's compiled-wiki rule.
2. If no page exists yet, compile one first: read the primary source (blog
   post URL, paper, etc.) with `web_extract` or `read_file`, write a
   `concepts/<slug>.md` page per the vault's page conventions (frontmatter
   with `type: concept`, one-line summary at top, a `## Sources` section with
   real links back to every external source used), and add it to
   `INDEX.md` in the same task.
3. If a page already exists, re-open its listed sources before drafting the
   guide — do not draft purely from the compiled page's prose if the
   original source is available; cross-check against it the way the course
   pipelines cross-check Unit Notes against slides. A concepts page is a
   compressed summary; the guide should recover intuition-layer detail the
   summary may have dropped.

**Never invent or paraphrase-as-fact anything not traceable to the source.**
If the source is ambiguous or you are inferring/interpreting beyond what it
states, say so explicitly in the guide ("Ian's post implies X, though it
isn't stated outright") rather than presenting inference as sourced fact.

## Step 1 — Extract for intuition, not just summary

For each key idea/mechanism/equation in the concept, capture:

1. **What it is** — the claim/mechanism/term as the source states it, in the
   source's own terminology.
2. **Why it matters / what problem it solves** — the motivating context (this
   is what a blog post's own framing usually gives you directly — reuse it).
3. **How it actually works** — the mechanism broken into plain-language
   steps. If the source assumes prior knowledge (jargon, an unstated prior
   result, a term-of-art), surface that gap explicitly and fill it with a
   short "background" aside — this is the single most valuable thing this
   skill produces, since the whole point of a concept study guide is usually
   "I think this assumes a lot of prior knowledge."
4. **The verdict / so-what** — most source material (blog posts especially)
   ends on a claim or judgment; state it clearly, don't bury it.

Distinguish, visually and in prose, between: (a) what the source explicitly
says, (b) generally-known background you're supplying to fill a gap the
source assumes, and (c) your own inference/interpretation. Use different
callout box types for (a)/(b) vs (c) — see Step 2.

## Step 2 — Structure and box types

Extend the course pipelines' template with concept-specific boxes:

- `factbox` — a claim taken directly from the source (cite it inline: "per
  [source name]").
- `bgbox` — background/prior-knowledge filled in by you to bridge an assumed
  gap; visually distinct (e.g. a neutral gray/green) from `factbox` so a
  reader can tell "this is what the source says" from "this is context I
  added because the source assumed you already knew it."
- Reuse `callout`/`eqbox` conventions from the sibling skills for
  equations/foundational claims where relevant (technical concepts only).

Standard shape per major idea:
1. One or two sentences: what is this idea and why does the source bring it
   up.
2. `factbox`: the core claim/mechanism as stated by the source.
3. `bgbox` (as needed): any background knowledge required to understand the
   `factbox` that the source didn't spell out.
4. Plain-language walkthrough of the mechanism.
5. The verdict/implication, if the source states one.

End the guide with a **Sources** section listing every external link used
(primary source + any papers/references it cites that you pulled in), plus a
link back to the vault's own `concepts/<slug>.md` page. This is
non-negotiable — a concept guide without a Sources section is incomplete,
mirroring the vault rule that "a page without sources gets flagged, not
trusted."

## Step 3 — Typeset as LaTeX (tectonic)

Same toolchain as the course pipelines — see
`lecture-study-guide-pipeline`'s `references/tectonic-setup.md` for the
install + compile + PNG-render-and-`vision_analyze` verification flow (reused
verbatim, not duplicated here). Start from that skill's
`references/study-guide-template.tex` and add the `factbox`/`bgbox`
environments described above. One `.tex` file per guide.

## Step 4 — Output location

Concept guides are not course-scoped, so they live under the concept itself:

```
Documents/second-brain/concepts/study-guides/
  study-guide-<slug>.pdf
  tex-src/
    study-guide-<slug>.tex
```

Use the same `<slug>` as the corresponding `concepts/<slug>.md` page so the
two are trivially paired. Link the guide from the concepts page (e.g. a
`## Study guide` line pointing at the PDF path) so future sessions can find
it from either direction.

## Pitfalls

- **Skipping the Sources section or citing only the concepts page.** The
  concepts page is a vault-internal compilation, not itself a primary
  source — always cite the original external URL(s)/paper(s).
- **Presenting your own inference as the source's claim.** Use `bgbox` (or
  explicit "not stated outright, but likely means..." prose) to keep these
  separate; conflating them is the exact failure mode this skill exists to
  avoid, since the whole trigger is usually "this assumes prior knowledge I
  don't have."
- **Treating this as a mini version of the course pipelines' multi-lecture
  guides.** One concept = one guide, no numbered series, no lecture-range
  segmentation logic.
- **Forgetting to link the guide back from the concepts page**, which breaks
  vault discoverability (the compiled page is the front door; the guide is a
  derived artifact under it).
- Don't skip the mandatory PNG-render + `vision_analyze` visual verification
  step even for a short guide — LaTeX compiles happily even when overflow or
  a bad citation-link render looks wrong.

## See also

- `lecture-study-guide-pipeline` — shares the tectonic/LaTeX toolchain
  (`references/tectonic-setup.md`, `references/study-guide-template.tex`);
  read those before drafting the `.tex` here.
- `physics-study-guide-pipeline` — sibling with the `eqbox`/intuition-box
  precedent this skill's `factbox`/`bgbox` split is modeled on.
- `obsidian` / vault `AGENTS.md` — the compiled-wiki rules (one lesson per
  file, sources mandatory, update-don't-duplicate) this skill inherits.

# Lab-based courses (hardware/embedded labs) — `labs/` directory extension

Some courses (e.g. embedded systems / hardware labs with graded assignments
spanning weeks, not just weekly problem sets) need a `labs/<slug>/` directory
alongside the standard `courses/<slug>/` skeleton — add it to that course's
`index.md` Contents list and give it its own `labs/README.md` index, same
pattern as `materials/`.

## Per-lab folder convention (`labs/lab<N>/`)

- Raw deliverables the professor hands out (PDF handout, `.s`/`.c` starter
  templates) go in as-delivered, verbatim, never edited — e.g.
  `lab1-handout.pdf`, `lab1-template.s`. This is the raw-in half of the
  raw-in/compiled-out rule, scoped to one lab instead of one course.
- A single compiled `README.md` per lab distills:
  - deliverable timeline / point breakdown
  - what's fixed vs. editable in the starter template (quote the template's
    own "write your code below this line" markers if present)
  - per-part behavioral requirements
  - submission/naming rules the autograder enforces
  - a short "what correctness+standards review means" checklist the agent
    uses when the user later shares their actual implementation for review
- If the user says only one part of a multi-part lab is currently assigned,
  keep the README's active-review checklist scoped to that part — don't
  imply later parts are in progress — but still capture full requirements
  for every part so the doc stays useful once the next part starts (avoids
  redoing the same handout research later).
- Every requirement in the README must trace back to the handout/template —
  link to the raw file (e.g. `[[lab1-handout.pdf]]`) as the source, same
  source-link discipline as the rest of the vault.

## Worked example (ECE 3140, Lab 1: Assembly Programming)

Produced this structure for a 3-week, 3-part lab (Morse code → procedure
calls → recursive Fibonacci) on a real course:

```
cornell/courses/ece-3140/labs/
  README.md              # index: links lab0 build logs + lab1
  lab1/
    lab1-handout.pdf      # raw, verbatim from Canvas attachment
    lab1-template.s       # raw starter code, verbatim
    README.md             # compiled: deliverables, template anatomy,
                           # per-part requirements, submission rules,
                           # review checklist (scoped to active part only)
```

Template-anatomy pattern worth reusing: explicitly call out in the README
which labels/sections of the starter file are fixed ("do not touch — the
autograder deducts points") vs. the marked editable region, and note anything
conspicuously *missing* from the template that the assignment expects the
student to write themselves (e.g. no delay/timing routine was provided even
though the lab requires precise timing — that omission itself is a required
building block, not an oversight to flag as a bug).

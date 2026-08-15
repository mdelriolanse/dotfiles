---
name: oss-contrib-writing
description: Write issues, PR bodies, feature proposals, and review replies for open source repos so they read as the contributor's own work rather than generated filler. Use when drafting anything that will be posted upstream — a GitHub issue, PR description, discussion post, RFC, or reply to a maintainer — especially on repos with strict contribution policies, automated intake gates, or maintainers hostile to AI-generated contributions.
---

# Writing for open source repos

Maintainers reject generated contributions because they are usually wrong, padded,
and unverified — not because of prose style. A post is convincing when it proves the
author read the code. Specificity is the whole game; polish is not.

Do not fake authorship signals. No deliberate typos, no invented errors, no claiming
work you did not do. Those read as odd rather than human, and if they worked they
would be deceiving a maintainer about the thing they explicitly asked about. Write
something that is not slop instead of slop that passes.

## Workflow

1. **Recon the repo first.** Read `CONTRIBUTING.md`, `AGENTS.md`/`CLAUDE.md`, issue and
   PR templates, and any intake gate under `.github/workflows/`. Find out what gets
   auto-closed. If the `contrib-recon` skill is available, use it. Check whether the
   idea already exists in issues and discussions before writing a word.
2. **Verify every claim against the source.** Any statement about how the project works
   gets checked and cited as `path/to/file.rs:120`. A wrong claim about their own code
   is the fastest rejection there is.
3. **Find the nearest existing thing.** Related feature, adjacent module, the primitive
   this would build on. Say what already exists and what genuinely does not.
4. **Draft into the repo's template fields.** Their headings, their order, no extra
   sections, no appendix.
5. **Cut the tells.** See the list below.
6. **Name the counterargument yourself.** The workaround that already exists, the reason
   this might not fit, the cost. A maintainer who thinks of it first assumes you didn't.
7. **Author's pass.** The contributor retypes two or three sentences in their own words.
   This is the step that actually does the humanizing. Say so; don't skip it silently.

## Cut these

- Em dashes. Also the balanced three-item rhythm ("faster, simpler, and more reliable").
- Markdown headers on anything under ~300 words. Prose does not need navigation.
- "Summary", "Overview", "In conclusion", "I hope this helps", emoji section markers.
- Adjectives standing in for facts: comprehensive, robust, seamless, powerful, elegant.
  Replace with a path, a number, or delete.
- Stacked hedges ("it seems that this might potentially"). Hedge once, precisely, where
  you are actually unsure: "as far as I can tell" earns its place on a real guess.
- Bulleted lists where two sentences work. Bullets for parallel items only.
- Restating the template question before answering it.
- Symmetry — every paragraph the same length, every section the same shape.

## Sizing

Issue or discussion: roughly one screen. PR body: what changed, why it exists, how you
verified it, in that order. Long is not thorough; long is unread. If the explanation
outruns the diff, the diff is probably wrong.

## Register

Short sentences. Contractions. Fragments are fine. Concrete first person about what you
were doing when you hit the problem ("I've got four or five agents going and I know I saw
a stack trace somewhere"). Bare verbs over nominalizations: "it crashes" not "a crash is
observed". State the ask plainly, once.

## Claims you must not make

Never write that you ran tests, benchmarks, or a reproduction that did not happen. Never
attribute a design intent to a maintainer they did not state. Never present a guess as a
reading of the code. If a claim was not verified, either verify it or mark it as a guess.

See [EXAMPLES.md](EXAMPLES.md) for before/after drafts.

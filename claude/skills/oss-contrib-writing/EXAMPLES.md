# Before / after

Real drafts, same proposal, three revisions apart. The improvements are factual, not
cosmetic — that is the point.

## Feature proposal: opening paragraph

**Before** (generated register: balanced clauses, em dash, abstract)

> Copy mode search works great inside one pane, but I usually don't know which pane the
> thing I'm looking for is in — I'll have four or five agents running across a couple of
> spaces, and I end up tabbing through panes one at a time.

**After** (spoken register, concrete situation, no em dash, varied sentence length)

> Copy mode search is fine when I know which pane I want. Usually I don't. I've got four
> or five agents going across a couple of spaces, I know I saw a stack trace somewhere in
> the last twenty minutes, and I end up tabbing through panes running the same search in
> each one until I hit it.

## The claim that would have sunk it

**Before** (plausible, unverified, wrong)

> It could be a mode inside the existing navigator rather than a new modal, since that
> already has the search-and-jump interaction.

The navigator matched workspace and tab *names* over a short list. Proposing it as
"most of the way there" tells the maintainer you never opened the file.

**After** (checked `src/app/actions.rs:457`, states the difference)

> This isn't the navigator with a different filter. The navigator matches workspace and
> tab names over a short list. This is full text across pane scrollback and the results
> are line hits. The list-and-jump shape is the part worth reusing, not the matching.

## Scoping the ask down using their code

Found by reading the repo: per-pane search already shipped, built on a vendored search
engine that already walks scrollback history.

> The search itself already exists though. Copy mode / and ? already searches a pane's
> scrollback through the ghostty search that covers history and active. So as far as I
> can tell this is fanning that out across panes, collecting the hits, and the UI for
> picking one. Not a new search engine.

Turns "build me full-text search" into a bounded ask. "As far as I can tell" is the one
hedge, placed on the one real guess.

## Naming the counterargument first

> I know I can already get most of this with herdr agent read piped to rg. It works, but
> it's a separate thing I have to go do, and it doesn't put me on the line in the pane.

The maintainer will think of the workaround. Getting there first converts their objection
into evidence you understand the tool.

## Closing

**Before**

> If this is something you'd want in herdr I'd be glad to work on it, but wanted to check
> the direction first rather than show up with a PR.

**After**

> Happy to build it if it's a direction you'd want. Figured I'd ask before writing any code.

Same content, half the words, no throat-clearing.

## Bug report skeleton

Current behavior, expected behavior, shortest reproduction, impact, environment. No
root-cause analysis, no proposed patch, no diagnosis dump unless asked — several projects
auto-close reports that add them.

## PR body skeleton

One paragraph on why the change exists and what was broken. Then what changed, grouped by
concern. Then how it was verified, naming the command actually run. Link the issue in the
repo's required form. Nothing else.

---
name: issue-to-docs
description: Pull a GitHub issue or PR body into local docs/ as a verbatim single-file spec plus chunked markdown. Use when the user runs /issue-to-docs, or asks to turn an issue/PR into local docs. Accepts an issue/PR URL, a fuzzy "issue 894 on the acme gateway repo", or no argument when cwd is a PR feature-branch clone.
disable-model-invocation: true
---

# Issue to Docs

Materialise one GitHub issue/PR as (1) a verbatim single-file spec under `./docs`
and (2) chunked markdown under `./docs`.

`gh` is the network here (local `git` is not authenticated). All remote reads go
through `gh`.

## 1. Resolve the target

Pick the case from the argument shape:

- **URL** — `.../issues/N` → issue; `.../pull/N` → PR. Owner/repo are in the URL.
- **Number + fuzzy repo** — e.g. "issue 894 on the acme gateway repo".
  Resolve the repo loosely: `gh repo list <owner> --limit 200 --json name`,
  then match the spoken name (case/spacing-insensitive, "gateway" → `acme-gateway`).
  Default owner is inferred from the cwd's git remote, or `<owner>` if you can't infer it. If two names match, ask which.
  Issue vs PR unknown → try `gh issue view` first, fall back to `gh pr view`.
- **No argument** — cwd is a PR feature-branch clone. Take the current branch's PR:
  `gh pr view --json number,title,body,url,headRefName`. If none, stop and say so.

Confirm the resolved `owner/repo#N (issue|PR)` in one line before fetching, unless
it came from an unambiguous URL.

## 2. Fetch the body

```
gh issue view N --repo owner/repo --json number,title,body,url,state,labels,comments
gh pr   view N --repo owner/repo --json number,title,body,url,state,labels,headRefName,comments
```

Use the body as the spec source. Fold in comments only if they add spec detail.

## 3. Write the verbatim spec file

Write the issue/PR body **word-for-word** to `docs/<slug>-spec.md`, where `<slug>`
is a short kebab-case feature name (e.g. `template-library`). Add only a one-line
source attribution at the top (`> Source: <owner/repo> issue #NNN.`). Change nothing
else — same headings, code fences, tables, and checklists the author wrote. This file
is the frozen spec of record; the chunks in step 4 are the restructured breakdown of
the same content.

When invoked inside a dev-graph container (cwd is a `worktrees/<name>/` directory with
a `docs/` subdir), write the spec to `./docs/<slug>-spec.md` — the container's
top-level docs, not a per-repo `docs/` path.

## 4. Write chunked docs

Target dir: `./docs/<repo>-<N>/` (create if missing; if there is no `docs/` in
cwd, ask before creating one). Inside a dev-graph container, the `issues/`
nesting is unnecessary — the container is already named for the issue, so the
chunks live one level down at `./docs/<repo>-<N>/`, not under `docs/issues/`.

- `00-index.md` — title, `owner/repo#N`, url, state, labels, one-line summary, and a
  linked list of the chunk files.
- Split the body into `NN-<section-slug>.md` chunks. Split on the body's own `##`
  headings; if a section runs long (>~300 lines) split it further by subsection.
  Keep each chunk one coherent topic. Preserve the original prose verbatim — this is
  the spec, don't paraphrase it.

## 5. Report

One block: resolved target, verbatim spec path, docs dir, and chunk count.

---
name: issue-to-docs
description: Pull a GitHub issue or PR body into local docs/ as a verbatim single-file spec plus chunked markdown, and mirror the spec as a fresh agentmemory project. Use when the user runs /issue-to-docs, or asks to turn an issue/PR into local docs + a dedicated memory project for the thing they're currently tackling. Accepts an issue/PR URL, a fuzzy "issue 894 on <provider> gateway repo", or no argument when cwd is a PR feature-branch clone.
argument-hint: "<issue|PR url> | <number + fuzzy repo> | (empty inside a PR clone)"
disable-model-invocation: true
---

# Issue to Docs

Materialise one GitHub issue/PR as (1) a verbatim single-file spec under `./docs`,
(2) chunked markdown under `./docs`, and (3) a dedicated agentmemory project holding
the spec, so the current piece of work has an exact local spec plus recallable
memories scoped to just it.

`gh` is the network here (local `git` is not authenticated). All remote reads go
through `gh`.

## 1. Resolve the target

Pick the case from the argument shape:

- **URL** — `.../issues/N` → issue; `.../pull/N` → PR. Owner/repo are in the URL.
- **Number + fuzzy repo** — e.g. "issue 894 on <provider> Gateway repo".
  Resolve the repo loosely: `gh repo list <org> --limit 200 --json name`,
  then match the spoken name (case/spacing-insensitive, "gateway" → `<provider>-gateway`).
  Default owner is `<org>`. If two names match, ask which.
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

## 4. Write chunked docs

Target dir: `./docs/issues/<repo>-<N>-<title-slug>/` (create if missing; if there is
no `docs/` in cwd, ask before creating one).

- `00-index.md` — title, `owner/repo#N`, url, state, labels, one-line summary, and a
  linked list of the chunk files.
- Split the body into `NN-<section-slug>.md` chunks. Split on the body's own `##`
  headings; if a section runs long (>~300 lines) split it further by subsection.
  Keep each chunk one coherent topic. Preserve the original prose verbatim — this is
  the spec, don't paraphrase it.

## 5. Mirror into a new agentmemory project

Project slug (stable, canonical): `issue-<repo>-<N>` (e.g. `issue-<provider>-gateway-894`).
Pass it as `project` on every `memory_save`.

- First run `memory_recall`/`memory_smart_search` for the slug to avoid dupes on re-run;
  only save facts not already there.
- Save one memory per chunk/spec item — the concrete requirement, constraint, or
  acceptance criterion, not a summary of the whole issue. Set `type` (`fact`,
  `architecture`, `workflow`) and `concepts`; put the chunk file path in `files`.
- Save one index memory naming the slug, `owner/repo#N`, the url, and the docs dir,
  so a later session can `memory_recall "<slug>"` and find everything.

## 6. Report

One block: resolved target, verbatim spec path, docs dir + chunk count, project slug +
memory count.
Tell the user they can now `memory_recall "issue-<repo>-<N>"` for the scoped spec.

# andrea-review skill — bundled content

## Layout

```
andrea-review/
├── SKILL.md                          # dispatch contract (the 9-step pipeline)
├── README.md                         # this file
└── playbook/
    └── andrea-review-playbook.md     # the 12-sector playbook (generic)
```

## What's where

- **SKILL.md** — how to run the 12-sector agent swarm over a PR diff. The
  dispatch contract: resolve diff → read playbook → fan out 12 sectors →
  join → dedup → validate → triage → report → persist. Includes `--prd`
  and `--no-fix-suggest` flags, the cross-cutting rules, the
  codebase-intelligence backend bindings, the output contract, and the
  never-auto-commit policy.
- **playbook/andrea-review-playbook.md** — the 12 sector definitions, each
  with its core question, paradigms (imperative, generic), backend-grounding
  guidance, and failure modes. This is what the orchestrator reads in
  Step 2 and what each sector agent's lens is sourced from. The paradigms
  are codebase-agnostic — the agent applies them to the code under review
  and grounds every finding against live code via the available backends.

## Maintenance

The playbook is bundled and self-contained. The dispatch contract (this
SKILL.md) is maintained separately from the playbook content — a playbook
refresh does not require editing this file.

To extend the playbook with a new paradigm, edit
`playbook/andrea-review-playbook.md` in place: add the paradigm to the
owning sector, keep the imperative voice, and name the backend that
should verify it. No separate extraction pipeline or snapshot step is
needed — the playbook is the source, not a snapshot of an external doc.

# andrea-review skill — bundled content

## Layout

```
andrea-review/
├── SKILL.md                          # dispatch contract (the 9-step pipeline)
├── README.md                         # this file
├── playbook/
│   └── andrea-review-playbook.md     # the refined playbook v2 (12 sectors, 77 paradigms)
└── sectors/
    ├── _CONTEXT.md                  # shared worker context (dispatch contract for extraction)
    ├── _synthesis-dedup.md          # 15 merge groups, 36 orphans, 5 drift findings
    ├── _synthesis-validation.md     # 27 paradigms re-verified, 4 systemic gaps
    ├── _synthesis-adversarial.md    # 77 paradigms scored on 4 axes, 6 guardrails
    └── sector-01-*.md … sector-12-*.md  # 12 sector extracts (full paradigm detail)
```

## Source of record vs bundled snapshot

The **source of record** lives in the <provider> repo:

- `~/<provider>/docs/andrea-review-playbook.md` — the playbook.
- `~/<provider>/docs/andrea-review-sectors/` — the sector extracts + synthesis artifacts.

The copies under `playbook/` and `sectors/` here are **snapshots** taken
when the skill was packaged. They make the skill self-contained (works
even if the <provider> docs move or the repo isn't checked out at
`~/<provider>`), at the cost of drift.

## When to refresh the snapshot

After editing the source-of-record playbook or re-running the extraction
pipeline, re-snapshot into the skill:

```bash
cp ~/<provider>/docs/andrea-review-playbook.md \
   ~/.config/opencode/skills/andrea-review/playbook/
cp ~/<provider>/docs/andrea-review-sectors/{_CONTEXT,_synthesis-*,sector-*}.md \
   ~/.config/opencode/skills/andrea-review/sectors/
```

The SKILL.md dispatch contract does not need to change for a content
refresh — only the bundled copies move.

## What's where

- **SKILL.md** — how to run the 12-sector agent swarm over a PR diff. The
  dispatch contract: resolve diff → read playbook → fan out 12 sectors →
  join → dedup → validate → triage → report → persist. Includes `--prd`
  and `--no-fix-suggest` flags, the 6 cross-cutting rules, the 6 backend
  bindings, the output contract, and the never-auto-commit policy.
- **playbook/andrea-review-playbook.md** — the 12 sector definitions with
  every paradigm grounded in a <Provider> infra anchor and a named
  codebase-intelligence backend. This is what the orchestrator reads in
  Step 2 and what each sector agent's paradigm list is sourced from.
- **sectors/** — the full extraction pipeline artifacts. The 12
  `sector-NN-*.md` files are the per-sector extracts (3-7 paradigms each,
  with anchors, backends, guardrails, fix-suggestion policy, adversarial
  caveats). The three `_synthesis-*.md` files are the dedup, validation,
  and adversarial passes over those extracts. `_CONTEXT.md` is the
  dispatch contract for re-running the extraction.
- **README.md** (this file) — the snapshot/refresh relationship.

## Drift between snapshot and source of record

If a playbook anchor is corrected in the source of record but the
snapshot isn't refreshed, the skill will cite stale anchors. CR-1 (re-
ground before citing) is the guardrail that catches this — the skill
re-verifies every anchor against live code via `semble_search` → Serena
`find_symbol` → `read`, so a stale snapshot degrades to "anchor_verified:
stale" findings rather than wrong findings. Refresh the snapshot when
convenient; the skill stays correct in the meantime.

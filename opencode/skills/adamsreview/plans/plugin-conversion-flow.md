# Plugin conversion — flow visualization

Visual aid for reviewing `adams-review`'s architecture in its post-conversion
(plugin) shape. Four diagrams, each self-contained for pasting into
<https://mermaid.live>. Read alongside `plugin-conversion-execution.md` and
`plugin-conversion.md`.

The conversion is a packaging change, not a behavior change — the runtime
pipeline is identical. The blue-tinted nodes in the first diagram are what's
new or renamed; everything else is unchanged from the current slash-command
shape.

---

## 1. End-to-end flow (post-conversion)

```mermaid
flowchart TD
    classDef new fill:#dbeafe,stroke:#1e40af,color:#000
    classDef phase fill:#fef3c7,stroke:#a16207,color:#000
    classDef agent fill:#ede9fe,stroke:#6d28d9,color:#000
    classDef stateNode fill:#dcfce7,stroke:#15803d,color:#000
    classDef critical fill:#fee2e2,stroke:#b91c1c,color:#000

    subgraph BOOT ["Plugin boot — NEW in conversion"]
        direction TB
        M1["/plugin marketplace add"]:::new
        M2["/plugin install adams-review"]:::new
        M3["Claude Code loads:<br/>plugin.json<br/>hooks/hooks.json<br/>marketplace.json"]:::new
        M4["SessionStart hook:<br/>bin/dep-check.sh<br/>checks uv, jq, gh, git"]:::new
        M1 --> M2 --> M3 --> M4
    end

    M4 --> DEPQ{"deps ok?"}
    DEPQ -- yes --> R1["zero bytes emitted<br/>(quiet success)"]
    DEPQ -- no --> R2["WARNING emitted<br/>to session context"]
    R1 --> READY["session ready"]
    R2 --> READY

    READY --> INV["user runs a command"]

    subgraph CMDS ["Five namespaced commands — RENAMED"]
        direction LR
        C1["/adams-review:review<br/>--ensemble / --full"]:::new
        C2["/adams-review:add<br/>paste or --file --line --claim"]:::new
        C3["/adams-review:walkthrough"]:::new
        C4["/adams-review:fix threshold"]:::new
        C5["/adams-review:promote F-id"]:::new
    end

    INV --> CMDS

    subgraph COMPOSE ["Fragment composition — CHANGED"]
        direction TB
        FM1["commands/stem.md<br/>top-level command file"]
        FM2["!$CLAUDE_PLUGIN_ROOT/bin/include NN-name.md<br/>(replaces !cat ~/.claude/...)"]:::new
        FM3["fragments/NN-name.md<br/>phase body"]
        FM1 --> FM2 --> FM3
    end

    C1 --> COMPOSE
    C2 --> COMPOSE
    C3 --> COMPOSE
    C4 --> COMPOSE
    C5 --> COMPOSE

    subgraph REV ["/adams-review:review — Phases 0 through 6"]
        direction TB
        P0["Phase 0 Preflight<br/>branch/PR detect, push,<br/>trivial-diff, record<br/>review_started_at"]:::phase
        P0 --> T{"trivial_mode?<br/>--full overrides"}
        T -- yes --> EXIT0["early exit"]
        T -- no --> P1

        P1["Phase 1 Detection<br/>PARALLEL FAN-OUT: 6 lenses<br/>(+1 L7 Opus under --ensemble,<br/>joint with Phase 1.5 CodeRabbit +<br/>Codex + gh PR scrape)"]:::phase
        P1 --> J1["join step<br/>origin-crosscheck,<br/>line-range-check,<br/>assign-finding-ids"]

        J1 --> P2["Phase 2 Dedup<br/>one Sonnet sub-agent<br/>merges equivalents"]:::phase
        P2 --> P3["Phase 3 Scoring + gate<br/>one Sonnet err-up scorer"]:::phase

        P3 --> G3{"phase3 gate:<br/>score ≥45 OR<br/>≥2 source families?"}
        G3 -- no --> BG["disposition=below_gate<br/>(exits to finalize)"]:::stateNode
        G3 -- yes --> P4["Phase 4 Validation<br/>PARALLEL FAN-OUT per candidate<br/>4a Opus deep (correctness, sec)<br/>4b Sonnet light (ux, policy, arch)"]:::phase

        P4 --> G4{"score_phase4 +<br/>actionability?"}
        G4 -- "≥60 auto, deep" --> CA["confirmed_mechanical<br/>is_actionable=true"]:::stateNode
        G4 -- "≥60 auto, light" --> CAL["confirmed_mechanical (light)<br/>Phase 8 skips unless promoted"]:::stateNode
        G4 -- "≥60 manual" --> CM["confirmed_manual"]:::stateNode
        G4 -- "≥60 report" --> CR["confirmed_report"]:::stateNode
        G4 -- "45–59" --> UNC["uncertain"]:::stateNode
        G4 -- "< 45" --> DIS["disproven"]:::stateNode
        G4 -. origin=pre_existing, high .-> PER["pre_existing_report<br/>normative override"]:::stateNode

        CA --> P5["Phase 5 Cross-cutting<br/>one deep-lane Opus<br/>(confirmed_mechanical deep only)"]:::phase
        P5 --> FIN
        CAL --> FIN
        CM --> FIN
        CR --> FIN
        UNC --> FIN
        DIS --> FIN
        BG --> FIN
        PER --> FIN

        FIN["Phase 6 Finalize<br/>tally subagent_tokens +<br/>orchestrator_tokens,<br/>render artifact.md,<br/>publish PR comment"]:::phase
    end

    C1 --> REV

    subgraph ADD ["/adams-review:add"]
        direction TB
        A1["locate artifact<br/>via latest.txt"]
        A1 --> A2{"input mode?"}
        A2 -- paste --> AN["Sonnet normalizer"]:::agent
        A2 -- structured --> AS["one-shot builder<br/>(orchestrator)"]
        AN --> A3
        AS --> A3
        A3["Sonnet dedup vs existing<br/>(one direction)"]:::agent
        A3 --> A4["Phase 4 validation<br/>lane-aware, NO Wave 2"]:::phase
        A4 --> A5["re-render +<br/>re-publish to existing<br/>comment_id"]
    end

    C2 --> ADD

    subgraph WALK ["/adams-review:walkthrough"]
        direction TB
        W1["preflight +<br/>scope choice:<br/>Qualifying / Full skip set"]
        W1 --> W2["per-finding Sonnet brief<br/>(proposes hints for<br/>manual/report)"]:::agent
        W2 --> W3{"user action"}
        W3 -- promote --> WP["promote-core fragment<br/>SHARED with :promote"]
        W3 -- edit hint --> WE["override hint"]
        W3 -- skip --> WN
        WP --> WN
        WE --> WN
        WN["next finding or end"]
        WN --> W2
        WN --> WI["end-of-run issue-filing:<br/>pre_existing_report<br/>one-by-one gh issue create"]
    end

    C3 --> WALK

    subgraph PROM ["/adams-review:promote"]
        direction TB
        PR1["load artifact,<br/>target F-id"]
        PR1 --> PR2["set human_confirmation<br/>via artifact-patch.py<br/>(metadata only — Phase 8 bypass)"]
        PR2 --> PR3["re-render +<br/>re-publish"]
    end

    C5 --> PROM

    subgraph FIX ["/adams-review:fix — Phases 7 through 9"]
        direction TB
        F7["Phase 7 Load artifact<br/>leftover-attempted gate,<br/>clean-tree gate,<br/>staleness check,<br/>compute eligible_finding_ids"]:::phase
        F7 --> F8["Phase 8<br/>PARALLEL FAN-OUT per fix_group<br/>Sonnet agents edit working tree<br/>(no git ops, no deletes)"]:::phase
        F8 --> F9P{"Phase 9.pre:<br/>overlap detected?"}
        F9P -- yes --> REC["Opus merge agent<br/>collapses to FG-RECON"]:::agent
        F9P -- no --> F9A
        REC --> F9A
        F9A["Phase 9a Opus pre-commit review<br/>PARALLEL FAN-OUT per surviving group"]:::phase
        F9A --> F9B["Phase 9b revert<br/>regression groups<br/>(git checkout + rm)"]:::phase
        F9B --> F9C["Phase 9c commit + push<br/>one commit per surviving group,<br/>re-tally tokens"]:::phase
    end

    C4 --> FIX

    subgraph STATE ["Shared state — SINGLE SOURCE OF TRUTH"]
        direction LR
        ART[("~/.adams-reviews/slug/<br/>branch/review_id/<br/>artifact.json")]:::critical
        LAT[("latest.txt<br/>cross-command handshake")]:::critical
        LOGS[("phases.jsonl<br/>tokens.jsonl<br/>trace.md")]
    end

    FIN --> ART
    FIN --> LAT
    FIN --> LOGS
    A5 --> ART
    WI --> ART
    PR3 --> ART
    F9C --> ART

    subgraph HLP ["bin/ helper layer — RELOCATED from commands/_shared/tools/"]
        direction LR
        HP["artifact-patch.py<br/>all writes"]
        HR["artifact-read.sh<br/>all reads"]
        HRN["artifact-render.py"]
        HPB["artifact-publish.sh"]
        HINC["include<br/>NEW wrapper"]:::new
        HETC["...16 others<br/>(log-*, tally-*, scrape, staleness,<br/>origin-crosscheck, group-fixes, ...)"]
    end

    HLP <-.-> ART
    HLP <-.-> LOGS
```

---

## 2. Finding disposition state machine

Disposition is the routing key (filters + reports read it). `current_state`
is the lifecycle phase. Both live on every finding.

```mermaid
flowchart LR
    classDef stateNode fill:#dcfce7,stroke:#15803d,color:#000
    classDef active fill:#fef3c7,stroke:#a16207,color:#000
    classDef terminal fill:#e5e7eb,stroke:#374151,color:#000

    NEW["new candidate<br/>(post Phase 1 join)"]

    NEW --> P3G{"Phase 3 gate"}
    NEW -. origin=pre_existing,<br/>confidence=high .-> PER["pre_existing_report<br/>is_actionable=false"]:::stateNode

    P3G -- "score <45, 1 family" --> BG["below_gate<br/>is_actionable=false"]:::stateNode
    P3G -- "passes or ≥2 families" --> P4V{"Phase 4 validation"}

    P4V -- "<45" --> DIS["disproven"]:::stateNode
    P4V -- "45–59" --> UNC["uncertain"]:::stateNode
    P4V -- "≥60, auto_fixable" --> CA["confirmed_mechanical<br/>is_actionable=TRUE"]:::active
    P4V -- "≥60, manual" --> CM["confirmed_manual"]:::stateNode
    P4V -- "≥60, report_only" --> CR["confirmed_report"]:::stateNode

    CA -- Phase 8 ran --> ATT["current_state=attempted<br/>(disposition unchanged)"]:::active
    ATT --> P9{"Phase 9 verdict"}
    P9 -- verified --> RES["current_state=resolved<br/>disposition=resolved"]:::terminal
    P9 -- partial --> PAR["partial<br/>current_state=open<br/>is_actionable=TRUE"]:::active
    P9 -- regression --> REG["regression<br/>current_state=open<br/>is_actionable=TRUE<br/>(fix group reverted)"]:::active

    PAR -. retry on next :fix .-> ATT
    REG -. retry on next :fix .-> ATT

    BG -. "/adams-review:promote<br/>sets human_confirmation" .-> PROMO["Phase 8 bypass<br/>(disposition unchanged)"]:::active
    CM -. promote .-> PROMO
    CR -. promote .-> PROMO
    UNC -. promote .-> PROMO
    PROMO -.-> ATT
```

---

## 3. Sub-agent dispatch lifecycle (one cycle)

Same shape every time the orchestrator hands work to a sub-agent — Phase 1,
Phase 4, Phase 8, walkthrough briefer, etc.

```mermaid
sequenceDiagram
    autonumber
    participant O as Orchestrator<br/>(main Claude session)
    participant SA as Sub-agent<br/>(Agent tool)
    participant BA as Bash helper
    participant TL as tokens.jsonl
    participant AR as artifact.json

    Note over O: Orchestrator in its own turn.<br/>Composes dispatch prompt(s).

    O->>+SA: Agent tool-use block<br/>(2–N blocks in ONE turn = parallel fan-out)
    Note right of O: subagent_type, model,<br/>prompt (from fragment),<br/>allowed-tools whitelist
    SA->>SA: sub-agent's own turns<br/>(its own LLM calls,<br/>own tool use, own Bash)
    SA-->>-O: returns text + usage

    Note over O: Orchestrator's NEXT turn<br/>receives all parallel results together.

    loop for each returned sub-agent
        O->>O: extract total_tokens<br/>from usage field, or parse<br/>total_tokens from output body
        O->>+BA: log-tokens.sh phase role id<br/>model finding_id tokens
        BA->>TL: append JSONL
        BA-->>-O: exit 0

        O->>O: parse structured output<br/>(strip fences, extract JSON)

        alt parse succeeds
            O->>+BA: artifact-patch.py<br/>--add-finding / --apply-decisions /<br/>--apply-fix-outcomes
            BA->>AR: atomic write (tmp + rename)
            BA-->>-O: exit 0
        else parse fails on 1st try
            O->>+SA: re-dispatch with addendum
            SA-->>-O: second return
            Note right of O: one retry only
        else parse fails on 2nd try
            O->>+BA: log-phase.sh<br/>drop-with-note to trace.md
            BA-->>-O: exit 0
            Note over O: candidate dropped.<br/>pipeline continues
        end
    end
```

Notes on this lifecycle:

- **Fan-out is a turn-boundary property.** "Multiple Agent blocks in one
  orchestrator turn" = parallel. Separate turns = serial.
- **Token logging fires before parse.** Every dispatched sub-agent's cost is
  recorded even when its output fails to parse (§24.4 invariant).
- **`orchestrator_tokens` vs `subagent_tokens` captures the split.**
  `subagent_tokens` rolls up `tokens.jsonl` (steps 5–6 above).
  `orchestrator_tokens` rolls up main-session per-turn usage (the work in
  steps 1, 2, 7, 8, 10, 11). Non-overlapping by construction.

---

## 4. Actor map — who does what per phase

### `/adams-review:review` (Phases 0–6)

| Phase | Orchestrator turns do | Sub-agents dispatched | Helpers called via Bash |
|---|---|---|---|
| **0 Preflight** | sequencing, AskUserQuestion on dirty-tree / prior-artifact | *none* | `repo-slug.sh`, `claude-md-paths.sh`, `gh`, `git` |
| **1 Detection** | composes parallel fan-out; aggregates returns | **6 lenses** (L1 Haiku, L2 Opus, L3–L6 Sonnet); +**L7 Opus** under `--ensemble`; +**Phase 1.5 normalizer Sonnet** under `--ensemble`; joint fan-out also dispatches `codex:codex-rescue` + `coderabbit:code-reviewer` | `external-scrape.sh` (Bash, not sub-agent), `comment-freshness.sh`, `origin-crosscheck.sh`, `line-range-check.sh`, `assign-finding-ids.sh`, `log-tokens.sh`, `artifact-patch.py --add-finding` |
| **2 Dedup** | composes one dispatch | **1 Sonnet** | `log-tokens.sh`, `artifact-patch.py --apply-decisions` |
| **3 Scoring gate** | composes one dispatch | **1 Sonnet** scorer | `log-tokens.sh`, `artifact-patch.py --apply-decisions` |
| **4 Validation** | parallel fan-out per candidate | **per candidate: Opus (deep) OR Sonnet (light)** | `log-tokens.sh`, `artifact-patch.py --apply-decisions` |
| **5 Cross-cutting** | composes one dispatch | **1 Opus** | `log-tokens.sh`, `artifact-patch.py` |
| **6 Finalize** | sequencing, PR comment POST | *none* | `tally-subagent-tokens.sh`, `orchestrator-tokens.sh`, `artifact-render.py`, `artifact-publish.sh` |

### `/adams-review:fix` (Phases 7–9)

| Phase | Orchestrator turns do | Sub-agents dispatched | Helpers called |
|---|---|---|---|
| **7 Load** | gate checks, eligibility filter | *none* | `artifact-read.sh`, `staleness.sh`, `prior-fix-diff.sh`, `group-fixes.py` |
| **8 Apply** | parallel fan-out per `fix_group` | **1 Sonnet per fix_group** (edits working tree, no git) | `log-tokens.sh`, `artifact-patch.py --apply-fix-start` |
| **9.pre** | `git status --porcelain` overlap scan | **1 Opus merge agent** iff overlap | `git` |
| **9a Post-fix review** | parallel fan-out per surviving group | **1 Opus per group** | `log-tokens.sh` |
| **9b Revert** | `git checkout` + `rm` on regression groups | *none* | `git` |
| **9c Commit + push** | one commit per surviving group | *none* | `git`, `tally-subagent-tokens.sh`, `orchestrator-tokens.sh`, `artifact-patch.py --apply-fix-outcomes`, `artifact-render.py`, `artifact-publish.sh` |

### Other commands

| Command | Sub-agents dispatched | Notable orchestrator work |
|---|---|---|
| **`/adams-review:add`** | **1 Sonnet** normalizer (paste mode only); **1 Sonnet** dedup; **1 Opus or Sonnet** per candidate validation (lane-aware, no Wave 2) | locates artifact via `latest.txt`, re-publishes to existing `comment_id` |
| **`/adams-review:walkthrough`** | **1 Sonnet** briefer per finding (serial loop, *not* a fan-out) | preflight scope choice via AskUserQuestion; per-finding user action via AskUserQuestion; issue-filing loop drafts in-orchestrator + `gh issue create` |
| **`/adams-review:promote`** | *none* | pure metadata write via `artifact-patch.py`, then re-render + re-publish |

---

## 5. Worth reconsidering before we execute the conversion

The plugin conversion is a packaging change. But packaging changes force a
re-walk of the architecture, and if anything here is going to change,
*before* is cheaper than *after*.

### Structural — changing is costlier post-conversion

1. **Five top-level commands vs. one command with subcommands.** Plugin
   namespacing (D18) gives users `/adams-review:review`, `/adams-review:fix`,
   etc. — five discrete command files under the hood. A single
   `/adams-review` entry with subcommand dispatch would be more conventional
   CLI shape. Trade-off: one entry is cleaner for docs + discovery; five is
   what Claude Code natively models (each with its own frontmatter
   `allowed-tools`, `argument-hint`, `description`). Stick with five unless
   you want AskUserQuestion-style discovery inside one command.

2. **Fragment count (14).** Stage 4 fragment-shrink was deferred. The
   conversion moves fragments from `commands/_shared/` to `fragments/` but
   doesn't consolidate them. If you want to collapse (e.g., merge
   `04-scoring-gate.md` into `03-dedup.md`, or inline `lens-*-reference.md`
   into `01-detection.md`), doing it pre-conversion avoids re-doing the path
   rewrites. Recommendation: keep Stage 4 deferred — fragment boundaries map
   to DESIGN phases; collapsing churns every `!include` line. Do it as a
   separate focused task later.

3. **`bin/include` wrapper vs. inlining fragments.** The plan keeps
   composition. The alternative is cat-the-fragment into each command file
   at build time (pre-commit hook or `make` target) — no runtime wrapper,
   no `${CLAUDE_PLUGIN_ROOT}` substitution path. Trade-off: inline-at-build
   produces much larger committed command files and makes cross-command
   fragment reuse (`promote-core.md`, lens references) painful. The wrapper
   is right, but now is the moment to disagree.

4. **Helper layout flat under `bin/`.** 20 scripts directly under `bin/`.
   You could split into `bin/readers/`, `bin/writers/`, `bin/utilities/`
   (mirroring the helper index in CLAUDE.md). Trade-off: subdirs mean longer
   `allowed-tools` paths and a less-flat discovery surface via `ls bin/`.
   Keep flat unless you're getting lost.

### Behavioral — architectural asymmetries worth a sanity check

5. **Light-lane asymmetry.** Phase 4b light-lane `confirmed_mechanical` findings
   are excluded from Phase 8 by the lane filter, and
   `/adams-review:walkthrough` exists specifically to close that gap. Most
   confusing shape in the pipeline. If you've gained confidence in Phase
   4b's judgment, you could lift the filter — but that's a behavior change,
   not a conversion change.

6. **`latest.txt` as the cross-command handshake.** Both `:add` and `:fix`
   resolve the target artifact by reading `latest.txt` (one line, one path).
   Failure mode: user ran `:review` in a different branch between commands
   → `latest.txt` points at the wrong review. Alternative: require
   `--review-id` on lifecycle commands. Recommendation: leave it —
   personal-use tool, `latest.txt` is doing its job.

7. **SessionStart hook scope.** Currently only runs `dep-check.sh`. Could
   also default `ADAMS_REVIEW_REVIEWS_ROOT`, warm a `gh auth status` check,
   or precompute `repo_slug`. Plan keeps it minimal because hook output
   injects into session context and burns tokens every turn. Recommendation:
   minimal is right. Anything environmental that can live in a Python
   helper should live there.

### Plugin-era opportunities not taken (and why that's OK)

8. **`codex:codex-rescue` and `coderabbit:code-reviewer` as first-class
   plugin sub-agents.** Ensemble mode already dispatches both — post-
   conversion they can lean on plugin-native `subagent_type` rather than
   shell-out. Plan already uses them this way. Keep as-is.

9. **PostToolUse hook for `attempted`-never-committed detection.** Currently
   Phase 7 detects leftover `attempted` findings and hard-aborts. A
   PostToolUse hook on `Bash(git commit:*)` could catch the gap earlier.
   Overkill for personal use. The current gate works.

### Cross-platform caveats to remember during execution

10. **Git Bash's BSD/GNU divergence surface is larger than one line in
    Out-of-scope.** Your `mktemp -t` caveat is documented. Also worth
    pre-checking: `date -u -d`, `stat --format`, `sed -i ''` (mac) vs
    `sed -i` (gnu), `readlink -f`. Grep helpers for these before Phase 4's
    "scripts run unmodified under Git Bash" assertion is tested.

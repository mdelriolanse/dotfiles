---
description: Benchmark current performance as a baseline, implement an optimization, re-benchmark, and only merge if the delta meets the threshold.
argument-hint: <optimization goal or target> [--threshold-p95 <ms>] [--threshold-rps <rps>]
---

**Input:** $ARGUMENTS
**Timestamp:** !date +%Y-%m-%d_%H-%M-%S
**Context:** @CLAUDE.md

Parse from $ARGUMENTS:
- `--threshold-p95 <ms>` — max acceptable p95 latency after optimization (optional; evaluator uses default 10% improvement rule if not set)
- `--threshold-rps <rps>` — min acceptable throughput after optimization (optional)
- Everything else is the optimization goal

## Phase 1 — Baseline

Use the Task tool to launch the `profiler` agent with:
- `mode: baseline`
- Instruction: benchmark the current state of the codebase; identify key operations related to the optimization goal; save baseline to `agent/perf/`

Wait for the baseline file path.

## Phase 2 — Plan

Use the Task tool to launch `plan-architect` with:
- The optimization goal from $ARGUMENTS
- The baseline profiler report
- Instruction: produce an optimization plan targeting the slowest operations from the baseline; each step should be measurable (state what metric it should improve and by how much); no feature additions, no behavioral changes

Wait for the plan file.

## Phase 3 — Implement

Create an optimization branch:
```bash
git checkout -b perf/{{optimization-slug}}
```

Use the Task tool to launch a `ralph-executor` agent with:
- The optimization plan
- The baseline file path
- Instruction: implement optimizations; run the existing test suite after each step to ensure no behavioral regressions; do not sacrifice correctness for performance

Wait for the executor to complete.

## Phase 4 — Re-Benchmark

Use the Task tool to launch the `profiler` agent with:
- `mode: compare`
- `baseline_file`: the baseline file path from Phase 1
- Any custom thresholds from the flags in $ARGUMENTS

Wait for the comparison report and verdict (PASS / REGRESSION DETECTED).

## Phase 5 — Gate

**If PASS** (metrics improved and no regressions):
- Use the Task tool to launch `commit-architect` to commit the optimization
- Report the performance delta to the user
- Offer to merge to main

**If REGRESSION DETECTED** (metrics worsened or tests failed):
- Do NOT commit
- Present the regression details to the user
- Ask whether to: (A) attempt a different optimization approach, (B) abandon and reset the branch, or (C) override and merge anyway (user's explicit choice required)

## Completion

Report:
- Baseline vs. optimized metrics comparison table
- Test suite status
- Whether the merge threshold was met
- Branch name (for manual inspection if not merging)

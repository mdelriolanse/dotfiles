---
name: review-graph
description: Run deep-review with the given arguments, then resolve-review on the report that run wrote. Use when the user types /review-graph.
disable-model-invocation: true
---

# review-graph

Slash command. Same arguments as `deep-review`. Do not reimplement Adams, Andrea, open-code-review, or the resolve-review fix loop. Follow the `deep-review` and `resolve-review` skills.

## Invoke

```
/review-graph
/review-graph --prd docs/spec.md
/review-graph --prd 412
/review-graph --ocr
/review-graph -n 3
/review-graph 1234 --prd 412 --ocr -n 2
```

Target, `--prd`, `--ocr`, and `-n` mean what they mean in `deep-review`. Pass them through unchanged. Do not drop or reinterpret them. This command has no extra flags.

## Procedure

1. Run the `deep-review` skill (`~/.cursor/skills/deep-review/SKILL.md`) in this session with the user's arguments unchanged: target, `--prd`, `--ocr`, `-n`.
2. When that run has finished, use the report it wrote: `<reviewed-repo>/docs/deep-review/<title>-<timestamp>.md` (the path `deep-review` prints as its last line). If that file is not on disk, stop.
3. Run the `resolve-review` skill (`~/.cursor/skills/resolve-review/SKILL.md`) on that report. Pass the path. Do not add scope words; resolve-review's default is both FIX and SKIP NOW.

One target, one deep-review, then resolve-review on that report. `/dev-graph` is a separate pipeline.

## Phase 6c — False-positive audit (dual-agent challenge)

Two sub-agents independently challenge every confirmed finding (confirmed
with score ≥ 60). The orchestrator reconciles their verdicts and
downgrades findings where both agents — or a split — flag the finding as
deceptively weak. This is a last-line-of-defense false-positive gate
before publish.

Capture `phase_6c_start_epoch=$(date +%s)` as the first action of this
phase — step 6c.5 logs the elapsed time.

### 6c.0. Check eligibility

Read confirmed findings that are candidates for audit:

```bash
artifact-read.sh \
  --path "$artifact_path" \
  --filter '[.findings[] | select(.disposition == "confirmed_mechanical" or .disposition == "confirmed_manual" or .disposition == "confirmed_report") | select(.score_phase4 != null and .score_phase4 >= 60) | {id, file, line_range, claim, disposition, score_phase4, impact_type, validation_result}]'
```

Capture as `audit_pool_json`.

If `audit_pool_json` is `[]` (no confirmed findings):

```bash
log-phase.sh \
  --review-dir "$review_dir" --phase 6c --name audit \
  --elapsed 0 \
  --summary "skipped — no confirmed findings to audit"
```

Jump to Phase 6. Otherwise proceed.

### 6c.1. Chunk the pool

Split into chunks of **at most 15 findings per chunk**.
Phase 6c is skeptical heavy work; keeping chunks small preserves
per-finding resolution.

```bash
audit_chunks='[]'
chunk_size=15
audit_count=$(printf '%s' "$audit_pool_json" | jq 'length')
chunk_count=$(( (audit_count + chunk_size - 1) / chunk_size ))
```

For each chunk `i` from `0` to `$((chunk_count - 1))`, slice the pool
and save to `$scratch_dir/phase6c-chunk-$i.json`.

($scratch_dir is `$review_dir/scratch`; create it if needed.)

### 6c.2. Dual-agent dispatch (one turn per chunk)

**Two sub-agents per chunk, issued in the SAME orchestrator turn.**
They are independent; parallelism per chunk is `2 agents` and wall-clock
latency per chunk is `max(agent_a_duration, agent_b_duration)`.

For every chunk file `${chunk_path}`:

**Agent α — Skeptic prompt body:**

> You are a ruthless devil's advocate. Your ONLY job is to find reasons
> why each finding in the list below IS WRONG. Do not try to be fair.
> Assume every finding is a false positive until proven otherwise.
>
> For each finding, independently:
> 1. Re-read the cited file and line range. Does the code actually show
>    what the claim says? Or is the claim an over-interpretation?
> 2. Did the prior validator (Phase 4) get biased by the original lens
>    claim and "confirm" something that isn't really proven?
> 3. Is the line_range sufficiently precise, or is it a broad swipe?
> 4. Could this finding be a hallucination that survived because no
>    prior stage actively challenged it?
>
> Return a JSON array, one entry per finding:
> ```
> [{"id":"F001","verdict":"retain|downgrade","summary":"two-sentence max explanation: what the claim says vs why it holds up or fails. Be specific — cite file:line or quote actual code."}, ...]
> ```
> `verdict=retain` only when you are genuinely convinced the finding is
> real after trying hard to tear it down. Otherwise `downgrade`.

**Agent β — Re-verifier prompt body:**

> You are an independent verifier reading these findings for the FIRST
> time. Do NOT look at the existing `validation_result` or any prior
> analysis. Start from the raw `file`, `line_range`, and `claim` only.
>
> For each finding:
> 1. Read the file at the cited line range.
> 2. Does the code independently support the claim? Or does the claim
>    describe a problem that isn't actually present in the code?
> 3. Is the severity/score assignment justified by the actual evidence?
>
> Return a JSON array, one entry per finding:
> ```
> [{"id":"F001","verdict":"retain|downgrade","summary":"two-sentence max: what you see in the code and whether it independently confirms or contradicts the claim."}, ...]
> ```
> `verdict=retain` only when the code itself, read cold, clearly shows
> the claimed issue. Otherwise `downgrade`.

Both Agent α and Agent β receive the same chunk findings array as input.
Both are launched via `Task` with `subagent_type: general`.

### 6c.3. Parse and reconcile

For each chunk, collect both agent responses.

**Light JSON repair** per §24.1 (one retry). On second failure for an
agent, treat every finding in that chunk as `verdict=retain` from that
agent (fail-safe: a broken audit does not destroy confirmed findings).
Log failures to `trace.md`.

After both agents return per chunk, build a reconciliation table keyed
by finding `id`:

| agent_a | agent_b | reconciled_verdict | reconciled_disposition |
|---------|---------|-------------------|------------------------|
| retain  | retain  | retain            | no change              |
| downgrade | downgrade | downgrade       | shift to `uncertain`   |
| retain  | downgrade | flagged           | shift to `uncertain`   |
| downgrade | retain  | flagged           | shift to `uncertain`   |

(Any disagreement → `flagged`. Both agents must independently believe the
finding is real for it to survive.)

`audit_result` shape to write per downgraded/flagged finding:

```json
{
  "verdict": "retain|downgrade|flagged",
  "summary": "<human-friendly 2-sentence rationale from the orchestrator, synthesizing both agents>",
  "agent_a": {"verdict":"...","summary":"..."},
  "agent_b": {"verdict":"...","summary":"..."}
}
```

For `retain` findings, write a minimal `audit_result` with
`verdict: "retain"` and both agent summaries preserved. This keeps the
audit trail complete.

### 6c.4. Apply to artifact

For each finding in the chunk:

```bash
# If reconciled_verdict == "retain":
artifact-patch.py \
  --path "$artifact_path" --finding-id "$id" \
  --set-json "audit_result={\"verdict\":\"retain\",\"summary\":\"...\",\"agent_a\":{...},\"agent_b\":{...}}"

# If reconciled_verdict in ("downgrade", "flagged"):
artifact-patch.py \
  --path "$artifact_path" --finding-id "$id" \
  --set-json "audit_result={\"verdict\":\"...\",\"summary\":\"...\",\"agent_a\":{...},\"agent_b\":{...}}" \
  --set "disposition=uncertain" \
  --set "is_actionable=false" \
  --set "confirmed_strength=null" \
  --set "reason=Phase 6c audit: downgraded from confirmed"
```

Apply the audit mark regardless of verdict so the renderer can show the
challenge summary even for retained findings (full transparency).

### 6c.5. Log Phase 6c summary

```bash
phase_6c_elapsed=$(( $(date +%s) - phase_6c_start_epoch ))

audit_counts=$(artifact-read.sh \
  --path "$artifact_path" \
  --filter '[.findings[] | select(.audit_result != null) | .audit_result.verdict] | group_by(.) | map({key:.[0], value:length}) | from_entries')

retained=$(printf '%s' "$audit_counts" | jq -r '.retain // 0')
downgraded=$(printf '%s' "$audit_counts" | jq -r '.downgrade // 0')
flagged=$(printf '%s' "$audit_counts" | jq -r '.flagged // 0')

log-phase.sh \
  --review-dir "$review_dir" --phase 6c --name audit \
  --elapsed "$phase_6c_elapsed" \
  --summary "pool=$audit_count; retained=$retained; downgraded=$downgraded; flagged=$flagged"

log-phase.sh \
  --review-dir "$review_dir" --phase 6c --record "$(jq -nc \
    --argjson elapsed "$phase_6c_elapsed" \
    --argjson pool "$audit_count" \
    --argjson retained "$retained" \
    --argjson downgraded "$downgraded" \
    --argjson flagged "$flagged" \
    '{name:"audit", elapsed_sec:$elapsed, counts_by_state:{}, counts_by_disposition:{}, pool:$pool, retained:$retained, downgraded:$downgraded, flagged:$flagged, delta:"\($downgraded + $flagged) challenged"}')"
```

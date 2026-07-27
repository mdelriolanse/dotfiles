---
name: plainly
description: Re-explain a diagnosed defect in plain human narrative so a lost reader gets it instantly — concrete example value, lifecycle timeline, should-vs-does, kicker. Use when the user says "I don't understand the defect", "explain more simply", "explain more concisely", "what's actually wrong", or after a long technical diagnosis asks for a plain restatement. Defects-first; the same moves work for designs and architectures.
allowed-tools: Read
metadata:
  author: <your-handle>
  domain: explanation
  triggers: explain simply, explain concisely, I don't understand, what's actually wrong, in plain English, plain restatement
  role: specialist
---

# plainly

Strip a diagnosed defect to the human narrative a reader can picture without reading the code. Symbols, file:line, and implementation live in the diagnosis being translated *from* — not here.

## When to fire

- After a long technical diagnosis, the user asks to simplify: "I don't understand the defect", "explain more simply", "explain more concisely", "what's actually wrong", "in plain English".
- The user wants a plain restatement, not more investigation.

**Gate:** if no diagnosis exists yet, do NOT fire — tell the user to run `inspect` first. This skill translates an existing diagnosis; it does not produce one.

## The four moves

The exemplar (quote it as the teaching reference):

> When a batch finishes, the user gave the input file a name like patients-oncology-batch.jsonl. That name sits in the file.filename DB column.
>
> 29 days later, a retention sweep runs. Its job: delete the S3 content and wipe the PII labels from the DB row. It nulls batch.metadata and batch_request.custom_id — but leaves file.filename alone.
>
> So the file's bytes are gone, but the human-readable name the customer typed still sits in the database forever. Same kind of sensitive label the sweep was built to clear — just missed.

1. **Concrete example value.** One specific pictured value, not "a filename" but `patients-oncology-batch.jsonl`. This single move does most of the work — it is what the reader pictures.
2. **Lifecycle timeline.** "When a batch finishes" → "29 days later" → "sits in the database forever." Time anchors carry the reader without code flow.
3. **Should vs does.** Name the system's job in one line, then the piece it missed. "Its job: wipe the PII labels. It nulls A and B — but leaves C alone." The gap is the defect.
4. **Kicker.** One line: the missed piece is the same class as the ones it got right — "just missed." Or who gets hurt and how. No hedging.

## Hard rules

- No file:line, no function names, no column types in the prose.
- Max ~4 sentences. If it doesn't fit, the defect isn't understood yet — go back to the diagnosis.
- Lead with the example value.
- Never restate the diagnosis; translate it.
- One symbol name allowed as a label if it grounds the reader, never analyzed.

## Shape of a reply

```
<one sentence: concrete value + where it lives>
<one or two sentences: lifecycle — what the system does, what it missed>
<one sentence: kicker — why the miss matters, or "just missed">
```

Nothing more unless the user asked to "walk me through" or "explain in detail".

## Generalizing to designs and architectures

The same four moves work with "the defect" swapped for "the design":

- **Example value** → a concrete request, user, or data shape.
- **Lifecycle** → the flow over time.
- **Should vs does** → intent vs actual (critique) or is vs replaces (proposal).
- **Kicker** → the one consequence that makes it worth choosing or rejecting.

Keep the 4-sentence ceiling. Compression is the point.

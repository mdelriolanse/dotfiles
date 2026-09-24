# Mistral OCR — API call, key handling, privacy

## Privacy: ask every time a new key/session is needed

This user prefers open-source/local-privacy tooling and avoids sending class
notes/homework to third-party services (see USER profile facts). Mistral OCR
is a cloud API — uploading a lecture PDF to it needs the user's explicit
one-off consent, every time you need a *new* key or session. Do not assume a
prior "yes" carries forward to a new batch of lectures or a new session. Offer
the tradeoff plainly (upload vs. a local/open alternative) via `clarify` before
touching the key.

## Getting the key

As of 2026-09-03 the user opted to persist a Mistral key at
`~/.hermes/secrets/api_keys.env` (var `MISTRAL_API_KEY`, file mode 600) —
this was an explicit one-off request that overrides the "ask every time /
never persist" default below. Check that file first:
`grep MISTRAL_API_KEY ~/.hermes/secrets/api_keys.env` — if present, `source`
it (or export the value) instead of asking the user to repaste. Still ask
the user for one-off consent before *uploading images/PDFs* to the API each
new batch (the persisted key removes the friction of re-pasting a secret,
it doesn't waive the "does this content need to leave the machine" check).

If no key is found there, fall back to the original rule: the vault doesn't
otherwise persist one. Ask the user to paste it fresh each time OCR is
needed; do not search for it repeatedly across sessions.

## The API call

```bash
export MISTRAL_API_KEY='<pasted-key>'

python3 - <<PYEOF
import json, base64
b64 = base64.b64encode(open("<path-to-lecture>.pdf","rb").read()).decode()
payload = {
    "model": "mistral-ocr-latest",
    "document": {"type": "document_url", "document_url": f"data:application/pdf;base64,{b64}"},
    "include_image_base64": False
}
json.dump(payload, open("/tmp/ocr_payload.json","w"))
PYEOF

curl -s -X POST "https://api.mistral.ai/v1/ocr" \
  -H "Authorization: Bearer $MISTRAL_API_KEY" \
  -H "Content-Type: application/json" \
  -d @/tmp/ocr_payload.json \
  -o /tmp/ocr_result.json -w "HTTP:%{http_code}\n"
```

Batch every lecture PDF in the target range through this same pattern before
cleaning up — one `export`, N calls, one `unset`.

## Parsing the response

Top-level keys: `pages`, `model`, `document_annotation`, `usage_info`. Each
page has: `index`, `markdown`, `images`, `tables`, `hyperlinks`, `header`,
`footer`, `dimensions`, `confidence_scores`, `blocks`. The `markdown` field is
what you want — it reconstructs headers, matrices as LaTeX, tables as markdown
tables, and diagrams as `![img-N.jpeg](img-N.jpeg)` placeholders (correctly
left un-transcribed rather than garbled).

```python
import json
for n in lecture_numbers:
    d = json.load(open(f"/tmp/ocr_lecN_result.json"))
    pages = d.get("pages", [])
    text = "\n\n".join(f"--- page {p['index']} ---\n" + p['markdown'] for p in pages)
    open(f"/tmp/lecN.md", "w").write(text)
```

## Quality notes (observed on this vault's math/physics lecture scans)

- Matrix LaTeX (nested brackets, subscripts, boxed answers) comes through
  accurately — this is the main reason to use OCR over vision-transcription.
- Row-reduction annotations (①-6③ style circled-number notation) are
  preserved faithfully.
- Section headers become proper markdown headers; tabular content becomes
  markdown tables.
- Minor artifacts to watch for: abbreviations like "solⁿ" for "solution"
  (superscript-n shorthand) may need light cleanup; always re-read the raw
  markdown yourself rather than trusting it blind.

## Cleanup — mandatory, every time

```bash
rm -f /tmp/ocr_payload.json /tmp/ocr_result.json  # per lecture, or a whole batch dir
unset MISTRAL_API_KEY
```

Never let the key land in `config.yaml`, memory, or any vault file. Delete
temp payload/response JSON files once the markdown has been extracted and
saved — don't leave the raw base64-encoded PDF payload sitting in `/tmp`.

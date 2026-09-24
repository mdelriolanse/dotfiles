# Generating practice-problem PDFs for a course's quizzes/

When the user asks to "formalize" a practice question (e.g. one filed away in
a daily todo, or found in lecture material) into a readable PDF, use the `pdf`
skill's `pdf_create.py` and store the output under
`cornell/courses/<slug>/quizzes/` — it's agent-compiled practice material, the
same bucket as generated SRS quizzes.

## Workflow
1. Trace the request back to its source: search `todos/`, the course's
   `materials/lectures/*.pdf` (via `read_file`, which auto-extracts PDF text),
   and past sessions (`session_search`) to find the exact question/slide being
   referenced. Don't invent a generic version — ground it in the real lecture
   content and reuse its notation/register values/style, but write a *fresh*
   problem instance (change the numbers) rather than reprinting the original
   PollEv slide verbatim, so it's genuine practice.
2. Build a `pdf_create.py` JSON spec with `write_file`. **Table elements use
   `{"type": "table", "rows": [[...], [...]], "header": true}`** — NOT `"data"`.
   Using `"data"` silently produces a table-less page (paragraphs/headings still
   render, so the mistake isn't obvious until you visually check the output).
3. Put the answer key in the same PDF after a `{"type": "pagebreak"}`, not a
   separate file, unless the user asks to attempt it cold first — then ask
   whether they want the key split out.
4. If reportlab/pypdf/pdfplumber aren't importable (no system pip — PEP 668),
   create a venv with `uv venv ~/.hermes/venvs/pdf` and
   `uv pip install --python ~/.hermes/venvs/pdf/bin/python reportlab pypdf pdfplumber`,
   then invoke scripts with that interpreter directly
   (`~/.hermes/venvs/pdf/bin/python .../pdf_create.py ...`). Reuse this venv for
   any future PDF-skill work in this vault instead of recreating it.
5. Verify: `pdf_read.py out.pdf --meta` (page count sane, not encrypted), then
   `pdf_page_image.py out.pdf --dpi 120 --out-dir /tmp/pdfcheck` and
   `vision_analyze` every page — confirm tables actually rendered (not just
   paragraphs) and nothing overflows a page edge.

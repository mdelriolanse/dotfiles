# Installing tectonic (no root, no apt, no texlive-full)

Tectonic is a self-contained LaTeX engine distributed as a static binary. It
downloads individual LaTeX packages on demand from its bundled TeX Live
snapshot (cached locally after first use), so there's no multi-GB
`texlive-full` install and no `sudo`/apt needed at all.

## Install (Linux x86_64)

```bash
# Find the current release asset (versions/URLs change — always re-check):
curl -s https://api.github.com/repos/tectonic-typesetting/tectonic/releases/latest \
  | grep browser_download_url | grep linux-musl | grep x86_64

# Download + install to ~/.local/bin (already on PATH for most shells):
curl -sL "<asset-url-from-above>" -o /tmp/tectonic.tar.gz
mkdir -p ~/.local/bin
tar -xzf /tmp/tectonic.tar.gz -C /tmp
mv /tmp/tectonic ~/.local/bin/tectonic
chmod +x ~/.local/bin/tectonic
rm /tmp/tectonic.tar.gz

# Verify:
export PATH="$HOME/.local/bin:$PATH"   # add to shell rc if not already there
tectonic --version
```

The release page also has `x86_64-unknown-linux-gnu` (needs glibc, slightly
smaller) and `aarch64`/`arm` variants — pick `musl` for the most portable
static binary if unsure.

## First compile per new package

The first time a `.tex` file uses a package tectonic hasn't fetched yet (e.g.
`tcolorbox`, `fancyhdr`), it silently downloads it from the network — this
needs connectivity once, then it's cached in `~/.cache/Tectonic/` (or
platform equivalent) for every future compile, even offline.

```bash
tectonic file.tex
# note: downloading article.cls
# note: downloading amsmath.sty
# ... (only happens once per package, ever)
# note: Writing `file.pdf` (55.7 KiB)
```

## Rendering pages to PNG for visual verification

Tectonic only produces the PDF — use `pypdfium2` (needs a venv, since this
machine has PEP 668 / no system pip) to rasterize pages for `vision_analyze`:

```bash
uv venv /tmp/latexvenv --quiet
source /tmp/latexvenv/bin/activate
uv pip install pypdfium2 pillow --quiet

python3 -c "
import pypdfium2 as pdfium
pdf = pdfium.PdfDocument('file.pdf')
for i in range(len(pdf)):
    bitmap = pdf[i].render(scale=2.2)
    bitmap.to_pil().save(f'file_p{i}.png')
"
```

Then `vision_analyze` each PNG — check for missing-glyph black boxes,
overflow off the page edge, and that matrices/equations actually render as
math (not raw LaTeX source leaking through from a typo).

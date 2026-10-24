---
name: copyable-pdf
description: Make scanned PDFs searchable and copyable with the `copyable-pdf` CLI (Tesseract OCR), or extract their text as .txt. Use when a PDF is a scan or photo with no selectable text, when the user wants to OCR a PDF, search or copy text from a scanned document, read the text of an image-only PDF, or fix an upside-down, crooked or shadowed scan.
---

# copyable-pdf

`copyable-pdf` renders each page of a PDF, runs Tesseract on it, and writes a
searchable PDF. It can also write the recognised text beside it.

## Before running

1. Find the command: `copyable-pdf` if it is on the PATH (Homebrew:
   `brew install maxgfr/tap/copyable-pdf`), otherwise `script.sh` from
   https://github.com/maxgfr/copyable-pdf.
2. Check whether the PDF really needs OCR: `pdftotext file.pdf - | head`. If
   that already prints the real text, the PDF has a text layer. Say so instead
   of OCRing it again, unless the user insists.
3. Missing tools or language packs make the script ask `[y/N]` on stdin. Run
   it with `</dev/null` so that prompt reads as "no" instead of hanging. The
   run then stops with exit 1 and names what is missing. Install it yourself,
   with the user's approval:
   - always: `tesseract` and `poppler` (`brew install tesseract poppler`, or
     `apt-get install tesseract-ocr poppler-utils`);
   - a language other than English: `brew install tesseract-lang`, or
     `apt-get install tesseract-ocr-<code>` (e.g. `tesseract-ocr-fra`);
   - `--preserve`: `qpdf`;
   - `--clean`: `imagemagick`;
   - `--paddle`: `uv` (PaddleOCR itself installs on its own).

## Running

Always pass the input path. With no arguments the script goes interactive and
waits for answers on stdin.

```bash
copyable-pdf [options] input.pdf </dev/null   # writes input_ocr.pdf in the current directory
```

Pick the options from the document and the request:

| Situation | Option |
| :--- | :--- |
| Not English (most important setting) | `-l fra`, `-l deu`, or mixed `-l fra+eng` |
| The original must stay untouched (archives, signed or legal documents, anything kept long-term) | `-p` / `--preserve` |
| Crooked scan, phone photo, shadows, grey or noisy background | `-c` / `--clean` (not with `--preserve`) |
| Small print, footnotes, dense tables | `-d 400` |
| Tesseract still misses text (phone photos, faded or noisy scans) | `--paddle` |
| `--paddle` will be used again | `--save-paddle` instead (keeps the ~1 GB install) |
| The user wants the text itself | `-t` (plain text), `-m` (layout kept, written as `.md`) |
| Custom output path | `-o path/out.pdf` (the directory must exist) |

- Pages are turned upright automatically. If a page with very little text
  comes out wrong, retry with `--plain` (no auto-rotation, no adaptive
  thresholding).
- The default mode rebuilds the PDF from 300 DPI renderings, so the file can
  grow and vector content is rasterised. `--preserve` keeps the original pages
  and adds an invisible text layer.
- `--clean` changes how the pages look in the output: they are straightened
  and their lighting is evened out.
- `--paddle` downloads about 1 GB on first use (about a minute), into the
  run's temp dir, deleted afterwards. Tell the user before a first run.
  `--save-paddle` keeps it in `~/.cache/copyable-pdf/paddle`; later `--paddle`
  runs reuse it. It is slower per page than Tesseract; `--paddle-model tiny`
  speeds it up.

## Results

- Exit 0: the output is written. Check it with
  `pdftotext out.pdf - | head -40` and show the user a short sample.
- Exit 2: bad options or input (missing file, not a PDF, output over the
  input, `--clean` with `--preserve`), caught before any OCR. Nothing is
  written.
- Exit 1: a missing dependency, or a page failed OCR. The error names the page.
  Nothing is written: the tool never returns a PDF with pages missing.
- A warning about an existing text layer means the input was already
  searchable; see step 2 above.

OCR costs a few seconds per page, spread over every core. Run long documents
in the background and report when they finish.

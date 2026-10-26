---
name: copyable-pdf
description: Make scanned PDFs and phone photos of documents searchable and copyable with the `copyable-pdf` CLI (local OCR with PaddleOCR's models, or Tesseract), or extract their text as .txt. Use when a PDF is a scan or photo with no selectable text, when the user wants to OCR a PDF, search or copy text from a scanned document, read the text of an image-only PDF, or fix an upside-down, crooked or shadowed scan.
---

# copyable-pdf

`copyable-pdf` renders each page of a PDF, recognises its text locally, and
writes a searchable PDF. It can also write the recognised text beside it. The
default engine is PaddleOCR's PP-OCRv6 models run by RapidOCR; `--tesseract`
uses Tesseract instead.

## Before running

1. Find the command: `copyable-pdf` if it is on the PATH (Homebrew:
   `brew install maxgfr/tap/copyable-pdf`, which also installs the OCR
   engine), otherwise `script.sh` from https://github.com/maxgfr/copyable-pdf.
2. Check whether the PDF really needs OCR: `pdftotext file.pdf - | head`. If
   that already prints the real text, the PDF has a text layer. Say so instead
   of OCRing it again, unless the user insists.
3. Missing tools make the script ask `[y/N]` on stdin. Run it with
   `</dev/null` so that prompt reads as "no" instead of hanging. The run then
   stops with exit 1 and names what is missing. Install it yourself, with the
   user's approval:
   - always: `poppler` and `uv` (`brew install poppler uv`);
   - `--tesseract`: `tesseract`, plus `tesseract-lang` (or
     `tesseract-ocr-<code>`) for languages other than English;
   - `--preserve`: `qpdf`;
   - `--clean`: `imagemagick`.
4. Outside Homebrew, the first run installs the OCR engine (about 300 MB,
   under a minute) into `~/.cache/copyable-pdf/ocr-engine` and keeps it. Tell
   the user before that first run. `--no-save` installs for one run only.

## Running

Always pass the input path. With no arguments the script goes interactive and
waits for answers on stdin.

```bash
copyable-pdf [options] input.pdf </dev/null   # writes input_ocr.pdf in the current directory
```

Pick the options from the document and the request:

| Situation | Option |
| :--- | :--- |
| Not English (most important setting) | `-l fra`, `-l spa`, or mixed `-l fra+eng` |
| Phone photos, or the original must stay untouched (archives, legal documents) | `-p` / `--preserve` (keeps the file small: no 300 DPI rebuild) |
| Small print, footnotes, dense tables | `-d 400` |
| Every character counts, time does not | `--model medium` |
| Speed matters more than accuracy | `--model tiny` |
| The user wants the text itself | `-t` (plain text), `-m` (layout kept, written as `.md`) |
| Custom output path | `-o path/out.pdf` (the directory must exist) |
| The user asks for Tesseract, or Python cannot be installed | `--tesseract` (much weaker on photos) |

- Pages are turned upright automatically, upside down or sideways.
- Without `--preserve` the PDF is rebuilt from 300 DPI renderings: photos can
  grow from a few MB to tens of MB, and vector content is rasterised.
- `--clean` straightens pages and evens out lighting; it helps `--tesseract`
  a lot and the default engine little. It changes how pages look and cannot
  be combined with `--preserve`.
- `--paddle`, `--save-paddle` and `--paddle-model` are 1.6 names, still
  accepted; the default engine already does what they did.

## Results

- Exit 0: the output is written. Check it with
  `pdftotext out.pdf - | head -40` and show the user a short sample.
- Exit 2: bad options or input (missing file, not a PDF, output over the
  input, `--clean` with `--preserve`, a language the engine lacks), caught
  before any OCR. Nothing is written.
- Exit 1: a missing dependency, or a page failed OCR. The error names the page.
  Nothing is written: the tool never returns a PDF with pages missing.
- A warning about an existing text layer means the input was already
  searchable; see step 2 above.

The default engine takes about a second a page; run long documents in the
background and report when they finish.

---
name: copyable-pdf
description: Make scanned PDFs and phone photos of documents searchable and copyable with the `copyable-pdf` CLI (local OCR with PaddleOCR's models), or extract their text as .txt. Use when a PDF is a scan or photo with no selectable text, when the user wants to OCR a PDF, search or copy text from a scanned document, read the text of an image-only PDF, or fix an upside-down or sideways scan.
---

# copyable-pdf

`copyable-pdf` renders each page of a PDF, recognises its text locally with
PaddleOCR's PP-OCRv6 models (run by RapidOCR), and writes a searchable PDF. It
can also write the recognised text beside it.

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
   - `--preserve`: `qpdf`.
4. Outside Homebrew, the first run installs the OCR engine (about 300 MB,
   under a minute) into `~/.cache/copyable-pdf/ocr-engine` and keeps it. Tell
   the user before that first run.

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
| The original must stay untouched (archives, legal documents, anything kept) | `-p` / `--preserve` |
| Print smaller than 5-6 pt | `-d 400` |
| The user wants the text itself | `-t` (writes a `.txt` beside the PDF) |
| Custom output path | `-o path/out.pdf` (the directory must exist) |

- Pages are turned upright automatically, upside down or sideways.
- Without `--preserve` the PDF is rebuilt from 300 DPI renderings: photos stay
  JPEG and scans lossless, but vector content is rasterised.
- Removed in 3.0, and refused with exit 2: `--tesseract`, `--plain`,
  `--tessdata-dir`, `--clean`, `--model`, `--no-save`, `-m/--markdown`,
  `--paddle`, `--save-paddle`, `--paddle-model`.

## Results

- Exit 0: the output is written. Check it with
  `pdftotext out.pdf - | head -40` and show the user a short sample.
- Exit 2: bad options or input (missing file, not a PDF, output over the
  input, a removed option, a language no model reads), caught before any OCR.
  Nothing is written.
- Exit 1: a missing dependency, or a page failed OCR. The error names the page.
  Nothing is written: the tool never returns a PDF with pages missing.
- A warning about an existing text layer means the input was already
  searchable; see step 2 above.

OCR takes about a second a page; run long documents in the background and
report when they finish.

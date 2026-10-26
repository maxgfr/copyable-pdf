# copyable-pdf

> A bash script that turns scanned PDFs and phone photos of documents into searchable, copyable PDFs, with PaddleOCR's models running locally.

![License](https://img.shields.io/badge/license-MIT-green)

`copyable-pdf` takes a PDF input, converts each page to an image, recognises the text on it (OCR), and merges everything back into a single, searchable PDF document. Nothing leaves your machine.

## Features

-   **OCR**: Make scanned documents searchable and copyable.
-   **Strong recognition**: PaddleOCR's PP-OCRv6 models, run by
    [RapidOCR](https://github.com/RapidAI/RapidOCR) on ONNX Runtime. They read
    phone photos, small print, crooked, faded or noisy scans, at about a page a
    second on a laptop CPU.
-   **Any way up**: Upside-down and sideways pages are turned automatically, and
    come out in reading order.
-   **Word-accurate text layer**: Every word sits where it is on the page, so
    selecting or finding a word highlights that word.
-   **Small output**: Photos stay JPEG, scans are stored losslessly and in grey
    when they have no colour.
-   **Preserve mode**: Keep the original pages untouched and add an invisible
    text layer on top, instead of rebuilding the PDF from images.
-   **Parallel**: Several pages at a time on multi-core machines.
-   **Text sidecars**: Also write the recognised text as `.txt` or `.md`.
-   **Interactive mode**: Run it with no arguments and it asks for each setting.

## Installation

### Via Homebrew

```bash
brew install maxgfr/tap/copyable-pdf
```

This installs everything, the OCR engine and its models included, so the first
run starts straight away.

### As an agent skill

Teach your coding agent (Claude Code, Codex, Cursor and others) when and how to
use `copyable-pdf`:

```bash
npx skills add maxgfr/copyable-pdf
```

Add `-g` to install it for every project. The skill lives in
[`skills/copyable-pdf`](skills/copyable-pdf/SKILL.md). It drives the CLI, so
install the CLI as well.

### Manual Installation

1.  Clone the repository:
    ```bash
    git clone https://github.com/maxgfr/copyable-pdf.git
    cd copyable-pdf
    ```
2.  Make the script executable:
    ```bash
    chmod +x script.sh
    ```
3.  (Optional) Move to your bin directory:
    ```bash
    mv script.sh /usr/local/bin/copyable-pdf
    ```

### Dependencies

-   **poppler**: For `pdftoppm`, `pdfunite`, `pdfinfo` and `pdftotext`.
-   **uv**: Builds the OCR engine's environment on first use (about 300 MB with
    its models, kept in `~/.cache/copyable-pdf/ocr-engine`).
-   **qpdf** (optional): Only needed for `--preserve`.

On macOS (Homebrew):
```bash
brew install poppler uv
brew install qpdf            # optional, for --preserve
```

On Ubuntu/Debian:
```bash
sudo apt-get install poppler-utils
curl -LsSf https://astral.sh/uv/install.sh | sh
sudo apt-get install qpdf    # optional, for --preserve
```

## Usage

```bash
copyable-pdf [options] input.pdf
```

Run it with no arguments for interactive mode, which asks for the input path,
the language, the DPI, the sidecars and the output name in turn.

### How it works

1.  Every page is rendered to an image at the chosen DPI, and the OCR engine
    finds and reads every line of text on it, word by word. A page that reads
    poorly as it is, or whose lines mostly read upside down, is read again
    turned round or on its side, and the best reading wins.
2.  By default those recognised pages are merged into a **new** PDF. The result
    is searchable everywhere, but it is a re-encoded copy of the original.
3.  With `--preserve`, only the recognised text is kept and stamped onto the
    original file as an invisible layer, so nothing about the original changes.

If a page fails to be recognised, the run stops and writes nothing, rather than
handing back a document that is quietly missing pages.

### Options

| Option | Description | Default |
| :--- | :--- | :--- |
| `-l, --lang <code>` | Language code(s), `+` separated: three letters (`eng`, `fra`, `spa`, `fra+eng`) or PaddleOCR's own (`en`, `fr`) | `eng` |
| `-o, --output <path>` | Custom output file path | `input_ocr.pdf` |
| `-d, --dpi <num>` | DPI resolution for OCR | `300` |
| `-j, --jobs <num>` | Number of OCR processes working on pages at once | a third of the cores, up to 4 |
| `-t, --text` | Generate an additional .txt file | `false` |
| `-m, --markdown` | Generate an additional .md file (layout-preserved plain text) | `false` |
| `-p, --preserve` | Keep the original pages, add an invisible text layer on top (needs `qpdf`) | `false` |
| `--model <size>` | OCR model: `tiny` (fastest), `small` or `medium` | `small` |
| `--no-save` | Install the OCR engine for this run only, in the temp dir, and delete it afterwards | `false` |
| `--install-engine` | Install the OCR engine and its models, then exit (`brew install` does this for you) | - |
| `-k, --keep` | Keep temporary files (debug) | `false` |
| `-v, --verbose` | Verbose output | `false` |
| `-h, --help` | Show help message | - |
| `-V, --version` | Print the version and exit | - |

`--paddle`, `--save-paddle` and `--paddle-model` from 1.6 are still accepted.
`--tesseract`, `--plain`, `--tessdata-dir` and `--clean` were removed in 3.0
with Tesseract, and are refused with an error rather than ignored.

### Examples

**Basic usage:**
```bash
copyable-pdf document.pdf
```

**A French document, with the text alongside:**
```bash
copyable-pdf -l fra -t document.pdf
```

**Phone photos of a Spanish form, originals kept:**
```bash
copyable-pdf -l spa -p photos.pdf
```

**Explicitly set output filename:**
```bash
copyable-pdf -o searchable_doc.pdf scan.pdf
```

## Getting the best results

-   **Set the right language**: `-l fra`, `-l spa`, or `-l fra+eng` for mixed
    documents.
-   **Use `--preserve` for anything worth keeping.** The original images,
    vectors and metadata stay exactly as they were, with only the text added.
-   **Raise the DPI for very small print.** 300 suits most documents, down to
    5-6 pt text; try 400 for anything smaller.
-   **`--model medium`** is slower and, on the benchmark below, no more
    accurate: keep `small` unless a document of yours proves otherwise.

## OCR engine

The text is recognised by PaddleOCR's PP-OCRv6 models (PP-OCRv5 for Cyrillic,
Arabic, Korean and other scripts v6 does not read), run by
[RapidOCR](https://github.com/RapidAI/RapidOCR) on ONNX Runtime. They come from
the same project as the `paddleocr` Python package and recognise the same, but
without its 1 GB PaddlePaddle runtime, and several times faster on a CPU.

-   **Installed once, kept.** The first run builds the engine with `uv` in
    `~/.cache/copyable-pdf/ocr-engine`, and every later run reuses it.
    `brew install` does this at install time. Delete that folder to remove it,
    or pass `--no-save` to install for one run and delete it afterwards.
-   **Languages**: Latin-script languages, English, Chinese and Japanese share
    one model, so `-l fra+eng` works. Other scripts take one language at a
    time.
-   **Private**: models are downloaded once; pages and text never leave your
    machine.

Measured on generated pages with known text, scored by character accuracy per
line, on an Apple Silicon laptop (10 cores):

| Page | 2.0 | 3.0 |
| :--- | :--- | :--- |
| Clean 11 pt | 94.9% | **100%** |
| Small print, 7 pt | 97.5% | **100%** |
| Tiny print, 5.5 pt | 97.3% | **100%** |
| Dense, two columns | 99.7% | **99.9%** |
| French and Spanish accents | 91.9% | **99.99%** |
| Noisy 150 DPI scan | 94.8% | **99.99%** |
| Phone photos (2 pages) | 91.5%, 17.7 MB | **99.98%, 2.7 MB** |
| Upside down / sideways | 93.6% / 93.7% | **100% / 100%** |
| 24 pages | 128 s, 53 MB | **90 s, 35 MB** |

Most of the gain comes from one setting: the line orientation classifier
RapidOCR picks by default turned about one upright line in ten upside down,
which then read as junk. 3.0 uses PP-OCRv5's, the one the `paddleocr` package
uses.

Why not a larger model? The document AI models at the top of 2026's benchmarks
(PaddleOCR-VL, GLM-OCR, MinerU, DeepSeek-OCR) are built for GPUs, are slow on a
CPU, and return text without the position of each line, which a searchable PDF
needs. PP-OCRv6 is the strongest engine that runs well on any machine and says
where every word is.

## Preserve mode

Rebuilding a PDF from 300 DPI renderings costs you the original. A scan stored
as JBIG2 or CCITT can grow several times over, and vector text, bookmarks and
metadata do not come back.

`--preserve` avoids that: images, vectors, bookmarks, metadata and file size
stay exactly as they were, with the recognised text selectable on top. It needs
`qpdf`, and only when the flag is used.

## License

MIT. The invisible text uses Tesseract's GlyphLessFont (Apache-2.0), embedded
in the script.

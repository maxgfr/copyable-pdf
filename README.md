# copyable-pdf

> A bash script that turns scanned PDFs and phone photos of documents into searchable, copyable PDFs, with PaddleOCR's models (or Tesseract) running locally.

![License](https://img.shields.io/badge/license-MIT-green)

`copyable-pdf` takes a PDF input, converts each page to an image, recognises the text on it (OCR), and merges everything back into a single, searchable PDF document. Nothing leaves your machine.

## Features

-   **OCR**: Make scanned documents searchable and copyable.
-   **Strong recognition by default**: PaddleOCR's PP-OCRv6 models, run by
    [RapidOCR](https://github.com/RapidAI/RapidOCR) on ONNX Runtime. They read
    phone photos, crooked, faded or noisy scans that Tesseract misses, about a
    page a second on a laptop CPU. Tesseract remains available with
    `--tesseract`.
-   **Preserve mode**: Keep the original pages untouched and add an invisible
    text layer on top, instead of rebuilding the PDF from images.
-   **Any way up**: Upside-down and sideways pages are turned automatically,
    and shadows or yellowed corners no longer hide the text in them.
-   **Clean mode**: Straighten crooked scans and flatten uneven lighting before
    OCR.
-   **Parallel Processing**: Uses multiple cores for faster OCR.
-   **Text sidecars**: Also write the recognised text as `.txt` or `.md`.
-   **Interactive mode**: Run it with no arguments and it asks for each setting.
-   **Dependency Check**: Automatically checks for missing tools, and offers to
    install them and any missing language pack.
-   **Customizable**: Set language, DPI and the number of parallel jobs.

## Installation

### Via Homebrew

```bash
brew install maxgfr/tap/copyable-pdf
```

This installs everything: the OCR engine and its models, Tesseract with every
language, qpdf and ImageMagick. The first run starts straight away.

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

Ensure you have the following installed:
-   **poppler**: For `pdftoppm`, `pdfunite`, `pdfinfo` and `pdftotext`.
-   **uv**: Builds the OCR engine's environment on first use (about 300 MB,
    kept in `~/.cache/copyable-pdf/ocr-engine`).
-   **tesseract** (optional): Only needed for `--tesseract`. When present, its
    glyphless font is also used for the invisible text.
-   **qpdf** (optional): Only needed for `--preserve`.
-   **ImageMagick** (optional): Only needed for `--clean`.

On macOS (Homebrew):
```bash
brew install poppler uv
brew install tesseract       # optional, for --tesseract
brew install qpdf            # optional, for --preserve
brew install imagemagick     # optional, for --clean
```

On Ubuntu/Debian:
```bash
sudo apt-get install poppler-utils
curl -LsSf https://astral.sh/uv/install.sh | sh
sudo apt-get install tesseract-ocr     # optional, for --tesseract
sudo apt-get install qpdf              # optional, for --preserve
sudo apt-get install imagemagick       # optional, for --clean
```

## Usage

```bash
copyable-pdf [options] input.pdf
```

Run it with no arguments for interactive mode, which asks for the input path,
the language, the DPI, the sidecars and the output name in turn.

### How it works

1.  Every page is rendered to an image at the chosen DPI, and the OCR engine
    finds and reads every line of text on it. A page that reads poorly as it
    is gets read turned round and on each side too, and the best reading wins,
    so upside-down and sideways pages come out right. With `--clean`, each page
    is also straightened and its lighting evened out first.
2.  By default those recognised pages are merged into a **new** PDF. The result
    is searchable everywhere, but it is a re-encoded copy of the original.
3.  With `--preserve`, only the recognised text is kept and stamped onto the
    original file as an invisible layer, so nothing about the original changes.

If a page fails to be recognised, the run stops and writes nothing, rather than
handing back a document that is quietly missing pages.

### Options

| Option | Description | Default |
| :--- | :--- | :--- |
| `-l, --lang <code>` | Language code(s), `+` separated (e.g. `eng`, `fra`, `eng+fra`) | `eng` |
| `-o, --output <path>` | Custom output file path | `input_ocr.pdf` |
| `-d, --dpi <num>` | DPI resolution for OCR | `300` |
| `-j, --jobs <num>` | Number of parallel jobs | Auto-detect |
| `-t, --text` | Generate an additional .txt file | `false` |
| `-m, --markdown` | Generate an additional .md file (layout-preserved plain text) | `false` |
| `-p, --preserve` | Keep the original pages, add an invisible text layer on top (needs `qpdf`) | `false` |
| `-c, --clean` | Straighten pages and flatten shadows before OCR (needs ImageMagick). The cleaned page is what the output shows. Not with `--preserve` | `false` |
| `--model <size>` | OCR model: `tiny` (fastest), `small` or `medium` (most accurate) | `small` |
| `--no-save` | Install the OCR engine for this run only, in the temp dir, and delete it afterwards | `false` |
| `--install-engine` | Install the OCR engine and its models, then exit (`brew install` does this for you) | - |
| `--tesseract` | Recognise with Tesseract instead. See [Tesseract](#tesseract) | `false` |
| `--plain` | With `--tesseract`: skip automatic rotation and adaptive thresholding | `false` |
| `--tessdata-dir <path>` | With `--tesseract`: read language models from this directory, e.g. a [`tessdata_best`](https://github.com/tesseract-ocr/tessdata_best) checkout | system tessdata |
| `-k, --keep` | Keep temporary files (debug) | `false` |
| `-v, --verbose` | Verbose output | `false` |
| `-h, --help` | Show help message | - |
| `-V, --version` | Print the version and exit | - |

### Examples

**Basic usage:**
```bash
copyable-pdf document.pdf
```

**Specify language (French) and higher DPI:**
```bash
copyable-pdf -l fra -d 600 document.pdf
```

**Explicitly set output filename:**
```bash
copyable-pdf -o searchable_doc.pdf scan.pdf
```

**Keep the original pages untouched:**
```bash
copyable-pdf --preserve scan.pdf
```

**Clean up a crooked phone photo of a French page:**
```bash
copyable-pdf --clean -l fra photo.pdf
```

## Getting the best results

-   **Set the right language**: `-l fra`, `-l spa`, or `-l fra+eng` for mixed
    documents.
-   **Use `--preserve` for photos.** Without it every page is rebuilt from a
    300 DPI rendering, and a 3 MB PDF of phone photos can come out at 90 MB.
    With it the original images are kept and only the text is added.
-   **Raise the DPI for small print.** 300 suits most documents; try 400 for
    footnotes or dense tables.
-   **`--model medium`** when every character counts and time does not.
-   **With `--tesseract`**: `--clean` helps a lot on crooked and shadowed
    scans (it changes how the output looks, and cannot be combined with
    `--preserve`); the `tessdata_best` models (`--tessdata-dir`) are slower and
    not always better; fall back to `--plain` if automatic rotation ever
    misreads a page with very little text on it.

## OCR engine

By default the text is recognised by PaddleOCR's PP-OCRv6 models (PP-OCRv5 for
Cyrillic, Arabic, Korean and other scripts v6 does not read), run by
[RapidOCR](https://github.com/RapidAI/RapidOCR) on ONNX Runtime. They come from
the same project as the `paddleocr` Python package and recognise the same, but
without its 1 GB PaddlePaddle runtime, and several times faster on a CPU.

-   **Installed once, kept.** The first run builds the engine with `uv`
    (about 300 MB with its models, under a minute) in
    `~/.cache/copyable-pdf/ocr-engine`, and every later run reuses it.
    `brew install` does this at install time. Delete that folder to remove it,
    or pass `--no-save` to install for one run and delete it afterwards.
-   **Fast**: about a second a page with the default `small` model on a laptop
    CPU. `--model tiny` is faster, `--model medium` more accurate and slower.
-   **Languages**: the same `-l` codes as Tesseract. Latin-script languages,
    English, Chinese and Japanese share one model, so `-l fra+eng` works. Other
    scripts take one language at a time.
-   **Private**: models are downloaded once; pages and text never leave your
    machine.

On a phone photo of a Spanish form (perspective, dark background, BORRADOR
watermark, JPEG; 2 pages, 21 printed labels each), on an Apple Silicon laptop:

| Engine | Labels read | Time |
| :--- | :--- | :--- |
| Default (`small`) | 100% | 11 s |
| Default, `--model medium` | 100% | 33 s |
| `paddleocr` package, small (1.6's `--paddle`) | 98% | 22 s |
| `--tesseract` | 48% | 9 s |

Why not a larger model? The document AI models at the top of 2026's benchmarks
(PaddleOCR-VL, GLM-OCR, MinerU, DeepSeek-OCR) are built for GPUs, are slow on a
CPU, and return text without the position of each line, which a searchable PDF
needs. PP-OCRv6 is the strongest engine that runs well on any machine and says
where every line is.

## Tesseract

`--tesseract` recognises with [Tesseract](https://github.com/tesseract-ocr/tesseract)
instead: no Python environment, but much weaker on photos and poor scans. It
detects page orientation and thresholds each region on its own (Sauvola) by
default; `--plain` turns both off. `--clean` helps it most on crooked and
shadowed scans, and `--tessdata-dir` points it at other models such as
`tessdata_best`.

## Preserve mode

Rebuilding a PDF from 300 DPI renderings costs you the original. A scan stored
as JBIG2 or CCITT can grow several times over, and vector text, bookmarks and
metadata do not come back.

`--preserve` avoids that: images, vectors, bookmarks, metadata and file size
stay exactly as they were, with the recognised text selectable on top. It needs
`qpdf`, and only when the flag is used, so the default path still depends on
nothing but Tesseract and poppler.

Use it for anything worth keeping. Use the default when `qpdf` is unavailable
and a plain searchable copy is enough.

## License

MIT

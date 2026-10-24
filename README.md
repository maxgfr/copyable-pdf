# copyable-pdf

> A lightweight, dependency-minimal bash script to convert scanned PDFs into searchable PDFs using Tesseract OCR.

![License](https://img.shields.io/badge/license-MIT-green)

`copyable-pdf` takes a PDF input, converts each page to an image, performs OCR (Optical Character Recognition) using Tesseract, and merges them back into a single, searchable PDF document.

## Features

-   **OCR**: Make scanned documents searchable and copyable.
-   **Preserve mode**: Keep the original pages untouched and add an invisible
    text layer on top, instead of rebuilding the PDF from images.
-   **Better recognition out of the box**: Upside-down pages are turned
    automatically, and shadows or yellowed corners no longer hide the text in
    them.
-   **Clean mode**: Straighten crooked scans and flatten uneven lighting before
    OCR.
-   **PaddleOCR engine**: For the hardest scans, recognise with PaddleOCR
    instead of Tesseract. It is installed on demand and deleted afterwards,
    unless you choose to keep it.
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
-   **tesseract**: For OCR.
-   **poppler**: For `pdftoppm`, `pdfunite`, `pdfinfo` and `pdftotext`.
-   **qpdf** (optional): Only needed for `--preserve`.
-   **ImageMagick** (optional): Only needed for `--clean`.
-   **uv** (optional): Only needed for `--paddle`, to build PaddleOCR's
    environment.

On macOS (Homebrew):
```bash
brew install tesseract poppler
brew install qpdf            # optional, for --preserve
brew install imagemagick     # optional, for --clean
brew install uv              # optional, for --paddle
```

On Ubuntu/Debian:
```bash
sudo apt-get install tesseract-ocr poppler-utils
sudo apt-get install qpdf    # optional, for --preserve
sudo apt-get install imagemagick  # optional, for --clean
curl -LsSf https://astral.sh/uv/install.sh | sh  # optional, for --paddle
```

## Usage

```bash
copyable-pdf [options] input.pdf
```

Run it with no arguments for interactive mode, which asks for the input path,
the language, the DPI, the sidecars and the output name in turn.

### How it works

1.  Every page is rendered to an image at the chosen DPI, and Tesseract
    recognises the text on it, several pages at a time. Tesseract first detects
    each page's orientation, so a page scanned upside down is read the right
    way up, and it thresholds each region of the page on its own (Sauvola), so
    a shadow does not blacken the text under it. With `--clean`, each page is
    also straightened and its lighting evened out before that.
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
| `--plain` | Skip automatic rotation and adaptive thresholding (the pre-1.4 behaviour) | `false` |
| `--paddle` | Recognise with PaddleOCR instead of Tesseract (needs `uv`). See [PaddleOCR engine](#paddleocr-engine) | `false` |
| `--paddle-model <size>` | PaddleOCR model: `tiny`, `small` or `medium` | `small` |
| `--save-paddle` | Keep the PaddleOCR install in `~/.cache/copyable-pdf/paddle` and reuse it | `false` |
| `--tessdata-dir <path>` | Read language models from this directory, e.g. a [`tessdata_best`](https://github.com/tesseract-ocr/tessdata_best) checkout | system tessdata |
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

-   **Set the right language.** It matters more than any other setting. Use
    `-l fra`, or `-l fra+eng` for mixed documents. A missing pack is offered for
    install.
-   **Use `--clean` on poor scans**: crooked pages, phone photos, shadows near
    the spine, grey or noisy backgrounds. It changes how the output looks, so
    leave it off for scans that are already clean, and it cannot be combined
    with `--preserve`, because a straightened page no longer lines up with the
    original.
-   **Raise the DPI for small print.** 300 suits most documents; try 400 for
    footnotes or dense tables.
-   **Try the `tessdata_best` models** if accuracy still falls short. Download
    the `.traineddata` files you need into one directory and pass it with
    `--tessdata-dir`. They are several times slower and not always better, so
    compare them on your own documents.
-   **Fall back to `--plain`** if automatic rotation ever misreads a page with
    very little text on it.
-   **Switch to `--paddle`** when Tesseract still misses text: phone photos,
    faded or noisy scans, unusual fonts.

## PaddleOCR engine

`--paddle` recognises the pages with [PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR)
instead of Tesseract. Its neural models read poor scans and photos that
Tesseract misses: on a crooked, blurred and noisy test page, Tesseract finds
nothing and PaddleOCR reads every line.

```bash
copyable-pdf --paddle scan.pdf                 # install, OCR, delete the install
copyable-pdf --save-paddle -l spa scan.pdf     # keep it for next time
```

-   **Nothing to install by hand except `uv`.** The first run downloads
    PaddleOCR, a compatible Python and the models, about 1 GB, in about a
    minute. A spinner shows progress while it does.
-   **Temporary by default.** Everything goes into the run's temporary
    directory and is deleted when the run ends.
-   **`--save-paddle` keeps it** in `~/.cache/copyable-pdf/paddle`. Every
    later `--paddle` run reuses it and starts in seconds. Delete that folder to
    remove it.
-   **Slower than Tesseract**: a few seconds per page with the default `small`
    model. `--paddle-model tiny` is faster, and `medium` is more accurate but
    several times slower.
-   **Languages**: the same `-l` codes as Tesseract. Latin-script languages,
    English, Chinese and Japanese share one model, so `-l fra+eng` works. Other
    scripts (Cyrillic, Arabic, Korean…) take one language at a time.
-   Works with `--preserve`, `--clean`, `-t` and `-m`. `--plain` and
    `--tessdata-dir` are Tesseract settings and are ignored.

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

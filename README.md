# copyable-pdf

> A lightweight, dependency-minimal bash script to convert scanned PDFs into searchable PDFs using Tesseract OCR.

![License](https://img.shields.io/badge/license-MIT-green)

`copyable-pdf` takes a PDF input, converts each page to an image, performs OCR (Optical Character Recognition) using Tesseract, and merges them back into a single, searchable PDF document.

## Features

-   **OCR**: Make scanned documents searchable and copyable.
-   **Preserve mode**: Keep the original pages untouched and add an invisible
    text layer on top, instead of rebuilding the PDF from images.
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

On macOS (Homebrew):
```bash
brew install tesseract poppler
brew install qpdf            # optional, for --preserve
```

On Ubuntu/Debian:
```bash
sudo apt-get install tesseract-ocr poppler-utils
sudo apt-get install qpdf    # optional, for --preserve
```

## Usage

```bash
copyable-pdf [options] input.pdf
```

Run it with no arguments for interactive mode, which asks for the input path,
the language, the DPI, the sidecars and the output name in turn.

### How it works

1.  Every page is rendered to an image at the chosen DPI, and Tesseract
    recognises the text on it, several pages at a time.
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

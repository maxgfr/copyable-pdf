# copyable-pdf

> A lightweight, dependency-minimal bash script to convert scanned PDFs into searchable PDFs using Tesseract OCR.

![License](https://img.shields.io/badge/license-MIT-green)

`copyable-pdf` takes a PDF input, converts each page to an image, performs OCR (Optical Character Recognition) using Tesseract, and merges them back into a single, searchable PDF document.

## Features

-   **OCR**: Make scanned documents searchable and copyable.
-   **Parallel Processing**: Uses multiple cores for faster OCR.
-   **Dependency Check**: Automatically checks for missing tools.
-   **Customizable**: Set language and DPI.

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
-   **poppler**: For `pdftoppm` and `pdfunite`.

On macOS (Homebrew):
```bash
brew install tesseract poppler
```

On Ubuntu/Debian:
```bash
sudo apt-get install tesseract-ocr poppler-utils
```

## Usage

```bash
copyable-pdf [options] input.pdf
```

### Options

| Option | Description | Default |
| :--- | :--- | :--- |
| `-l, --lang <code>` | Language code (e.g., `fra`, `eng`) | `eng` |
| `-o, --output <path>` | Custom output file path | `input_ocr.pdf` |
| `-d, --dpi <num>` | DPI resolution for OCR | `300` |
| `-j, --jobs <num>` | Number of parallel jobs | Auto-detect |
| `-t, --text` | Generate an additional .txt file | `false` |
| `-m, --markdown` | Generate an additional .md file (layout-preserved plain text) | `false` |
| `-p, --preserve` | Keep the original pages, add an invisible text layer on top (needs `qpdf`) | `false` |
| `-k, --keep` | Keep temporary files (debug) | `false` |
| `-v, --verbose` | Verbose output | `false` |
| `-h, --help` | Show help message | - |

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

By default `copyable-pdf` rebuilds the document: every page is rendered to a
300 DPI image, recognised, and the images are merged into a new PDF. That works
anywhere, but the result is a re-encoded copy — a scan stored as JBIG2 or CCITT
can grow several times over, and vector text, bookmarks and metadata are gone.

`--preserve` takes the other route. Pages are still rendered and recognised, but
only the recognised text is kept, as an invisible layer that is stamped onto the
untouched original with `qpdf`. Images, vectors, bookmarks, metadata and file
size stay as they were, and the text is selectable on top.

It needs one extra tool, and only when the flag is used:

```bash
brew install qpdf          # macOS
sudo apt-get install qpdf  # Ubuntu/Debian
```

Use it for anything you care about keeping. Use the default when you have no
`qpdf` and a plain searchable copy is enough.

## License

MIT

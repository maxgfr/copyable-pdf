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
brew tap maxgfr/homebrew-tap
brew install copyable-pdf
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

## License

MIT
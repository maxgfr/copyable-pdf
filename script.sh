#!/bin/bash

# ==============================================================================
#  copyable-pdf
#  Converts PDF to Images -> OCRs Images -> Merges back to Searchable PDF
# ==============================================================================

set -e

# --- Configuration & Defaults ---
VERSION="1.0.0"
DEFAULT_DPI=300
DEFAULT_LANG="eng"
KEEP_TEMP=false
VERBOSE=false
COLOR_SUPPORT=true

# --- Colors ---
if [ -t 1 ] && [ "$COLOR_SUPPORT" = true ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    YELLOW='\033[1;33m'
    BOLD='\033[1m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    BLUE=''
    YELLOW=''
    BOLD=''
    NC=''
fi

# --- Helper Functions ---

log_info() {
    printf "${BLUE}[INFO]${NC} %s\n" "$1"
}

log_success() {
    printf "${GREEN}[OK]${NC} %s\n" "$1"
}

log_warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1" >&2
}

log_error() {
    printf "${RED}[ERROR]${NC} %s\n" "$1" >&2
}

print_banner() {
    echo -e "${BLUE}"
    echo "  ██████╗ ██████╗ ██████╗ ██╗   ██╗ █████╗ ██████╗ ██╗     ███████╗      ██████╗ ██████╗ ███████╗"
    echo " ██╔════╝██╔═══██╗██╔══██╗╚██╗ ██╔╝██╔══██╗██╔══██╗██║     ██╔════╝      ██╔══██╗██╔══██╗██╔════╝"
    echo " ██║     ██║   ██║██████╔╝ ╚████╔╝ ███████║██████╔╝██║     █████╗  █████╗██████╔╝██║  ██║█████╗  "
    echo " ██║     ██║   ██║██╔═══╝   ╚██╔╝  ██╔══██║██╔══██╗██║     ██╔══╝  ╚════╝██╔═══╝ ██║  ██║██╔══╝  "
    echo " ╚██████╗╚██████╔╝██║        ██║   ██║  ██║██████╔╝███████╗███████╗      ██║     ██████╔╝██║     "
    echo "  ╚═════╝ ╚═════╝ ╚═╝        ╚═╝   ╚═╝  ╚═╝╚═════╝ ╚══════╝╚══════╝      ╚═╝     ╚═════╝ ╚═╝     "
    echo -e "${NC}"
    echo -e "                           Convert PDFs to searchable OCR documents v$VERSION"
    echo ""
}

print_usage() {
    echo "Usage: copyable-pdf [options] [input_file]"
    echo ""
    echo "Arguments:"
    echo "  input_file           Path to the input PDF file (optional in interactive mode)"
    echo ""
    echo "Options:"
    echo "  -l, --lang <code>    Language code (default: eng)"
    echo "  -o, --output <path>  Custom output file path"
    echo "  -d, --dpi <num>      DPI resolution for OCR (default: 300)"
    echo "  -j, --jobs <num>     Number of parallel jobs (default: auto)"
    echo "  -k, --keep           Keep temporary files (debug mode)"
    echo "  -v, --verbose        Verbose output"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./script.sh document.pdf"
    echo "  ./script.sh -l fra -d 600 document.pdf"
    echo "  ./script.sh --jobs 8 -k document.pdf"
}

ask_yes_no() {
    local prompt="$1"
    # Print prompt to stderr to avoid capturing it if used in subshells (though strictly we use read -p for interactive)
    # Using printf >&2 to be safe
    printf "\n%b%s [y/N]: %b" "$BOLD" "$prompt" "$NC" >&2
    read -r answer
    [[ "$answer" == "y" || "$answer" == "Y" ]]
}

prompt_input() {
    local prompt_text="$1"
    local default_val="$2"
    local user_val
    
    if [ -n "$default_val" ]; then
        printf "%b%s [%s]: %b" "$BOLD" "$prompt_text" "$default_val" "$NC" >&2
    else
        printf "%b%s: %b" "$BOLD" "$prompt_text" "$NC" >&2
    fi
    
    read -r user_val
    if [ -z "$user_val" ]; then
        echo "$default_val"
    else
        echo "$user_val"
    fi
}

detect_pkg_manager() {
    if command -v brew >/dev/null 2>&1; then echo "brew"; return; fi
    if command -v apt-get >/dev/null 2>&1; then echo "apt"; return; fi
    if command -v dnf >/dev/null 2>&1; then echo "dnf"; return; fi
    if command -v yum >/dev/null 2>&1; then echo "yum"; return; fi
}

install_package() {
    local manager="$1"
    local pkg="$2"
    log_info "Installing $pkg via $manager..."
    
    case "$manager" in
        brew) brew install "$pkg" ;;
        apt) sudo apt-get update && sudo apt-get install -y "$pkg" ;;
        dnf) sudo dnf install -y "$pkg" ;;
        yum) sudo yum install -y "$pkg" ;;
        *) return 1 ;;
    esac
}

require_command() {
    local cmd="$1"
    local pkg="$2"
    
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_warn "Missing dependency: $cmd"
        local manager=$(detect_pkg_manager)
        if [ -n "$manager" ]; then
            if ask_yes_no "Install '$pkg' using $manager?"; then
                install_package "$manager" "$pkg" || true
            fi
        else
            log_error "No package manager found. Install '$pkg' manually."
        fi
        
        # Check again
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "Command '$cmd' still not found. Exiting."
            exit 1
        fi
    fi
}

require_language() {
    local lang="$1"
    if ! tesseract --list-langs 2>/dev/null | grep -qx "$lang"; then
        log_warn "Missing Tesseract language data: $lang"
        local manager=$(detect_pkg_manager)
        if [ -n "$manager" ]; then
             if ask_yes_no "Install language pack for '$lang'?"; then
                case "$manager" in
                    brew) install_package "$manager" "tesseract-lang" || true ;;
                    apt) install_package "$manager" "tesseract-ocr-${lang}" || true ;;
                    dnf|yum) install_package "$manager" "tesseract-langpack-${lang}" || true ;;
                esac
             fi
        fi
        
        if ! tesseract --list-langs 2>/dev/null | grep -qx "$lang"; then
            log_error "Language '$lang' still not installed. Exiting."
            exit 1
        fi
    fi
}

# --- Main Logic ---

# 1. Parse Arguments (Manual Parsing)
INPUT_FILE=""
OUTPUT_FILE=""
DPI="$DEFAULT_DPI"
LANG="$DEFAULT_LANG"
JOBS=""

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -l|--lang)
            LANG="$2"
            shift; shift
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift; shift
            ;;
        -d|--dpi)
            DPI="$2"
            shift; shift
            ;;
        -j|--jobs)
            JOBS="$2"
            shift; shift
            ;;
        -k|--keep)
            KEEP_TEMP=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            print_banner
            print_usage
            exit 0
            ;;
        *)
            if [ -z "$INPUT_FILE" ]; then
                INPUT_FILE="$1"
                shift
            else
                log_error "Unknown argument: $1"
                print_usage
                exit 1
            fi
            ;;
    esac
done

# 2. Interactive Mode (if no input file)
if [ -z "$INPUT_FILE" ]; then
    print_banner
    log_info "Interactive Mode"
    
    while [ -z "$INPUT_FILE" ]; do
        INPUT_FILE=$(prompt_input "Enter PDF path" "")
        if [ ! -f "$INPUT_FILE" ]; then
            log_error "File not found: $INPUT_FILE"
            INPUT_FILE=""
        fi
    done
    
    LANG=$(prompt_input "Language code" "$DEFAULT_LANG")
    DPI=$(prompt_input "DPI Resolution" "$DEFAULT_DPI")
    
    # Optional Output
    local default_out
    default_out="$(basename "$INPUT_FILE" .pdf)_ocr.pdf"
    OUTPUT_FILE=$(prompt_input "Output file" "$default_out")
fi

# 3. Validation & Defaults
if [ ! -f "$INPUT_FILE" ]; then
    log_error "Input file '$INPUT_FILE' does not exist."
    exit 1
fi

if [ -z "$OUTPUT_FILE" ]; then
    OUTPUT_FILE="$(basename "$INPUT_FILE" .pdf)_ocr.pdf"
fi

# Auto-detect cores if not set
if [ -z "$JOBS" ]; then
    if command -v nproc >/dev/null 2>&1; then
        JOBS=$(nproc)
    elif command -v sysctl >/dev/null 2>&1; then
        JOBS=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
    else
        JOBS=4
    fi
fi

if [ "$VERBOSE" = true ]; then
    echo ""
    echo "Configuration:"
    echo "  Input:  $INPUT_FILE"
    echo "  Output: $OUTPUT_FILE"
    echo "  Lang:   $LANG"
    echo "  DPI:    $DPI"
    echo "  Jobs:   $JOBS"
    echo "  Keep:   $KEEP_TEMP"
    echo ""
fi

# 4. Dependency Checks
log_info "Checking dependencies..."
require_command tesseract tesseract
require_command pdftoppm poppler
require_language "$LANG"

# Check PDF merge tool (pdfunite is part of poppler, which is already required)
MERGE_TOOL="pdfunite"
if ! command -v pdfunite >/dev/null 2>&1; then
    log_error "Command 'pdfunite' not found, but it should be part of 'poppler'."
    log_error "Please ensure 'poppler' is installed correctly."
    exit 1
fi

# 5. Execution

TEMP_DIR=$(mktemp -d)
if [ "$KEEP_TEMP" = false ]; then
    trap 'rm -rf "$TEMP_DIR"' EXIT
else
    log_info "Temporary files will be kept at: $TEMP_DIR"
fi

log_info "Step 1/3: Converting PDF to images ($DPI DPI) using $JOBS parallel jobs..."
# Note: pdftoppm itself isn't parallel per page easily without splitting PDF first.
# We will just run it once. It's usually fast enough.
pdftoppm "$INPUT_FILE" "$TEMP_DIR/page" -png -r "$DPI"

# Count pages
PAGE_COUNT=$(ls -1 "$TEMP_DIR"/page-*.png 2>/dev/null | wc -l | tr -d ' ')
if [ "$PAGE_COUNT" -eq 0 ]; then
    log_error "No images generated."
    exit 1
fi
log_success "Generated $PAGE_COUNT pages."

log_info "Step 2/3: OCR Processing ($LANG)..."

# Export vars for xargs
export LANG_CODE="$LANG"
export VERBOSE

process_page_worker() {
    local img="$1"
    local base="${img%.*}" # remove extension
    
    if [ "$VERBOSE" = true ]; then
        echo "  Processing $(basename "$img")..."
    fi
    
    # tesseract input output -l lang pdf q
    tesseract "$img" "$base" -l "$LANG_CODE" pdf >/dev/null 2>&1
}
export -f process_page_worker

# Find all pngs and feed to xargs
# Using -print0 for safety with filenames, though ours are simple page-N.png
find "$TEMP_DIR" -name "page-*.png" -print0 | xargs -0 -P "$JOBS" -I {} bash -c 'process_page_worker "$@"' _ {}

log_success "OCR Complete."

log_info "Step 3/3: Merging PDF..."

# Gather PDF chunks in CORRECT order
# pdftoppm specific naming: page-1.png, page-2.png ... page-10.png
# We simply loop sequence 1..PAGE_COUNT to guarantee order.

ORDERED_PDFS=""
for i in $(seq 1 "$PAGE_COUNT"); do
    p="$TEMP_DIR/page-$i.pdf"
    if [ -f "$p" ]; then
        ORDERED_PDFS="$ORDERED_PDFS $p"
    else
        log_warn "Page $i missing."
    fi
done

if [ -z "$ORDERED_PDFS" ]; then
    log_error "No PDF pages to merge."
    exit 1
fi

pdfunite $ORDERED_PDFS "$OUTPUT_FILE"

echo ""
log_success "Done! Output saved to:"
echo -e "${BOLD}$OUTPUT_FILE${NC}"
echo ""


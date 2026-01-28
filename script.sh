#!/bin/bash

# ==============================================================================
#  copyable-pdf
#  Converts PDF to Images -> OCRs Images -> Merges back to Searchable PDF
# ==============================================================================

set -e

# --- Configuration & Defaults ---
VERSION="1.2.0"
DEFAULT_DPI=300
DEFAULT_LANG="eng"
KEEP_TEMP=false
VERBOSE=false
COLOR_SUPPORT=true
GEN_TEXT=false
GEN_MD=false

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

draw_progress_bar() {
    local current="$1"
    local total="$2"
    local width=40
    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    # \r goes to start of line, clear line
    printf "\r["
    if [ $filled -gt 0 ]; then printf "%0.s#" $(seq 1 $filled); fi
    if [ $empty -gt 0 ]; then printf "%0.s-" $(seq 1 $empty); fi
    printf "] %d%% (%d/%d)" "$percent" "$current" "$total"
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
    echo "  input_file           Path to the input PDF file"
    echo ""
    echo "Options:"
    echo "  -l, --lang <code>    Language code(s) (e.g., 'eng', 'fra', 'eng+fra') (default: eng)"
    echo "  -o, --output <path>  Custom output file path"
    echo "  -d, --dpi <num>      DPI resolution for OCR (default: 300)"
    echo "  -j, --jobs <num>     Number of parallel jobs (default: auto)"
    echo "  -t, --text           Generate an additional .txt file"
    echo "  -m, --markdown       Generate an additional .md file"
    echo "  -k, --keep           Keep temporary files (debug mode)"
    echo "  -v, --verbose        Verbose output"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  copyable-pdf document.pdf"
    echo "  copyable-pdf -l fra+eng -t document.pdf"
    echo "  copyable-pdf --jobs 8 -k document.pdf"
}

ask_yes_no() {
    local prompt="$1"
    # Print prompt to stderr to avoid capturing it if used in subshells
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
    local langs_arg="$1"
    # Split by '+'
    local IFS='+'
    read -ra LANGS <<< "$langs_arg"
    
    for lang in "${LANGS[@]}"; do
        if ! tesseract --list-langs 2>/dev/null | grep -qx "$lang"; then
            log_warn "Missing Tesseract language data for: $lang"
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
    done
}

# --- Main Logic ---

# 1. Parse Arguments
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
        -t|--text)
            GEN_TEXT=true
            shift
            ;;
        -m|--markdown)
            GEN_MD=true
            shift
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
    
    LANG=$(prompt_input "Language code(s) (e.g. eng or fra+eng)" "$DEFAULT_LANG")
    DPI=$(prompt_input "DPI Resolution" "$DEFAULT_DPI")
    
    if ask_yes_no "Generate text file (.txt)?"; then GEN_TEXT=true; fi
    if ask_yes_no "Generate markdown file (.md)?"; then GEN_MD=true; fi
    
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
    echo "  Input:     $INPUT_FILE"
    echo "  Output:    $OUTPUT_FILE"
    echo "  Lang:      $LANG"
    echo "  DPI:       $DPI"
    echo "  Jobs:      $JOBS"
    echo "  Text:      $GEN_TEXT"
    echo "  Markdown:  $GEN_MD"
    echo ""
fi

# 4. Dependency Checks
log_info "Checking dependencies..."
require_command tesseract tesseract
require_command pdftoppm poppler
require_command pdftotext poppler
require_language "$LANG"

# Check PDF merge tool
MERGE_TOOL="pdfunite"
if ! command -v pdfunite >/dev/null 2>&1; then
    log_error "Command 'pdfunite' not found (should be part of 'poppler')."
    exit 1
fi

# 5. Execution

TEMP_DIR=$(mktemp -d)
if [ "$KEEP_TEMP" = false ]; then
    trap 'rm -rf "$TEMP_DIR"' EXIT
else
    log_info "Temporary files will be kept at: $TEMP_DIR"
fi

log_info "Step 1/3: Converting PDF to images ($DPI DPI)..."
pdftoppm "$INPUT_FILE" "$TEMP_DIR/page" -png -r "$DPI"

# List all generated page images
PAGE_IMAGES=("$TEMP_DIR"/page-*.png)
if [ ! -f "${PAGE_IMAGES[0]}" ]; then
    log_error "No images generated."
    exit 1
fi
PAGE_COUNT=${#PAGE_IMAGES[@]}
log_success "Generated $PAGE_COUNT pages."

log_info "Step 2/3: OCR Processing ($LANG) with $JOBS jobs..."

# Export vars for xargs
export LANG_CODE="$LANG"
export VERBOSE

process_page_worker() {
    local img="$1"
    local base="${img%.*}" # remove extension
    
    if [ "$VERBOSE" = true ]; then
        echo "Processing $(basename "$img")..." >&2
    fi
    
    # tesseract input output -l lang pdf quiet
    tesseract "$img" "$base" -l "$LANG_CODE" pdf >/dev/null 2>&1
    
    # Signal completion similar to progress
    echo "DONE"
}
export -f process_page_worker

# Run parallel OCR and update progress bar
counter=0
# We pipe the output of xargs (which prints DONE lines) to our loop
# Note: stdbuf -oL ensures output isn't buffered so progress updates smoothly
find "$TEMP_DIR" -name "page-*.png" -print0 | \
    xargs -0 -P "$JOBS" -I {} bash -c 'process_page_worker "$@"' _ {} | \
    while read -r line; do
        if [ "$line" == "DONE" ]; then
            counter=$((counter + 1))
            if [ "$VERBOSE" = false ]; then
                draw_progress_bar "$counter" "$PAGE_COUNT"
            fi
        fi
    done

echo "" # Newline after progress bar
log_success "OCR Complete."

log_info "Step 3/3: Merging PDF & Finalizing..."

# Handle merging in chunks to avoid "Too many open files" error
PAGE_LIST=()
# We use a pattern that matches the files generated by Tesseract
# Note: sort -V is used for natural sorting (page-1, page-2, ..., page-10)
for p in $(ls -1 "$TEMP_DIR"/page-*.pdf 2>/dev/null | sort -V); do
    PAGE_LIST+=("$p")
done

PAGE_COUNT_PDF=${#PAGE_LIST[@]}

if [ "$PAGE_COUNT_PDF" -eq 0 ]; then
    log_warn "No PDF pages to merge."
    exit 1
fi

if [ "$PAGE_COUNT_PDF" -le 100 ]; then
    pdfunite "${PAGE_LIST[@]}" "$OUTPUT_FILE"
else
    log_info "Merging $PAGE_COUNT_PDF pages in chunks"
    CHUNK_SIZE=100
    CHUNKS=()
    for ((i=0; i<PAGE_COUNT_PDF; i+=CHUNK_SIZE)); do
        # Extract a slice of the array
        CHUNK_SLICE=("${PAGE_LIST[@]:i:CHUNK_SIZE}")
        CHUNK_FILE="$TEMP_DIR/chunk-$((i/CHUNK_SIZE)).pdf"
        
        if [ "$VERBOSE" = true ]; then
            log_info "  Creating chunk $((i/CHUNK_SIZE + 1))..."
        fi
        
        pdfunite "${CHUNK_SLICE[@]}" "$CHUNK_FILE"
        CHUNKS+=("$CHUNK_FILE")
    done
    
    log_info "Final merge of ${#CHUNKS[@]} chunks..."
    pdfunite "${CHUNKS[@]}" "$OUTPUT_FILE"
fi

log_success "Original PDF merged to: $OUTPUT_FILE"

# Post-processing opts
if [ "$GEN_TEXT" = true ]; then
    TXT_FILE="${OUTPUT_FILE%.*}.txt"
    log_info "Generating text file..."
    pdftotext "$OUTPUT_FILE" "$TXT_FILE"
    log_success "Text saved to: $TXT_FILE"
fi

if [ "$GEN_MD" = true ]; then
    MD_FILE="${OUTPUT_FILE%.*}.md"
    log_info "Generating markdown file..."
    # -layout maintains physical layout which is closer to what we want in MD than raw stream
    pdftotext -layout "$OUTPUT_FILE" "$MD_FILE"
    log_success "Markdown saved to: $MD_FILE"
fi

echo ""
echo -e "${BOLD}Done!${NC}"
echo ""


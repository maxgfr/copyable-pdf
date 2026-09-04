#!/bin/bash

# ==============================================================================
#  copyable-pdf
#  Converts PDF to Images -> OCRs Images -> Merges back to Searchable PDF
# ==============================================================================

set -eo pipefail

# --- Configuration & Defaults ---
VERSION="1.2.3"
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

# A redrawn bar is meaningless once stdout is a file: piping a run to a log or
# to CI used to bury the output under hundreds of \r-joined bar frames on one
# unreadable line. Off a terminal, report a plain line now and then instead.
report_progress() {
    local current="$1"
    local total="$2"

    if [ -t 1 ]; then
        draw_progress_bar "$current" "$total"
    elif [ $((current % 10)) -eq 0 ] || [ "$current" -eq "$total" ]; then
        log_info "page $current/$total"
    fi
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
    echo "  -m, --markdown       Generate an additional .md file (layout-preserved plain text)"
    echo "  -k, --keep           Keep temporary files (debug mode)"
    echo "  -v, --verbose        Verbose output"
    echo "  -h, --help           Show this help message"
    echo "  -V, --version        Print the version and exit"
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
        local manager
        manager=$(detect_pkg_manager)
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
            local manager
            manager=$(detect_pkg_manager)
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

# Fail with a usable message when an option that takes a value was given none.
# Without this, `shift; shift` on a missing operand aborts under `set -e` and the
# user gets a bare exit code and no output at all.
#
# Takes the option name and how many argv entries are LEFT (including the option
# itself). Counting is the only reliable test: passing "$2" through would arrive
# as an empty string whether the value was absent or genuinely empty, so the
# callee could never tell the two apart.
require_value() {
    if [ "$2" -lt 2 ]; then
        log_error "Option '$1' requires a value."
        print_usage
        exit 2
    fi
}

# 1. Parse Arguments
INPUT_FILE=""
OUTPUT_FILE=""
DPI="$DEFAULT_DPI"
# NOT `LANG`: that is the POSIX locale variable, and it is already exported in
# almost every shell, so assigning a tesseract code to it ships an invalid locale
# ("fra+eng") to every child process — pdftoppm, pdftotext, sort, tesseract
# itself. Keep the OCR language in a name of our own.
OCR_LANG="$DEFAULT_LANG"
JOBS=""

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -l|--lang)
            require_value "$key" "$#"
            OCR_LANG="$2"
            shift; shift
            ;;
        -o|--output)
            require_value "$key" "$#"
            OUTPUT_FILE="$2"
            shift; shift
            ;;
        -d|--dpi)
            require_value "$key" "$#"
            DPI="$2"
            shift; shift
            ;;
        -j|--jobs)
            require_value "$key" "$#"
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
        -V|--version)
            echo "copyable-pdf $VERSION"
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
    
    OCR_LANG=$(prompt_input "Language code(s) (e.g. eng or fra+eng)" "$DEFAULT_LANG")
    DPI=$(prompt_input "DPI Resolution" "$DEFAULT_DPI")

    if ask_yes_no "Generate text file (.txt)?"; then GEN_TEXT=true; fi
    if ask_yes_no "Generate .md file (layout-preserved plain text)?"; then GEN_MD=true; fi

    # Optional Output. NOT `local` — this block runs at script scope, not inside
    # a function, where bash rejects `local` outright ("can only be used in a
    # function"). Under `set -e` that aborted the whole run, which is why
    # interactive mode never reached a conversion.
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

# Everything below is checked BEFORE any OCR runs. Each of these used to surface
# only at the very end — after minutes of rasterising and recognising every page
# — as a raw poppler "I/O Error" or a pdftoppm usage dump.
# A directory as the output path used to sail through validation — `dirname
# outdir/` is `.`, which exists and is writable — and only surfaced after the
# whole document had been OCR'd, as poppler's `I/O Error: Could not open file`.
case "$OUTPUT_FILE" in
    */) log_error "Output path is a directory: $OUTPUT_FILE"; exit 2 ;;
esac
if [ -d "$OUTPUT_FILE" ]; then
    log_error "Output path is a directory: $OUTPUT_FILE"
    exit 2
fi

# Writing the OCR result over its own source destroys the original: the input
# has already been rasterised into the temp directory by then, so there is
# nothing left to recover from.
if [ -e "$OUTPUT_FILE" ] && [ "$INPUT_FILE" -ef "$OUTPUT_FILE" ]; then
    log_error "Output would overwrite the input: $OUTPUT_FILE"
    exit 2
fi

OUT_DIR="$(dirname "$OUTPUT_FILE")"
if [ ! -d "$OUT_DIR" ]; then
    log_error "Output directory does not exist: $OUT_DIR"
    exit 2
fi
if [ ! -w "$OUT_DIR" ]; then
    log_error "Output directory is not writable: $OUT_DIR"
    exit 2
fi

case "$DPI" in
    ''|*[!0-9]*) log_error "DPI must be a positive integer (got '$DPI')."; exit 2 ;;
    0) log_error "DPI must be greater than 0."; exit 2 ;;
esac

if [ -n "$JOBS" ]; then
    case "$JOBS" in
        ''|*[!0-9]*) log_error "Jobs must be a positive integer (got '$JOBS')."; exit 2 ;;
        0) log_error "Jobs must be greater than 0."; exit 2 ;;
    esac
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
    echo "  Lang:      $OCR_LANG"
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
require_language "$OCR_LANG"

# Check PDF merge tool
if ! command -v pdfunite >/dev/null 2>&1; then
    log_error "Command 'pdfunite' not found (should be part of 'poppler')."
    exit 1
fi
require_command pdfinfo poppler

# Only now can the input be checked: pdfinfo ships with poppler, so this has to
# come after the dependency checks. A corrupt or password-protected PDF used to
# get as far as pdftoppm and come back as a raw poppler error with a temp
# directory already created.
if ! PDF_INFO="$(pdfinfo "$INPUT_FILE" 2>&1)"; then
    log_error "'$INPUT_FILE' is not a readable PDF (corrupt or encrypted)."
    log_error "  $(echo "$PDF_INFO" | tail -n 1)"
    exit 2
fi
PDF_PAGES="$(echo "$PDF_INFO" | awk '/^Pages:/{print $2; exit}')"
case "$PDF_PAGES" in
    ''|*[!0-9]*) PDF_PAGES="" ;;
esac
if [ -n "$PDF_PAGES" ]; then
    log_info "Input has $PDF_PAGES page(s)."
fi

# A PDF that already has real text is about to have it thrown away: every page
# is rasterised to PNG and re-recognised, so reliable embedded text is replaced
# by OCR guesses and a small vector file balloons. Re-OCR is a legitimate thing
# to want, so this warns rather than refuses.
if command -v pdffonts >/dev/null 2>&1; then
    FONT_COUNT="$(pdffonts "$INPUT_FILE" 2>/dev/null | tail -n +3 | grep -c . || true)"
    if [ "${FONT_COUNT:-0}" -gt 0 ]; then
        log_warn "Input already has a text layer ($FONT_COUNT font(s)); OCR will replace it."
    fi
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
if [ -n "$PDF_PAGES" ] && [ "$PAGE_COUNT" -ne "$PDF_PAGES" ]; then
    log_error "Rasterised $PAGE_COUNT page(s) but the PDF has $PDF_PAGES; refusing to continue."
    exit 1
fi
log_success "Generated $PAGE_COUNT pages."

log_info "Step 2/3: OCR Processing ($OCR_LANG) with $JOBS jobs..."

# Export vars for xargs
export LANG_CODE="$OCR_LANG"
export VERBOSE

process_page_worker() {
    local img="$1"
    local base="${img%.*}" # remove extension
    local name
    name="$(basename "$img")"
    
    if [ "$VERBOSE" = true ]; then
        echo "Processing $name..." >&2
    fi
    
    # tesseract input output -l lang pdf. Its exit status decides what we report:
    # ignoring it (as this used to) meant a page whose OCR crashed produced no
    # page-N.pdf, the merge silently carried on with whatever was left, and the
    # run exited 0 with a PDF missing pages and no warning anywhere.
    if ! tesseract "$img" "$base" -l "$LANG_CODE" pdf >/dev/null 2>"$base.err"; then
        echo "FAIL $name"
        return 1
    fi
    rm -f "$base.err"
    
    # Signal completion similar to progress
    echo "DONE"
}
export -f process_page_worker

# Run parallel OCR and update progress bar
counter=0
# We pipe the output of xargs (which prints DONE lines) to our loop.
# `|| true` on the pipeline: a worker that fails makes xargs exit 123, and under
# `pipefail` that would abort the script right here — before the counting check
# below could name the pages that failed. Let the check decide, so the user gets
# a readable error instead of a bare exit code.
find "$TEMP_DIR" -name "page-*.png" -print0 | \
    xargs -0 -P "$JOBS" -I {} bash -c 'process_page_worker "$@"' _ {} | \
    while read -r line; do
        case "$line" in
            DONE)
                counter=$((counter + 1))
                if [ "$VERBOSE" = false ]; then
                    report_progress "$counter" "$PAGE_COUNT"
                fi
                ;;
            "FAIL "*)
                log_error "OCR failed on ${line#FAIL }"
                ;;
        esac
    done || true

# Close the progress bar's line — but only if one was actually drawn.
if [ -t 1 ] && [ "$VERBOSE" = false ]; then
    echo ""
fi

log_info "Step 3/3: Merging PDF & Finalizing..."

# Handle merging in chunks to avoid "Too many open files" error
# Glob rather than parse `ls`: the old `for p in $(ls -1 ...)` word-split on
# spaces, so a TMPDIR containing one (mktemp honours TMPDIR on Linux) turned
# every page path into two non-existent ones and the merge failed.
#
# No `sort -V` needed: pdftoppm zero-pads each page number to the width of the
# LAST page, so within one run the glob is already in page order.
shopt -s nullglob
PAGE_LIST=("$TEMP_DIR"/page-*.pdf)
ERR_LIST=("$TEMP_DIR"/page-*.err)
shopt -u nullglob

PAGE_COUNT_PDF=${#PAGE_LIST[@]}

# One OCR result per page, or nothing at all. Merging only what survived hands
# back a PDF quietly missing pages, with exit 0 — the worst possible outcome for
# a tool people point at documents whose paper originals they are about to bin.
if [ "$PAGE_COUNT_PDF" -ne "$PAGE_COUNT" ]; then
    log_error "OCR produced $PAGE_COUNT_PDF page(s) out of $PAGE_COUNT; refusing to write a PDF with pages missing."
    for err in "${ERR_LIST[@]}"; do
        err_base="$(basename "$err" .err)"
        log_error "  $err_base.png: $(tr '\n' ' ' < "$err" | cut -c1-200)"
    done
    exit 1
fi

log_success "OCR Complete."

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
# The sidecar stem, derived from the basename ONLY. `${OUTPUT_FILE%.*}` strips at
# the last dot anywhere in the path, so `-o out/v1.2/report` used to drop
# `out/v1.txt` beside the directory instead of inside it — silently, exit 0.
OUT_BASE="$(basename "$OUTPUT_FILE")"
OUT_STEM="$OUT_DIR/${OUT_BASE%.*}"

if [ "$GEN_TEXT" = true ]; then
    TXT_FILE="$OUT_STEM.txt"
    log_info "Generating text file..."
    pdftotext "$OUTPUT_FILE" "$TXT_FILE"
    log_success "Text saved to: $TXT_FILE"
fi

if [ "$GEN_MD" = true ]; then
    MD_FILE="$OUT_STEM.md"
    log_info "Generating .md file (layout-preserved plain text)..."
    # Not markdown: `pdftotext -layout` keeps the physical layout with spaces,
    # it does not emit headings, lists or emphasis. The extension is a
    # convenience for editors, and the help text now says so.
    pdftotext -layout "$OUTPUT_FILE" "$MD_FILE"
    log_success "Markdown saved to: $MD_FILE"
fi

echo ""
echo -e "${BOLD}Done!${NC}"
echo ""


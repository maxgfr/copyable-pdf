#!/bin/bash

# ==============================================================================
#  copyable-pdf
#  Converts PDF to Images -> OCRs Images -> Merges back to Searchable PDF
# ==============================================================================

set -eo pipefail

# --- Configuration & Defaults ---
VERSION="2.0.0"
DEFAULT_DPI=300
DEFAULT_LANG="eng"
KEEP_TEMP=false
VERBOSE=false
COLOR_SUPPORT=true
GEN_TEXT=false
GEN_MD=false
PRESERVE=false
CLEAN=false
PLAIN=false
TESSDATA_DIR=""
# The default engine: PaddleOCR's PP-OCRv6 models, run by RapidOCR on ONNX
# Runtime. --tesseract switches to Tesseract.
PADDLE=true
PADDLE_MODEL="small"
NO_SAVE=false
INSTALL_ONLY=false
# Pinned: the helper below relies on this RapidOCR's results and model names,
# and a pin change is what makes an installed engine get rebuilt.
PADDLE_PACKAGES=(rapidocr==3.10.0 onnxruntime==1.31.0)
# Where the engine lives between runs. The Homebrew formula points this inside
# its own prefix (COPYABLE_PDF_HOME), where `brew install` has already put it.
PADDLE_SAVED_HOME="${COPYABLE_PDF_HOME:-${XDG_CACHE_HOME:-$HOME/.cache}/copyable-pdf}/ocr-engine"

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

# A spinner for the steps that give no progress of their own: installing
# PaddleOCR, loading its models, cleaning pages. Off a terminal, one log line.
#
# It is never killed. It used to be, and the first progress line stops it from
# inside the pipeline's subshell, which is not its parent: bash then reaped a
# job that died of SIGTERM and printed "Terminated: 15" plus the spinner's
# whole source over the progress bar. Instead, stopping creates a file; the
# spinner clears its own line, answers with a second file, and exits 0.
SPINNER_PID=""
SPINNER_FLAG=""
spinner_start() {
    local msg="$1"
    if [ ! -t 1 ]; then
        log_info "$msg..."
        return
    fi
    SPINNER_FLAG="$TEMP_DIR/.spinner-$RANDOM"
    (
        local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
        local i=0 start=$SECONDS
        while [ ! -e "$SPINNER_FLAG.stop" ]; do
            printf "\r${BLUE}%s${NC} %s (%ds)" "${frames[i % ${#frames[@]}]}" "$msg" "$((SECONDS - start))"
            i=$((i + 1))
            sleep 0.1
        done
        printf "\r\033[K"
        : > "$SPINNER_FLAG.done"
    ) &
    SPINNER_PID=$!
}

# Safe to call from anywhere, any number of times. Returns once the spinner's
# line is cleared, so whatever prints next starts on a clean line.
spinner_stop() {
    if [ -z "$SPINNER_PID" ]; then
        return 0
    fi
    if [ ! -e "$SPINNER_FLAG.done" ]; then
        : > "$SPINNER_FLAG.stop"
        local n=0
        while [ ! -e "$SPINNER_FLAG.done" ] && [ "$n" -lt 50 ]; do
            sleep 0.02
            n=$((n + 1))
        done
    fi
    # Only the main shell is the spinner's parent, so only it can reap it.
    if [ "$BASHPID" = "$$" ]; then
        wait "$SPINNER_PID" 2>/dev/null || true
        rm -f "$SPINNER_FLAG.stop" "$SPINNER_FLAG.done"
    fi
    SPINNER_PID=""
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
    echo "  -p, --preserve       Keep the original pages and add an invisible text"
    echo "                       layer on top (needs qpdf) instead of rebuilding"
    echo "                       the PDF from rasterised images"
    echo "  -c, --clean          Straighten pages and flatten shadows before OCR"
    echo "                       (needs ImageMagick). The output shows the"
    echo "                       cleaned pages. Not with --preserve"
    echo "      --model <tiny|small|medium>"
    echo "                       OCR model size: faster or more accurate (default: small)"
    echo "      --no-save        Install the OCR engine for this run only, in the"
    echo "                       temp dir, and delete it afterwards"
    echo "      --install-engine Install the OCR engine and its models, then exit"
    echo "                       (Homebrew does this at install time)"
    echo "      --tesseract      Recognise with Tesseract instead of the default"
    echo "                       engine (PaddleOCR's models): lighter, much weaker"
    echo "                       on photos and poor scans"
    echo "      --plain          With --tesseract: skip automatic rotation and"
    echo "                       adaptive thresholding (the pre-1.4 behaviour)"
    echo "      --tessdata-dir <path>"
    echo "                       With --tesseract: read language models from this"
    echo "                       directory (e.g. a tessdata_best checkout)"
    echo "  -k, --keep           Keep temporary files (debug mode)"
    echo "  -v, --verbose        Verbose output"
    echo "  -h, --help           Show this help message"
    echo "  -V, --version        Print the version and exit"
    echo ""
    echo "Examples:"
    echo "  copyable-pdf document.pdf"
    echo "  copyable-pdf -l fra+eng -t document.pdf"
    echo "  copyable-pdf --jobs 8 -k document.pdf"
    echo "  copyable-pdf --preserve scan.pdf"
    echo "  copyable-pdf -l spa -p -t photo-of-a-form.pdf"
    echo "  copyable-pdf --tesseract --clean -l fra scan.pdf"
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

# Is this traineddata available to tesseract? Honours --tessdata-dir, so the
# check looks where the OCR will actually look.
has_tess_lang() {
    local dir_opts=()
    if [ -n "$TESSDATA_DIR" ]; then
        dir_opts=(--tessdata-dir "$TESSDATA_DIR")
    fi
    tesseract "${dir_opts[@]}" --list-langs 2>/dev/null | grep -qx "$1"
}

require_language() {
    local langs_arg="$1"
    # Split by '+'
    local IFS='+'
    read -ra LANGS <<< "$langs_arg"

    for lang in "${LANGS[@]}"; do
        if ! has_tess_lang "$lang"; then
            # A package manager installs into the system tessdata, never into a
            # directory the user picked, so offering it there would install
            # something the run still cannot see.
            if [ -n "$TESSDATA_DIR" ]; then
                log_error "No '$lang.traineddata' in $TESSDATA_DIR."
                exit 1
            fi
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
            
            if ! has_tess_lang "$lang"; then
                log_error "Language '$lang' still not installed. Exiting."
                exit 1
            fi
        fi
    done
}

# Tesseract language code -> PaddleOCR's, or nothing when Paddle has no model.
paddle_lang_code() {
    case "$1" in
        eng) echo en ;;        fra) echo fr ;;        spa) echo es ;;
        deu) echo de ;;        ita) echo it ;;        por) echo pt ;;
        nld) echo nl ;;        pol) echo pl ;;        ces) echo cs ;;
        dan) echo da ;;        swe) echo sv ;;        nor) echo no ;;
        fin) echo "fi" ;;        ron) echo ro ;;        hun) echo hu ;;
        tur) echo tr ;;        cat) echo ca ;;        hrv) echo hr ;;
        slk) echo sk ;;        slv) echo sl ;;        lit) echo lt ;;
        lav) echo lv ;;        est) echo et ;;        ind) echo id ;;
        msa) echo ms ;;        vie) echo vi ;;        lat) echo la ;;
        gle) echo ga ;;        cym) echo cy ;;        afr) echo af ;;
        isl) echo is ;;        sqi) echo sq ;;        eus) echo eu ;;
        glg) echo gl ;;        mlt) echo mt ;;        bos) echo bs ;;
        aze) echo az ;;        uzb) echo uz ;;        swa) echo sw ;;
        tgl) echo tl ;;        oci) echo oc ;;        ltz) echo lb ;;
        chi_sim) echo ch ;;    chi_tra) echo chinese_cht ;;
        jpn) echo japan ;;     kor) echo korean ;;
        rus) echo ru ;;        ukr) echo uk ;;        bel) echo be ;;
        bul) echo bg ;;        mkd) echo mk ;;        srp) echo rs_cyrillic ;;
        kaz) echo kk ;;        mon) echo mn ;;
        ara) echo ar ;;        fas) echo fa ;;        urd) echo ur ;;
        hin) echo hi ;;        mar) echo mr ;;        nep) echo ne ;;
        tha) echo th ;;        ell) echo el ;;        tam) echo ta ;;
        tel) echo te ;;
    esac
}

# Install the OCR engine (or find it installed) and set PADDLE_PY and
# PADDLE_MODELS_DIR. Everything lives under one directory — the interpreter uv
# fetches, the packages, the models — so deleting it removes every trace. It is
# kept between runs; --no-save puts it in the run's temp dir instead.
setup_paddle() {
    local home where
    if [ "$NO_SAVE" = true ]; then
        home="$TEMP_DIR/ocr-engine"
        where="a temporary folder, deleted after the run"
    else
        home="$PADDLE_SAVED_HOME"
        where="$home"
    fi
    export UV_PYTHON_INSTALL_DIR="$home/python" UV_NO_CACHE=1 UV_NO_PROGRESS=1
    PADDLE_PY="$home/venv/bin/python"
    PADDLE_MODELS_DIR="$home/models"

    local marker
    marker="$home/venv/.copyable-pdf-$(echo "${PADDLE_PACKAGES[*]}" | tr ' =' '_-')"
    if [ -x "$PADDLE_PY" ] && [ -f "$marker" ]; then
        if [ "$VERBOSE" = true ]; then
            log_info "Using the OCR engine in $home"
        fi
        return
    fi

    rm -rf "$home/venv"
    mkdir -p "$home"
    # onnxruntime ships wheels for a handful of Python versions only, so ask uv
    # for 3.12 whatever the system Python is; uv downloads one if it has to.
    spinner_start "Installing the OCR engine into $where (~300 MB, one-off)"
    if ! { uv venv -q --python 3.12 "$home/venv" &&
           uv pip install -q --python "$PADDLE_PY" "${PADDLE_PACKAGES[@]}"; } \
            >"$TEMP_DIR/engine-install.log" 2>&1; then
        spinner_stop
        log_error "Could not install the OCR engine:"
        tail -n 5 "$TEMP_DIR/engine-install.log" | while read -r l; do log_error "  $l"; done
        rm -rf "$home/venv"
        exit 1
    fi
    touch "$marker"
    spinner_stop
    log_success "OCR engine installed in $where."
}

# The OCR side, written out at run time: copyable-pdf installs as a single
# file, so the helper travels inside it.
write_paddle_helper() {
    cat > "$1" <<'PADDLE_HELPER_EOF'
"""Recognise page images with PaddleOCR's models and write one PDF per page.

The models (PP-OCRv6, or PP-OCRv5 for scripts v6 does not read) run through
RapidOCR on ONNX Runtime: the same recognition as the PaddleOCR package, at a
fraction of its size and several times its speed on a CPU.

Each page-N.png becomes page-N.pdf, built the way tesseract builds its own:
the page image (unless --textonly) under an invisible text layer in a
glyphless CID font, so the rest of copyable-pdf merges and stamps the result
exactly as it does tesseract's. On stdout, one line per page: DONE, or
FAIL <name> with the reason in page-N.err. READY once the models are loaded.
Everything else goes to stderr, so stdout carries only that.
"""
import argparse
import contextlib
import math
import os
import sys
import zlib

# One multilingual PP-OCRv6 model reads all of these.
V6_LANGS = {
    "ch", "chinese_cht", "en", "japan", "af", "az", "bs", "ca", "cs", "cy",
    "da", "de", "es", "et", "eu", "fi", "fr", "ga", "gl", "hr", "hu", "id",
    "is", "it", "ku", "la", "lb", "lt", "lv", "mi", "ms", "mt", "nl", "no",
    "oc", "pl", "pt", "qu", "rm", "ro", "rs_latin", "sk", "sl", "sq", "sv",
    "sw", "tl", "tr", "uz", "vi",
}
# Everything else has one PP-OCRv5 model per script.
V5_SCRIPT = {
    "ru": "eslav", "uk": "eslav", "be": "eslav",
    "bg": "cyrillic", "mk": "cyrillic", "rs_cyrillic": "cyrillic",
    "kk": "cyrillic", "mn": "cyrillic",
    "ar": "arabic", "fa": "arabic", "ur": "arabic",
    "hi": "devanagari", "mr": "devanagari", "ne": "devanagari",
    "korean": "korean", "th": "th", "el": "el", "ta": "ta", "te": "te",
}


def load_ocr(langs, model, models_dir):
    from rapidocr import LangRec, ModelType, OCRVersion, RapidOCR

    params = {"Global.log_level": "error"}
    if models_dir:
        os.makedirs(models_dir, exist_ok=True)
        params["Global.model_root_dir"] = models_dir
    if all(lang in V6_LANGS for lang in langs):
        # The tiny v6 model has no Japanese.
        size = ModelType.SMALL if model == "tiny" and "japan" in langs else ModelType(model)
        for part in ("Det", "Rec"):
            params[f"{part}.ocr_version"] = OCRVersion.PPOCRV6
            params[f"{part}.model_type"] = size
    else:
        script = next(V5_SCRIPT[lang] for lang in langs if lang in V5_SCRIPT)
        if len({V5_SCRIPT.get(lang, "v6") for lang in langs}) > 1:
            print(f"These languages need different models; reading '{script}'.",
                  file=sys.stderr)
        for part in ("Det", "Rec"):
            params[f"{part}.ocr_version"] = OCRVersion.PPOCRV5
            params[f"{part}.model_type"] = ModelType.MOBILE
        params["Rec.lang_type"] = LangRec(script)
    return RapidOCR(params=params)


# Each rotation to try, and how a point (u, v) in the rotated image maps back
# to the page (w, h: the page's size). A line read in a rotated frame comes
# back with its corners in reading order, which is what write_page wants.
def rotations():
    import cv2

    return [
        (None, lambda u, v, w, h: (u, v)),
        (cv2.ROTATE_180, lambda u, v, w, h: (w - u, h - v)),
        (cv2.ROTATE_90_CLOCKWISE, lambda u, v, w, h: (v, h - u)),
        (cv2.ROTATE_90_COUNTERCLOCKWISE, lambda u, v, w, h: (w - v, u)),
    ]


def recognise(ocr, img_path):
    """Lines as (text, corners in reading order), whatever way up the page is.

    The page is read as it is first; only if that reads poorly is it read
    turned round and on each side, keeping the reading that recognised the
    most text with the most confidence. An upright page costs one pass.

    Only lines lying flat count: a page on its side still gets read, line by
    line stood upright, but with every box standing on end its text layer
    comes out as words run together. Turned a quarter, the same lines lie
    flat and win.
    """
    import cv2

    img = cv2.imread(img_path)
    h, w = img.shape[:2]
    best = None
    for code, back in rotations():
        out = ocr(img if code is None else cv2.rotate(img, code))
        txts = [str(t) for t in (out.txts or ())]
        scores = [float(s) for s in (out.scores or ())]
        boxes = [] if out.boxes is None else out.boxes.tolist()
        flat = [math.dist(b[0], b[1]) >= math.dist(b[0], b[3]) for b in boxes]
        weight = sum(s * len(t) for t, s, f in zip(txts, scores, flat) if f)
        if best is None or weight > best[0]:
            best = (weight, txts, boxes, back)
        confident = [s for s, f in zip(scores, flat) if f]
        if best[0] == weight and confident and len(confident) * 2 > len(boxes) \
                and sum(confident) / len(confident) >= 0.9:
            break
    _, txts, boxes, back = best
    return [(t, [back(x, y, w, h) for x, y in box]) for t, box in zip(txts, boxes)]


def tounicode_cmap():
    # Identity: every 2-byte code is that UTF-16 code unit. bfrange blocks may
    # not cross a high byte, and a block holds at most 100 entries.
    ranges = [b"<%02X00> <%02XFF> <%02X00>" % (h, h, h) for h in range(256)]
    blocks = []
    for i in range(0, len(ranges), 100):
        chunk = ranges[i:i + 100]
        blocks.append(b"%d beginbfrange\n%s\nendbfrange" % (len(chunk), b"\n".join(chunk)))
    return (
        b"/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n"
        b"/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def\n"
        b"/CMapName /Adobe-Identity-UCS def\n/CMapType 2 def\n"
        b"1 begincodespacerange\n<0000> <FFFF>\nendcodespacerange\n"
        + b"\n".join(blocks)
        + b"\nendcmap\nCMapName currentdict /CMap defineresource pop\nend\nend\n"
    )


def stream(entries, data, compress=True):
    if compress:
        data = zlib.compress(data)
        entries += b" /Filter /FlateDecode"
    return b"<< %s /Length %d >>\nstream\n%s\nendstream" % (entries, len(data), data)


def write_page(img_path, out_path, lines, dpi, textonly, font):
    from PIL import Image

    im = Image.open(img_path)
    w_px, h_px = im.size
    scale = 72.0 / dpi
    pw, ph = w_px * scale, h_px * scale

    ops = []
    if not textonly:
        ops.append(b"q %.2f 0 0 %.2f 0 0 cm /Im0 Do Q" % (pw, ph))
    ops.append(b"BT 3 Tr")
    for text, poly in lines:
        if not text:
            continue
        # The corners come in reading order: start and end of the top edge,
        # then end and start of the baseline, in image pixels (y down).
        # Convert to PDF points (y up).
        tl, tr, br, bl = [(x * scale, ph - y * scale) for x, y in poly]
        origin, end, top = bl, br, tl
        dx, dy = end[0] - origin[0], end[1] - origin[1]
        length = math.hypot(dx, dy)
        size = math.hypot(top[0] - origin[0], top[1] - origin[1])
        if length < 1 or size < 1:
            continue
        # A line a few degrees off square is a crooked scan, not rotated text.
        # Laid along its true slope, text extractors split it mid-word ("f ox"),
        # so square it up, pivoting on the middle of its baseline.
        theta = math.atan2(dy, dx)
        square = round(theta / (math.pi / 2)) * (math.pi / 2)
        if abs(theta - square) < math.radians(15):
            mid = ((origin[0] + end[0]) / 2, (origin[1] + end[1]) / 2)
            theta = square
            origin = (mid[0] - length / 2 * math.cos(theta),
                      mid[1] - length / 2 * math.sin(theta))
        cos, sin = math.cos(theta), math.sin(theta)
        # The glyphless font is 500 units wide per character; stretch the line
        # so it spans the box the text was found in.
        tz = 100.0 * length / (len(text) * 0.5 * size)
        hexed = text.encode("utf-16-be").hex().upper().encode()
        ops.append(b"%.4f %.4f %.4f %.4f %.2f %.2f Tm /F0 %.2f Tf %.2f Tz <%s> Tj"
                   % (cos, sin, -sin, cos, origin[0], origin[1], size, tz, hexed))
    ops.append(b"ET")

    objs = {}
    objs[1] = b"<< /Type /Catalog /Pages 2 0 R >>"
    objs[2] = b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>"
    xobj = b"" if textonly else b" /XObject << /Im0 11 0 R >>"
    objs[3] = (b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %.2f %.2f]"
               b" /Resources << /Font << /F0 5 0 R >>%s >> /Contents 4 0 R >>"
               % (pw, ph, xobj))
    objs[4] = stream(b"", b"\n".join(ops))
    objs[5] = (b"<< /Type /Font /Subtype /Type0 /BaseFont /GlyphLessFont"
               b" /Encoding /Identity-H /DescendantFonts [6 0 R] /ToUnicode 8 0 R >>")
    c2g = b"9 0 R" if font else b"/Identity"
    objs[6] = (b"<< /Type /Font /Subtype /CIDFontType2 /BaseFont /GlyphLessFont"
               b" /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >>"
               b" /FontDescriptor 7 0 R /DW 500 /CIDToGIDMap %s >>" % c2g)
    ff = b" /FontFile2 10 0 R" if font else b""
    objs[7] = (b"<< /Type /FontDescriptor /FontName /GlyphLessFont /Flags 5"
               b" /FontBBox [0 0 500 1000] /ItalicAngle 0 /Ascent 1000 /Descent 0"
               b" /CapHeight 1000 /StemV 80%s >>" % ff)
    objs[8] = stream(b"", tounicode_cmap())
    if font:
        # Every character maps to glyph 1, the font's one (empty) glyph.
        objs[9] = stream(b"", b"\x00\x01" * 65536)
        objs[10] = stream(b"/Length1 %d" % len(font), font)
    if not textonly:
        if im.mode not in ("L", "RGB"):
            im = im.convert("L" if im.mode in ("1", "LA", "I;16") else "RGB")
        space = b"/DeviceGray" if im.mode == "L" else b"/DeviceRGB"
        objs[11] = stream(
            b"/Type /XObject /Subtype /Image /Width %d /Height %d"
            b" /ColorSpace %s /BitsPerComponent 8" % (w_px, h_px, space),
            im.tobytes(),
        )

    out = bytearray(b"%PDF-1.5\n%\xe2\xe3\xcf\xd3\n")
    size = max(objs) + 1
    offsets = [0] * size
    for num in range(1, size):
        if num in objs:
            offsets[num] = len(out)
            out += b"%d 0 obj\n%s\nendobj\n" % (num, objs[num])
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % size
    for num in range(1, size):
        if num in objs:
            out += b"%010d 00000 n \n" % offsets[num]
        else:
            out += b"0000000000 65535 f \n"
    out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (size, xref)
    with open(out_path, "wb") as f:
        f.write(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lang", required=True, help="PaddleOCR codes, comma separated")
    ap.add_argument("--model", default="small")
    ap.add_argument("--models-dir", default="")
    ap.add_argument("--warmup", action="store_true",
                    help="load (downloading if needed) the models, then exit")
    ap.add_argument("--dpi", type=float, default=300)
    ap.add_argument("--textonly", action="store_true")
    ap.add_argument("--font", default="")
    ap.add_argument("images", nargs="*")
    args = ap.parse_args()

    out = sys.stdout
    font = b""
    if args.font and os.path.isfile(args.font):
        with open(args.font, "rb") as f:
            font = f.read()

    def report(line):
        print(line, file=out, flush=True)

    def fail(img, reason):
        base = os.path.splitext(img)[0]
        with open(base + ".err", "w") as f:
            f.write(reason + "\n")
        with contextlib.suppress(FileNotFoundError):
            os.remove(base + ".pdf")
        report("FAIL " + os.path.basename(img))

    try:
        with contextlib.redirect_stdout(sys.stderr):
            ocr = load_ocr(args.lang.split(","), args.model, args.models_dir)
    except Exception as exc:  # no network, bad model name, broken install...
        for img in args.images:
            fail(img, f"The OCR models could not load: {type(exc).__name__}: {exc}")
        if args.warmup:
            print(f"{type(exc).__name__}: {exc}", file=sys.stderr)
        return 1
    report("READY")
    if args.warmup:
        return 0

    status = 0
    for img in args.images:
        try:
            with contextlib.redirect_stdout(sys.stderr):
                lines = recognise(ocr, img)
            write_page(img, os.path.splitext(img)[0] + ".pdf", lines,
                       args.dpi, args.textonly, font)
            report("DONE")
        except Exception as exc:
            fail(img, f"{type(exc).__name__}: {exc}")
            status = 1
    return status


if __name__ == "__main__":
    sys.exit(main())
PADDLE_HELPER_EOF
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
        -p|--preserve)
            PRESERVE=true
            shift
            ;;
        -c|--clean)
            CLEAN=true
            shift
            ;;
        --plain)
            PLAIN=true
            shift
            ;;
        --tessdata-dir)
            require_value "$key" "$#"
            TESSDATA_DIR="$2"
            shift; shift
            ;;
        --tesseract)
            PADDLE=false
            shift
            ;;
        # --paddle and --save-paddle are what 1.6 needed for what is now the
        # default; still accepted, so existing commands keep working.
        --paddle|--save-paddle)
            PADDLE=true
            shift
            ;;
        --model|--paddle-model)
            require_value "$key" "$#"
            PADDLE_MODEL="$2"
            shift; shift
            ;;
        --no-save)
            NO_SAVE=true
            shift
            ;;
        --install-engine)
            INSTALL_ONLY=true
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

case "$PADDLE_MODEL" in
    tiny|small|medium) ;;
    *) log_error "--model must be tiny, small or medium (got '$PADDLE_MODEL')."; exit 2 ;;
esac

# Install the engine and fetch its models now, so the first real run starts
# straight away. The Homebrew formula calls this from post_install.
if [ "$INSTALL_ONLY" = true ]; then
    require_command uv uv
    TEMP_DIR=$(mktemp -d)
    trap 'spinner_stop; rm -rf "$TEMP_DIR"' EXIT
    NO_SAVE=false
    setup_paddle
    write_paddle_helper "$TEMP_DIR/ocr.py"
    spinner_start "Downloading the OCR models ($PADDLE_MODEL)"
    if ! "$PADDLE_PY" -W ignore "$TEMP_DIR/ocr.py" --warmup --lang en \
            --model "$PADDLE_MODEL" --models-dir "$PADDLE_MODELS_DIR" \
            >/dev/null 2>"$TEMP_DIR/warmup.log"; then
        spinner_stop
        log_error "Could not download the OCR models:"
        tail -n 5 "$TEMP_DIR/warmup.log" | while read -r l; do log_error "  $l"; done
        exit 1
    fi
    spinner_stop
    log_success "OCR engine ready in $PADDLE_SAVED_HOME."
    exit 0
fi

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

# Cleaning deskews the page, so its text no longer sits where it does on the
# original — and --preserve stamps the text onto the original. The two would
# produce a text layer shifted off every line, so refuse rather than ship that.
if [ "$CLEAN" = true ] && [ "$PRESERVE" = true ]; then
    log_error "--clean straightens the page, so its text cannot line up with the untouched original that --preserve keeps. Use one or the other."
    exit 2
fi

if [ -n "$TESSDATA_DIR" ] && [ ! -d "$TESSDATA_DIR" ]; then
    log_error "Tessdata directory does not exist: $TESSDATA_DIR"
    exit 2
fi

# PaddleOCR's models name languages their own way; translate now, so an
# unsupported one fails here rather than after an install.
PADDLE_LANGS=""
if [ "$PADDLE" = true ]; then
    IFS='+' read -ra TESS_LANGS <<< "$OCR_LANG"
    for lang in "${TESS_LANGS[@]}"; do
        code="$(paddle_lang_code "$lang")"
        if [ -z "$code" ]; then
            log_error "The default OCR engine has no model for language '$lang'. Add --tesseract to use Tesseract."
            exit 2
        fi
        PADDLE_LANGS="${PADDLE_LANGS:+$PADDLE_LANGS,}$code"
    done
    if [ "$PLAIN" = true ] || [ -n "$TESSDATA_DIR" ]; then
        log_warn "--plain and --tessdata-dir are Tesseract settings; add --tesseract to use them."
    fi
fi

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
    echo "  Preserve:  $PRESERVE"
    echo "  Clean:     $CLEAN"
    echo "  Plain:     $PLAIN"
    if [ "$PADDLE" = true ]; then
        echo "  Engine:    PaddleOCR models via RapidOCR ($PADDLE_MODEL, $PADDLE_LANGS)"
    else
        echo "  Engine:    Tesseract"
    fi
    if [ -n "$TESSDATA_DIR" ]; then
        echo "  Tessdata:  $TESSDATA_DIR"
    fi
    echo ""
fi

# 4. Dependency Checks
log_info "Checking dependencies..."
# The default engine needs no tesseract at all: only uv, to build its
# environment. Tesseract, when installed, still lends its glyphless font.
if [ "$PADDLE" = true ]; then
    require_command uv uv
else
    require_command tesseract tesseract
    require_language "$OCR_LANG"
fi
require_command pdftoppm poppler
require_command pdftotext poppler

# Check PDF merge tool
if ! command -v pdfunite >/dev/null 2>&1; then
    log_error "Command 'pdfunite' not found (should be part of 'poppler')."
    exit 1
fi
require_command pdfinfo poppler
# Only --preserve needs qpdf, so the default path keeps its dependency list to
# tesseract and poppler.
if [ "$PRESERVE" = true ]; then
    require_command qpdf qpdf
fi

# ImageMagick 7 ships `magick`; 6 only has `convert`. Only --clean needs either.
IM=""
if [ "$CLEAN" = true ]; then
    if command -v magick >/dev/null 2>&1; then
        IM="magick"
    elif command -v convert >/dev/null 2>&1; then
        IM="convert"
    else
        require_command magick imagemagick
        IM="magick"
    fi
fi

# PSM 1 is PSM 3 (fully automatic layout) plus orientation detection. Without
# it an upside-down page comes back as reversed gibberish, not as an error. The
# text keeps the coordinates of the image as given, so --preserve stays aligned.
# It needs osd.traineddata, which every packaged tesseract ships, but a bare
# --tessdata-dir may not have it.
PSM=3
THRESHOLD_METHOD=""
if [ "$PLAIN" = false ] && [ "$PADDLE" = false ]; then
    if has_tess_lang osd; then
        PSM=1
    else
        log_warn "No 'osd' language data, so pages will not be auto-rotated."
    fi
    # Sauvola thresholds each region against its own neighbourhood, so a shadow
    # or a yellowed corner no longer swallows the text in it the way a single
    # page-wide Otsu threshold does. The option only exists from tesseract 5.
    TESS_MAJOR="$(tesseract --version 2>&1 | awk 'NR==1{split($2, v, "."); print v[1]}')"
    case "$TESS_MAJOR" in
        ''|*[!0-9]*) ;;
        *) if [ "$TESS_MAJOR" -ge 5 ]; then THRESHOLD_METHOD=2; fi ;;
    esac
fi

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
        if [ "$PRESERVE" = true ]; then
            log_warn "Input already has a text layer ($FONT_COUNT font(s)); --preserve keeps it and adds OCR on top, so copied text may appear twice."
        else
            log_warn "Input already has a text layer ($FONT_COUNT font(s)); OCR will replace it. Use --preserve to keep it."
        fi
    fi
fi

# 5. Execution

TEMP_DIR=$(mktemp -d)
# A spinner left running would keep drawing over the terminal after the script
# has exited, so it is stopped on every way out.
cleanup() {
    spinner_stop
    if [ "$KEEP_TEMP" = false ]; then
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT
if [ "$KEEP_TEMP" = true ]; then
    log_info "Temporary files will be kept at: $TEMP_DIR"
fi

if [ "$PADDLE" = true ]; then
    setup_paddle
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

if [ "$PADDLE" = true ]; then
    log_info "Step 2/3: OCR Processing ($OCR_LANG) with PaddleOCR models ($PADDLE_MODEL)..."
else
    log_info "Step 2/3: OCR Processing ($OCR_LANG) with $JOBS jobs..."
fi

# Export vars for xargs
export LANG_CODE="$OCR_LANG"
export VERBOSE
export PRESERVE
export CLEAN IM PSM THRESHOLD_METHOD TESSDATA_DIR

# The pages already run in parallel, one process each. Left alone, tesseract
# (OpenMP) and ImageMagick each also spread over every core, so N jobs ran N×N
# threads that mostly waited on each other.
if [ "$JOBS" -gt 1 ]; then
    export OMP_THREAD_LIMIT=1 MAGICK_THREAD_LIMIT=1
fi

# Straighten the page, then divide out uneven lighting: the page over a
# heavily blurred copy of itself is 1 (white) wherever there is only
# background, shadow or not, while text stays dark. No -normalize after it:
# stretching the contrast turns scanner noise in the margins into specks
# that the OCR reads as junk lines. Done in place: the cleaned image is
# both what gets recognised and what the output page shows.
# The blur runs on a 1/10 thumbnail scaled back to the page's exact size: the
# same lighting map, but in 2 s a page instead of 12. Two passes, because the
# deskew decides that size and ImageMagick 6 cannot feed it back into -resize
# within one command (no %[...] escapes in its geometry arguments).
clean_page() {
    local img="$1"
    local base="${img%.*}"
    local size
    if ! size="$("$IM" "$img" -background white -deskew 40% +repage \
                    -write "$img" -format '%wx%h' info: 2>"$base.err")" ||
       ! "$IM" "$img" \( +clone -scale 10% -blur 0x2.5 -resize "${size}!" \) \
            -compose Divide_Src -composite "$img" 2>>"$base.err"; then
        echo "FAIL $(basename "$img")"
        return 1
    fi
    rm -f "$base.err"
}
export -f clean_page

process_page_worker() {
    local img="$1"
    local base="${img%.*}" # remove extension
    local name
    name="$(basename "$img")"

    if [ "$VERBOSE" = true ]; then
        echo "Processing $name..." >&2
    fi

    if [ "$CLEAN" = true ]; then
        clean_page "$img" || return 1
    fi

    # tesseract input output -l lang pdf. Its exit status decides what we report:
    # ignoring it (as this used to) meant a page whose OCR crashed produced no
    # page-N.pdf, the merge silently carried on with whatever was left, and the
    # run exited 0 with a PDF missing pages and no warning anywhere.
    # Under --preserve the page PDF must carry the recognised text and nothing
    # else: it is going to be stamped onto the untouched original, so painting
    # the image again would hide it behind a second, worse copy of itself.
    # The PDF renderer is switched on by its parameter, not by the `pdf` config
    # file: that file lives in the system tessdata, and a --tessdata-dir that
    # holds only models (a tessdata_best checkout does) has no configs/, so
    # tesseract would skip it, write a .txt instead, and still exit 0.
    local tess_opts=(--psm "$PSM" -c tessedit_create_pdf=1)
    if [ -n "$TESSDATA_DIR" ]; then
        tess_opts+=(--tessdata-dir "$TESSDATA_DIR")
    fi
    if [ -n "$THRESHOLD_METHOD" ]; then
        tess_opts+=(-c "thresholding_method=$THRESHOLD_METHOD")
    fi
    if [ "$PRESERVE" = true ]; then
        tess_opts+=(-c textonly_pdf=1)
    fi

    if ! tesseract "$img" "$base" -l "$LANG_CODE" "${tess_opts[@]}" >/dev/null 2>"$base.err"; then
        # Drop anything half-written, so a truncated page cannot be counted as
        # a successful one and merged into the output.
        rm -f "$base.pdf"
        echo "FAIL $name"
        return 1
    fi
    # Exit 0 is not proof of a page: tesseract also exits 0 when it skipped a
    # renderer. Reporting DONE anyway left the merge to fail with "0 page(s)"
    # and no reason, since the .err that would explain it had been deleted.
    if [ ! -s "$base.pdf" ]; then
        echo "tesseract exited 0 but wrote no PDF" >> "$base.err"
        echo "FAIL $name"
        return 1
    fi
    rm -f "$base.err"
    
    # Signal completion similar to progress
    echo "DONE"
}
export -f process_page_worker

# Turn the workers' DONE / FAIL lines into the progress bar. The first line of
# any kind also ends the spinner that covers PaddleOCR's model loading.
track_progress() {
    local line counter=0
    while read -r line; do
        spinner_stop
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
    done
}

# `|| true` on each pipeline: a worker that fails makes it exit non-zero, and
# under `pipefail` that would abort the script right here — before the counting
# check below could name the pages that failed. Let the check decide, so the
# user gets a readable error instead of a bare exit code.
if [ "$PADDLE" = true ]; then
    # Cleaning stays parallel; recognition is one process, because each one
    # would load its own copy of the models, and PaddleOCR already uses every
    # core for a page.
    if [ "$CLEAN" = true ]; then
        spinner_start "Cleaning pages"
        find "$TEMP_DIR" -name "page-*.png" -print0 | \
            xargs -0 -P "$JOBS" -I {} bash -c 'clean_page "$@"' _ {} >/dev/null || true
        spinner_stop
    fi
    shopt -s nullglob
    CLEAN_ERRS=("$TEMP_DIR"/page-*.err)
    shopt -u nullglob
    if [ "${#CLEAN_ERRS[@]}" -gt 0 ]; then
        for err in "${CLEAN_ERRS[@]}"; do
            log_error "Cleaning failed on $(basename "$err" .err).png: $(tr '\n' ' ' < "$err" | cut -c1-200)"
        done
        exit 1
    fi

    PADDLE_HELPER="$TEMP_DIR/paddle_ocr.py"
    write_paddle_helper "$PADDLE_HELPER"
    paddle_args=(--lang "$PADDLE_LANGS" --model "$PADDLE_MODEL" --dpi "$DPI" --models-dir "$PADDLE_MODELS_DIR")
    if [ "$PRESERVE" = true ]; then
        paddle_args+=(--textonly)
    fi
    # The invisible text is set in tesseract's glyphless font when it is
    # around; without it the font is simply not embedded.
    if command -v tesseract >/dev/null 2>&1; then
        TESS_DATA="$(tesseract --list-langs 2>&1 | sed -n 's/.*"\(.*\)".*/\1/p' | head -n 1)"
        if [ -f "${TESS_DATA%/}/pdf.ttf" ]; then
            paddle_args+=(--font "${TESS_DATA%/}/pdf.ttf")
        fi
    fi
    spinner_start "Loading the OCR models"
    "$PADDLE_PY" -W ignore "$PADDLE_HELPER" "${paddle_args[@]}" "${PAGE_IMAGES[@]}" \
        2>"$TEMP_DIR/paddle.log" | track_progress || true
    spinner_stop
else
    find "$TEMP_DIR" -name "page-*.png" -print0 | \
        xargs -0 -P "$JOBS" -I {} bash -c 'process_page_worker "$@"' _ {} | \
        track_progress || true
fi

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
    # A PaddleOCR process that died outright (out of memory, a crash in native
    # code) leaves no per-page reason, only its own log.
    if [ "$PADDLE" = true ] && [ "${#ERR_LIST[@]}" -eq 0 ] && [ -s "$TEMP_DIR/paddle.log" ]; then
        log_error "  The OCR engine stopped; last lines of its log:"
        tail -n 5 "$TEMP_DIR/paddle.log" | while read -r l; do log_error "    $l"; done
    fi
    exit 1
fi

log_success "OCR Complete."

# Under --preserve the merge produces the text layer, not the deliverable: the
# original file is the deliverable, and it is stamped with this a moment later.
MERGE_TARGET="$OUTPUT_FILE"
if [ "$PRESERVE" = true ]; then
    MERGE_TARGET="$TEMP_DIR/text-layer.pdf"
fi

if [ "$PAGE_COUNT_PDF" -le 100 ]; then
    pdfunite "${PAGE_LIST[@]}" "$MERGE_TARGET"
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
    pdfunite "${CHUNKS[@]}" "$MERGE_TARGET"
fi

if [ "$PRESERVE" = true ]; then
    log_info "Stamping the text layer onto the original pages..."
    # qpdf exits 3 when it only had warnings, and pdfunite output reliably earns
    # one ("reported number of objects is not one plus the highest object
    # number") while still producing a perfectly good file. Treat 0 and 3 as
    # success; anything else, or an empty result, is a real failure.
    set +e
    qpdf "$INPUT_FILE" --overlay "$MERGE_TARGET" -- "$OUTPUT_FILE" 2>"$TEMP_DIR/qpdf.err"
    QPDF_RC=$?
    set -e
    if { [ "$QPDF_RC" -ne 0 ] && [ "$QPDF_RC" -ne 3 ]; } || [ ! -s "$OUTPUT_FILE" ]; then
        log_error "qpdf could not stamp the text layer onto '$INPUT_FILE'."
        while read -r qline; do log_error "  $qline"; done < "$TEMP_DIR/qpdf.err"
        rm -f "$OUTPUT_FILE"
        exit 1
    fi
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


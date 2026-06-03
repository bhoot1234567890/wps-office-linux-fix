#!/bin/bash
# fix-wps.sh — Get WPS Office 11.1.0 working on modern Linux
# Run with: sudo bash fix-wps.sh
# Review before running. See README.md for details.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[x]${NC} $*"; }

# --- Checks ---

if [[ $EUID -ne 0 ]]; then
    error "Run as root: sudo bash $0"
    exit 1
fi

WPS_DIR="/opt/kingsoft/wps-office"
if [[ ! -d "$WPS_DIR" ]]; then
    error "WPS Office not found at $WPS_DIR"
    error "Install it first: sudo dpkg -i wps-office_*.deb"
    exit 1
fi

# --- Step 1: Fix libxml2 ---

info "Checking libxml2..."

LIBXML_TARGET="/usr/lib/x86_64-linux-gnu/libxml2.so.2"
if [[ -e "$LIBXML_TARGET" ]]; then
    warn "libxml2.so.2 already exists — skipping"
else
    # Find the available version
    LIBXML_SRC=$(find /usr/lib/x86_64-linux-gnu/ -maxdepth 1 -name 'libxml2.so.*' -not -name 'libxml2.so' | sort -V | tail -1)
    if [[ -z "$LIBXML_SRC" ]]; then
        error "No libxml2 found on system. Install it: sudo apt install libxml2"
        exit 1
    fi
    ln -s "$LIBXML_SRC" "$LIBXML_TARGET"
    info "Linked $LIBXML_SRC -> $LIBXML_TARGET"
fi

# --- Step 2: Disable wpscloudsvr ---

info "Disabling crashing wpscloudsvr..."

CLOUDSVR="$WPS_DIR/office6/wpscloudsvr"
if file "$CLOUDSVR" | grep -q "shell script"; then
    warn "wpscloudsvr already replaced — skipping"
else
    mv "$CLOUDSVR" "$CLOUDSVR.bak"
    cat > "$CLOUDSVR" << 'SCRIPT'
#!/bin/bash
exit 0
SCRIPT
    chmod +x "$CLOUDSVR"
    info "Replaced wpscloudsvr with no-op (backup at wpscloudsvr.bak)"
fi

# --- Step 3: Switch to classic mode ---

info "Switching to classic component mode..."

CONF="$HOME/.config/Kingsoft/Office.conf"
# Find the real user home (even under sudo)
REAL_HOME=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)
CONF="$REAL_HOME/.config/Kingsoft/Office.conf"

if [[ -f "$CONF" ]]; then
    sed -i 's/AppComponentMode=prome_fushion/AppComponentMode=classic/' "$CONF"
    sed -i 's/AppComponentModeInstall=prome_fushion/AppComponentModeInstall=classic/' "$CONF"
    info "Set AppComponentMode=classic in $CONF"
else
    warn "Config not found at $CONF — will be created on first launch"
fi

# --- Step 4: Install Microsoft fonts ---

info "Installing Microsoft core fonts..."

FONT_DIR="$REAL_HOME/.local/share/fonts/microsoft"
mkdir -p "$FONT_DIR"

# Check if cabextract is available
if ! command -v cabextract &>/dev/null; then
    warn "cabextract not found — installing..."
    apt install -y cabextract 2>/dev/null || warn "Could not install cabextract. Install fonts manually."
fi

# Download mscorefonts if not already present
FONT_COUNT=$(find "$FONT_DIR" -name '*.ttf' -o -name '*.TTF' 2>/dev/null | wc -l)
if [[ "$FONT_COUNT" -lt 10 ]]; then
    info "Downloading MS core web fonts..."
    TMPDIR=$(mktemp -d)
    trap "rm -rf $TMPDIR" EXIT

    for f in andale32 arial32 arialb32 comic32 courie32 georgi32 impact32 times32 trebuc32 verdan32 webdin32; do
        curl -fsSL --connect-timeout 10 --max-time 30 -o "$TMPDIR/${f}.exe" \
            "https://downloads.sourceforge.net/project/corefonts/the%20fonts/final/${f}.exe" 2>/dev/null && \
            info "  Downloaded ${f}.exe" || warn "  Failed to download ${f}.exe"
    done

    EXTRACT_DIR="$TMPDIR/extracted"
    mkdir -p "$EXTRACT_DIR"
    for f in "$TMPDIR"/*.exe; do
        [[ -f "$f" ]] && cabextract -q -d "$EXTRACT_DIR" "$f" 2>/dev/null
    done

    cp "$EXTRACT_DIR"/*.ttf "$EXTRACT_DIR"/*.TTF "$FONT_DIR/" 2>/dev/null
    info "Installed $(find "$FONT_DIR" -name '*.ttf' -o -name '*.TTF' | wc -l) font files"
else
    warn "Fonts already installed ($FONT_COUNT files) — skipping download"
fi

# Copy Wine fonts if available (Symbol, Wingdings, Webdings)
for wf in /opt/wine-stable/share/wine/fonts /opt/wine-devel/share/wine/fonts /usr/share/wine/fonts; do
    if [[ -d "$wf" ]]; then
        [[ -f "$wf/symbol.ttf" ]]  && cp "$wf/symbol.ttf"  "$FONT_DIR/Symbol.ttf"  && info "  Copied Symbol from Wine"
        [[ -f "$wf/wingding.ttf" ]] && cp "$wf/wingding.ttf" "$FONT_DIR/Wingdings.ttf" && info "  Copied Wingdings from Wine"
        [[ -f "$wf/webdings.ttf" ]] && cp "$wf/webdings.ttf" "$FONT_DIR/Webdings.ttf" && info "  Copied Webdings from Wine"
        break
    fi
done

# Check for proprietary fonts in user's Downloads
for SEARCH_DIR in "$REAL_HOME/Downloads" "$REAL_HOME/Desktop" "$REAL_HOME/Documents"; do
    for font in "MTEXTRA.TTF" "mtexttra.ttf" "WINGDNG2.TTF" "wingdng2.ttf" "WINGDNG3.TTF" "wingdng3.ttf" "Wingdings 2.ttf" "Wingdings 3.ttf"; do
        if [[ -f "$SEARCH_DIR/$font" ]]; then
            cp "$SEARCH_DIR/$font" "$FONT_DIR/"
            info "  Copied $font from $SEARCH_DIR"
        fi
    done
done

# Rebuild font cache
info "Rebuilding font cache..."
sudo -u "${SUDO_USER:-$USER}" fc-cache -f "$FONT_DIR" 2>/dev/null || fc-cache -f "$FONT_DIR"

# --- Done ---

echo ""
info "All fixes applied!"
echo ""
echo "  Missing fonts? Place these in $FONT_DIR:"
echo "    - WINGDNG2.TTF  (from Microsoft Office/Windows)"
echo "    - WINGDNG3.TTF  (from Microsoft Office/Windows)"
echo "    - MTEXTRA.TTF   (from Microsoft Office/Windows)"
echo "  Then run: fc-cache -f $FONT_DIR"
echo ""
echo "  Wayland blank window? Launch with:"
echo "    QT_QPA_PLATFORM=xcb /usr/bin/wps"
echo ""
info "Launch WPS: /usr/bin/wps"

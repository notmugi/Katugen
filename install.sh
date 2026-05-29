#!/usr/bin/env bash
# install.sh — Install katugen.
#
# Sets up:
#   - matugen templates in   ~/.config/matugen/templates
#   - matugen config at      ~/.config/matugen/config.toml
#   - generator script at    ~/.local/bin/matugen-generate.sh
#   - Dolphin service menu   ~/.local/share/kio/servicemenus/matugen-generate.desktop
#
# Idempotent: existing files are backed up to *.bak-YYYYmmddHHMMSS before being
# replaced. Re-run safely.

set -euo pipefail

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

MATUGEN_DIR="$XDG_CONFIG_HOME/matugen"
TEMPLATES_DIR="$MATUGEN_DIR/templates"
CONFIG_FILE="$MATUGEN_DIR/config.toml"

BIN_DIR="$HOME/.local/bin"
SCRIPT_DST="$BIN_DIR/matugen-generate.sh"

SERVICEMENU_DIR="$XDG_DATA_HOME/kio/servicemenus"
SERVICEMENU_DST="$SERVICEMENU_DIR/matugen-generate.desktop"

STAMP="$(date +%Y%m%d%H%M%S)"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
c_reset=$'\033[0m'; c_bold=$'\033[1m'
c_blue=$'\033[34m'; c_green=$'\033[32m'; c_yellow=$'\033[33m'; c_red=$'\033[31m'

info()  { printf '%s==>%s %s\n'         "$c_blue"   "$c_reset" "$*"; }
ok()    { printf '%s  ✓%s %s\n'         "$c_green"  "$c_reset" "$*"; }
warn()  { printf '%s  !%s %s\n'         "$c_yellow" "$c_reset" "$*"; }
err()   { printf '%s ✗%s %s\n' "$c_red" "$c_reset" "$*" >&2; }

backup_if_exists() {
    local f="$1"
    if [[ -e "$f" || -L "$f" ]]; then
        local b="${f}.bak-${STAMP}"
        mv -- "$f" "$b"
        warn "Existing file moved to: $b"
    fi
}

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        err "Required command not found: $1"
        echo "    $2" >&2
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
info "Checking prerequisites"
missing=0
require_cmd matugen "Install matugen (e.g. 'yay -S matugen-bin' on Arch)." || missing=1
require_cmd realpath "Install coreutils." || missing=1
if [[ $missing -ne 0 ]]; then
    err "Aborting due to missing prerequisites."
    exit 1
fi
ok "matugen $(matugen --version 2>&1 | head -1)"

if ! command -v plasma-apply-colorscheme >/dev/null 2>&1; then
    warn "plasma-apply-colorscheme not found — KDE auto-apply will be skipped at runtime."
fi
if ! command -v kbuildsycoca6 >/dev/null 2>&1 && ! command -v kbuildsycoca5 >/dev/null 2>&1; then
    warn "kbuildsycoca6/5 not found — the Dolphin menu will appear after you log out and back in."
fi

# ---------------------------------------------------------------------------
# Create target directories
# ---------------------------------------------------------------------------
info "Creating target directories"
mkdir -p \
    "$TEMPLATES_DIR" \
    "$BIN_DIR" \
    "$SERVICEMENU_DIR" \
    "$XDG_DATA_HOME/color-schemes" \
    "$XDG_CONFIG_HOME/alacritty/themes" \
    "$XDG_CONFIG_HOME/btop/themes" \
    "$XDG_CONFIG_HOME/gtk-3.0" \
    "$XDG_CONFIG_HOME/gtk-4.0" \
    "$XDG_CONFIG_HOME/qt5ct/colors" \
    "$XDG_CONFIG_HOME/qt6ct/colors" \
    "$XDG_CONFIG_HOME/BetterDiscord/themes" \
    "$XDG_CONFIG_HOME/vesktop/themes" \
    "$XDG_CACHE_HOME/wal"
ok "Directories ready"

# ---------------------------------------------------------------------------
# Install templates
# ---------------------------------------------------------------------------
info "Installing matugen templates → $TEMPLATES_DIR"
# Mirror tree so subfolders (e.g. terminal/) are preserved.
cp -r "$REPO_DIR/templates/." "$TEMPLATES_DIR/"
ok "Templates copied"

# ---------------------------------------------------------------------------
# Install matugen config (substitute @TEMPLATES@ placeholder)
# ---------------------------------------------------------------------------
info "Installing matugen config → $CONFIG_FILE"
backup_if_exists "$CONFIG_FILE"
sed "s|@TEMPLATES@|${TEMPLATES_DIR}|g" \
    "$REPO_DIR/config/matugen-config.toml" > "$CONFIG_FILE"
ok "Config written"

# ---------------------------------------------------------------------------
# Install generator script
# ---------------------------------------------------------------------------
info "Installing generator script → $SCRIPT_DST"
backup_if_exists "$SCRIPT_DST"
install -m 0755 "$REPO_DIR/scripts/matugen-generate.sh" "$SCRIPT_DST"
ok "Script installed (executable)"

case ":$PATH:" in
    *":$BIN_DIR:"*) : ;;
    *) warn "$BIN_DIR is not in your PATH — that's fine for the service menu (it uses the full path), but you may want to add it to your shell rc." ;;
esac

# ---------------------------------------------------------------------------
# Install Dolphin service menu (substitute @SCRIPT@ placeholder)
# ---------------------------------------------------------------------------
info "Installing Dolphin service menu → $SERVICEMENU_DST"
backup_if_exists "$SERVICEMENU_DST"
sed "s|@SCRIPT@|${SCRIPT_DST}|g" \
    "$REPO_DIR/servicemenus/matugen-generate.desktop" > "$SERVICEMENU_DST"
chmod +x "$SERVICEMENU_DST"
ok "Service menu installed"

# ---------------------------------------------------------------------------
# Refresh KIO cache so Dolphin picks up the menu without logout
# ---------------------------------------------------------------------------
info "Rebuilding KIO service cache"
if command -v kbuildsycoca6 >/dev/null 2>&1; then
    kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
    ok "kbuildsycoca6 done"
elif command -v kbuildsycoca5 >/dev/null 2>&1; then
    kbuildsycoca5 --noincremental >/dev/null 2>&1 || true
    ok "kbuildsycoca5 done"
else
    warn "Skipped (no kbuildsycoca found)"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
cat <<EOF

${c_bold}${c_green}Installation complete.${c_reset}

Try it: right-click any image in Dolphin → ${c_bold}Generate${c_reset} → ${c_bold}Light${c_reset} or ${c_bold}Dark${c_reset}.

${c_bold}One-time per-app setup${c_reset} (only needed once, after first run):
  • Alacritty: add  import = ["~/.config/alacritty/themes/matugen.toml"]  to your alacritty.toml
  • btop:      Esc → Options → Color theme → matugen
  • Qt apps:   in qt5ct / qt6ct, set Color Scheme → matugen
  • Discord:   enable matugen.theme.css in BetterDiscord / Vesktop themes panel
  • KDE:       System Settings → Colors → choose "Matugen" (auto-applied on each run too)

Logs:  ${XDG_CACHE_HOME}/matugen-generate.log
EOF

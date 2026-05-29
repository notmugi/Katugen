#!/usr/bin/env bash
# install.sh — Install katugen.
#
# - Copies *every* matugen template from this repo into ~/.config/matugen/templates.
# - For each template, checks whether the target app's config dir actually
#   exists on this system; only enables the template if it does. Two templates
#   (the KDE color scheme and the pywalfox cache) are always installed.
# - Generates ~/.config/matugen/config.toml dynamically from config/templates.tsv.
# - Installs ~/.local/bin/matugen-generate.sh and the Dolphin service menu.
#
# Re-running this script is safe: it rewrites the matugen config in place so
# newly installed apps get picked up automatically, while existing user files
# (the script and the .desktop entry) are backed up to *.bak-YYYYmmddHHMMSS
# only when they actually differ from the new version.

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

REGISTRY="$REPO_DIR/config/templates.tsv"

STAMP="$(date +%Y%m%d%H%M%S)"

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
c_reset=$'\033[0m'; c_bold=$'\033[1m'; c_dim=$'\033[2m'
c_blue=$'\033[34m'; c_green=$'\033[32m'; c_yellow=$'\033[33m'; c_red=$'\033[31m'

info()  { printf '%s==>%s %s\n'         "$c_blue"   "$c_reset" "$*"; }
ok()    { printf '%s  ✓%s %s\n'         "$c_green"  "$c_reset" "$*"; }
skip()  { printf '%s  ·%s %s%s%s\n'     "$c_dim"    "$c_reset" "$c_dim" "$*" "$c_reset"; }
warn()  { printf '%s  !%s %s\n'         "$c_yellow" "$c_reset" "$*"; }
err()   { printf '%s ✗%s %s\n' "$c_red" "$c_reset" "$*" >&2; }

# ---------------------------------------------------------------------------
# Path expansion (~ -> $HOME)
# ---------------------------------------------------------------------------
expand_tilde() {
    local p="$1"
    # shellcheck disable=SC2088  # literal tilde patterns, not expansion
    case "$p" in
        '~')   echo "$HOME" ;;
        '~/'*) echo "$HOME/${p#'~/'}" ;;
        *)     echo "$p" ;;
    esac
}

# ---------------------------------------------------------------------------
# Safe replace: only overwrite if content differs; back up the old version.
# ---------------------------------------------------------------------------
install_if_changed() {
    local src="$1" dst="$2" mode="${3:-0644}"
    mkdir -p "$(dirname "$dst")"
    if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
        skip "unchanged: $dst"
        chmod "$mode" "$dst"
        return 0
    fi
    if [[ -e "$dst" || -L "$dst" ]]; then
        local b="${dst}.bak-${STAMP}"
        mv -- "$dst" "$b"
        warn "backed up old version → $b"
    fi
    install -m "$mode" "$src" "$dst"
    ok "wrote $dst"
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
info "Checking prerequisites"
missing=0
for c in matugen realpath; do
    if ! command -v "$c" >/dev/null 2>&1; then
        err "Required command not found: $c"
        missing=1
    fi
done
if [[ $missing -ne 0 ]]; then
    err "Aborting. Install matugen (e.g. 'yay -S matugen-bin' on Arch) and try again."
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
# Copy templates into ~/.config/matugen/templates (mirror full tree).
# ---------------------------------------------------------------------------
info "Installing matugen templates → $TEMPLATES_DIR"
mkdir -p "$TEMPLATES_DIR"
# Use rsync if available for in-place updates without clobbering unrelated files.
if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$REPO_DIR/templates/" "$TEMPLATES_DIR/"
else
    rm -rf "$TEMPLATES_DIR"
    mkdir -p "$TEMPLATES_DIR"
    cp -r "$REPO_DIR/templates/." "$TEMPLATES_DIR/"
fi
ok "Templates synced"

# ---------------------------------------------------------------------------
# Generate matugen config.toml from registry, skipping apps not present.
# ---------------------------------------------------------------------------
info "Detecting installed apps and generating $CONFIG_FILE"
tmp_config="$(mktemp)"
trap 'rm -f "$tmp_config"' EXIT

cat > "$tmp_config" <<'EOF'
# Matugen configuration — generated by katugen install.sh
# Re-run install.sh to refresh this file when you install/uninstall apps.

[config]
EOF

# Always-on minimum dirs (kcolorscheme + pywalfox cache live outside ~/.config)
mkdir -p \
    "$XDG_DATA_HOME/color-schemes" \
    "$XDG_CACHE_HOME/wal" \
    "$BIN_DIR" \
    "$SERVICEMENU_DIR"

enabled=0
skipped=0
declare -a enabled_names=()

while IFS=$'\t' read -r id rel marker out; do
    # Strip surrounding whitespace and skip blank/comment lines.
    id="${id%%#*}"
    [[ -z "${id// }" ]] && continue
    [[ "$id" == "id" ]] && continue   # accidental header

    if [[ -z "${rel:-}" || -z "${marker:-}" || -z "${out:-}" ]]; then
        warn "Malformed registry row, skipping: id=$id"
        continue
    fi

    src="$TEMPLATES_DIR/$rel"
    if [[ ! -f "$src" ]]; then
        warn "Template file missing in repo: $rel (skipping)"
        ((skipped++)) || true
        continue
    fi

    if [[ "$marker" == "ALWAYS" ]]; then
        enable=1
    else
        expanded_marker="$(expand_tilde "$marker")"
        if [[ -d "$expanded_marker" ]]; then
            enable=1
        else
            enable=0
        fi
    fi

    if [[ $enable -eq 1 ]]; then
        # Ensure the output's parent directory exists so matugen can write there.
        expanded_out="$(expand_tilde "$out")"
        mkdir -p "$(dirname "$expanded_out")"

        {
            printf '\n[templates.%s]\n' "$id"
            printf "input_path  = '%s/%s'\n" "$TEMPLATES_DIR" "$rel"
            printf "output_path = '%s'\n" "$out"
        } >> "$tmp_config"
        enabled_names+=("$id")
        ((enabled++)) || true
    else
        ((skipped++)) || true
    fi
done < "$REGISTRY"

install_if_changed "$tmp_config" "$CONFIG_FILE" 0644

ok "Enabled $enabled templates:"
printf '       %s\n' "${enabled_names[@]}" | column -c 80 || printf '       %s\n' "${enabled_names[@]}"
if [[ $skipped -gt 0 ]]; then
    skip "Skipped $skipped (app config dir not found — install that app and re-run)"
fi

# ---------------------------------------------------------------------------
# Install generator script
# ---------------------------------------------------------------------------
info "Installing generator script → $SCRIPT_DST"
install_if_changed "$REPO_DIR/scripts/matugen-generate.sh" "$SCRIPT_DST" 0755

case ":$PATH:" in
    *":$BIN_DIR:"*) : ;;
    *) warn "$BIN_DIR is not in your PATH — fine for the service menu, but you may want to add it to your shell rc." ;;
esac

# ---------------------------------------------------------------------------
# Install Dolphin service menu (substitute @SCRIPT@ placeholder)
# ---------------------------------------------------------------------------
info "Installing Dolphin service menu → $SERVICEMENU_DST"
rendered="$(mktemp)"
sed "s|@SCRIPT@|${SCRIPT_DST}|g" "$REPO_DIR/servicemenus/matugen-generate.desktop" > "$rendered"
install_if_changed "$rendered" "$SERVICEMENU_DST" 0755
rm -f "$rendered"

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

${c_bold}${c_green}katugen installed.${c_reset}

Try it: right-click any image in Dolphin → ${c_bold}Generate${c_reset} → ${c_bold}Light${c_reset} or ${c_bold}Dark${c_reset}.

If you later install a new app that katugen knows about, just re-run this
script and it'll be picked up automatically.

Logs:  ${XDG_CACHE_HOME}/matugen-generate.log
EOF

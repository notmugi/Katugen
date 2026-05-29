#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 mugi (https://github.com/notmugi)
# install.sh — Install katugen.
#
# - Copies every matugen template from this repo into ~/.config/matugen/templates.
# - Detects which apps you have installed by checking for marker files/dirs,
#   and only wires up templates for those apps. Two templates (the KDE color
#   scheme and the pywalfox cache) are always installed.
# - Generates ~/.config/matugen/config.toml from the inline registration calls
#   in this script's "Application registry" section below.
# - Installs ~/.local/bin/matugen-generate.sh, helper scripts in
#   ~/.local/share/katugen/, and the Dolphin service menu.
#
# Re-running this script is safe (idempotent): it only overwrites files whose
# content actually changed, backing up the old version to *.bak-YYYYmmddHHMMSS.

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

# Helper scripts live alongside the generator so post_hook commands have a
# stable, user-writable location.
HELPER_DIR="$HOME/.local/share/katugen"
APPLY_DST="$HELPER_DIR/template-apply.sh"
PYDIR_DST="$HELPER_DIR/python"

SERVICEMENU_DIR="$XDG_DATA_HOME/kio/servicemenus"
SERVICEMENU_DST="$SERVICEMENU_DIR/matugen-generate.desktop"

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
# State accumulated during the "Application registry" section below.
# `register` appends one [templates.<id>] block to $tmp_config, and only when
# the marker exists. `add_if` is a tiny conditional sugar.
# ---------------------------------------------------------------------------
tmp_config=""        # populated below
enabled=0
skipped=0
enabled_names=()

# register <id> <template_relpath> <output_path> [post_hook_command]
# Always emits the block. Use add_if to guard.
register() {
    local id="$1" rel="$2" out="$3" hook="${4:-}"
    local src="$TEMPLATES_DIR/$rel"
    if [[ ! -f "$src" ]]; then
        warn "Template missing in repo: $rel (skipping $id)"
        skipped=$((skipped+1))
        return 0
    fi

    # Ensure the output's parent directory exists so matugen can write there.
    local expanded_out="${out/#\~/$HOME}"
    mkdir -p "$(dirname "$expanded_out")"

    {
        printf '\n[templates.%s]\n' "$id"
        printf "input_path  = '%s/%s'\n" "$TEMPLATES_DIR" "$rel"
        printf "output_path = '%s'\n" "$out"
        if [[ -n "$hook" ]]; then
            # Escape single quotes for TOML literal string.
            local escaped="${hook//\'/\'\\\'\'}"
            printf "post_hook   = '%s'\n" "$escaped"
        fi
    } >> "$tmp_config"
    enabled_names+=("$id")
    enabled=$((enabled+1))
}

# add_if <marker_path> <register args...>
# Marker may be a directory or a file. ~ is expanded to $HOME.
add_if() {
    local marker="$1"; shift
    local expanded="${marker/#\~/$HOME}"
    if [[ -e "$expanded" ]]; then
        register "$@"
    else
        skipped=$((skipped+1))
    fi
}

# Convenience: Discord-style apps register both Noctalia themes (material +
# midnight) for one client at once.
add_discord_if() {
    local marker="$1" client_dir="$2"
    local expanded="${marker/#\~/$HOME}"
    if [[ -e "$expanded" ]]; then
        register "discord-material-$client_dir" \
                 "discord-material.css" \
                 "$marker/themes/matugen-material.theme.css"
        register "discord-midnight-$client_dir" \
                 "discord-midnight.css" \
                 "$marker/themes/matugen-midnight.theme.css"
    else
        skipped=$((skipped+2))
    fi
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
if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$REPO_DIR/templates/" "$TEMPLATES_DIR/"
else
    rm -rf "$TEMPLATES_DIR"
    mkdir -p "$TEMPLATES_DIR"
    cp -r "$REPO_DIR/templates/." "$TEMPLATES_DIR/"
fi
ok "Templates synced"

# ---------------------------------------------------------------------------
# Detect installed apps and build the matugen config.
# ---------------------------------------------------------------------------
info "Detecting installed apps and generating $CONFIG_FILE"

# Always-on minimum dirs.
mkdir -p \
    "$XDG_DATA_HOME/color-schemes" \
    "$XDG_CACHE_HOME/wal" \
    "$XDG_CACHE_HOME/katugen/zen-browser" \
    "$BIN_DIR" \
    "$SERVICEMENU_DIR" \
    "$HELPER_DIR" \
    "$PYDIR_DST"

tmp_config="$(mktemp)"
trap 'rm -f "$tmp_config"' EXIT

cat > "$tmp_config" <<'EOF'
# Matugen configuration — generated by katugen install.sh
# Re-run install.sh to refresh this file when you install/uninstall apps.

[config]
EOF

# ===========================================================================
# Application registry — the only place to edit when adding/changing an app.
#
# Each block is either:
#   register   <id> <template> <output> [post-hook]
#       — always installed (unconditional)
#   add_if     <marker> <id> <template> <output> [post-hook]
#       — installed iff <marker> exists (file OR directory)
#
# `<post-hook>` may reference:
#   $APPLY_DST  → ~/.local/share/katugen/template-apply.sh
#   $PYDIR_DST  → ~/.local/share/katugen/python
#   $KATUGEN_MODE  → "light" or "dark" (exported by matugen-generate.sh)
# ===========================================================================

# ---- Always-on -----------------------------------------------------------
register   kcolorscheme   kcolorscheme.colors \
           "~/.local/share/color-schemes/matugen.colors"
register   pywalfox       pywalfox.json \
           "~/.cache/wal/colors.json" \
           "$APPLY_DST pywalfox \"\$KATUGEN_MODE\""

# ---- GTK ------------------------------------------------------------------
add_if "~/.config/gtk-3.0" \
       gtk3   gtk3.css   "~/.config/gtk-3.0/matugen.css"
add_if "~/.config/gtk-4.0" \
       gtk4   gtk4.css   "~/.config/gtk-4.0/matugen.css" \
       "$PYDIR_DST/gtk-refresh.py \"\$KATUGEN_MODE\""

# ---- Qt (qt5ct / qt6ct) ---------------------------------------------------
add_if "~/.config/qt5ct" \
       qt5ct   qtct.conf   "~/.config/qt5ct/colors/matugen.conf"
add_if "~/.config/qt6ct" \
       qt6ct   qtct.conf   "~/.config/qt6ct/colors/matugen.conf"

# ---- Terminals — output in themes/, post-hook wires into main config ------
add_if "~/.config/alacritty" \
       alacritty   terminal/alacritty.toml \
       "~/.config/alacritty/themes/matugen.toml" \
       "$APPLY_DST alacritty"
add_if "~/.config/foot" \
       foot   terminal/foot   "~/.config/foot/themes/matugen" \
       "$APPLY_DST foot"
add_if "~/.config/ghostty" \
       ghostty   terminal/ghostty   "~/.config/ghostty/themes/matugen" \
       "$APPLY_DST ghostty"
add_if "~/.config/kitty" \
       kitty   terminal/kitty.conf   "~/.config/kitty/themes/matugen.conf" \
       "$APPLY_DST kitty"
add_if "~/.config/wezterm" \
       wezterm   terminal/wezterm.toml \
       "~/.config/wezterm/colors/Matugen.toml" \
       "$APPLY_DST wezterm"

# ---- Shell prompt — palette block inserted into starship.toml -------------
# Starship has no `include` directive; the post-hook splices a marker-bracketed
# block into the user's starship.toml. Marker is the user's actual config.
add_if "~/.config/starship.toml" \
       starship   terminal/starship.toml \
       "~/.cache/katugen/starship-palette.toml" \
       "$APPLY_DST starship"

# ---- TUI apps -------------------------------------------------------------
add_if "~/.config/btop" \
       btop   btop.theme   "~/.config/btop/themes/matugen.theme" \
       "$APPLY_DST btop"
add_if "~/.config/cava/config" \
       cava   cava.ini   "~/.config/cava/themes/matugen" \
       "$APPLY_DST cava"
add_if "~/.config/helix" \
       helix   helix.toml   "~/.config/helix/themes/matugen.toml"
add_if "~/.config/yazi" \
       yazi   yazi.toml \
       "~/.config/yazi/flavors/matugen.yazi/flavor.toml" \
       "$APPLY_DST yazi"
add_if "~/.config/zathura" \
       zathura   zathurarc   "~/.config/zathura/matugenrc" \
       "$APPLY_DST zathura"

# ---- Editors --------------------------------------------------------------
add_if "~/.config/zed" \
       zed   zed.json   "~/.config/zed/themes/matugen.json"
add_if "~/.config/emacs" \
       emacs   emacs.el   "~/.config/emacs/matugen-theme.el"

# vscode dropped: requires an installed VS Code theme extension and dynamic
# resolution of its install path. Out of scope.

# ---- Discord clients (both Noctalia themes for each detected client) ------
add_discord_if "~/.config/vesktop"                                           vesktop
add_discord_if "~/.config/BetterDiscord"                                     bd
add_discord_if "~/.config/webcord"                                           webcord
add_discord_if "~/.config/armcord"                                           armcord
add_discord_if "~/.config/equibop"                                           equibop
add_discord_if "~/.config/Equicord"                                          equicord
add_discord_if "~/.config/Vencord"                                           vencord
add_discord_if "~/.var/app/com.discordapp.Discord/config/Vencord"            vencord-flatpak
add_discord_if "~/.config/dorion"                                            dorion
add_discord_if "~/.config/lightcord"                                         lightcord

# ---- Spicetify — overwrites the Comfy theme's color.ini ------------------
add_if "~/.config/spicetify/Themes/Comfy" \
       spicetify   spicetify.ini \
       "~/.config/spicetify/Themes/Comfy/color.ini" \
       "spicetify -q apply --no-restart"

# ---- Telegram Desktop -----------------------------------------------------
add_if "~/.config/telegram-desktop" \
       telegram   telegram.tdesktop-theme \
       "~/.config/telegram-desktop/themes/matugen.tdesktop-theme"

# ---- Steam (Material-Theme skin must be installed separately) ------------
add_if "~/.steam/steam/steamui/skins/Material-Theme" \
       steam   steam.css \
       "~/.steam/steam/steamui/skins/Material-Theme/css/main/colors/matugen.css"

# ---- Wayland compositors --------------------------------------------------
add_if "~/.config/hypr/hyprland.conf" \
       hyprland   hyprland.conf \
       "~/.config/hypr/matugen/matugen-colors.conf"
add_if "~/.config/hypr/hyprland.conf" \
       hyprland-lua   hyprland.lua \
       "~/.config/hypr/matugen/matugen-colors.lua" \
       "$APPLY_DST hyprland"
add_if "~/.config/hyprtoolkit" \
       hyprtoolkit   hyprtoolkit.conf \
       "~/.config/hypr/hyprtoolkit.conf"
add_if "~/.config/niri/config.kdl" \
       niri   niri.kdl   "~/.config/niri/matugen.kdl" \
       "$APPLY_DST niri"
add_if "~/.config/sway/config" \
       sway   sway   "~/.config/sway/matugen" \
       "$APPLY_DST sway"
add_if "~/.config/labwc/rc.xml" \
       labwc   labwc.conf   "~/.config/labwc/themerc-override" \
       "$APPLY_DST labwc"
add_if "~/.config/mango/config.conf" \
       mango   mango.conf   "~/.config/mango/matugen.conf" \
       "$APPLY_DST mango"
add_if "~/.config/scroll/config" \
       scroll   scroll   "~/.config/scroll/matugen" \
       "$APPLY_DST scroll"

# ---- App launchers --------------------------------------------------------
add_if "~/.config/fuzzel" \
       fuzzel   fuzzel.conf   "~/.config/fuzzel/themes/matugen" \
       "$APPLY_DST fuzzel"
add_if "~/.config/walker/config.toml" \
       walker   walker.css \
       "~/.config/walker/themes/matugen/style.css" \
       "$APPLY_DST walker"
add_if "~/.local/share/vicinae" \
       vicinae   vicinae.toml \
       "~/.local/share/vicinae/themes/matugen.toml" \
       "vicinae theme set matugen"

# ---- Noctalia shell — colors.json read directly --------------------------
add_if "~/.config/noctalia" \
       noctalia   noctalia.json   "~/.config/noctalia/colors.json"

# ---- Zen Browser — staged in cache, post-hook auto-imports into profiles -
add_if "~/.zen" \
       zen-userchrome   zen-browser/zen-userChrome.css \
       "~/.cache/katugen/zen-browser/zen-userChrome.css"
add_if "~/.zen" \
       zen-usercontent   zen-browser/zen-userContent.css \
       "~/.cache/katugen/zen-browser/zen-userContent.css" \
       "$APPLY_DST zen"

# ===========================================================================
# End of application registry
# ===========================================================================

install_if_changed "$tmp_config" "$CONFIG_FILE" 0644

ok "Enabled $enabled templates:"
printf '       %s\n' "${enabled_names[@]}" | column -c 80 || printf '       %s\n' "${enabled_names[@]}"
if [[ $skipped -gt 0 ]]; then
    skip "Skipped $skipped (app config dir not found — install that app and re-run)"
fi

# ---------------------------------------------------------------------------
# Install helper scripts (template-apply.sh + python helpers)
# ---------------------------------------------------------------------------
info "Installing helper scripts → $HELPER_DIR"
install_if_changed "$REPO_DIR/scripts/template-apply.sh"  "$APPLY_DST" 0755
for py in "$REPO_DIR"/scripts/python/*.py; do
    install_if_changed "$py" "$PYDIR_DST/$(basename "$py")" 0755
done

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

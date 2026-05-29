#!/usr/bin/env bash
# matugen-generate.sh
# Generate a Material You colorscheme from an image using matugen,
# then apply the KDE color scheme and nudge GTK apps to refresh.
#
# Usage: matugen-generate.sh <light|dark> /path/to/image

set -euo pipefail

MODE="${1:-}"
IMAGE="${2:-}"

if [[ -z "$MODE" || -z "$IMAGE" ]]; then
    echo "Usage: $0 <light|dark> /path/to/image" >&2
    exit 1
fi

if [[ "$MODE" != "light" && "$MODE" != "dark" ]]; then
    echo "Mode must be 'light' or 'dark' (got: $MODE)" >&2
    exit 1
fi

# Resolve absolute path (handles spaces, symlinks, mounted drives, etc.)
WALLPAPER_PATH="$(realpath -- "$IMAGE")"

if [[ ! -f "$WALLPAPER_PATH" ]]; then
    echo "File not found: $WALLPAPER_PATH" >&2
    exit 1
fi

LOG="$HOME/.cache/matugen-generate.log"
mkdir -p "$(dirname "$LOG")"

{
    echo "==== $(date -Iseconds) | mode=$MODE | image=$WALLPAPER_PATH ===="

    # 1. Apply wallpaper natively in Plasma (if available).
    if command -v plasma-apply-wallpaperimage >/dev/null 2>&1; then
        plasma-apply-wallpaperimage "$WALLPAPER_PATH" || true
    fi

    # 2. Generate themes via matugen.
    #    --prefer saturation gives livelier accents and also avoids the
    #    "multiple source colors found" prompt in non-interactive runs.
    matugen image --mode "$MODE" --prefer saturation "$WALLPAPER_PATH"

    # 3. Force Plasma to flush + apply the generated color scheme.
    if command -v plasma-apply-colorscheme >/dev/null 2>&1; then
        # Bounce off another scheme so KDE actually re-reads the file.
        if [[ "$MODE" == "dark" ]]; then
            plasma-apply-colorscheme BreezeLight >/dev/null 2>&1 || true
        else
            plasma-apply-colorscheme BreezeDark  >/dev/null 2>&1 || true
        fi
        plasma-apply-colorscheme matugen || true
    fi

    # 4. Nudge GTK apps to pick up the new light/dark preference.
    if command -v gsettings >/dev/null 2>&1; then
        if [[ "$MODE" == "dark" ]]; then
            gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'  || true
        else
            gsettings set org.gnome.desktop.interface color-scheme 'prefer-light' || true
        fi
    fi

    # 5. Push the freshly written ~/.cache/wal/colors.json to Firefox
    #    via the pywalfox native-messaging host, and set the light/dark variant.
    #    Requires the pywalfox Firefox extension to be installed and the
    #    native host registered (`pywalfox install` once, per-user).
    if command -v pywalfox >/dev/null 2>&1; then
        pywalfox update      || true
        pywalfox "$MODE"     || true
    fi

    echo "Done."
} >>"$LOG" 2>&1

# Desktop notification (non-fatal if unavailable).
if command -v notify-send >/dev/null 2>&1; then
    notify-send -a "Matugen" "Colorscheme generated (${MODE})" "$(basename "$WALLPAPER_PATH")"
fi

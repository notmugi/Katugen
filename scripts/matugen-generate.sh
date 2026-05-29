#!/usr/bin/env bash
# matugen-generate.sh
# Generate a Material You colorscheme from an image and apply it system-wide.
#
# Usage: matugen-generate.sh <light|dark> /path/to/image
#
# Per-template integration (auto-include into user configs, live reloads,
# KDE+GTK signaling, pywalfox refresh, etc.) is driven by post_hook entries
# in ~/.config/matugen/config.toml, which are generated from katugen's
# templates.tsv at install time and call into:
#   - scripts/template-apply.sh   (one big bash case per app)
#   - scripts/python/kde-apply-scheme.py
#   - scripts/python/gtk-refresh.py
#
# The KATUGEN_MODE env var is exported here so post-hooks can branch on
# light vs dark when needed (e.g. pywalfox, GTK).

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

WALLPAPER_PATH="$(realpath -- "$IMAGE")"
if [[ ! -f "$WALLPAPER_PATH" ]]; then
    echo "File not found: $WALLPAPER_PATH" >&2
    exit 1
fi

LOG="$HOME/.cache/matugen-generate.log"
mkdir -p "$(dirname "$LOG")"

export KATUGEN_MODE="$MODE"

{
    echo "==== $(date -Iseconds) | mode=$MODE | image=$WALLPAPER_PATH ===="

    # 1. Apply the wallpaper natively in Plasma (best-effort).
    if command -v plasma-apply-wallpaperimage >/dev/null 2>&1; then
        plasma-apply-wallpaperimage "$WALLPAPER_PATH" || true
    fi

    # 2. Generate every enabled template via matugen. Per-template post_hooks
    #    handle KDE color application, GTK refresh, terminal/app integration,
    #    pywalfox push, and Plasma/Hyprland/Sway reloads.
    #    --prefer saturation: livelier accents; also avoids the
    #    "multiple source colors found" prompt non-interactively.
    matugen image --mode "$MODE" --prefer saturation "$WALLPAPER_PATH"

    echo "Done."
} >>"$LOG" 2>&1

# Notify (non-fatal if unavailable).
if command -v notify-send >/dev/null 2>&1; then
    notify-send -a "Matugen" "Colorscheme generated (${MODE})" "$(basename "$WALLPAPER_PATH")"
fi

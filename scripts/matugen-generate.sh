#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 mugi (https://github.com/notmugi)
#
# Usage: matugen-generate.sh <light|dark> /path/to/image
# Generates a Material You scheme from $image and applies it to KDE + GTK +
# Firefox. Per-template post_hooks handle per-app integration.

set -euo pipefail

MODE="${1:-}"; IMAGE="${2:-}"

if [[ -z "$MODE" || -z "$IMAGE" ]]; then
    echo "Usage: $0 <light|dark> /path/to/image" >&2; exit 1
fi
if [[ "$MODE" != "light" && "$MODE" != "dark" ]]; then
    echo "Mode must be 'light' or 'dark' (got: $MODE)" >&2; exit 1
fi

WALLPAPER_PATH="$(realpath -- "$IMAGE")"
[[ -f "$WALLPAPER_PATH" ]] || { echo "File not found: $WALLPAPER_PATH" >&2; exit 1; }

LOG="$HOME/.cache/matugen-generate.log"
mkdir -p "$(dirname "$LOG")"

# Exported so per-template post_hooks (pywalfox, gtk4, …) can branch on mode.
export KATUGEN_MODE="$MODE"

{
    echo "==== $(date -Iseconds) | mode=$MODE | image=$WALLPAPER_PATH ===="

    # Wallpaper.
    command -v plasma-apply-wallpaperimage >/dev/null 2>&1 && \
        plasma-apply-wallpaperimage "$WALLPAPER_PATH" || true

    # Generate. --source-color-index 0 picks the most dominant color (by area)
    # and is non-interactive (no "multiple source colors" prompt).
    matugen image --mode "$MODE" --source-color-index 0 "$WALLPAPER_PATH"

    # KDE: bounce off the opposite Breeze so Plasma re-reads matugen.colors.
    if command -v plasma-apply-colorscheme >/dev/null 2>&1; then
        if [[ "$MODE" == "dark" ]]; then
            plasma-apply-colorscheme BreezeLight >/dev/null 2>&1 || true
        else
            plasma-apply-colorscheme BreezeDark  >/dev/null 2>&1 || true
        fi
        plasma-apply-colorscheme matugen || true
    fi

    # GTK light/dark preference.
    if command -v gsettings >/dev/null 2>&1; then
        gsettings set org.gnome.desktop.interface color-scheme "prefer-$MODE" || true
    fi

    # Firefox via pywalfox (also runs as a per-template post_hook; harmless
    # double-call. Requires `pywalfox install` once.)
    if command -v pywalfox >/dev/null 2>&1; then
        pywalfox update || true
        pywalfox "$MODE" || true
    fi

    echo "Done."
} >>"$LOG" 2>&1

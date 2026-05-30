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

# Apply-queue: per-template post_hooks just append to this file instead of
# running inline. We flush them in parallel below, so the ~30 hooks finish
# in one short burst rather than a 2-3s sequential stutter.
KATUGEN_QUEUE="$(mktemp -t katugen-queue.XXXXXX)"
export KATUGEN_QUEUE
trap 'rm -f "$KATUGEN_QUEUE" "${KATUGEN_QUEUE}.lock"' EXIT

# Path to the helper that handles each app. Honour XDG_DATA_HOME.
APPLY_DST="${XDG_DATA_HOME:-$HOME/.local/share}/katugen/template-apply.sh"

# How many apply jobs to run concurrently. nproc is a reasonable default;
# override with KATUGEN_PARALLEL=N for testing.
PARALLEL="${KATUGEN_PARALLEL:-$(command -v nproc >/dev/null 2>&1 && nproc || echo 4)}"

{
    echo "==== $(date -Iseconds) | mode=$MODE | image=$WALLPAPER_PATH ===="

    # Wallpaper.
    command -v plasma-apply-wallpaperimage >/dev/null 2>&1 && \
        plasma-apply-wallpaperimage "$WALLPAPER_PATH" || true

    # Generate. --source-color-index 0 picks the most dominant color (by area)
    # and is non-interactive (no "multiple source colors" prompt).
    matugen image --mode "$MODE" --source-color-index 0 "$WALLPAPER_PATH"

    # Flush the queued per-app applies in parallel. Each line is "<app>\t<mode>".
    if [ -s "$KATUGEN_QUEUE" ] && [ -x "$APPLY_DST" ]; then
        echo "-- flushing $(wc -l < "$KATUGEN_QUEUE") queued apply jobs (parallel=$PARALLEL)"
        # Tell the helper we're inside the flush so it actually runs the case
        # body instead of re-queueing.
        export KATUGEN_QUEUE_FLUSHING=1
        # xargs -P runs N workers in parallel, one queue line per invocation.
        # `tr` strips the tab so $1 = app, $2 = mode for the helper.
        tr '\t' ' ' < "$KATUGEN_QUEUE" \
            | xargs -P "$PARALLEL" -r -I{} bash -c 'set -- $1; "$0" "$@"' "$APPLY_DST" {} \
            || true
        unset KATUGEN_QUEUE_FLUSHING
    fi

    # KDE: force Plasma to re-read the regenerated matugen.colors file.
    # plasma-apply-colorscheme refuses to re-apply the "current" scheme, so
    # we clear the scheme name in kdeglobals first, then re-apply.
    if command -v plasma-apply-colorscheme >/dev/null 2>&1 && \
       command -v kwriteconfig6 >/dev/null 2>&1; then
        kwriteconfig6 --file kdeglobals --group General --key ColorScheme ""
        plasma-apply-colorscheme matugen || true
    fi

    # GTK light/dark preference.
    if command -v gsettings >/dev/null 2>&1; then
        gsettings set org.gnome.desktop.interface color-scheme "prefer-$MODE" || true
    fi

    # Firefox via pywalfox — the pywalfox post_hook (queued above) already
    # ran `pywalfox update && pywalfox $MODE`, so no need to repeat here.

    echo "Done."
} >>"$LOG" 2>&1

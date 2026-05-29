#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 mugi (https://github.com/notmugi)
# uninstall.sh — Remove katugen.
#
# Removes:
#   - generator script at    ~/.local/bin/matugen-generate.sh
#   - Dolphin service menu   ~/.local/share/kio/servicemenus/matugen-generate.desktop
#   - matugen config at      ~/.config/matugen/config.toml         (with --purge)
#   - installed templates    ~/.config/matugen/templates           (with --purge)
#
# By default the matugen config and templates are LEFT IN PLACE so you don't
# lose customizations. Pass --purge to remove them too.
#
# Generated outputs (e.g. ~/.local/share/color-schemes/matugen.colors) are
# never touched — delete those manually if you want a fully clean slate.

set -euo pipefail

PURGE=0
for a in "$@"; do
    case "$a" in
        --purge) PURGE=1 ;;
        -h|--help)
            sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "Unknown option: $a" >&2; exit 1 ;;
    esac
done

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

SCRIPT_DST="$HOME/.local/bin/matugen-generate.sh"
SERVICEMENU_DST="$XDG_DATA_HOME/kio/servicemenus/matugen-generate.desktop"
HELPER_DIR="$HOME/.local/share/katugen"
CONFIG_FILE="$XDG_CONFIG_HOME/matugen/config.toml"
TEMPLATES_DIR="$XDG_CONFIG_HOME/matugen/templates"

remove() {
    if [[ -e "$1" || -L "$1" ]]; then
        rm -rf -- "$1"
        echo "  removed: $1"
    else
        echo "  (skip)   $1  — not present"
    fi
}

echo "==> Uninstalling katugen"
remove "$SERVICEMENU_DST"
remove "$SCRIPT_DST"
remove "$HELPER_DIR"

if [[ $PURGE -eq 1 ]]; then
    remove "$CONFIG_FILE"
    remove "$TEMPLATES_DIR"
else
    echo "  (kept)   $CONFIG_FILE     — pass --purge to remove"
    echo "  (kept)   $TEMPLATES_DIR  — pass --purge to remove"
fi

if command -v kbuildsycoca6 >/dev/null 2>&1; then
    kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
elif command -v kbuildsycoca5 >/dev/null 2>&1; then
    kbuildsycoca5 --noincremental >/dev/null 2>&1 || true
fi

echo "Done."

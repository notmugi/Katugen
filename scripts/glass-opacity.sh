#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# glass-opacity — manage the persistent opacity used by Katugen's
# KWin Glass templates.
#
# The opacity is the first two hex digits of the TintColor (alpha channel,
# 00-ff). It's stored at ~/.config/katugen/glass.conf and consumed by
# template-apply.sh on every matugen run, so every future generation reuses
# whatever you set here.
#
# Usage:
#   glass-opacity              # show current value
#   glass-opacity get          # same as above
#   glass-opacity set <hex>    # set new value (2 hex digits) and apply now
#   glass-opacity reset        # back to default (90)
#   glass-opacity presets      # list named presets
#   glass-opacity <preset>     # apply a named preset (light/medium/strong/...)

set -euo pipefail

DEFAULT_OPACITY="90"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/katugen"
CONF_FILE="$CONF_DIR/glass.conf"
CACHED_THEME="$HOME/.cache/matugen/kwin-glass.conf"
KWINRC="$HOME/.config/kwinrc"

declare -A PRESETS=(
    [transparent]="33"   # ~20%
    [light]="66"         # ~40%
    [medium]="90"        # ~56% (default)
    [strong]="bf"        # ~75%
    [solid]="ff"         # 100%
)

die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*"; }

valid_hex() { [[ "$1" =~ ^[0-9a-fA-F]{2}$ ]]; }

read_opacity() {
    if [ -f "$CONF_FILE" ]; then
        local v
        v=$(grep -E '^OPACITY=' "$CONF_FILE" 2>/dev/null | tail -n1 | cut -d= -f2 | tr -d '[:space:]')
        if valid_hex "$v"; then
            printf '%s' "${v,,}"
            return
        fi
    fi
    printf '%s' "$DEFAULT_OPACITY"
}

write_opacity() {
    local val="${1,,}"
    mkdir -p "$CONF_DIR"
    cat > "$CONF_FILE" <<EOF
# Managed by glass-opacity. Two hex digits (00-ff). Default: $DEFAULT_OPACITY.
OPACITY=$val
EOF
}

percent_for() {
    local hex="$1"
    awk -v n="$((16#$hex))" 'BEGIN{ printf "%.0f", n*100/255 }'
}

# Re-apply the glass effect immediately using whatever color matugen
# last generated (or whatever is currently in kwinrc if no cache exists).
apply_now() {
    local opacity="$1" color="" raw=""

    if [ -f "$CACHED_THEME" ]; then
        raw=$(grep '^TintColor=' "$CACHED_THEME" | head -n1 | cut -d= -f2)
    fi

    if [ -z "$raw" ] && [ -f "$KWINRC" ]; then
        raw=$(awk '/^\[Effect-blurplus\]/{f=1;next} /^\[/{f=0} f && /^TintColor=/{print; exit}' "$KWINRC" | cut -d= -f2)
    fi

    if [ -n "$raw" ]; then
        # Strip leading '#' and optional placeholder/old opacity, keep RRGGBB.
        local stripped="${raw#\#}"
        stripped="${stripped/__OPACITY__/}"
        if [ "${#stripped}" -ge 6 ]; then
            color="${stripped: -6}"
        fi
    fi

    if [ -z "$color" ]; then
        info "no existing tint color found; opacity saved but nothing to re-apply yet."
        info "run matugen-generate (or right-click an image → Generate) to apply."
        return 0
    fi

    local tint="#${opacity}${color}"

    mkdir -p "$(dirname "$KWINRC")"
    touch "$KWINRC"
    if ! grep -q '^\[Effect-blurplus\]' "$KWINRC"; then
        printf '\n[Effect-blurplus]\n' >> "$KWINRC"
    fi
    if awk '/^\[Effect-blurplus\]/{f=1;next} /^\[/{f=0} f && /^TintColor=/{found=1} END{exit !found}' "$KWINRC"; then
        sed -i "/^\[Effect-blurplus\]/,/^\[/ s|^TintColor=.*|TintColor=$tint|" "$KWINRC"
    else
        sed -i "/^\[Effect-blurplus\]/a TintColor=$tint" "$KWINRC"
    fi

    if command -v qdbus >/dev/null 2>&1 && qdbus org.kde.KWin >/dev/null 2>&1; then
        local loaded
        loaded=$(qdbus org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded glass 2>/dev/null || echo false)
        [ "$loaded" = "false" ] && qdbus org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect glass >/dev/null 2>&1 || true
        qdbus org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect glass >/dev/null 2>&1 || true
    fi
    info "applied TintColor=$tint"
}

cmd_get() {
    local v; v=$(read_opacity)
    printf 'opacity = %s  (%s%%)\n' "$v" "$(percent_for "$v")"
}

cmd_set() {
    local v="${1:-}"
    [ -n "$v" ] || die "set requires a value (e.g. 'glass-opacity set bf')"
    v="${v#\#}"
    valid_hex "$v" || die "opacity must be 2 hex digits (00-ff), got: $v"
    write_opacity "$v"
    info "saved opacity=$v ($(percent_for "$v")%) → $CONF_FILE"
    apply_now "${v,,}"
}

cmd_reset() {
    cmd_set "$DEFAULT_OPACITY"
}

cmd_presets() {
    printf 'named presets:\n'
    for name in transparent light medium strong solid; do
        local v="${PRESETS[$name]}"
        printf '  %-12s %s  (%s%%)\n' "$name" "$v" "$(percent_for "$v")"
    done
}

usage() {
    sed -n '5,18p' "$0" | sed 's/^# \{0,1\}//'
}

main() {
    local sub="${1:-get}"; shift || true
    case "$sub" in
        ""|get)   cmd_get ;;
        set)      cmd_set "${1:-}" ;;
        reset)    cmd_reset ;;
        presets)  cmd_presets ;;
        -h|--help|help) usage ;;
        *)
            if [[ -v PRESETS[$sub] ]]; then
                cmd_set "${PRESETS[$sub]}"
            else
                die "unknown command: $sub (try: get, set <hex>, reset, presets, or a preset name)"
            fi
            ;;
    esac
}

main "$@"

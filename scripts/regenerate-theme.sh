#!/usr/bin/env bash
# regenerate-theme.sh — apply a new Material You scheme variant.
#
# Usage: regenerate-theme.sh <scheme>      e.g. scheme-tonal-spot
#
# Steps (in order; later steps only run if earlier ones succeed):
#   1. Re-run matugen against the current wallpaper with the chosen scheme.
#   2. Rewrite the default scheme in set-wallpaper.sh so future wallpaper
#      changes keep using it.
#   3. Restart Quickshell (detached) so every surface picks up the new colors.
#
# Does NOT set a wallpaper, write ~/.wa*.jpg, or touch the greeter.
#
# Env:
#   XEON_NO_RESTART=1   skip step 3 (useful when testing from a terminal)
set -euo pipefail

SCHEME="${1:?usage: regenerate-theme.sh <scheme>}"

# Scheme is interpolated into a sed expression below, so keep it strict.
if ! [[ "$SCHEME" =~ ^[a-z0-9-]+$ ]]; then
    echo "regenerate-theme.sh: invalid scheme name '$SCHEME'." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WALLPAPER_FILE="$SHELL_DIR/data/current-wallpaper.txt"
SET_WALLPAPER="$SCRIPT_DIR/set-wallpaper.sh"

# ── 1. Regenerate the theme ────────────────────────────────────────────
if ! command -v matugen >/dev/null 2>&1; then
    echo "regenerate-theme.sh: 'matugen' not found." >&2
    exit 1
fi

if [ ! -s "$WALLPAPER_FILE" ]; then
    echo "regenerate-theme.sh: wallpaper record '$WALLPAPER_FILE' is missing or empty." >&2
    exit 1
fi

WALLPAPER="$(tr -d '\r\n' < "$WALLPAPER_FILE")"

if [ -z "$WALLPAPER" ] || [ ! -f "$WALLPAPER" ]; then
    echo "regenerate-theme.sh: wallpaper image '$WALLPAPER' does not exist." >&2
    exit 1
fi

matugen image "$WALLPAPER" -m smart -t "$SCHEME" --source-color-index 0

# ── 2. Persist the scheme as set-wallpaper.sh's default ────────────────
if [ ! -f "$SET_WALLPAPER" ] || ! grep -qE '^SCHEME="\$\{3:-[^}]*\}"$' "$SET_WALLPAPER"; then
    echo "regenerate-theme.sh: could not find the SCHEME default line in '$SET_WALLPAPER'." >&2
    exit 1
fi
sed -i -E "s|^SCHEME=\"\\$\\{3:-[^}]*\\}\"\$|SCHEME=\"\${3:-$SCHEME}\"|" "$SET_WALLPAPER"

# ── 3. Restart Quickshell, detached ────────────────────────────────────
# This script is normally a child of the very qs process we are about to
# kill, so the restart runs in its own session after we have exited.
if [ "${XEON_NO_RESTART:-0}" = "1" ]; then
    echo "regenerate-theme.sh: XEON_NO_RESTART set, skipping Quickshell restart." >&2
    exit 0
fi

setsid -f bash -c '
    sleep 0.5
    qs kill -c xeon-shell 2>/dev/null || killall qs 2>/dev/null || true
    sleep 1
    exec qs -c xeon-shell
' >>/tmp/xeon-shell-restart.log 2>&1 </dev/null

exit 0

#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# paste-emoji.sh — Wayland emoji clipboard copy and context-aware paste
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

EMOJI="${1:-}"
TARGET_ADDR="${2:-}"
TARGET_CLASS="${3:-}"
PASTE_MODE="${4:-paste}"

if [ -z "$EMOJI" ]; then
    echo "Usage: $0 <emoji> [target_address|none] [target_class] [paste|copy-only]" >&2
    exit 1
fi

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell-emoji"
mkdir -p "$STATE_DIR"
LOG_FILE="$STATE_DIR/paste.log"

log_msg() {
    # Rotate log if it exceeds 50 KB to keep disk usage minimal
    if [ -f "$LOG_FILE" ] && [ "$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)" -gt 50000 ]; then
        tail -n 200 "$LOG_FILE" > "$LOG_FILE.tmp" 2>/dev/null && mv "$LOG_FILE.tmp" "$LOG_FILE"
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') [paste-emoji] $*" >> "$LOG_FILE"
}

# 1. Always copy to Wayland clipboard (redirect output so background pipes close cleanly)
printf '%s' "$EMOJI" | wl-copy >/dev/null 2>&1

# If copy-only requested, exit immediately
if [ "$PASTE_MODE" = "copy-only" ]; then
    log_msg "Copied '$EMOJI' to clipboard (copy-only mode requested)"
    exit 0
fi

# Case A2: Explicit sentinel 'none' passed by QML when window capture succeeded
# but found no active window (empty workspace/desktop). Copy only, never fall back.
if [ "$TARGET_ADDR" = "none" ]; then
    log_msg "Copied '$EMOJI' to clipboard; skipped paste (source=qml no-target, no active window focused)"
    exit 0
fi

# Helper: parse fields from hyprctl activewindow -j without jq, tolerating failures
get_active_field() {
    local field="$1"
    (hyprctl activewindow -j 2>/dev/null || echo '{}') | sed -n 's/.*"'"$field"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 || true
}

# Track target source: qml vs fallback
TARGET_SOURCE="qml"
if [ -z "$TARGET_ADDR" ] || [ "$TARGET_ADDR" = "null" ]; then
    TARGET_SOURCE="fallback"
    TARGET_ADDR="$(get_active_field address)"
    TARGET_CLASS="$(get_active_field class)"
fi

# If still no target window (empty workspace/desktop after fallback), do not attempt paste
if [ -z "$TARGET_ADDR" ] || [ "$TARGET_ADDR" = "{}" ]; then
    log_msg "Copied '$EMOJI' to clipboard; skipped paste (source=$TARGET_SOURCE, no active target window)"
    exit 0
fi

# Format address with '0x' prefix if missing
if [[ ! "$TARGET_ADDR" =~ ^0x ]]; then
    TARGET_ADDR="0x$TARGET_ADDR"
fi

# 2. Blocklist check (case-insensitive substring match)
# Avoid accidental paste in file managers or file browsers where Ctrl+V duplicates files
CLASS_LOWER=$(echo "$TARGET_CLASS" | tr '[:upper:]' '[:lower:]')
BLOCKLIST_REGEX="nautilus|thunar|org\.kde\.dolphin|pcmanfm|nemo"
if [[ "$CLASS_LOWER" =~ $BLOCKLIST_REGEX ]]; then
    log_msg "Copied '$EMOJI' to clipboard; skipped paste (source=$TARGET_SOURCE, class '$TARGET_CLASS' matched blocklist)"
    exit 0
fi

# 3. Floor delay & Focus restoration polling
# Environment Variables:
#   FOCUS_FLOOR_DELAY_MS (or FOCUS_RESTORE_DELAY_MS alias):
#     Small delay before beginning active window focus polling. Allows Hyprland compositor
#     time to unmap the layer-shell overlay surface and restore seat keyboard focus.
#   FOCUS_POLL_MAX_MS:
#     Maximum duration in milliseconds to poll for the target window to regain focus.
RAW_FLOOR="${FOCUS_FLOOR_DELAY_MS:-${FOCUS_RESTORE_DELAY_MS:-40}}"
if [[ "$RAW_FLOOR" =~ ^[0-9]+$ ]]; then
    FLOOR_DELAY_MS="$RAW_FLOOR"
else
    log_msg "WARNING: Invalid floor delay '$RAW_FLOOR'; falling back to default 40ms"
    FLOOR_DELAY_MS=40
fi

RAW_MAX="${FOCUS_POLL_MAX_MS:-300}"
if [[ "$RAW_MAX" =~ ^[0-9]+$ ]]; then
    MAX_MS="$RAW_MAX"
else
    log_msg "WARNING: Invalid max poll duration '$RAW_MAX'; falling back to default 300ms"
    MAX_MS=300
fi

if [ "$FLOOR_DELAY_MS" -gt 0 ]; then
    sleep "$(awk -v ms="$FLOOR_DELAY_MS" 'BEGIN { printf "%.3f", ms / 1000 }')"
fi

POLL_INTERVAL="0.015"
ELAPSED=0
REGAINED=0
CURRENT_ADDR=""
START_TIME_MS=$(date +%s%3N)

while [ "$ELAPSED" -lt "$MAX_MS" ]; do
    CURRENT_ADDR="$(get_active_field address)"
    if [ -n "$CURRENT_ADDR" ]; then
        if [[ ! "$CURRENT_ADDR" =~ ^0x ]]; then
            CURRENT_ADDR="0x$CURRENT_ADDR"
        fi
        if [ "$CURRENT_ADDR" = "$TARGET_ADDR" ]; then
            REGAINED=1
            break
        fi
    fi
    sleep "$POLL_INTERVAL"
    ELAPSED=$((ELAPSED + 15))
done

END_TIME_MS=$(date +%s%3N)
TOTAL_POLL_MS=$(( (END_TIME_MS - START_TIME_MS) + FLOOR_DELAY_MS ))

if [ "$REGAINED" -ne 1 ]; then
    log_msg "Copied '$EMOJI' to clipboard; skipped paste: target window $TARGET_ADDR never regained focus within ${MAX_MS}ms (source=$TARGET_SOURCE, last active: '$CURRENT_ADDR', poll=${TOTAL_POLL_MS}ms)"
    exit 0
fi

# 4. Determine correct paste shortcut (Terminal vs Standard GUI)
TERMINAL_REGEX="ghostty|kitty|foot|alacritty|wezterm|xterm|rxvt|konsole|gnome-terminal"
if [[ "$CLASS_LOWER" =~ $TERMINAL_REGEX ]]; then
    # Terminal paste from clipboard uses Ctrl+Shift+V
    MODS="CTRL,SHIFT"
    KEY="v"
else
    # Standard GUI app / text editor paste uses Ctrl+V
    MODS="CTRL"
    KEY="v"
fi

# 5. Dispatch keystroke via Hyprland Lua dispatcher and validate output is exactly 'ok'
DISPATCH_OUTPUT="$(hyprctl dispatch "hl.dsp.send_shortcut({ mods = '$MODS', key = '$KEY', window = 'address:$TARGET_ADDR' })" 2>&1 || true)"

if [ "$DISPATCH_OUTPUT" != "ok" ]; then
    log_msg "ERROR: hyprctl dispatch failed for window $TARGET_ADDR (mods=$MODS, key=$KEY, source=$TARGET_SOURCE, poll=${TOTAL_POLL_MS}ms): $DISPATCH_OUTPUT"
    exit 1
fi

log_msg "Successfully pasted '$EMOJI' into window $TARGET_ADDR ($TARGET_CLASS) via $MODS+$KEY (source=$TARGET_SOURCE, poll=${TOTAL_POLL_MS}ms)"

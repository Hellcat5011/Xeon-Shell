#!/usr/bin/env bash
# get-current-wallpaper.sh — detect currently active wallpaper path
# Usage: get-current-wallpaper.sh [daemon]
set -euo pipefail

DAEMON="${1:-}"

try_awww() {
    if command -v awww >/dev/null 2>&1; then
        local out
        out=$(awww query 2>/dev/null || true)
        if [ -n "$out" ]; then
            local path
            path=$(echo "$out" | grep -o "image: .*" | sed 's/image: //' | head -n 1)
            if [ -n "$path" ] && [ -f "$path" ]; then
                echo "$path"
                return 0
            fi
        fi
    fi
    return 1
}

try_swww() {
    if command -v swww >/dev/null 2>&1; then
        local out
        out=$(swww query 2>/dev/null || true)
        if [ -n "$out" ]; then
            local path
            path=$(echo "$out" | awk -F': ' '{print $2}' | head -n 1)
            if [ -n "$path" ] && [ -f "$path" ]; then
                echo "$path"
                return 0
            fi
        fi
    fi
    return 1
}

try_hyprpaper() {
    if command -v hyprctl >/dev/null 2>&1; then
        local out
        out=$(hyprctl hyprpaper listactive 2>/dev/null || true)
        if [ -n "$out" ]; then
            local path
            path=$(echo "$out" | awk -F' = ' '{print $2}' | head -n 1)
            if [ -n "$path" ] && [ -f "$path" ]; then
                echo "$path"
                return 0
            fi
        fi
    fi
    return 1
}

# 1. Try specified daemon
if [ "$DAEMON" = "awww" ]; then
    try_awww && exit 0
elif [ "$DAEMON" = "swww" ]; then
    try_swww && exit 0
elif [ "$DAEMON" = "hyprpaper" ]; then
    try_hyprpaper && exit 0
fi

# 2. Try any running daemon
try_awww && exit 0
try_swww && exit 0
try_hyprpaper && exit 0

# 3. Check data/current-wallpaper.txt
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TXT_FILE="$SCRIPT_DIR/../data/current-wallpaper.txt"
if [ -f "$TXT_FILE" ]; then
    txt_path=$(cat "$TXT_FILE" | tr -d '\r\n')
    if [ -n "$txt_path" ] && [ -f "$txt_path" ]; then
        echo "$txt_path"
        exit 0
    fi
fi

# 4. Check ~/.wa.jpg
if [ -f "$HOME/.wa.jpg" ]; then
    echo "$HOME/.wa.jpg"
    exit 0
fi

exit 1

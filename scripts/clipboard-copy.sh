#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# clipboard-copy.sh — Centralized wl-copy wrapper with lock-file suppression
# ─────────────────────────────────────────────────────────────────────────────
# Usage:
#   clipboard-copy.sh text           # reads text content from stdin
#   clipboard-copy.sh image <path>   # copies image from file path
#
# Creates a lock file BEFORE calling wl-copy so that the clipboard-add.sh
# watcher knows to skip the incoming event (it was self-initiated).
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

TYPE="${1:-}"
LOCK_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/qs-clipboard-self.lock"

if [ -z "$TYPE" ]; then
    echo "Usage: $0 text | $0 image <path>" >&2
    exit 1
fi

# Create the lock file BEFORE wl-copy so the watcher sees it
touch "$LOCK_FILE"

if [ "$TYPE" = "text" ]; then
    # Read content from stdin and pipe to wl-copy
    wl-copy
elif [ "$TYPE" = "image" ]; then
    IMAGE_PATH="${2:-}"
    if [ -z "$IMAGE_PATH" ]; then
        rm -f "$LOCK_FILE"
        echo "clipboard-copy.sh: image path required" >&2
        exit 1
    fi
    # Validate path exists and is a regular file
    if [ ! -f "$IMAGE_PATH" ]; then
        rm -f "$LOCK_FILE"
        echo "clipboard-copy.sh: file not found: $IMAGE_PATH" >&2
        exit 1
    fi
    wl-copy -t image/png < "$IMAGE_PATH"
else
    rm -f "$LOCK_FILE"
    echo "clipboard-copy.sh: unknown type '$TYPE'" >&2
    exit 1
fi

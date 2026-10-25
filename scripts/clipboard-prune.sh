#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# clipboard-prune.sh — Removes clipboard entries older than 24 hours
# ─────────────────────────────────────────────────────────────────────────────
# Runs in a loop (default every 15 minutes). Launched by clipboard-daemon.sh.
# Handles entries with and without the `timestamp` field (legacy entries
# without a timestamp are assigned age based on their `id` field which is
# epoch nanoseconds).
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

CACHE_DIR="$HOME/.cache/quickshell-clipboard"
IMAGE_DIR="$CACHE_DIR/images"
HISTORY_FILE="$CACHE_DIR/history.json"
PRUNE_INTERVAL="${QS_CLIPBOARD_PRUNE_INTERVAL:-900}"   # seconds (default 15 min)
MAX_AGE="${QS_CLIPBOARD_MAX_AGE:-86400}"                # seconds (default 24 hours)

prune_once() {
    # Nothing to prune if history doesn't exist
    if [ ! -s "$HISTORY_FILE" ]; then
        return
    fi

    local now
    now=$(date +%s)
    local cutoff=$(( now - MAX_AGE ))

    # Collect image paths of entries that will be pruned, then filter the JSON.
    # For entries without a `timestamp` field, derive it from `id` (epoch nanoseconds).
    local expired_images
    expired_images=$(jq -r --argjson cutoff "$cutoff" '
        [.[] | 
            # Derive effective timestamp: use .timestamp if present,
            # otherwise convert .id (epoch nanoseconds) to epoch seconds
            . + {_ts: (if .timestamp then .timestamp else ((.id | tonumber) / 1000000000 | floor) end)} |
            select(._ts < $cutoff) |
            select(.isImage == true) |
            .imagePath // empty
        ] | .[]
    ' "$HISTORY_FILE" 2>/dev/null || true)

    # Delete expired image files
    if [ -n "$expired_images" ]; then
        while IFS= read -r img_url; do
            local img_path="${img_url#file://}"
            # Safety: only delete files inside our image cache directory
            case "$img_path" in
                "$IMAGE_DIR"/*.png)
                    if [ -f "$img_path" ]; then
                        rm -f "$img_path"
                    fi
                    ;;
            esac
        done <<< "$expired_images"
    fi

    # Filter out expired entries from the JSON
    local new_json
    new_json=$(jq --argjson cutoff "$cutoff" '
        [.[] |
            . + {_ts: (if .timestamp then .timestamp else ((.id | tonumber) / 1000000000 | floor) end)} |
            select(._ts >= $cutoff) |
            del(._ts)
        ]
    ' "$HISTORY_FILE" 2>/dev/null || true)

    if [ -n "$new_json" ]; then
        echo "$new_json" > "${HISTORY_FILE}.tmp" && mv "${HISTORY_FILE}.tmp" "$HISTORY_FILE"
    fi
}

# ── Main loop ────────────────────────────────────────────────────────────────
while true; do
    prune_once
    sleep "$PRUNE_INTERVAL"
done

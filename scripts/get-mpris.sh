#!/usr/bin/env bash

# Use /tmp to cache last player and thumbnails
LAST_PLAYER_FILE="/tmp/quickshell_last_player"

update() {
    player=""
    for p in $(playerctl -l 2>/dev/null); do
        if [ "$(playerctl -p "$p" status 2>/dev/null)" = "Playing" ]; then
            player="$p"
            echo "$player" > "$LAST_PLAYER_FILE"
            break
        fi
    done
    
    # Fallback to the last playing app if current is paused
    if [ -z "$player" ]; then
        if [ -f "$LAST_PLAYER_FILE" ] && playerctl -l 2>/dev/null | grep -q "^$(cat "$LAST_PLAYER_FILE")$"; then
            player=$(cat "$LAST_PLAYER_FILE")
        else
            player=$(playerctl -l 2>/dev/null | head -n 1)
        fi
    fi

    if [ -z "$player" ]; then
        echo "{}"
        return
    fi
    
    status=$(playerctl -p "$player" status 2>/dev/null)
    if [ "$status" = "Stopped" ] || [ -z "$status" ]; then
        echo "{}"
        return
    fi
    
    # Wait slightly to avoid a race condition where the metadata event triggers before
    # the player has fully updated its DBus properties with the new track info
    sleep 0.1
    
    title=$(playerctl -p "$player" metadata title 2>/dev/null)
    artist=$(playerctl -p "$player" metadata artist 2>/dev/null)
    artUrl=$(playerctl -p "$player" metadata mpris:artUrl 2>/dev/null)
    
    # Handle local video files (e.g. mpv-mpris) by extracting a thumbnail
    if [[ "$artUrl" == file://* ]]; then
        local_path="${artUrl#file://}"
        mime=$(file -b --mime-type "$local_path" 2>/dev/null)
        if [[ "$mime" == video/* ]]; then
            hash=$(echo -n "$local_path" | md5sum | cut -d' ' -f1)
            thumb_path="/tmp/mpris_thumb_${hash}.jpg"
            if [ ! -f "$thumb_path" ]; then
                ffmpeg -y -i "$local_path" -ss 00:00:01.000 -vframes 1 "$thumb_path" 2>/dev/null
            fi
            artUrl="file://$thumb_path"
        fi
    fi
    
    position=$(playerctl -p "$player" position 2>/dev/null)
    length_us=$(playerctl -p "$player" metadata mpris:length 2>/dev/null)
    
    jq -n -c --arg status "$status" --arg title "$title" --arg artist "$artist" --arg artUrl "$artUrl" --arg player "$player" \
       --argjson position "${position:-0}" --argjson lengthUs "${length_us:-0}" \
       '{status: $status, title: $title, artist: $artist, artUrl: $artUrl, player: $player, position: $position, length: ($lengthUs / 1000000)}'
}

# ---------------------------------------------------------------------------
# Event loop
#
# The two `playerctl --follow` processes write into a FIFO; the main loop reads
# from it with a 1s timeout, which doubles as the fallback poll (no separate
# "tick" subshell needed).
#
# Cleanup guarantees:
#   1. trap on EXIT/INT/TERM/HUP kills exactly the children we started.
#   2. `setpriv --pdeathsig` makes the kernel signal each follower if this
#      script dies, even via SIGKILL (where traps cannot run).
#   3. The loop exits if the process that launched us (Quickshell) is gone.
# ---------------------------------------------------------------------------

PARENT_PID=$PPID
FIFO=$(mktemp -u /tmp/quickshell_mpris_fifo.XXXXXX)
mkfifo "$FIFO"
pids=()

cleanup() {
    trap - EXIT INT TERM HUP
    [ "${#pids[@]}" -gt 0 ] && kill "${pids[@]}" 2>/dev/null
    rm -f "$FIFO"
}
trap cleanup EXIT
trap 'exit 0' INT TERM HUP

# Open read+write so opening the FIFO never blocks and readers never see EOF
exec 3<>"$FIFO"

# Prefix that ties a child's lifetime to ours (falls back to nothing if the
# util-linux `setpriv` binary is missing)
guard=()
command -v setpriv >/dev/null 2>&1 && guard=(setpriv --pdeathsig TERM)

"${guard[@]}" stdbuf -oL playerctl metadata --follow --format 'trigger' >&3 2>/dev/null &
pids+=($!)
"${guard[@]}" stdbuf -oL playerctl status --follow >&3 2>/dev/null &
pids+=($!)

# Output initial state
update

while kill -0 "$PARENT_PID" 2>/dev/null; do
    # Returns on a playerctl event OR after 1s (fallback poll)
    read -r -t 1 -u 3 _
    update
done

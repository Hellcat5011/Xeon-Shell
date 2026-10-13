#!/bin/bash
# volume.sh: Volume control wrapper with 100% cap and OSD integration.
#
# Usage:
#   volume.sh +<step>   — Increase volume by <step> (e.g. +5)
#   volume.sh -<step>   — Decrease volume by <step> (e.g. -5)
#   volume.sh mute      — Toggle mute
#
# Hyprland keybind examples:
#   bind = , XF86AudioRaiseVolume, exec, ~/.config/quickshell/xeon-shell/scripts/volume.sh +5
#   bind = , XF86AudioLowerVolume, exec, ~/.config/quickshell/xeon-shell/scripts/volume.sh -5
#   bind = , XF86AudioMute,        exec, ~/.config/quickshell/xeon-shell/scripts/volume.sh mute

set -euo pipefail

MAX_VOLUME=100

get_volume() {
    wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{printf "%.0f", $2 * 100}'
}

get_muted() {
    wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q MUTED && echo 1 || echo 0
}

action="${1:-}"

case "$action" in
    +[0-9]*)
        step="${action#+}"
        current=$(get_volume)
        target=$((current + step))
        if [ "$target" -gt "$MAX_VOLUME" ]; then
            target=$MAX_VOLUME
        fi
        wpctl set-volume @DEFAULT_AUDIO_SINK@ "$(awk "BEGIN{printf \"%.2f\", $target/100}")"
        # Unmute on volume up
        wpctl set-mute @DEFAULT_AUDIO_SINK@ 0
        qs -c xeon-shell ipc call osd volume "$target" &
        ;;
    -[0-9]*)
        step="${action#-}"
        current=$(get_volume)
        target=$((current - step))
        if [ "$target" -lt 0 ]; then
            target=0
        fi
        wpctl set-volume @DEFAULT_AUDIO_SINK@ "$(awk "BEGIN{printf \"%.2f\", $target/100}")"
        qs -c xeon-shell ipc call osd volume "$target" &
        ;;
    mute)
        wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
        if [ "$(get_muted)" = "1" ]; then
            qs -c xeon-shell ipc call osd volume 0 &
        else
            vol=$(get_volume)
            qs -c xeon-shell ipc call osd volume "$vol" &
        fi
        ;;
    *)
        echo "Usage: volume.sh {+<step>|-<step>|mute}" >&2
        exit 1
        ;;
esac

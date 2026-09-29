#!/usr/bin/env bash
if ! command -v pactl >/dev/null 2>&1; then
    echo '{"sinks":[],"default":""}'
    exit 0
fi

sinks=$(pactl -f json list sinks 2>/dev/null || echo "[]")
default=$(pactl get-default-sink 2>/dev/null || echo "")

[ -z "$sinks" ] && sinks="[]"
jq -n --argjson sinks "$sinks" --arg def "$default" '{sinks: $sinks, default: $def}' 2>/dev/null || echo '{"sinks":[],"default":""}'

#!/usr/bin/env bash
# get-battery.sh — detect system battery and report capacity + charging state.
# Outputs a single line of JSON:
#   {"present":true,"percent":75,"charging":false}
#   {"present":false,"percent":0,"charging":false}

bat_path=""
for p in /sys/class/power_supply/BAT*; do
    [ -d "$p" ] && bat_path="$p" && break
done

if [ -z "$bat_path" ]; then
    echo '{"present":false,"percent":0,"charging":false}'
    exit 0
fi

percent=$(cat "$bat_path/capacity" 2>/dev/null || echo "0")
status=$(cat "$bat_path/status" 2>/dev/null || echo "Unknown")

charging=false
case "$status" in
    Charging|Full) charging=true ;;
esac

echo "{\"present\":true,\"percent\":$percent,\"charging\":$charging}"

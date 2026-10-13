#!/bin/bash

CACHE_FILE="/tmp/monitor_brightness"
BUS="4"
OPERATOR=$1
STEP=$2

# Initialize cache if it doesn't exist
if [ ! -f "$CACHE_FILE" ]; then
    ddcutil getvcp 10 -b $BUS | grep -oP 'current value =\s*\K\d+' > "$CACHE_FILE"
fi

CURRENT_VAL=$(cat "$CACHE_FILE")

if [ "$OPERATOR" = "+" ]; then
    NEW_VAL=$((CURRENT_VAL + STEP))
elif [ "$OPERATOR" = "-" ]; then
    NEW_VAL=$((CURRENT_VAL - STEP))
else
    exit 1
fi

if [ "$NEW_VAL" -gt 100 ]; then NEW_VAL=100; fi
if [ "$NEW_VAL" -lt 5 ]; then NEW_VAL=5; fi

echo "$NEW_VAL" > "$CACHE_FILE"

# trigger the SwayOSD UI
qs -c xeon-shell ipc call osd brightness $NEW_VAL
RATIO=$(awk -v v="$NEW_VAL" 'BEGIN { printf "%.2f", v/100 }')
# swayosd-client # --custom-icon display-brightness \
               # --custom-progress-text "Brightness: ${NEW_VAL}%" \
               # --custom-progress "$RATIO"

# Apply to monitor in the background
sleep 0.3 && ddcutil setvcp 10 $NEW_VAL -b $BUS > /dev/null 2>&1 &

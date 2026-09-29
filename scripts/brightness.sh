#!/bin/bash
# brightness.sh: Reusable functions for brightness control (laptop and external)

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/xeon-shell/idle-dim"
BUS_CACHE="$STATE_DIR/buses.txt"

# Laptop panel control
get_laptop() {
    if command -v brightnessctl &> /dev/null; then
        brightnessctl g
    fi
}

set_laptop() {
    if command -v brightnessctl &> /dev/null; then
        brightnessctl s "$1" -q
    fi
}

# External display control
get_external() {
    local bus="$1"
    ddcutil getvcp 10 -b "$bus" --terse 2>/dev/null | awk '{print $4}'
}

set_external() {
    local bus="$1"
    local val="$2"
    # Using --noverify halves the latency (avoids read-after-write check)
    ddcutil setvcp 10 "$val" -b "$bus" --noverify 2>/dev/null
}

# Generic setter for a future universal brightness slider
set_all() {
    local val="$1"
    set_laptop "$val%"
    if [ -f "$BUS_CACHE" ]; then
        while read -r bus; do
            set_external "$bus" "$val" &
        done < "$BUS_CACHE"
        wait
    fi
}

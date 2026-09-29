#!/bin/bash
# idle-dim-manager.sh: Handles dimming for laptop panels and external displays.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/brightness.sh"

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/xeon-shell/idle-dim"
mkdir -p "$STATE_DIR"

DIM_STATE="$STATE_DIR/dim_state.json"
DIM_ACTIVE="$STATE_DIR/is_dimmed"

# Dim values
LAPTOP_DIM=10
EXT_DIM=10

cache_displays() {
    mkdir -p "$STATE_DIR"
    # Extract valid I2C bus numbers (e.g. 4 from /dev/i2c-4)
    ddcutil detect 2>/dev/null | grep "I2C bus:" | awk -F'-' '{print $2}' > "$BUS_CACHE"
}

dim() {
    exec 200> "$STATE_DIR/dim.lock"
    flock -x 200 || exit 1

    # Don't double-dim if already dimmed
    if [ -f "$DIM_ACTIVE" ]; then
        exit 0
    fi
    
    LAPTOP_VAL=$(get_laptop)
    
    # Read external displays
    declare -A ext_vals
    if [ -f "$BUS_CACHE" ]; then
        while read -r bus; do
            val=$(get_external "$bus")
            if [ -n "$val" ]; then
                ext_vals["$bus"]="$val"
            fi
        done < "$BUS_CACHE"
    fi
    
    # Save state using jq safely
    local json="{}"
    json=$(jq -n --arg laptop "$LAPTOP_VAL" '{laptop: $laptop, valid: true}')
    for bus in "${!ext_vals[@]}"; do
        json=$(echo "$json" | jq --arg k "ext_$bus" --arg v "${ext_vals[$bus]}" '.[$k] = $v')
    done
    echo "$json" > "$DIM_STATE"
    
    touch "$DIM_ACTIVE"
    
    # Apply dimming
    set_laptop "$LAPTOP_DIM%"
    
    if [ -f "$BUS_CACHE" ]; then
        while read -r bus; do
            set_external "$bus" "$EXT_DIM" &
        done < "$BUS_CACHE"
        wait
    fi
}

restore() {
    echo "$(date): restore called" >> "$STATE_DIR/log.txt"
    exec 200> "$STATE_DIR/dim.lock"
    flock -x 200 || exit 1

    if [ ! -f "$DIM_ACTIVE" ] || [ ! -f "$DIM_STATE" ]; then
        exit 0
    fi
    
    LAPTOP_VAL=$(jq -r '.laptop' "$DIM_STATE")
    if [ "$LAPTOP_VAL" != "null" ] && [ -n "$LAPTOP_VAL" ]; then
        set_laptop "$LAPTOP_VAL"
    fi
    
    if [ -f "$BUS_CACHE" ]; then
        while read -r bus; do
            EXT_VAL=$(jq -r ".ext_$bus" "$DIM_STATE")
            if [ "$EXT_VAL" != "null" ] && [ -n "$EXT_VAL" ]; then
                set_external "$bus" "$EXT_VAL" &
            fi
        done < "$BUS_CACHE"
        wait
    fi
    
    rm -f "$DIM_ACTIVE" "$DIM_STATE"
}

startup_restore() {
    # If the shell crashed while dimmed, the DIM_ACTIVE flag will still exist.
    if [ -f "$DIM_ACTIVE" ]; then
        restore
    fi
}

case "$1" in
    cache-displays)
        cache_displays
        ;;
    dim)
        dim
        ;;
    restore)
        restore
        ;;
    startup-restore)
        startup_restore
        ;;
    *)
        echo "Usage: $0 {cache-displays|dim|restore|startup-restore}"
        exit 1
        ;;
esac

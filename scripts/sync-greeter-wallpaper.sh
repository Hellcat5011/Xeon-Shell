#!/bin/bash
# sync-greeter-wallpaper.sh
# Copies the current wallpaper to the greeter's state directory.
# Runs as the normal user without sudo.

STATE_DIR="${GREETER_STATE_DIR:-/var/lib/greetd/quickshell-greeter}"
WALLPAPER="$HOME/.wa.jpg"

if [ ! -d "$STATE_DIR" ] || [ ! -w "$STATE_DIR" ]; then
    echo "NOTICE: Target directory $STATE_DIR does not exist or is not writable." >&2
    echo "Greeter sync skipped. (Complete privileged setup and log in again to enable)." >&2
    exit 0
fi

if [ ! -f "$WALLPAPER" ]; then
    echo "NOTICE: Wallpaper file $WALLPAPER not found. Greeter will use default theme background." >&2
    exit 0
fi

if ! cp "$WALLPAPER" "$STATE_DIR/wallpaper.jpg"; then
    echo "ERROR: Failed to copy wallpaper to $STATE_DIR" >&2
    exit 1
fi

chmod 644 "$STATE_DIR/wallpaper.jpg"
echo "Greeter wallpaper updated."

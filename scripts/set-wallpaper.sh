#!/usr/bin/env bash
# set-wallpaper.sh — set the wallpaper, then regenerate the Material You
# theme so the launcher's colors follow it.
#
# Usage: set-wallpaper.sh /path/to/image.jpg [daemon] [scheme]
# Called automatically by WallpaperSelector.qml — you generally don't
# need to run this by hand, but it's a plain script so you can.
set -euo pipefail

WALLPAPER="${1:?usage: set-wallpaper.sh <image path> [daemon] [scheme]}"
DAEMON="${2:-awww}"
SCHEME="${3:-scheme-smart}"

if [ "$DAEMON" = "awww" ]; then
  if ! command -v awww >/dev/null 2>&1; then
    echo "set-wallpaper.sh: 'awww' not found." >&2
    exit 1
  fi
  awww img "$WALLPAPER" --transition-type random --transition-duration 1 --transition-fps 60
elif [ "$DAEMON" = "swww" ]; then
  if ! command -v swww >/dev/null 2>&1; then
    echo "set-wallpaper.sh: 'swww' not found." >&2
    exit 1
  fi
  swww img "$WALLPAPER" --transition-type random --transition-duration 1 --transition-fps 60
elif [ "$DAEMON" = "hyprpaper" ]; then
  if ! command -v hyprctl >/dev/null 2>&1; then
    echo "set-wallpaper.sh: 'hyprctl' not found." >&2
    exit 1
  fi
  # hyprpaper requires preload and wallpaper commands
  hyprctl hyprpaper preload "$WALLPAPER"
  for monitor in $(hyprctl monitors -j | jq -r '.[].name'); do
    hyprctl hyprpaper wallpaper "$monitor,$WALLPAPER"
  done
else
  echo "set-wallpaper.sh: unknown daemon '$DAEMON'" >&2
  exit 1
fi

# Detect primary monitor width for resolution-adaptive sizing
SCREEN_W=$(hyprctl monitors -j 2>/dev/null | jq -r '.[0].width // empty' 2>/dev/null)
SCREEN_W="${SCREEN_W:-1920}"
THUMB_W=$((SCREEN_W * 50 / 100))

if command -v magick >/dev/null 2>&1; then
  # Lockscreen wallpaper at monitor resolution (only downscale, never upscale)
  magick "$WALLPAPER" -resize "${SCREEN_W}x>" -quality 95 "$HOME/.wa.jpg"
  # App launcher thumbnail
  magick "$WALLPAPER" -resize "${THUMB_W}x>" -quality 90 "$HOME/.wa-thumb.jpg"
else
  cp "$WALLPAPER" "$HOME/.wa.jpg"
  cp "$WALLPAPER" "$HOME/.wa-thumb.jpg"
fi

if command -v matugen >/dev/null 2>&1; then
  # Regenerates every template configured in ~/.config/matugen/config.toml,
  # including data/colors.json that Theme.qml is watching.
  matugen image "$WALLPAPER" -m dark -t "$SCHEME" --source-color-index 0
  
  # Save the current wallpaper path for the App Launcher
  echo "$WALLPAPER" > "$(dirname "$0")/../data/current-wallpaper.txt"
  
  # Tell Quickshell to reload the theme (avoids polling)
  qs -c xeon-shell ipc call theme reload || true
else
  echo "set-wallpaper.sh: 'matugen' not found, theme not regenerated." >&2
  exit 1
fi

# Push current wallpaper + config snapshot to the greeter's /var/lib
# state dir so the greeter follows the desktop. Best-effort: a failure
# here must not prevent the wallpaper from having been set.
SYNC_SCRIPT="$(dirname "$0")/sync-greeter-wallpaper.sh"
if [ -x "$SYNC_SCRIPT" ]; then
    if ! bash "$SYNC_SCRIPT"; then
        echo "set-wallpaper.sh: greeter sync failed (see above)" >&2
    fi
fi

#!/bin/bash
# gen-wallpaper-thumbs.sh — generate cached thumbnails for the wallpaper selector.
# Outputs "original_path|thumb_path" lines for each wallpaper found.
# Thumbnails are cached in ~/.cache/xeon-shell/thumbs/ and regenerated
# only when the source image is newer than the cached thumbnail.
# Orphaned thumbnails (from deleted source images) are cleaned up automatically.
set -euo pipefail

WALLPAPER_DIR="${1:?usage: gen-wallpaper-thumbs.sh <wallpaper_dir>}"

CACHE_DIR="$HOME/.cache/xeon-shell/thumbs"
mkdir -p "$CACHE_DIR"

# Resolution-adaptive thumbnail width (~35% of primary monitor)
SCREEN_W=$(hyprctl monitors -j 2>/dev/null | jq -r '.[0].width // empty' 2>/dev/null)
SCREEN_W="${SCREEN_W:-1920}"
THUMB_W=$((SCREEN_W * 35 / 100))

HAS_MAGICK=false
command -v magick >/dev/null 2>&1 && HAS_MAGICK=true

# Collect all wallpaper paths
mapfile -t IMAGES < <(find "$WALLPAPER_DIR" -maxdepth 1 -type f \
  \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \
  -o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.svg' -o -iname '*.avif' \
  -o -iname '*.heic' -o -iname '*.heif' -o -iname '*.jxl' -o -iname '*.tiff' \) \
  2>/dev/null || true)

[ "${#IMAGES[@]}" -eq 0 ] && exit 0

# Track valid thumbnail filenames for orphan cleanup
declare -A VALID_THUMBS

# Generate missing/stale thumbnails in parallel
for img in "${IMAGES[@]}"; do
  hash=$(echo -n "$img" | md5sum | cut -d' ' -f1)
  VALID_THUMBS["${hash}.jpg"]=1
  if $HAS_MAGICK; then
    thumb="$CACHE_DIR/${hash}.jpg"
    if [ ! -f "$thumb" ] || [ "$img" -nt "$thumb" ]; then
      magick "$img" -resize "${THUMB_W}x>" -quality 85 "$thumb" 2>/dev/null &
    fi
  fi
done
wait

# Remove orphaned thumbnails from deleted source images
for cached in "$CACHE_DIR"/*.jpg; do
  [ -f "$cached" ] || continue
  name=$(basename "$cached")
  if [ -z "${VALID_THUMBS[$name]+x}" ]; then
    rm -f "$cached"
  fi
done

# Output original|thumb pairs
for img in "${IMAGES[@]}"; do
  hash=$(echo -n "$img" | md5sum | cut -d' ' -f1)
  thumb="$CACHE_DIR/${hash}.jpg"
  if [ -f "$thumb" ]; then
    echo "${img}|${thumb}"
  else
    echo "${img}|${img}"
  fi
done

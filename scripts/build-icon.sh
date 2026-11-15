#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SOURCE="$ROOT/Assets/AppIcon.svg"
OUTPUT="$ROOT/Assets/AppIcon.icns"

command -v rsvg-convert >/dev/null 2>&1 || {
  echo "rsvg-convert is required to rebuild the icon (install librsvg)." >&2
  exit 1
}
command -v iconutil >/dev/null 2>&1 || {
  echo "iconutil is required to rebuild the icon." >&2
  exit 1
}

ICONSET=$(mktemp -d "${TMPDIR:-/tmp}/gh-inbox-iconset.XXXXXX")
trap 'rm -rf "$ICONSET"' EXIT INT TERM
mkdir -p "$ICONSET/AppIcon.iconset"

render() {
  rsvg-convert -w "$2" -h "$2" "$SOURCE" -o "$ICONSET/AppIcon.iconset/$1"
}

render icon_16x16.png 16
render icon_16x16@2x.png 32
render icon_32x32.png 32
render icon_32x32@2x.png 64
render icon_128x128.png 128
render icon_128x128@2x.png 256
render icon_256x256.png 256
render icon_256x256@2x.png 512
render icon_512x512.png 512
render icon_512x512@2x.png 1024

iconutil -c icns "$ICONSET/AppIcon.iconset" -o "$OUTPUT"
rsvg-convert -w 1024 -h 1024 "$SOURCE" -o "$ROOT/Assets/AppIcon.png"
printf '%s\n' "$OUTPUT"

#!/bin/zsh
# Regenerates Resources/AppIcon.icns and the Xcode AppIcon set from scripts/make_icon.swift.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RES="$ROOT/Resources"
MASTER="$RES/AppIcon-1024.png"
ICONSET="$ROOT/build/AppIcon.iconset"
rm -rf "$ICONSET"
APPICONSET="$ROOT/Assets.xcassets/AppIcon.appiconset"

mkdir -p "$RES" "$ICONSET" "$APPICONSET"
swift "$ROOT/scripts/make_icon.swift" "$MASTER"

for size in 16 32 128 256 512; do
  double=$((size * 2))
  sips -z $size $size "$MASTER" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $double $double "$MASTER" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$RES/AppIcon.icns"
cp "$ICONSET"/*.png "$APPICONSET/"

cat > "$APPICONSET/Contents.json" << 'JSON'
{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

echo "Wrote $RES/AppIcon.icns"

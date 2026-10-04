#!/bin/zsh
set -euo pipefail

# Finder uses this for the disk image file and the mounted volume.
stamp_icon() {
  ICON="$ICON" TARGET="$TARGET" swift -e '
import AppKit
let env = ProcessInfo.processInfo.environment
guard let image = NSImage(contentsOfFile: env["ICON"] ?? "") else {
  fputs("missing icon\n", stderr)
  exit(1)
}
let ok = NSWorkspace.shared.setIcon(image, forFile: env["TARGET"] ?? "", options: [])
if !ok { exit(1) }
'
}

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/PhotoFlow.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"

rm -rf "$DIST"
mkdir -p "$MACOS" "$RES"

cat > "$APP/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>PhotoFlow</string>
	<key>CFBundleExecutable</key>
	<string>PhotoFlow</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>com.photoflow.app</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>PhotoFlow</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>CFBundleLocalizations</key>
	<array>
		<string>en</string>
		<string>zh-Hans</string>
	</array>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.photography</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
PLIST

echo "APPL????" > "$APP/Contents/PkgInfo"

if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
  "$ROOT/scripts/make_icon.sh"
fi
cp "$ROOT/Resources/AppIcon.icns" "$RES/AppIcon.icns"
# Empty .lproj folders let AppKit translate its own menu items (Edit, Window…).
mkdir -p "$RES/en.lproj" "$RES/zh-Hans.lproj"

echo "Compiling PhotoFlow…"
# Package.swift is the only list of sources and frameworks; build for this Mac's architecture.
swift build --package-path "$ROOT" -c release
cp "$(swift build --package-path "$ROOT" -c release --show-bin-path)/PhotoFlow" "$MACOS/PhotoFlow"

codesign --force --deep --sign - "$APP" >/dev/null
echo "Built $APP"

DMG="$DIST/PhotoFlow.dmg"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
STAGE="$WORK/stage"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/PhotoFlow.app"
ln -s /Applications "$STAGE/Applications"

# A writable image so the mounted volume can carry the app icon, then compress it.
RW="$WORK/PhotoFlow-rw.dmg"
hdiutil create -volname "PhotoFlow" -srcfolder "$STAGE" -ov -format UDRW "$RW" >/dev/null
MOUNT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | sed -n 's/.*\(\/Volumes\/.*\)/\1/p' | tail -1)"
ICON="$RES/AppIcon.icns" TARGET="$MOUNT" stamp_icon
hdiutil detach "$MOUNT" >/dev/null
hdiutil convert "$RW" -format UDZO -ov -o "$DMG" >/dev/null
ICON="$RES/AppIcon.icns" TARGET="$DMG" stamp_icon
echo "Built $DMG"

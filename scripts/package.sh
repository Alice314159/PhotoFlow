#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/PhotoFlow.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"
SDK="$(xcrun --show-sdk-path)"

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
	<key>CFBundleIconName</key>
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
xcrun swiftc -parse-as-library \
  -O \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -framework SwiftUI \
  -framework AppKit \
  -framework Combine \
  -framework ImageIO \
  -framework Vision \
  -framework CoreLocation \
  -lsqlite3 \
  "$ROOT/PhotoFlowApp.swift" \
  "$ROOT"/Models/*.swift \
  "$ROOT"/Services/*.swift \
  "$ROOT"/ViewModels/*.swift \
  "$ROOT"/Views/*.swift \
  -o "$MACOS/PhotoFlow"

codesign --force --deep --sign - "$APP" >/dev/null
echo "Built $APP"

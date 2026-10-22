#!/bin/bash
# Builds Kirpik.app. Usage:
#   ./build.sh            -> build/Kirpik.app
#   ./build.sh --install  -> installs to /Applications/Kirpik.app and launches it
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Kirpik"
BUNDLE_ID="com.erenoz.kirpik"
APP="build/$APP_NAME.app"

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

# AppIcons/AppIcon.appiconset -> AppIcon.icns (iconutil only accepts the .iconset extension)
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
cp AppIcons/AppIcon.appiconset/icon_*.png "$ICONSET/"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature. Every rebuild changes it, so Screen Recording permission must be granted again.
codesign --force --deep --sign - "$APP"
echo "Built: $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x "$APP_NAME" 2>/dev/null || true
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" /Applications/
    # The old permission no longer matches the new signature; reset it so macOS asks cleanly again.
    tccutil reset ScreenCapture "$BUNDLE_ID" >/dev/null 2>&1 || true
    open "/Applications/$APP_NAME.app"
    echo "Installed and launched: /Applications/$APP_NAME.app"
fi

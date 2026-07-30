#!/bin/bash
# Builds ContextDock.app from the SwiftPM release binary.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/ContextDock.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ContextDockApp "$APP/Contents/MacOS/ContextDock"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>ContextDock</string>
    <key>CFBundleIdentifier</key><string>com.contextdock.app</string>
    <key>CFBundleName</key><string>ContextDock</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
PLIST
codesign --force --sign - "$APP" 2>/dev/null || true
echo "Built $APP"

#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/Klasör Panosu.app"
mkdir -p "$APP/Contents/MacOS"
xcrun swiftc -swift-version 5 -O -framework AppKit -framework ServiceManagement "$ROOT/Source/main.swift" -o "$APP/Contents/MacOS/KlasorPanosu"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>KlasorPanosu</string>
<key>CFBundleIdentifier</key><string>com.wabp.klasorpanosu</string>
<key>CFBundleName</key><string>Klasör Panosu</string>
<key>CFBundleDisplayName</key><string>Klasör Panosu</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.4.1</string>
<key>CFBundleVersion</key><string>7</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppleEventsUsageDescription</key><string>Finder’da açtığın klasörleri son kullanılanlar listesine eklemek için Finder erişimi gerekir.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/KlasorPanosu" --self-test
printf 'Uygulama hazır: %s\n' "$APP"

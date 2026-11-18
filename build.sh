#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/Foldy.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
ICONSET="$ROOT/Assets/Foldy.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ROOT/Assets/Foldy.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$ROOT/Assets/Foldy.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Foldy.icns"
cp "$ROOT/Assets/FoldyMenu.png" "$APP/Contents/Resources/FoldyMenu.png"
mkdir -p "$ROOT/work/build"
for arch in arm64 x86_64; do
  xcrun swiftc -target "${arch}-apple-macos13.0" -swift-version 5 -O -framework AppKit -framework ServiceManagement "$ROOT/Source/main.swift" -o "$ROOT/work/build/Foldy-$arch"
done
lipo -create "$ROOT/work/build/Foldy-arm64" "$ROOT/work/build/Foldy-x86_64" -output "$APP/Contents/MacOS/Foldy"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Foldy</string>
<key>CFBundleIdentifier</key><string>com.wabp.klasorpanosu</string>
<key>CFBundleName</key><string>Foldy</string>
<key>CFBundleDisplayName</key><string>Foldy</string>
<key>CFBundleIconFile</key><string>Foldy.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.5.1</string>
<key>CFBundleVersion</key><string>9</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppleEventsUsageDescription</key><string>Finder’da açtığın klasörleri son kullanılanlar listesine eklemek için Finder erişimi gerekir.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/Foldy" --self-test
printf 'Uygulama hazır: %s\n' "$APP"

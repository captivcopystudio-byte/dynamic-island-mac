#!/usr/bin/env bash
# Builds "Dynamic Island.app" into ./build using only the Xcode Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Dynamic Island"
BUNDLE_ID="com.opensource.dynamicisland"
VERSION="${VERSION:-1.0.0}"
APP="build/${APP_NAME}.app"

echo "==> Compiling (release, arm64)"
swift build -c release --arch arm64

echo "==> Assembling ${APP}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --arch arm64 --show-bin-path)/DynamicIsland" "$APP/Contents/MacOS/DynamicIsland"

echo "==> Building media bridge (browser / YouTube / any-app audio)"
clang -dynamiclib -fobjc-arc -O2 -arch arm64 -mmacosx-version-min=14.0 -framework Foundation \
  -o "$APP/Contents/Resources/MediaRemoteAdapter.dylib" bridge/MediaRemoteAdapter.m
cp bridge/mr-bridge.pl "$APP/Contents/Resources/mr-bridge.pl"
codesign --force --sign - "$APP/Contents/Resources/MediaRemoteAdapter.dylib"

echo "==> Rendering icon"
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
swift scripts/make-icon.swift build/icon-1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleExecutable</key><string>DynamicIsland</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>Dynamic Island uses Apple Events to show and control what's playing in Music and Spotify.</string>
</dict>
</plist>
PLIST

echo "==> Signing (ad-hoc)"
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"

echo "==> Done: $APP"

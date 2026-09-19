#!/bin/bash
# Builds WifiShow and assembles a universal .app bundle, ad-hoc signed.
set -euo pipefail
cd "$(dirname "$0")"

APP="WifiShow.app"
ID="com.henrico.wifishow"
VERSION="1.0.0"
MIN_MACOS="14.0"
SRC=(Sources/Model.swift Sources/Scanner.swift Sources/Details.swift
     Sources/SpeedTest.swift Sources/Views.swift Sources/ViewsDetail.swift
     Sources/App.swift)
FRAMEWORKS=(-framework SwiftUI -framework AppKit -framework Charts
            -framework CoreWLAN -framework CoreLocation)

command -v swiftc >/dev/null || {
  echo "error: swiftc not found. Install the Command Line Tools:"
  echo "      xcode-select --install"
  exit 1
}

rm -rf "$APP" .build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build

echo "› building arm64..."
swiftc -O -swift-version 5 -target arm64-apple-macos$MIN_MACOS \
  "${SRC[@]}" -o .build/WifiShow-arm64 "${FRAMEWORKS[@]}"

echo "› building x86_64..."
swiftc -O -swift-version 5 -target x86_64-apple-macos$MIN_MACOS \
  "${SRC[@]}" -o .build/WifiShow-x86_64 "${FRAMEWORKS[@]}"

echo "› merging into universal binary..."
lipo -create .build/WifiShow-arm64 .build/WifiShow-x86_64 \
     -output "$APP/Contents/MacOS/WifiShow"

[ -f Resources/WifiShow.icns ] && cp Resources/WifiShow.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string></array>
  <key>CFBundleName</key><string>WifiShow</string>
  <key>CFBundleDisplayName</key><string>WifiShow</string>
  <key>CFBundleIdentifier</key><string>$ID</string>
  <key>CFBundleExecutable</key><string>WifiShow</string>
  <key>CFBundleIconFile</key><string>WifiShow</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
  <key>NSLocationWhenInUseUsageDescription</key><string>macOS requires location permission to reveal the name (SSID) and address (BSSID) of nearby Wi-Fi networks. No data ever leaves your Mac.</string>
  <key>NSLocationUsageDescription</key><string>macOS requires location permission to reveal the name (SSID) and address (BSSID) of nearby Wi-Fi networks. No data ever leaves your Mac.</string>
</dict></plist>
PLIST

echo "› signing (ad-hoc)..."
codesign --force --sign - --identifier "$ID" "$APP"

rm -rf .build
echo "✓ $APP  ($(lipo -archs "$APP/Contents/MacOS/WifiShow"))"

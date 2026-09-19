#!/bin/bash
# Compila o WifiShow e monta o bundle .app universal, assinado ad-hoc.
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
  echo "erro: swiftc nao encontrado. Instale as Command Line Tools:"
  echo "      xcode-select --install"
  exit 1
}

rm -rf "$APP" .build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build

echo "› compilando arm64..."
swiftc -O -swift-version 5 -target arm64-apple-macos$MIN_MACOS \
  "${SRC[@]}" -o .build/WifiShow-arm64 "${FRAMEWORKS[@]}"

echo "› compilando x86_64..."
swiftc -O -swift-version 5 -target x86_64-apple-macos$MIN_MACOS \
  "${SRC[@]}" -o .build/WifiShow-x86_64 "${FRAMEWORKS[@]}"

echo "› unindo em binario universal..."
lipo -create .build/WifiShow-arm64 .build/WifiShow-x86_64 \
     -output "$APP/Contents/MacOS/WifiShow"

[ -f Resources/WifiShow.icns ] && cp Resources/WifiShow.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
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
  <key>NSLocationWhenInUseUsageDescription</key><string>O macOS exige permissao de localizacao para revelar o nome (SSID) e o endereco (BSSID) das redes Wi-Fi proximas. Nenhum dado sai do seu Mac.</string>
  <key>NSLocationUsageDescription</key><string>O macOS exige permissao de localizacao para revelar o nome (SSID) e o endereco (BSSID) das redes Wi-Fi proximas. Nenhum dado sai do seu Mac.</string>
</dict></plist>
PLIST

echo "› assinando (ad-hoc)..."
codesign --force --sign - --identifier "$ID" "$APP"

rm -rf .build
echo "✓ $APP  ($(lipo -archs "$APP/Contents/MacOS/WifiShow"))"

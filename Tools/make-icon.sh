#!/bin/bash
# Regenera Resources/WifiShow.icns a partir de Tools/MakeIcon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
cp Tools/MakeIcon.swift "$tmp/main.swift"
swiftc -O "$tmp/main.swift" -o "$tmp/run" -framework AppKit
"$tmp/run" "$tmp"
iconutil -c icns "$tmp/WifiShow.iconset" -o Resources/WifiShow.icns
cp "$tmp/icon-preview.png" Resources/icon-preview.png
echo "✓ Resources/WifiShow.icns"

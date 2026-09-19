#!/bin/bash
# WifiShow test suite. Requires no network and no permissions.
set -euo pipefail
cd "$(dirname "$0")"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

echo "▸ Channel plan (primary channel -> carrier center)"
mkdir -p "$tmp/plan"
cp Tests/ChannelPlanTests.swift "$tmp/plan/main.swift"
swiftc -swift-version 5 Sources/Model.swift "$tmp/plan/main.swift" \
  -o "$tmp/plan/run" -framework CoreWLAN
"$tmp/plan/run" || fail=1

echo
echo "▸ networkquality parsing"
mkdir -p "$tmp/speed"
cp Tests/SpeedTestParsing.swift "$tmp/speed/main.swift"
swiftc -swift-version 5 Sources/SpeedTest.swift "$tmp/speed/main.swift" \
  -o "$tmp/speed/run"
"$tmp/speed/run" Tests/fixtures-networkquality.json || fail=1

echo
[ $fail -eq 0 ] && echo "✓ full suite passed" || { echo "✗ failures detected"; exit 1; }

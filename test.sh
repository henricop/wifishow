#!/bin/bash
# Suite de testes do WifiShow. Nao precisa de rede nem de permissoes.
set -euo pipefail
cd "$(dirname "$0")"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

echo "▸ Plano de canais (canal primario -> centro da portadora)"
mkdir -p "$tmp/plan"
cp Tests/ChannelPlanTests.swift "$tmp/plan/main.swift"
swiftc -swift-version 5 Sources/Model.swift "$tmp/plan/main.swift" \
  -o "$tmp/plan/run" -framework CoreWLAN
"$tmp/plan/run" || fail=1

echo
echo "▸ Parsing do networkquality"
mkdir -p "$tmp/speed"
cp Tests/SpeedTestParsing.swift "$tmp/speed/main.swift"
swiftc -swift-version 5 Sources/SpeedTest.swift "$tmp/speed/main.swift" \
  -o "$tmp/speed/run"
"$tmp/speed/run" Tests/fixtures-networkquality.json || fail=1

echo
[ $fail -eq 0 ] && echo "✓ suite completa passou" || { echo "✗ houve falhas"; exit 1; }

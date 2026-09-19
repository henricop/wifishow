#!/bin/bash
# Valida a matematica de canal/frequencia contra redes reais conhecidas.
set -euo pipefail
cd "$(dirname "$0")"
tmp=$(mktemp -d)
cp Tests/ChannelPlanTests.swift "$tmp/main.swift"
swiftc -swift-version 5 Sources/Model.swift "$tmp/main.swift" -o "$tmp/run" -framework CoreWLAN
"$tmp/run"

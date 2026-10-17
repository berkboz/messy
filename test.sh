#!/bin/bash
# Compiles the app's logic files with Tests/main.swift and runs the checks.
set -euo pipefail
cd "$(dirname "$0")"
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
S=Sources/Temiz
if ! swiftc -O -o "$OUT/tests" \
  $S/Util.swift $S/Theme.swift $S/DesignSystem.swift $S/Sounds.swift $S/Clutter.swift $S/ClutterView.swift $S/Security.swift $S/Threats.swift $S/Uninstall.swift $S/Updates.swift \
  Tests/main.swift 2>"$OUT/log"; then
  grep -E 'error' "$OUT/log"; exit 1
fi
"$OUT/tests"

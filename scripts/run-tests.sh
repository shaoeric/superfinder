#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SDK="$(xcrun --show-sdk-path)"
SWIFTC="$(xcrun --find swiftc)"
TARGET="arm64-apple-macos13.0"
BUILD="$ROOT/build"
mkdir -p "$BUILD/.module-cache" "$BUILD/.test-tmp"

"$SWIFTC" -O -sdk "$SDK" -target "$TARGET" -swift-version 5 \
  -module-cache-path "$BUILD/.module-cache" \
  Sources/Shared/AppConfig.swift \
  Sources/Shared/Command.swift \
  Sources/Shared/CommandStore.swift \
  Sources/Shared/PathFormatter.swift \
  Sources/Shared/CutBufferStore.swift \
  Sources/Shared/MenuModel.swift \
  Sources/Shared/MoveEngine.swift \
  Tests/main.swift \
  -o "$BUILD/superfinder-tests"

"$BUILD/superfinder-tests"

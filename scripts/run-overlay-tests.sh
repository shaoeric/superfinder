#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Offline renderer test: builds a synthetic 2x "display" and renders the real
# CaptureOverlayView layer tree. It needs no screen-recording permission and
# catches annotation/selection coordinate regressions.
SDK="$(xcrun --show-sdk-path)"
SWIFTC="$(xcrun --find swiftc)"
BUILD="$ROOT/build/overlay-fixture"
mkdir -p "$BUILD/.module-cache"

"$SWIFTC" -O -sdk "$SDK" -target arm64-apple-macos13.0 -swift-version 5 \
  -module-cache-path "$BUILD/.module-cache" \
  -framework AppKit -framework QuartzCore \
  Sources/Screenshot/Core/*.swift \
  Sources/Screenshot/UI/CaptureHUD.swift \
  Sources/Screenshot/UI/CaptureOverlayWindow.swift \
  Tests/OverlayFixture/main.swift \
  -o "$BUILD/runner"

"$BUILD/runner"

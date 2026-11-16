#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Offline UI construction test: builds the real toolbar, color palette and
# pinned-image window without ordering them on screen, so no screen-recording
# permission and no visible windows are needed. It checks the color swatch
# wiring, window levels and the pinned-image ⌘C key route.
SDK="$(xcrun --show-sdk-path)"
SWIFTC="$(xcrun --find swiftc)"
BUILD="$ROOT/build/ui-fixture"
mkdir -p "$BUILD/.module-cache"

"$SWIFTC" -O -sdk "$SDK" -target arm64-apple-macos13.0 -swift-version 5 \
  -module-cache-path "$BUILD/.module-cache" \
  -framework AppKit -framework QuartzCore -framework ImageIO \
  -framework UniformTypeIdentifiers \
  Sources/Screenshot/Core/*.swift \
  Sources/Screenshot/UI/CaptureHUD.swift \
  Sources/Screenshot/UI/ScreenshotDefaults.swift \
  Sources/Screenshot/UI/CaptureToolbar.swift \
  Sources/Screenshot/UI/ColorPalettePanel.swift \
  Sources/Screenshot/UI/ScreenshotToast.swift \
  Sources/Screenshot/UI/PinnedImageWindow.swift \
  Tests/UIFixture/main.swift \
  -o "$BUILD/runner"

"$BUILD/runner"

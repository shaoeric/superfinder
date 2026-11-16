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
  Sources/Screenshot/Core/Annotation.swift \
  Sources/Screenshot/Core/AnnotationSpace.swift \
  Sources/Screenshot/Core/AnnotationRenderer.swift \
  Sources/Screenshot/Core/CaptureSelection.swift \
  Sources/Screenshot/Core/CapturedScreen.swift \
  Sources/Screenshot/Core/MemoryBudget.swift \
  Sources/Screenshot/Core/MosaicRenderer.swift \
  Sources/Screenshot/Core/ScreenshotComposer.swift \
  Sources/Screenshot/Core/ScreenshotDocument.swift \
  Sources/Screenshot/Core/TextLayout.swift \
  -framework AppKit -framework QuartzCore \
  Tests/main.swift \
  -o "$BUILD/superfinder-tests"

"$ROOT/scripts/check-low-power.sh"

"$BUILD/superfinder-tests"

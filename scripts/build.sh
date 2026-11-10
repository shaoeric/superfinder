#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SDK="$(xcrun --show-sdk-path)"
SWIFTC="$(xcrun --find swiftc)"
TARGET="arm64-apple-macos13.0"
BUILD="$ROOT/build"
APP="$BUILD/SuperFinder.app"
APPEX="$APP/Contents/PlugIns/SuperFinderExtension.appex"
HOST_BIN="$APP/Contents/MacOS/SuperFinder"
EXT_BIN="$APPEX/Contents/MacOS/SuperFinderExtension"

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APPEX/Contents/MacOS" "$APPEX/Contents/Resources" "$BUILD/.module-cache"

SHARED_SOURCES=(
  Sources/Shared/AppConfig.swift
  Sources/Shared/Command.swift
  Sources/Shared/CommandStore.swift
  Sources/Shared/PathFormatter.swift
  Sources/Shared/CutBufferStore.swift
  Sources/Shared/MenuModel.swift
  Sources/Shared/MoveEngine.swift
)

HOST_SOURCES=(
  Sources/Host/ProcessRunner.swift
  Sources/Host/InstanceLock.swift
  Sources/Host/LoginItemManager.swift
  Sources/Host/ExtensionStatus.swift
  Sources/Host/StatusBarController.swift
  Sources/Host/SettingsWindowController.swift
  Sources/Host/CommandWatcher.swift
  Sources/Host/MoveCoordinator.swift
  Sources/Host/AppDelegate.swift
  Sources/Host/main.swift
)

EXT_SOURCES=(
  Sources/Extension/FinderSync.swift
)

COMMON_FLAGS=(-O -sdk "$SDK" -target "$TARGET" -swift-version 5 -module-cache-path "$BUILD/.module-cache")

echo "==> Compiling host app"
"$SWIFTC" "${COMMON_FLAGS[@]}" \
  -module-name SuperFinder \
  -framework AppKit -framework FinderSync \
  "${SHARED_SOURCES[@]}" "${HOST_SOURCES[@]}" \
  -o "$HOST_BIN"

echo "==> Compiling Finder extension"
"$SWIFTC" "${COMMON_FLAGS[@]}" \
  -module-name SuperFinderExtension \
  -parse-as-library \
  -Xlinker -e -Xlinker _NSExtensionMain \
  -framework AppKit -framework FinderSync \
  "${SHARED_SOURCES[@]}" "${EXT_SOURCES[@]}" \
  -o "$EXT_BIN"

echo "==> Copying plists"
cp Resources/Info-Host.plist "$APP/Contents/Info.plist"
cp Resources/Info-Extension.plist "$APPEX/Contents/Info.plist"
chmod 755 "$HOST_BIN" "$EXT_BIN"

echo "==> Signing extension (ad-hoc)"
codesign --force --sign - \
  --entitlements Resources/Extension.entitlements \
  --generate-entitlement-der \
  "$APPEX"

echo "==> Signing app (ad-hoc)"
codesign --force --sign - "$APP"

echo "==> Verifying"
codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist" "$APPEX/Contents/Info.plist" Resources/Extension.entitlements

echo "Built: $APP"

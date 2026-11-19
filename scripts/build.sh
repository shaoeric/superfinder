#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/signing-config.sh"

if [[ ! -e "$SUPERFINDER_SIGNING_KEYCHAIN" || ! -f "$SUPERFINDER_SIGNING_PASSWORD_FILE" ]]; then
  echo "错误：未找到稳定签名身份。" >&2
  echo "请先运行：./scripts/setup-signing.sh" >&2
  exit 1
fi
SIGNING_PASSWORD="$(cat "$SUPERFINDER_SIGNING_PASSWORD_FILE")"
/usr/bin/security unlock-keychain -p "$SIGNING_PASSWORD" "$SUPERFINDER_SIGNING_KEYCHAIN" >/dev/null
if ! /usr/bin/security find-identity -v -p codesigning "$SUPERFINDER_SIGNING_KEYCHAIN" 2>/dev/null | grep -qF "$SUPERFINDER_SIGNING_IDENTITY"; then
  echo "错误：签名钥匙串中没有「$SUPERFINDER_SIGNING_IDENTITY」。" >&2
  echo "请检查 $SUPERFINDER_SIGNING_KEYCHAIN" >&2
  exit 1
fi

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
  Sources/Shared/FinderHiddenFiles.swift
  Sources/Shared/MenuModel.swift
  Sources/Shared/MoveEngine.swift
)

SCREENSHOT_SOURCES=(
  Sources/Screenshot/Core/*.swift
  Sources/Screenshot/Service/*.swift
  Sources/Screenshot/UI/*.swift
)

HOST_SOURCES=(
  Sources/Host/ProcessRunner.swift
  Sources/Host/InstanceLock.swift
  Sources/Host/LoginItemManager.swift
  Sources/Host/ExtensionStatus.swift
  Sources/Host/StatusBarController.swift
  Sources/Host/SettingsWindowController.swift
  Sources/Host/CommandWatcher.swift
  Sources/Host/FinderHiddenFilesToggler.swift
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
  -framework AppKit -framework FinderSync -framework Carbon -framework QuartzCore \
  -framework ApplicationServices -framework CoreGraphics \
  -framework ScreenCaptureKit -framework ImageIO -framework UniformTypeIdentifiers \
  "${SHARED_SOURCES[@]}" "${SCREENSHOT_SOURCES[@]}" "${HOST_SOURCES[@]}" \
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

echo "==> Preparing stable signing identity"
OLD_SEARCH="$(/usr/bin/security list-keychains -d user | tr -d ' \"')"
restore_search_list() {
  /usr/bin/security list-keychains -d user -s $OLD_SEARCH >/dev/null 2>&1 || true
}
trap restore_search_list EXIT
/usr/bin/security list-keychains -d user -s "$SUPERFINDER_SIGNING_KEYCHAIN" $OLD_SEARCH
if ! /usr/bin/security list-keychains -d user | grep -qF "$SUPERFINDER_SIGNING_KEYCHAIN"; then
  echo "错误：无法把签名钥匙串加入用户搜索列表。" >&2
  echo "在 DSH 等沙箱中请用 danger-full-access 运行构建；普通终端中请检查钥匙串路径。" >&2
  exit 1
fi

echo "==> Signing extension ($SUPERFINDER_SIGNING_IDENTITY)"
codesign --force --sign "$SUPERFINDER_SIGNING_IDENTITY" \
  --entitlements Resources/Extension.entitlements \
  --generate-entitlement-der \
  "$APPEX"

echo "==> Signing app ($SUPERFINDER_SIGNING_IDENTITY)"
codesign --force --sign "$SUPERFINDER_SIGNING_IDENTITY" "$APP"

echo "==> Verifying"
codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist" "$APPEX/Contents/Info.plist" Resources/Extension.entitlements
SIGNATURE_REQUIREMENT="$(codesign -d -r- "$APP" 2>&1 | tail -1)"
if printf '%s\n' "$SIGNATURE_REQUIREMENT" | grep -q 'cdhash'; then
  echo "错误：签名仍是 ad-hoc（cdhash），重建后 TCC 授权会失效。" >&2
  exit 1
fi
restore_search_list
trap - EXIT

echo "Signature: $SIGNATURE_REQUIREMENT"
echo "Built: $APP"

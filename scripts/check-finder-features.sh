#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FAILED=0
fail() {
  echo "Finder 功能检查失败：$1" >&2
  FAILED=1
}

MENU="Sources/Shared/MenuModel.swift"
WATCHER="Sources/Host/CommandWatcher.swift"
COORDINATOR="Sources/Host/MoveCoordinator.swift"
TOGGLER="Sources/Host/FinderHiddenFilesToggler.swift"
EXTENSION="Sources/Extension/FinderSync.swift"
ENTITLEMENTS="Resources/Extension.entitlements"
BUILD="scripts/build.sh"

# The toggle must exist in both Finder context menus and its title must follow
# the current Finder preference.
if ! grep -q 'case toggleHiddenFiles' "$MENU"; then
  fail "右键菜单缺少隐藏文件切换动作"
fi
if ! grep -q '显示隐藏文件' "$MENU" || ! grep -q '不显示隐藏文件' "$MENU"; then
  fail "隐藏文件菜单项没有按状态切换标题"
fi
if ! grep -q 'FinderHiddenFiles.isVisible' "$EXTENSION"; then
  fail "Finder 扩展没有读取当前隐藏文件状态"
fi
if ! grep -q 'MenuModel.itemsMenu' "$EXTENSION" \
   || ! grep -q 'MenuModel.containerMenu' "$EXTENSION"; then
  fail "隐藏文件菜单没有同时覆盖选中项和空白处右键"
fi

# The action is a global command: it may have no selected paths and must be
# dispatched through the existing host command queue.
if ! grep -q 'hasMinimumPayload' "$WATCHER"; then
  fail "命令队列仍会丢弃无选中路径的隐藏文件命令"
fi
if ! grep -q 'action: .toggleHiddenFiles' "$EXTENSION" \
   || ! grep -q 'sources: \[\]' "$EXTENSION"; then
  fail "Finder 扩展没有发送隐藏文件切换命令"
fi

# Normal toggling must use Finder's native shortcut, not restart Finder.
if ! grep -q 'CGEvent' "$TOGGLER" \
   || ! grep -q 'postToPid' "$TOGGLER" \
   || ! grep -q 'keyboardSetUnicodeString' "$TOGGLER" \
   || ! grep -q 'AXIsProcessTrusted' "$TOGGLER"; then
  fail "直接切换没有通过辅助功能发送 Finder 原生快捷键"
fi
# Finder swallows key equivalents while its context menu is still tracking, so
# the shortcut must be posted after the menu settles.
if ! grep -q 'asyncAfter(deadline: .now() + 0.35)' "$TOGGLER"; then
  fail "快捷键没有等待 Finder 菜单收起后再发送"
fi
# Finder's live ⌘⇧. does not write AppleShowAllFiles; SuperFinder persists the
# state itself so the menu title and the next Finder launch stay correct.
if ! grep -q 'private static func persist' "$TOGGLER" \
   || ! grep -q 'preferenceKey' "$TOGGLER"; then
  fail "切换后没有持久化隐藏文件状态"
fi
if grep -q 'defaults read' "$TOGGLER"; then
  fail "仍在用 AppleShowAllFiles 校验快捷键结果（Finder 不会更新该值）"
fi
if ! grep -q 'FinderHiddenFilesToggler.toggle' "$COORDINATOR"; then
  fail "主程序没有走不重启 Finder 的直接切换路径"
fi
DIRECT_BODY="$(awk '/private func handleToggleHiddenFiles/{flag=1} flag{print} flag&&/^    }$/{exit}' "$COORDINATOR")"
if printf '%s\n' "$DIRECT_BODY" | grep -q 'killall'; then
  fail "正常切换路径仍在重启 Finder"
fi
if ! grep -q 'presentAccessibilityPrompt' "$COORDINATOR" \
   || ! grep -q 'restartFinderForHiddenFiles' "$COORDINATOR"; then
  fail "缺少辅助功能授权提示或显式重启回退"
fi
if ! grep -q '"/usr/bin/killall", \["Finder"\]' "$COORDINATOR"; then
  fail "显式“仍然重启 Finder”回退不可用"
fi
if ! grep -q '"/usr/bin/defaults"' "$COORDINATOR" \
   || ! grep -q 'preferenceDomain' "$COORDINATOR" \
   || ! grep -q 'preferenceKey' "$COORDINATOR"; then
  fail "显式重启回退没有写入 Finder 偏好"
fi

# Rebuilds must keep the same signing identity, otherwise TCC authorization
# for Screen Recording/Accessibility is tied to a new cdhash each time.
if grep -q -- '--sign -' "$BUILD"; then
  fail "构建脚本仍在使用 ad-hoc 签名"
fi
if ! grep -q 'SUPERFINDER_SIGNING_IDENTITY' "$BUILD" \
   || ! grep -q 'scripts/setup-signing.sh' "$BUILD"; then
  fail "构建脚本没有使用稳定本地签名身份"
fi

# Reading another sandboxed preference domain requires the narrow read-only
# temporary exception. Without it the menu title is stuck on the default.
if ! grep -q 'shared-preference.read-only' "$ENTITLEMENTS" \
   || ! grep -q 'com.apple.finder' "$ENTITLEMENTS"; then
  fail "扩展缺少 Finder 偏好域的只读权限"
fi

if [[ "$FAILED" -ne 0 ]]; then
  exit 1
fi
echo "Finder 功能检查通过：状态标题、原生 ⌘⇧. 直接切换、辅助功能授权提示、显式重启回退和稳定签名。"

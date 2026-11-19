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
EXTENSION="Sources/Extension/FinderSync.swift"
ENTITLEMENTS="Resources/Extension.entitlements"

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

# The host writes Finder's preference and restarts Finder so the change takes
# effect immediately.
if ! grep -q '"/usr/bin/defaults"' "$COORDINATOR" \
   || ! grep -q 'preferenceDomain' "$COORDINATOR" \
   || ! grep -q 'preferenceKey' "$COORDINATOR"; then
  fail "主程序没有写入 Finder 隐藏文件偏好"
fi
if ! grep -q '"/usr/bin/killall", \["Finder"\]' "$COORDINATOR"; then
  fail "主程序写入后没有重启 Finder"
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
echo "Finder 功能检查通过：右键隐藏文件开关、状态标题、命令队列、Finder 重启和沙盒只读偏好权限。"

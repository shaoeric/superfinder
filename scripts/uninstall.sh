#!/bin/bash
set -uo pipefail

APP="/Applications/SuperFinder.app"
APPEX="$APP/Contents/PlugIns/SuperFinderExtension.appex"
PLIST="$HOME/Library/LaunchAgents/com.shaobt.superfinder.plist"
LABEL="com.shaobt.superfinder"
UID_="$(id -u)"

echo "==> 1/8 移除登录项"
/bin/launchctl bootout "gui/$UID_" "$PLIST" 2>/dev/null || true
rm -f "$PLIST"

echo "==> 2/8 退出 SuperFinder"
pkill -f "SuperFinder.app/Contents/MacOS/SuperFinder" 2>/dev/null || true
sleep 0.5

echo "==> 3/8 注销 Finder 扩展"
if [[ -d "$APPEX" ]]; then
  /usr/bin/pluginkit -r "$APPEX" 2>/dev/null || true
fi
/usr/bin/pluginkit -e ignore -i "com.shaobt.superfinder.FinderSync" 2>/dev/null || true

echo "==> 4/8 删除应用"
rm -rf "$APP"

echo "==> 5/8 删除数据与偏好"
rm -rf "$HOME/Library/Application Support/SuperFinder"
rm -rf "$HOME/Library/Containers/com.shaobt.superfinder.FinderSync"
rm -f "$HOME/Library/Preferences/com.shaobt.superfinder.plist"
rm -f "$HOME/Library/Preferences/com.shaobt.superfinder.FinderSync.plist"
rm -rf "$HOME/Library/Saved Application State/com.shaobt.superfinder.savedState"
rm -rf "$HOME/Library/Caches/com.shaobt.superfinder"

echo "==> 6/8 重启 Finder"
/usr/bin/killall Finder 2>/dev/null || true
sleep 1

echo "==> 7/8 重置 TCC 记录（如存在）"
for service in SystemPolicyDesktopFolder SystemPolicyDocumentsFolder SystemPolicyDownloadsFolder SystemPolicyAllFiles; do
  /usr/bin/tccutil reset "$service" com.shaobt.superfinder 2>/dev/null || true
  /usr/bin/tccutil reset "$service" com.shaobt.superfinder.FinderSync 2>/dev/null || true
done

echo "==> 8/8 验证"
FAILED=0
if [[ -e "$APP" ]]; then echo "残留：$APP"; FAILED=1; fi
if [[ -e "$PLIST" ]]; then echo "残留：$PLIST"; FAILED=1; fi
if [[ -e "$HOME/Library/Application Support/SuperFinder" ]]; then echo "残留：共享目录"; FAILED=1; fi
if [[ -e "$HOME/Library/Containers/com.shaobt.superfinder.FinderSync" ]]; then echo "残留：扩展容器"; FAILED=1; fi
if /usr/bin/pluginkit -mAD -p com.apple.FinderSync 2>/dev/null | grep -q "com.shaobt.superfinder.FinderSync"; then
  echo "残留：pluginkit 中仍有扩展记录"
  FAILED=1
fi
if pgrep -f "SuperFinder.app/Contents/MacOS/SuperFinder" >/dev/null 2>&1; then
  echo "残留：SuperFinder 进程"
  FAILED=1
fi

if [[ "$FAILED" -eq 0 ]]; then
  echo "清理完成，未发现残留。"
else
  echo "清理完成，但上面项目仍有残留；如扩展容器被系统保护，请给终端/DSH 完全磁盘访问权限后重跑。"
fi

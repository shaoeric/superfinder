#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_APP="$ROOT/build/SuperFinder.app"
APP_DST="/Applications/SuperFinder.app"
APPEX_DST="$APP_DST/Contents/PlugIns/SuperFinderExtension.appex"
PLIST="$HOME/Library/LaunchAgents/com.shaobt.superfinder.plist"
LABEL="com.shaobt.superfinder"
UID_="$(id -u)"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
SHARED_SUPPORT="$HOME/Library/Application Support/SuperFinder"
SHARED_COMMANDS="$SHARED_SUPPORT/commands"

if [[ ! -d "$BUILD_APP" ]]; then
  echo "错误：找不到构建产物 $BUILD_APP，请先运行 scripts/build.sh" >&2
  exit 1
fi

echo "==> 1/9 退出正在运行的 SuperFinder"
pkill -f "SuperFinder.app/Contents/MacOS/SuperFinder" 2>/dev/null || true
sleep 0.5

echo "==> 2/9 注销旧扩展（如存在）"
if [[ -d "$APPEX_DST" ]]; then
  /usr/bin/pluginkit -r "$APPEX_DST" 2>/dev/null || true
fi

echo "==> 3/9 安装到 /Applications"
rm -rf "$APP_DST"
/usr/bin/ditto "$BUILD_APP" "$APP_DST"
/usr/bin/xattr -cr "$APP_DST"
/usr/bin/codesign --verify --deep --strict "$APP_DST"

echo "==> 4/9 注册应用"
"$LSREGISTER" -f "$APP_DST" 2>/dev/null || true

echo "==> 5/9 创建共享目录"
mkdir -p "$SHARED_COMMANDS"
chmod 700 "$SHARED_SUPPORT" "$SHARED_COMMANDS"

echo "==> 6/9 注册并启用 Finder 扩展"
/usr/bin/pluginkit -a "$APPEX_DST" 2>/dev/null || true
/usr/bin/pluginkit -e use -i "com.shaobt.superfinder.FinderSync" 2>&1 || true

echo "==> 7/9 安装登录时自动启动"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<'PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.shaobt.superfinder</string>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/bin/open</string>
		<string>-g</string>
		<string>-a</string>
		<string>/Applications/SuperFinder.app</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>LimitLoadToSessionType</key>
	<string>Aqua</string>
</dict>
</plist>
PLIST_EOF
chmod 644 "$PLIST"
/bin/launchctl bootout "gui/$UID_" "$PLIST" 2>/dev/null || true
/bin/launchctl enable "gui/$UID_/$LABEL" 2>/dev/null || true
/bin/launchctl bootstrap "gui/$UID_" "$PLIST" 2>&1 || true

echo "==> 8/9 启动应用"
/usr/bin/open -g "$APP_DST" 2>/dev/null || true
sleep 1

echo "==> 9/9 重启 Finder 以加载扩展"
/usr/bin/killall Finder 2>/dev/null || true
sleep 2

echo
echo "================ 安装结果 ================"
if pgrep -f "$APP_DST/Contents/MacOS/SuperFinder" >/dev/null 2>&1; then
  echo "主程序进程：运行中"
else
  echo "主程序进程：未运行（请检查 Console/log）"
fi

PLUGIN_OUT="$(/usr/bin/pluginkit -mAD -p com.apple.FinderSync 2>/dev/null || true)"
if echo "$PLUGIN_OUT" | grep -E '^\+.*com\.shaobt\.superfinder\.FinderSync' >/dev/null 2>&1; then
  echo "Finder 扩展：已启用（+）"
else
  echo "Finder 扩展：尚未确认启用"
  echo "  当前扩展状态："
  echo "$PLUGIN_OUT" | grep -i 'Shaobt\|superfinder' || true
  echo "  可稍后在 SuperFinder 设置中点击「尝试启用扩展」，或执行："
  echo "  pluginkit -e use -i com.shaobt.superfinder.FinderSync && killall Finder"
fi

if /bin/launchctl print "gui/$UID_/$LABEL" >/dev/null 2>&1; then
  echo "登录项：已加载"
else
  echo "登录项：未加载（可在设置中重新勾选）"
fi

echo "共享目录：$SHARED_SUPPORT"
echo "提示：首次移动桌面/文稿/下载中的文件时，macOS 会请求文件夹访问权限。"
echo "=========================================="

#!/bin/bash
set -uo pipefail

APP="/Applications/SuperFinder.app"
APPEX="$APP/Contents/PlugIns/SuperFinderExtension.appex"
PLIST="$HOME/Library/LaunchAgents/com.shaobt.superfinder.plist"
LABEL="com.shaobt.superfinder"
UID_="$(id -u)"
FAILED=0

ok()   { echo "OK   $1"; }
fail() { echo "FAIL $1"; FAILED=1; }
warn() { echo "WARN $1"; }

echo "== SuperFinder 安装验证 =="

if [[ -d "$APP" ]]; then ok "应用存在：$APP"; else fail "应用不存在"; fi
if /usr/bin/codesign --verify --deep --strict "$APP" 2>/dev/null; then
  ok "代码签名校验通过"
else
  fail "代码签名校验失败"
fi

if [[ -d "$APPEX" ]]; then ok "Finder 扩展存在"; else fail "Finder 扩展不存在"; fi
if /usr/bin/plutil -lint "$APP/Contents/Info.plist" "$APPEX/Contents/Info.plist" >/dev/null 2>&1; then
  ok "Info.plist 格式正确"
else
  fail "Info.plist 格式错误"
fi

if pgrep -f "$APP/Contents/MacOS/SuperFinder" >/dev/null 2>&1; then
  ok "主程序进程运行中"
else
  fail "主程序进程未运行"
fi

if pgrep -f "$APPEX/Contents/MacOS/SuperFinderExtension" >/dev/null 2>&1; then
  ok "Finder 扩展进程运行中"
else
  warn "Finder 扩展进程未运行（可尝试重启 Finder）"
fi

PLUGIN_OUT="$(/usr/bin/pluginkit -mAD -p com.apple.FinderSync 2>/dev/null || true)"
if [[ -z "$PLUGIN_OUT" ]]; then
  warn "无法读取 pluginkit（可能需要在终端或授予完全磁盘访问后运行）"
elif echo "$PLUGIN_OUT" | grep -E '^\+.*com\.shaobt\.superfinder\.FinderSync' >/dev/null 2>&1; then
  ok "Finder 扩展已启用（+）"
else
  fail "Finder 扩展未启用"
fi

if /bin/launchctl print "gui/$UID_/$LABEL" >/dev/null 2>&1; then
  ok "登录项已加载"
else
  fail "登录项未加载"
fi

if [[ -d "$HOME/Library/Application Support/SuperFinder/commands" ]]; then
  ok "共享命令目录存在"
else
  warn "共享命令目录不存在（主程序启动时会创建）"
fi

if [[ -d "$HOME/Library/Containers/com.shaobt.superfinder.FinderSync" ]]; then
  ok "扩展沙盒容器存在"
else
  warn "扩展沙盒容器尚未创建（首次加载扩展后创建）"
fi

echo
if [[ "$FAILED" -eq 0 ]]; then
  echo "验证通过。"
else
  echo "验证发现问题，请查看上面的 FAIL 项。"
fi
exit "$FAILED"

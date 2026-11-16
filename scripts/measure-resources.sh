#!/bin/bash
set -euo pipefail

APP="/Applications/SuperFinder.app/Contents/MacOS/SuperFinder"
PID="${1:-$(pgrep -f "$APP" | head -1 || true)}"
if [[ -z "${PID:-}" ]]; then
  echo "找不到正在运行的 SuperFinder 主程序。请先启动应用，或传入 pid。" >&2
  exit 1
fi

echo "SuperFinder pid=$PID"
echo "采样 30 秒（在终端或授予完全磁盘访问后运行；DSH 沙盒内 ps/top 可能被拒绝）..."
echo "时间   CPU%   RSS_KB  线程"
for i in $(seq 1 30); do
  line="$(ps -o %cpu=,rss=,thcount= -p "$PID" 2>/dev/null | tr -s ' ' | sed 's/^ //')"
  if [[ -z "$line" ]]; then
    echo "无法读取进程状态（可能需要完全磁盘访问）"
    break
  fi
  echo "$(date +%H:%M:%S)  $line"
  sleep 1
done

echo
echo "共享目录大小："
du -sh "$HOME/Library/Application Support/SuperFinder" 2>/dev/null || true
echo
echo "能耗请在 Activity Monitor 的「能耗」页查看；如需命令行数据可用："
echo "  sudo powermetrics --samplers tasks -i 1000 -n 30 --show-process-energy | grep -i superfinder"

#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PATTERN='Timer\(|scheduledTimer|CADisplayLink|CVDisplayLink|DispatchSourceTimer'
TARGETS=(
  Sources/Screenshot
  Sources/Host/CommandWatcher.swift
)

FAILED=0
for target in "${TARGETS[@]}"; do
  if grep -RInE "$PATTERN" "$target" >/tmp/superfinder-low-power-grep.txt 2>/dev/null; then
    echo "低功耗检查失败：发现定时/轮询渲染 API" >&2
    cat /tmp/superfinder-low-power-grep.txt >&2
    FAILED=1
  fi
done

if grep -n "beginActivity" Sources/Host/CommandWatcher.swift >/dev/null 2>&1; then
  echo "低功耗检查失败：CommandWatcher 不应常驻阻止 App Nap" >&2
  FAILED=1
fi

if grep -q "commandPollInterval" Sources/Host/CommandWatcher.swift 2>/dev/null; then
  echo "低功耗检查失败：CommandWatcher 仍包含轮询间隔" >&2
  FAILED=1
fi

rm -f /tmp/superfinder-low-power-grep.txt

if [[ "$FAILED" -ne 0 ]]; then
  exit 1
fi

echo "低功耗检查通过：截屏渲染和命令队列均为事件驱动。"

#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Regression guard for the drag "trailing" bug: drag/mouse-up handling used to
# sample NSEvent.mouseLocation, which is the live pointer position, not the
# position carried by the event being handled. When the main thread catches up
# after the user releases the trackpad button, that samples a newer location and
# moves the selection/annotation once more. The drag path must use event points.
FILE="Sources/Screenshot/UI/ScreenshotController.swift"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

sed -n '/private func handleMouseDown/,/\/\/ MARK: - Creation/p' "$FILE" >"$TMP"

FAILED=0
if ! grep -q "private func handleDrag" "$TMP"; then
  echo "拖拽坐标检查失败：未找到 handleDrag 实现" >&2
  FAILED=1
fi
if grep -n "NSEvent.mouseLocation" "$TMP" >&2; then
  echo "拖拽坐标检查失败：拖拽路径仍在使用实时鼠标位置，必须使用事件自带坐标" >&2
  FAILED=1
fi
if ! grep -q "screenLocalPoint(of: event)" "$TMP"; then
  echo "拖拽坐标检查失败：拖拽路径未使用事件同步的屏幕坐标" >&2
  FAILED=1
fi

if [[ "$FAILED" -ne 0 ]]; then
  exit 1
fi
echo "拖拽坐标检查通过：拖拽和鼠标抬起均使用事件自带坐标。"

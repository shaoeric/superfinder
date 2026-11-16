#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FAILED=0
fail() {
  echo "截屏功能检查失败：$1" >&2
  FAILED=1
}

CONTROLLER="Sources/Screenshot/UI/ScreenshotController.swift"
PIN="Sources/Screenshot/UI/PinnedImageWindow.swift"
ANNOTATION="Sources/Screenshot/Core/Annotation.swift"
PALETTE="Sources/Screenshot/UI/ColorPalettePanel.swift"
TOOLBAR="Sources/Screenshot/UI/CaptureToolbar.swift"

# Text editing must only auto-commit on a new mouse-down, never on the
# mouse-up of the click that opened the editor (which used to flash and close).
if ! grep -B8 'textEditor.commitNow()' "$CONTROLLER" | grep -q 'event.type == .leftMouseDown'; then
  fail "文本编辑未按鼠标按下事件提交，可能再次出现闪退"
fi

# Rectangle rotation handle must stay at the top-left, away from delete.
if ! grep -q 'x: -shape.halfWidth - 22' "$ANNOTATION"; then
  fail "矩形旋转柄不在左上角"
fi

# Clipboard copy shortcut and toolbar action.
if ! grep -q 'case 8: // C' "$CONTROLLER"; then
  fail "截图编辑器缺少 ⌘C 处理"
fi
if ! grep -q 'doc.on.doc' "$TOOLBAR"; then
  fail "工具栏缺少复制图片按钮"
fi

# Pinned image context menu and Cmd+C path.
if ! grep -q '显示工具条' "$PIN"; then
  fail "贴图右键菜单缺少「显示工具条」"
fi
if ! grep -q '复制图片' "$PIN"; then
  fail "贴图右键菜单缺少「复制图片」"
fi
if ! grep -q 'performKeyEquivalent' "$PIN"; then
  fail "贴图缺少 ⌘C 快捷键处理"
fi

# Color palette must be above the overlay/toolbar window level.
if ! grep -q 'screenSaver.rawValue + 3' "$PALETTE"; then
  fail "取色板窗口层级不够高"
fi

if [[ "$FAILED" -ne 0 ]]; then
  exit 1
fi
echo "截屏功能检查通过：文本编辑、左上角旋转柄、⌘C、贴图工具条、取色板。"

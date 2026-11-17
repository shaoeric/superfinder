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
HUD="Sources/Screenshot/UI/CaptureHUD.swift"
OVERLAY="Sources/Screenshot/UI/CaptureOverlayWindow.swift"

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

# Text tool must draw the Latin letter T, never a localized text glyph.
if ! grep -q 'enum TextToolIcon' "$TOOLBAR" || ! grep -q 'path.lineWidth = 1.5' "$TOOLBAR"; then
  fail "文本工具没有使用自绘的拉丁字母 T"
fi

# Rectangles use a filled/outline switch; mosaic rendering was removed.
if ! grep -q 'var filled: Bool' "$ANNOTATION"; then
  fail "矩形缺少 filled 填充状态"
fi
if grep -RIn 'mosaic\|Mosaic' Sources/Screenshot >/dev/null 2>&1; then
  fail "矩形仍在引用已移除的马赛克实现"
fi
if ! grep -q 'rectFillControl' "$TOOLBAR"; then
  fail "矩形属性栏缺少非填充/填充切换"
fi

# Latest picked color becomes the default for subsequent annotations.
if ! grep -q 'defaults.rectangleColor = color' "$CONTROLLER" \
   || ! grep -q 'defaults.lineColor = color' "$CONTROLLER" \
   || ! grep -q 'defaults.textColor = color' "$CONTROLLER"; then
  fail "颜色没有同步到后续标注的默认值"
fi

# Copy feedback and persistent pins above the overlay.
if ! grep -q 'ScreenshotToast.shared.show' "$CONTROLLER" \
   || ! grep -q 'showCopyToast' "$CONTROLLER"; then
  fail "复制缺少可见提示"
fi
if ! grep -q 'ScreenCompositor' "$CONTROLLER" \
   || ! grep -q 'orderedWindows' "$CONTROLLER"; then
  fail "新截图没有把已有贴图合成进基础截图"
fi

# Esc closes and frees a focused pin.
if ! grep -q 'override func cancelOperation' "$PIN" \
   || ! grep -q 'keyCode == 53' "$PIN"; then
  fail "贴图缺少 Esc 关闭处理"
fi
if ! grep -q 'editingSession = nil' "$PIN"; then
  fail "关闭贴图没有释放编辑会话内存"
fi

# An inactive pinned window must accept the first click for dragging.
if ! grep -q 'acceptsFirstMouse' "$PIN"; then
  fail "贴图窗口首击不能直接拖拽"
fi

# Screenshot toolbar is a fixed light #EBEBEB surface with dark chrome.
if ! grep -q 'srgbRed: 235.0 / 255.0' "$TOOLBAR"; then
  fail "工具栏背景不是 #EBEBEB"
fi
if ! grep -q 'static let backgroundColor' "$TOOLBAR"; then
  fail "工具栏缺少可复用的浅色背景定义"
fi

# Selection is aided by a full-screen crosshair, updated by mouse events only.
if ! grep -q 'func showCrosshair' "$OVERLAY" || ! grep -q 'crosshairLayer' "$OVERLAY"; then
  fail "框选阶段缺少十字辅助线"
fi
if ! grep -q 'showCrosshair' "$CONTROLLER"; then
  fail "控制器没有更新十字辅助线"
fi
MOUSE_MOVED_BODY="$(awk '/private func mouseMoved/{flag=1} flag{print} flag&&/^    }$/{exit}' "$CONTROLLER")"
if ! printf '%s\n' "$MOUSE_MOVED_BODY" | grep -q 'showCrosshair'; then
  fail "鼠标移动没有更新十字辅助线"
fi
if printf '%s\n' "$MOUSE_MOVED_BODY" | grep -q 'updateHUD'; then
  fail "鼠标移动仍在重绘 HUD"
fi

# HUD keeps only the selection size; no live coordinate/pixel readout.
if grep -Eq '坐标|RGB' "$HUD"; then
  fail "HUD 仍在渲染鼠标坐标或像素颜色"
fi
if ! grep -q '尺寸' "$HUD"; then
  fail "HUD 未保留选区尺寸"
fi

# Color palette must be above the overlay/toolbar window level.
if ! grep -q 'screenSaver.rawValue + 3' "$PALETTE"; then
  fail "取色板窗口层级不够高"
fi

if [[ "$FAILED" -ne 0 ]]; then
  exit 1
fi
echo "截屏功能检查通过：文本编辑/T图标、左上角旋转柄、填充切换、颜色继承、⌘C提示、贴图合成/首击拖拽/Esc释放、取色板、#EBEBEB 工具栏、框选十字线、HUD 仅显示尺寸。"

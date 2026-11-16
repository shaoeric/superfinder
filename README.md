# SuperFinder

仿“超级右键”的 macOS 小工具：**Finder 右键增强 + 菜单栏后台应用 + 截屏标注**。

- 菜单栏常驻图标，菜单里提供「开始截屏 / 设置… / Finder 扩展状态 / 重新加载 Finder / 退出」
- 在 Finder 中对文件或文件夹右键，可直接剪切、移动、复制绝对路径
- 在 Finder 窗口空白处右键，可把已剪切的文件移动到当前目录，或复制当前目录路径
- 全局快捷键 `⌃Q` 截屏：蒙版选区、矩形/线段/文本标注、像素橡皮擦、撤销/重做、贴图、保存
- 后台自动启动（LaunchAgent），无悬浮球、无 Dock 图标
- 单例运行：重复启动会唤起已运行的实例并打开设置，不会产生第二个进程

当前版本：1.1.7（本地 ad-hoc 签名，非 App Store、非公证）。

## 功能

### 选中文件/文件夹右键

| 菜单项 | 说明 |
|---|---|
| 剪切（准备移动） | 记住当前选中的项目，不立即移动 |
| 移动 N 项到此文件夹 | 仅当只选中一个项目时出现；把之前剪切的项目移动到这个项目（主程序会校验它必须是文件夹） |
| 移动到文件夹… | 弹出目录选择面板，移动当前选中的项目 |
| 复制绝对路径 | 复制选中项目的绝对路径；多选时每行一个 |
| 在终端中打开 | 仅当只选中一个项目时出现；选中的是文件夹就打开它，是文件则打开它所在目录 |

### 窗口空白处右键

| 菜单项 | 说明 |
|---|---|
| 移动 N 项到这里 | 把剪切的項目移动到当前目录 |
| 取消待移动（N 项） | 清空剪切缓冲区 |
| 复制当前目录路径 | 复制当前 Finder 目录的绝对路径 |
| 在终端中打开当前目录 | 在系统 Terminal.app 中打开当前 Finder 目录 |
| SuperFinder 设置… | 打开设置窗口（菜单栏图标被刘海挡住时也可用这个入口） |

### 移动规则

- 源已不存在：跳过并在结果里提示。
- 源和目标父目录相同（已经在目标位置）：跳过，不报错。
- 把文件夹移动到它自己或它的子目录：拒绝，不损坏数据。
- 目标不是文件夹：明确报错。
- 同名冲突：弹窗选择
  - **保留两者**：自动重命名为 `名称 2.ext` / `目录名 2`
  - **替换**：原项目移入废纸篓（可恢复），再放入新项目
  - **取消**：不执行
- 跨卷移动使用 `FileManager.moveItem`，系统会先复制再移除源。
- 复制路径不解析符号链接，保持 Finder 中显示的路径。

## 截屏与标注（⌃Q）

按 `⌃Q`，或点击菜单栏图标 →「开始截屏」。

### 选区

- 以鼠标当前所在显示器为初始活动屏；所有显示器显示遮罩。
- 鼠标未开始拖拽前移动到另一块显示器，会切换活动屏并重新冻结该屏。
- 拖拽选择截图区域；选区内显示原色，其他区域使用暗色蒙版。
- 选区左上角 HUD 实时显示：
  - `尺寸 W × H px`
  - `坐标 X:… Y:…`
  - 鼠标位置的 `RGB(r,g,b) #HEX`
- 选区支持八向拖拽缩放、拖动移动；是否显示手柄取决于当前工具和选中状态。
- 拖动/缩放/移动标注时使用鼠标事件自带坐标；松开左键后再移动触摸板，不会把选区或标注多拖动一段。
- 为控制内存，**一次截屏只处理一个显示器**，单张选区不跨屏。跨屏移动鼠标会切换活动屏。

### 工具栏

选区下方显示工具栏：

- 选择/移动
- 矩形
- 线段
- 文本
- 橡皮擦
- 撤销 / 重做
- 取消截图
- 贴图
- 复制图片（`⌘C`）
- 保存截图

选中工具或已有标注时，工具栏上方显示属性栏；按工具切换颜色、粗细、填充模式、线型、箭头、字体、字号、橡皮大小。

### 标注

**矩形**

- 轮廓颜色、粗细。
- 非填充（默认）与填充模式；填充模式下用轮廓同色绘制实心矩形。
- 选中后显示带角度的虚线外接框、四角尺寸柄、左上角旋转柄和右上角删除叉。
- 拖动旋转柄旋转；按住 `Shift` 以 15° 吸附。

**线段**

- 颜色、粗细。
- 实线、虚线、点划线。
- 首尾箭头：无、细箭头、粗箭头。
- 选中后拖动两端手柄调整起止点，拖动线身移动。

**文本**

- 颜色、字体、字号。
- 工具图标使用英文字母 `T`；支持中文、多行和 emoji；常用字体包括系统、苹方、宋体、黑体、楷体、Helvetica Neue、Menlo。
- 编辑时 `Shift+Enter` 换行，`Return` 提交，`Esc` 取消。
- 选中后拖动移动位置；双击或按 `Return` 可重新编辑。

**通用交互**

- 鼠标悬停已有标注会高亮；选择工具点击选中，点击空白取消。
- 选中标注显示带角度的虚线外接框、删除叉；矩形额外显示旋转柄。
- 点击右上角删除叉，或按 `Delete` / `Backspace` 删除选中标注。
- 点击属性栏的颜色块打开预设调色板；“更多颜色…”打开系统取色器；选中的颜色会立即应用到当前标注，并成为后续矩形/线段/文本的默认颜色。
- 滚轮调整选中标注的粗细/字号，或当前工具的默认粗细/字号/橡皮大小。
- 撤销/重做：`⌘Z` / `⇧⌘Z`，或工具栏按钮。

### 橡皮擦

- 圆形/方形笔刷，大小可调（4–120 pt）。
- 按像素清理标注，不改变截图背景。
- 笔刷碰到某个标注时，该标注会被冻结为栅格像素并从可编辑集合移出；文本被擦到后不再可编辑，矩形/线段也同样冻结。
- 撤销可以恢复被冻结的矢量标注。
- 拖动时显示擦除轨迹预览，松开鼠标后一次性应用像素擦除。

### 贴图与保存

- **贴图**：把选区结果固定为始终浮在普通窗口之上的窗口，可拖动到任意位置；支持多个贴图，悬停显示关闭按钮，右键可关闭/保存/复制。贴图激活后按 `Esc` 可关闭当前贴图，其他贴图不受影响；关闭时立即释放原图、标注文档和编辑会话内存，且不会写入磁盘。
- **截图时保持贴图可见**：开始新的截图/重新编辑时，已有贴图会临时浮在蒙版之上且点击穿透，不会被遮住，也不会干扰选区拖动；截图结束后恢复普通悬浮层级。
- **复制**：编辑截图时按 `⌘C` 或点击工具栏复制按钮，生成包含标注的 PNG/TIFF 并写入系统剪贴板；贴图窗口获得焦点后也可按 `⌘C` 复制当前贴图。复制成功会显示「已复制到剪贴板」浮层并给出触感反馈。
- **继续编辑**：右键贴图选择「显示工具条」，会重新打开原截图编辑会话；可调整选区尺寸（裁剪大小）、拖动贴图窗口改变位置，并继续编辑标注。完成后点贴图/保存应用，按 `Esc` 放弃本次编辑。
- **保存**：`⌘S` 或工具栏保存，默认桌面、文件名带时间戳，支持 PNG/JPEG。
  - 输出不包含蒙版、HUD、工具栏、鼠标光标。
  - 不生成临时文件、不保存历史、不建截图缓存目录。
  - 保存失败会清理半成品；取消保存会返回编辑。

### 低功耗与内存设计

- 截屏是**一次性** ScreenCaptureKit 截图，不启动持续录屏流。
- 选区、悬停、HUD、标注预览均由鼠标/键盘/状态变化事件驱动；没有 60 Hz 定时器、`CADisplayLink`、`CVDisplayLink` 或轮询重绘。
- 现有 Finder 命令队列也从 0.5 秒轮询改为目录事件源 + 分布式通知；空闲时不阻止 App Nap。
- 一次截屏只保留**一张活动屏基础截图**和可选的**一张冻结标注位图**，不做全桌面合成缓存。
- 截图与保存使用显示器的**原生 backing scale**（Retina 为 2x），显示层直接使用原图，不做“缩略图/降采样显示”。
- 内存上限只作为**渲染安全阀**（防止异常分配/递归/卡死），不会为了压低内存而降低截图或标注质量；贴图内存不设产品级限制。
- 空闲 CPU 增量接近 0；后台磁盘写入为 0（用户主动保存的文件除外）。

## 系统要求

- macOS 13 或更高（开发验证环境：macOS 26.5 arm64）
- 截屏功能要求 macOS 14+（ScreenCaptureKit `SCScreenshotManager`）
- 无需 Xcode；使用 Command Line Tools 的 `swiftc` 构建
- 截屏需要「屏幕录制」权限

## 构建

```bash
cd superfinder
./scripts/build.sh
```

产物：`build/SuperFinder.app`。构建会自动：

1. 用 `swiftc` 编译主程序和 Finder Sync 扩展
2. 组装 `.app` / `.appex` 包
3. 用 `pluginkit` 可识别的 ad-hoc 签名给扩展和主程序签名
4. `codesign --verify --deep --strict` 校验

## 安装 / 启用

```bash
./scripts/install.sh
```

安装脚本会：

- 把 `build/SuperFinder.app` 安装到 `/Applications/SuperFinder.app`
- 重新注册并启用 Finder 扩展（`pluginkit -a` / `pluginkit -e use`）
- 安装 `~/Library/LaunchAgents/com.shaobt.superfinder.plist`（登录时自动启动）
- 创建 `~/Library/Application Support/SuperFinder/commands`
- 重启 Finder，让扩展菜单立刻生效

> 在 DSH 等沙箱环境中运行安装脚本时，需要 danger-full-access 权限（写入 `/Applications`、调用 `pluginkit`/`launchctl`、重启 Finder）。

若想手动启用 Finder 扩展：

```bash
pluginkit -e use -i com.shaobt.superfinder.FinderSync
killall Finder
```

macOS 15 及以上已把 Finder 扩展从旧版「扩展」面板移走；可在
「系统设置 → 通用 → 登录项与扩展」中查看，也可以用上面的 `pluginkit` 命令。
设置窗口里也提供了「尝试启用扩展」和「打开系统扩展设置」按钮。

## 使用

### Finder 右键

1. 打开 Finder，选中一个或多个文件/文件夹。
2. 右键 →「剪切（准备移动）」。
3. 在目标文件夹空白处右键 →「移动 N 项到这里」；或右键目标文件夹 →「移动 N 项到此文件夹」。
4. 也可以对当前选择使用「移动到文件夹…」。
5. 右键单个文件夹/文件 →「在终端中打开」；或在目录空白处右键 →「在终端中打开当前目录」。
6. 点击菜单栏图标 →「设置…」可管理登录启动、扩展状态和 Finder 重启。

### 截屏

1. 按 `⌃Q`，或在菜单栏选择「开始截屏」。
2. 首次使用时允许 SuperFinder 的「屏幕录制」权限（可能需要重启应用）。
3. 拖拽选择区域；用工具栏选择矩形/线段/文本/橡皮擦，调整属性。
4. 使用撤销/重做修改标注；点击贴图或保存。
5. `Esc` 取消截图。

截屏快捷键固定为 `⌃Q`；如果与系统/其他应用冲突，仍可从菜单栏启动截屏。

## 屏幕录制权限

1. 第一次截屏时，macOS 会请求「屏幕录制」权限。
2. 打开「系统设置 → 隐私与安全性 → 屏幕录制」，允许 SuperFinder。
3. 如果授权后仍然无法截图，退出并重新打开 SuperFinder；部分 macOS 版本需要重启应用才生效。
4. ad-hoc 签名每次重新构建后签名会变化，macOS 可能重新要求授权，这是本地工具的正常行为。

也可以从设置窗口点击「打开屏幕录制设置」。

## 菜单栏图标被刘海挡住？

MacBook 刘海屏的菜单栏空间有限，当图标多到放不下时，macOS 会把**最左侧新增的图标排到刘海下面**，看起来“消失”了。这不是 SuperFinder 崩溃。

处理方式（任选）：

- 在「系统设置 → 菜单栏」中关闭几个不用的系统图标，腾出位置后 SuperFinder 图标会重新出现。
- 或 ⌘ 拖动菜单栏图标，把重要的移到靠右（时钟一侧）。
- 使用菜单栏管理工具（Bartender、Frost 等）。
- 外接显示器没有刘海，通常可以直接看到图标。
- 菜单栏图标不可见时，仍可在 Finder 空白处右键 →「SuperFinder 设置…」打开设置，或直接打开 `/Applications/SuperFinder.app`；截屏 `⌃Q` 仍可用。

目前 macOS 没有公开 API 让应用强制把自己的菜单栏图标插到最右侧；这是系统行为。

## 权限

- 本工具移动文件时，主程序需要读取源、写入目标目录。
- 首次移动**桌面、文稿、下载**等受保护目录中的文件时，macOS 会弹出「SuperFinder 想要访问…」，请选择**允许**。
- 如果希望完全免提示，可以在「系统设置 → 隐私与安全性 → 完全磁盘访问权限」里手动加入 `SuperFinder.app`（可选）。
- 截屏需要「屏幕录制」权限；不截屏时不会采集屏幕。
- 复制绝对路径、剪切操作本身不需要文件访问权限。

## 目录与数据

| 内容 | 位置 |
|---|---|
| 应用 | `/Applications/SuperFinder.app` |
| Finder 扩展 | `/Applications/SuperFinder.app/Contents/PlugIns/SuperFinderExtension.appex` |
| 登录项 | `~/Library/LaunchAgents/com.shaobt.superfinder.plist` |
| 扩展沙盒容器 | `~/Library/Containers/com.shaobt.superfinder.FinderSync` |
| 命令队列 | `~/Library/Application Support/SuperFinder/commands` |
| 剪切缓冲区 | 扩展容器内 `Application Support/SuperFinder/cut-buffer.json` |
| 截图保存 | 用户每次在保存面板选择的位置；无自动缓存目录 |

扩展通过 `com.apple.security.temporary-exception.files.home-relative-path.read-write`
仅获得对 `~/Library/Application Support/SuperFinder/` 的读写；文件移动和截屏由主程序执行。

## 测试

```bash
./scripts/run-tests.sh
```

覆盖：命令 JSON 编解码、剪切缓冲区、路径格式化、菜单状态、移动计划/冲突/保留两者/替换/自移动保护/符号链接；截图事件坐标/多显示器几何、选区几何、标注命中、左上角旋转柄、实心矩形、冻结层、撤销/重做、合成裁剪、剪贴板 PNG/TIFF、贴图编辑会话、工作位图上限。

低功耗静态检查：

```bash
./scripts/check-low-power.sh
```

它检查截屏渲染和命令队列中是否出现 Timer/display link/轮询渲染 API。

离屏渲染测试（不需要屏幕录制权限）：

```bash
./scripts/run-overlay-tests.sh
```

它用一块合成的 2x 屏幕渲染真实的 `CaptureOverlayView` 图层树，检查非零原点选区下标注是否落在正确位置，因此坐标/手柄回归可以在不弹系统授权的情况下验证。

离屏 UI 构造测试（不需要屏幕录制权限，也不会显示窗口）：

```bash
./scripts/run-ui-tests.sh
```

它构造真实的工具栏、取色板、复制提示和贴图窗口，检查三组颜色块/12 个预设色、T 图标、非填充/填充开关、窗口层级、工具栏可成为 key window，以及贴图窗口的 `⌘C`/Esc/首击拖拽/尺寸更新。

安装后验证：

```bash
./scripts/verify.sh
```

资源采样（需要终端或完全磁盘访问；DSH 沙盒内 `ps/top` 可能被拒绝）：

```bash
./scripts/measure-resources.sh
```

安装后手动检查：

```bash
/usr/bin/pluginkit -m -i com.shaobt.superfinder.FinderSync -vvv
pgrep -fl SuperFinder
pgrep -fl SuperFinderExtension
/bin/launchctl print gui/$(id -u)/com.shaobt.superfinder
codesign -d --entitlements :- /Applications/SuperFinder.app/Contents/PlugIns/SuperFinderExtension.appex
```

查看日志：

```bash
log show --last 5m --predicate 'subsystem == "com.shaobt.superfinder"' --info
log show --last 5m --predicate 'subsystem == "com.shaobt.superfinder.FinderSync"' --info
```

## 卸载

```bash
./scripts/uninstall.sh
```

脚本会移除应用、登录项、Finder 扩展注册、扩展容器、偏好和 TCC 记录（含屏幕录制），并重启 Finder。
如果扩展容器被系统保护无法删除，请给终端/DSH 完全磁盘访问权限后重跑。

## 已知限制

- 截屏一次只处理**一个显示器**，不支持跨屏单张选区；鼠标在开始选区前移动到另一屏会切换活动屏。
- 截图按显示器原生 backing scale 采集；超大屏/多窗口贴图会按真实像素占用内存。
- 截屏要求 macOS 14+；Finder 功能仍兼容 macOS 13。
- 屏幕录制权限无法脚本自动授予；ad-hoc 重新签名后可能需重新授权。
- 快捷键固定 `⌃Q`，暂不提供自定义。
- 贴图只存在内存中，退出应用后消失；不会为了内存预算压缩或降采样贴图。
- 不支持滚动截屏、窗口自动识别、OCR、云端上传、自动保存历史。
- Finder Sync 的监视范围不跨越文件系统边界；外接磁盘/挂载 DMG 中可能没有右键菜单（框架限制）。
- 移动不可通过 Finder 撤销；同名“替换”会把旧项目移入废纸篓，而不是直接删除。
- 菜单栏图标位置由 macOS 决定，可能被刘海遮挡（见上方说明）。
- 仅对当前用户安装/启用；不处理多用户、MDM 或 App Store 分发。

## 开发说明

- 主程序：`Sources/Host/`，LSUIElement AppKit 状态栏应用，无沙盒。
- 截屏核心：`Sources/Screenshot/Core/`，选区、标注、冻结层、合成。
- 截屏服务/UI：`Sources/Screenshot/Service/`、`Sources/Screenshot/UI/`。
- Finder 扩展：`Sources/Extension/`，`FIFinderSync` 子类，App Sandbox。
- 共享代码：`Sources/Shared/`，命令模型、移动引擎、菜单模型等。
- 资源：`Resources/Info-Host.plist`、`Resources/Info-Extension.plist`、`Resources/Extension.entitlements`。
- 构建脚本：`scripts/build.sh`。
- 安装/卸载：`scripts/install.sh`、`scripts/uninstall.sh`。
- 低功耗检查：`scripts/check-low-power.sh`；资源采样：`scripts/measure-resources.sh`。

重新构建后建议重新执行 `install.sh`，因为扩展需要重新签名、注册并重启 Finder。

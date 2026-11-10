# SuperFinder

仿“超级右键”的 macOS 小工具：**Finder 右键增强 + 菜单栏后台应用**。

- 菜单栏常驻图标，菜单里提供「设置… / Finder 扩展状态 / 重新加载 Finder / 退出」
- 在 Finder 中对文件或文件夹右键，可直接剪切、移动、复制绝对路径
- 在 Finder 窗口空白处右键，可把已剪切的文件移动到当前目录，或复制当前目录路径
- 后台自动启动（LaunchAgent），无悬浮球、无 Dock 图标
- 单例运行：重复启动会唤起已运行的实例并打开设置，不会产生第二个进程

当前版本：1.0.0（本地 ad-hoc 签名，非 App Store、非公证）。

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

## 系统要求

- macOS 13 或更高（开发验证环境：macOS 26.5 arm64）
- 无需 Xcode；使用了 Command Line Tools 的 `swiftc` 构建

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

1. 打开 Finder，选中一个或多个文件/文件夹。
2. 右键 →「剪切（准备移动）」。
3. 在 Finder 中右键单个文件夹/文件 →「在终端中打开」；或在目录空白处右键 →「在终端中打开当前目录」。
4. 打开目标文件夹，在空白处右键 →「移动 N 项到这里」。
   - 或直接右键目标文件夹 →「移动 N 项到此文件夹」。
   - 或对当前选择使用「移动到文件夹…」。
5. 点击菜单栏图标 →「设置…」可管理登录启动、扩展状态和 Finder 重启；
   设置窗口里也有「打开菜单栏设置」和「退出 SuperFinder」。

## 菜单栏图标被刘海挡住？

MacBook 刘海屏的菜单栏空间有限，当图标多到放不下时，macOS 会把**最左侧新增的图标排到刘海下面**，看起来“消失”了。这不是 SuperFinder 崩溃。

处理方式（任选）：

- 在「系统设置 → 菜单栏」中关闭几个不用的系统图标（例如聚焦、专注模式、屏幕镜像、显示器等），腾出位置后 SuperFinder 图标会重新出现。
- 或 ⌘ 拖动菜单栏图标，把重要的移到靠右（时钟一侧）。
- 使用菜单栏管理工具（Bartender、Frost 等）。
- 外接显示器没有刘海，通常可以直接看到图标。
- 菜单栏图标不可见时，仍可在 Finder 空白处右键 →「SuperFinder 设置…」打开设置，或直接打开 `/Applications/SuperFinder.app`。

目前 macOS 没有公开 API 让应用强制把自己的菜单栏图标插到最右侧；这是系统行为。

## 权限

- 本工具移动文件时，主程序需要读取源、写入目标目录。
- 首次移动**桌面、文稿、下载**等受保护目录中的文件时，macOS 会弹出「SuperFinder 想要访问…」，请选择**允许**。
- 如果希望完全免提示，可以在「系统设置 → 隐私与安全性 → 完全磁盘访问权限」里手动加入 `SuperFinder.app`（可选）。
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

扩展通过 `com.apple.security.temporary-exception.files.home-relative-path.read-write`
仅获得对 `~/Library/Application Support/SuperFinder/` 的读写；文件移动由主程序执行。

## 测试

```bash
./scripts/run-tests.sh
```

覆盖：命令 JSON 编解码、剪切缓冲区、路径格式化、菜单状态、移动计划/冲突/保留两者/替换/自移动保护/符号链接等。

安装后验证：

```bash
./scripts/verify.sh
```

也可以单独执行：

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

脚本会移除应用、登录项、Finder 扩展注册、扩展容器、偏好和 TCC 记录，并重启 Finder。
如果扩展容器被系统保护无法删除，请给终端/DSH 完全磁盘访问权限后重跑。

## 已知限制

- Finder Sync 的监视范围不跨越文件系统边界；外接磁盘/挂载 DMG 中可能没有右键菜单（框架限制）。
- 本工具没有实现工具栏按钮、新建文件、打开终端等其他“超级右键”功能。
- 移动不可通过 Finder 撤销；同名“替换”会把旧项目移入废纸篓，而不是直接删除。
- 菜单栏图标位置由 macOS 决定，可能被刘海遮挡（见上方说明）。
- ad-hoc 签名的应用每次重新构建后签名会变化，macOS 可能重新询问文件访问权限；这是本地工具的正常行为。
- 仅对当前用户安装/启用；不处理多用户、MDM 或 App Store 分发。

## 开发说明

- 主程序：`Sources/Host/`，LSUIElement AppKit 状态栏应用，无沙盒。
- Finder 扩展：`Sources/Extension/`，`FIFinderSync` 子类，App Sandbox。
- 共享代码：`Sources/Shared/`，命令模型、移动引擎、菜单模型等。
- 资源：`Resources/Info-Host.plist`、`Resources/Info-Extension.plist`、`Resources/Extension.entitlements`。
- 构建脚本：`scripts/build.sh`。
- 安装/卸载：`scripts/install.sh`、`scripts/uninstall.sh`。

重新构建后建议重新执行 `install.sh`，因为扩展需要重新签名、注册并重启 Finder。

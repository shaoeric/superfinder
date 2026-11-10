import AppKit

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private let statusLabel = NSTextField(labelWithString: "")
    private let autoStartCheckbox = NSButton(
        checkboxWithTitle: "登录时自动启动",
        target: nil,
        action: nil
    )
    private let versionLabel = NSTextField(labelWithString: "版本 1.0.0 · 本地 ad-hoc 签名")

    var isVisible: Bool {
        window?.isVisible == true
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 590),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SuperFinder 设置"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentMinSize = NSSize(width: 520, height: 500)
        super.init(window: window)
        window.delegate = self
        buildUI()
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refresh()
    }

    // MARK: - UI

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24)
        ])

        let title = NSTextField(labelWithString: AppConfig.appName)
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        stack.addArrangedSubview(title)

        let subtitle = makeWrappingLabel(
            "仿“超级右键”的 Finder 右键增强工具。菜单栏图标、设置和退出都从这里管理。",
            font: .systemFont(ofSize: 12),
            color: .secondaryLabelColor
        )
        addFullWidth(subtitle, to: stack)

        stack.addArrangedSubview(makeSectionLabel("Finder 右键扩展"))

        statusLabel.font = .systemFont(ofSize: 13, weight: .medium)
        stack.addArrangedSubview(statusLabel)

        let extensionButtons = NSStackView(views: [
            makeButton(title: "打开系统扩展设置", action: #selector(openExtensionSettings(_:))),
            makeButton(title: "尝试启用扩展", action: #selector(enableExtension(_:)))
        ])
        extensionButtons.orientation = .horizontal
        extensionButtons.spacing = 10
        extensionButtons.alignment = .centerY
        stack.addArrangedSubview(extensionButtons)

        let extensionHint = makeWrappingLabel(
            "macOS 15 及以上把 Finder 扩展移到了「系统设置 → 通用 → 登录项与扩展」。"
            + "如果状态显示未启用，可以先点「尝试启用扩展」；仍不行时，在系统设置中启用，或重启 Finder。",
            font: .systemFont(ofSize: 11),
            color: .secondaryLabelColor
        )
        addFullWidth(extensionHint, to: stack)

        stack.addArrangedSubview(makeSectionLabel("菜单栏图标位置"))

        let menuBarHint = makeWrappingLabel(
            "当前 Mac 的顶部菜单栏项目较多时，macOS 会把新图标排到刘海下面导致看不见。"
            + "可以打开「系统设置 → 菜单栏」，临时关闭几个不用的项目，SuperFinder 图标就会重新出现；"
            + "也可以重启登录后让图标重新排序。",
            font: .systemFont(ofSize: 11),
            color: .secondaryLabelColor
        )
        addFullWidth(menuBarHint, to: stack)

        let menuBarButtons = NSStackView(views: [
            makeButton(title: "打开菜单栏设置", action: #selector(openMenuBarSettings(_:)))
        ])
        menuBarButtons.orientation = .horizontal
        menuBarButtons.spacing = 10
        menuBarButtons.alignment = .centerY
        stack.addArrangedSubview(menuBarButtons)

        stack.addArrangedSubview(makeSectionLabel("通用"))

        autoStartCheckbox.target = self
        autoStartCheckbox.action = #selector(autoStartChanged(_:))
        stack.addArrangedSubview(autoStartCheckbox)

        stack.addArrangedSubview(makeSectionLabel("Finder 右键菜单支持的功能"))

        let features = makeWrappingLabel(
            "• 剪切（准备移动）：先记住当前选中的文件/文件夹\n"
            + "• 移动到文件夹…：选择目标文件夹后立即移动当前选择\n"
            + "• 移动 N 项到这里：在目标文件夹空白处右键，把剪切的項目移动过去\n"
            + "• 复制绝对路径：复制选中项目的绝对路径，多选时每行一个\n"
            + "• 复制当前目录路径：在 Finder 窗口空白处右键复制当前目录\n"
            + "• 在终端中打开：选中单个文件夹/文件右键，或在目录空白处右键打开当前目录",
            font: .systemFont(ofSize: 12),
            color: .labelColor
        )
        addFullWidth(features, to: stack)

        stack.addArrangedSubview(makeSectionLabel("权限提示"))

        let permissions = makeWrappingLabel(
            "首次移动桌面、文稿、下载等受保护目录中的文件时，macOS 会询问「SuperFinder 想要访问…」，请选择允许。"
            + "如果希望完全免提示，可以在「系统设置 → 隐私与安全性 → 完全磁盘访问权限」中手动加入 SuperFinder。",
            font: .systemFont(ofSize: 11),
            color: .secondaryLabelColor
        )
        addFullWidth(permissions, to: stack)

        let bottomButtons = NSStackView(views: [
            makeButton(title: "重启 Finder", action: #selector(restartFinderAction(_:))),
            makeButton(title: "退出 SuperFinder", action: #selector(quitAction(_:))),
            makeButton(title: "完成", action: #selector(doneAction(_:)))
        ])
        bottomButtons.orientation = .horizontal
        bottomButtons.spacing = 10
        bottomButtons.alignment = .centerY
        stack.addArrangedSubview(bottomButtons)

        versionLabel.font = .systemFont(ofSize: 11)
        versionLabel.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(versionLabel)

        window?.contentView?.layoutSubtreeIfNeeded()
    }

    private func makeSectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func makeWrappingLabel(
        _ text: String,
        font: NSFont,
        color: NSColor
    ) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = font
        label.textColor = color
        label.isSelectable = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private func makeButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    private func addFullWidth(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    // MARK: - State

    private func refresh() {
        let state = ExtensionStatus.current()
        statusLabel.stringValue = "状态：\(state.displayName)"
        switch state {
        case .enabled:
            statusLabel.textColor = .systemGreen
        case .disabled, .notRegistered:
            statusLabel.textColor = .systemOrange
        case .unknown:
            statusLabel.textColor = .secondaryLabelColor
        }

        autoStartCheckbox.state = LoginItemManager.shared.isEnabled ? .on : .off
    }

    // MARK: - Actions

    @objc private func openExtensionSettings(_ sender: Any?) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else {
            return
        }
        if !NSWorkspace.shared.open(url) {
            let alert = NSAlert()
            alert.messageText = "无法打开系统设置"
            alert.informativeText = "请手动打开「系统设置 → 通用 → 登录项与扩展」查看 Finder 扩展。"
            alert.runModal()
        }
    }

    @objc private func openMenuBarSettings(_ sender: Any?) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension") else {
            return
        }
        if !NSWorkspace.shared.open(url) {
            let alert = NSAlert()
            alert.messageText = "无法打开系统设置"
            alert.informativeText = "请手动打开「系统设置 → 菜单栏」调整菜单栏项目。"
            alert.runModal()
        }
    }

    @objc private func quitAction(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    @objc private func enableExtension(_ sender: Any?) {
        let result = ExtensionStatus.enable()
        refresh()

        let alert = NSAlert()
        if result.success {
            alert.messageText = "已申请启用 Finder 扩展"
            alert.informativeText = "如果右键菜单仍未出现，请点击「重启 Finder」，或在系统设置中手动启用后再重启 Finder。"
            alert.addButton(withTitle: "重启 Finder")
            alert.addButton(withTitle: "稍后")
            if alert.runModal() == .alertFirstButtonReturn {
                restartFinder(confirm: false)
            }
        } else {
            alert.alertStyle = .warning
            alert.messageText = "启用失败"
            alert.informativeText = result.message
                + "\n\n可以在终端执行：\npluginkit -e use -i \(AppConfig.extensionBundleID)\nkillall Finder"
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }

    @objc private func autoStartChanged(_ sender: NSButton) {
        let shouldEnable = sender.state == .on
        do {
            try LoginItemManager.shared.setEnabled(shouldEnable)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "登录项设置失败"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        autoStartCheckbox.state = LoginItemManager.shared.isEnabled ? .on : .off
    }

    @objc private func restartFinderAction(_ sender: Any?) {
        restartFinder(confirm: true)
    }

    @objc private func doneAction(_ sender: Any?) {
        window?.close()
    }

    private func restartFinder(confirm: Bool) {
        if confirm {
            let alert = NSAlert()
            alert.messageText = "重新加载 Finder？"
            alert.informativeText = "Finder 会重启，所有 Finder 窗口会重新打开，右键菜单会重新加载。"
            alert.addButton(withTitle: "重新加载")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        do {
            _ = try ProcessRunner.runCheckingStatus("/usr/bin/killall", ["Finder"])
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "重启 Finder 失败"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        refresh()
    }
}

import AppKit

final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var extensionStatusItem: NSMenuItem!
    private var baseImage: NSImage?
    private var flashWorkItem: DispatchWorkItem?
    private var tooltipWorkItem: DispatchWorkItem?

    var onOpenSettings: (() -> Void)?
    var onReloadFinder: (() -> Void)?
    var onQuit: (() -> Void)?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        baseImage = Self.makeStatusImage()
        if let button = statusItem.button {
            button.image = baseImage
            button.imagePosition = .imageOnly
            button.toolTip = AppConfig.appName
            button.setAccessibilityLabel(AppConfig.appName)
        }

        buildMenu()
        statusItem.menu = menu
        refreshExtensionStatus()

    }

    // MARK: - Menu

    private func buildMenu() {
        menu.autoenablesItems = false
        menu.delegate = self

        let settingsItem = NSMenuItem(
            title: "设置…",
            action: #selector(openSettingsAction(_:)),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        extensionStatusItem = NSMenuItem(
            title: "Finder 扩展：检查中…",
            action: #selector(openSettingsAction(_:)),
            keyEquivalent: ""
        )
        extensionStatusItem.target = self
        menu.addItem(extensionStatusItem)

        let reloadItem = NSMenuItem(
            title: "重新加载 Finder",
            action: #selector(reloadFinderAction(_:)),
            keyEquivalent: ""
        )
        reloadItem.target = self
        menu.addItem(reloadItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出 \(AppConfig.appName)",
            action: #selector(quitAction(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)
    }

    func refreshExtensionStatus() {
        let state = ExtensionStatus.current()
        extensionStatusItem.title = "Finder 扩展：\(state.displayName)"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshExtensionStatus()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshExtensionStatus()
    }

    // MARK: - Feedback

    func setBusy(_ busy: Bool) {
        if busy {
            cancelFlash()
            statusItem.button?.toolTip = "正在移动…"
        } else {
            statusItem.button?.toolTip = AppConfig.appName
        }
    }

    func flashSuccess(count: Int) {
        let original = baseImage
        let image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "已移动")
            ?? original
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = count > 0 ? "已移动 \(count) 项" : AppConfig.appName
        scheduleRestore(after: 1.8)
    }

    func showTransientTooltip(_ text: String, duration: TimeInterval = 2.0) {
        statusItem.button?.toolTip = text
        tooltipWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.statusItem.button?.toolTip = AppConfig.appName
        }
        tooltipWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }

    private func scheduleRestore(after delay: TimeInterval) {
        flashWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.statusItem.button?.image = self.baseImage
            self.statusItem.button?.toolTip = AppConfig.appName
        }
        flashWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func cancelFlash() {
        flashWorkItem?.cancel()
        flashWorkItem = nil
    }

    // MARK: - Actions

    @objc private func openSettingsAction(_ sender: Any?) {
        onOpenSettings?()
    }

    @objc private func reloadFinderAction(_ sender: Any?) {
        onReloadFinder?()
    }

    @objc private func quitAction(_ sender: Any?) {
        onQuit?()
    }

    // MARK: - Icon

    private static func makeStatusImage() -> NSImage {
        let symbolNames = [
            "contextualmenu.and.cursorarrow",
            "filemenu.and.cursorarrow",
            "folder"
        ]
        for name in symbolNames {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: AppConfig.appName) {
                image.isTemplate = true
                image.size = NSSize(width: 18, height: 18)
                return image
            }
        }

        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let frame = NSBezierPath(
                roundedRect: NSRect(x: 1.5, y: 4.0, width: 15.0, height: 11.0),
                xRadius: 2.5,
                yRadius: 2.5
            )
            frame.lineWidth = 1.4
            frame.stroke()

            let dots = NSBezierPath()
            for x in [4.5, 9.0, 13.5] {
                dots.appendOval(in: NSRect(x: x - 0.8, y: 9.2, width: 1.6, height: 1.6))
            }
            dots.fill()

            return true
        }
        image.isTemplate = true
        return image
    }
}

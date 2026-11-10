import AppKit
import FinderSync
import os

@objc(FinderSync)
final class FinderSync: FIFinderSync {
    private let log = Logger(subsystem: AppConfig.extensionBundleID, category: "finder")
    private let cutBuffer = CutBufferStore.defaultStore()

    override init() {
        super.init()

        // Monitor every local directory so the menus appear anywhere in Finder.
        // Finder Sync does not span filesystem boundaries; mounted external
        // volumes may not show the menu. Documented limitation.
        let root = URL(fileURLWithPath: "/")
        FIFinderSyncController.default().directoryURLs = [root]

        log.info("FinderSync extension initialized; monitoring root directory")
    }

    // MARK: - Menu

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let controller = FIFinderSyncController.default()

        switch menuKind {
        case .contextualMenuForItems:
            guard let selected = controller.selectedItemURLs(), !selected.isEmpty else {
                return nil
            }
            let specs = MenuModel.itemsMenu(
                selectedCount: selected.count,
                cutCount: cutBuffer.count
            )
            return makeMenu(specs)

        case .contextualMenuForContainer:
            let hasTargetedURL = controller.targetedURL() != nil
            let specs = MenuModel.containerMenu(
                cutCount: cutBuffer.count,
                hasTargetedURL: hasTargetedURL
            )
            return makeMenu(specs)

        default:
            return nil
        }
    }

    private func makeMenu(_ specs: [FinderMenuItemSpec]) -> NSMenu {
        let menu = NSMenu(title: AppConfig.appName)
        for spec in specs {
            let item = NSMenuItem(
                title: spec.title,
                action: selector(for: spec.action),
                keyEquivalent: ""
            )
            item.target = self
            item.isEnabled = spec.enabled
            if let symbolName = spec.symbolName,
               let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
                image.isTemplate = true
                item.image = image
            }
            menu.addItem(item)
        }
        return menu
    }

    private func selector(for action: FinderMenuAction) -> Selector {
        switch action {
        case .cutSelection:
            return #selector(cutSelection(_:))
        case .moveCutItemsHere:
            return #selector(moveCutItemsHere(_:))
        case .moveSelectionToChosenFolder:
            return #selector(moveSelectionToChosenFolder(_:))
        case .copySelectedPaths:
            return #selector(copySelectedPaths(_:))
        case .copyTargetedPath:
            return #selector(copyTargetedPath(_:))
        case .openTerminalForSelection:
            return #selector(openTerminalForSelection(_:))
        case .openTerminalHere:
            return #selector(openTerminalHere(_:))
        case .clearCutBuffer:
            return #selector(clearCutBuffer(_:))
        case .openSettings:
            return #selector(openSettings(_:))
        }
    }

    // MARK: - Actions

    @objc func cutSelection(_ sender: Any?) {
        guard let urls = FIFinderSyncController.default().selectedItemURLs(), !urls.isEmpty else {
            return
        }
        cutBuffer.save(paths: urls.map(\.path))
        playPop()
        log.info("Cut \(urls.count, privacy: .public) item(s)")
    }

    @objc func moveCutItemsHere(_ sender: Any?) {
        let controller = FIFinderSyncController.default()
        let sources = cutBuffer.load()
        guard !sources.isEmpty else { return }

        let destination = controller.targetedURL() ?? controller.selectedItemURLs()?.first
        guard let destination else {
            showError("找不到目标文件夹", detail: "请重新打开目标文件夹后再试。")
            return
        }

        let command = MoveCommand(
            action: .moveHere,
            sources: sources,
            destination: destination.path
        )
        dispatch(command, clearCutAfter: true)
    }

    @objc func moveSelectionToChosenFolder(_ sender: Any?) {
        guard let urls = FIFinderSyncController.default().selectedItemURLs(), !urls.isEmpty else {
            return
        }
        let command = MoveCommand(
            action: .moveToFolder,
            sources: urls.map(\.path),
            destination: nil
        )
        dispatch(command, clearCutAfter: false)
    }

    @objc func copySelectedPaths(_ sender: Any?) {
        guard let urls = FIFinderSyncController.default().selectedItemURLs(), !urls.isEmpty else {
            return
        }
        copyToPasteboard(PathFormatter.absolutePaths(for: urls))
    }

    @objc func copyTargetedPath(_ sender: Any?) {
        guard let url = FIFinderSyncController.default().targetedURL() else { return }
        copyToPasteboard(url.path)
    }

    @objc func openTerminalForSelection(_ sender: Any?) {
        guard let urls = FIFinderSyncController.default().selectedItemURLs(), urls.count == 1 else {
            return
        }
        dispatchTerminal(at: urls[0])
    }

    @objc func openTerminalHere(_ sender: Any?) {
        guard let url = FIFinderSyncController.default().targetedURL() else { return }
        dispatchTerminal(at: url)
    }

    private func dispatchTerminal(at url: URL) {
        let command = MoveCommand(
            action: .openTerminal,
            sources: [url.path],
            destination: nil
        )
        dispatch(command, clearCutAfter: false)
    }

    @objc func clearCutBuffer(_ sender: Any?) {
        cutBuffer.clear()
    }

    @objc func openSettings(_ sender: Any?) {
        guard let url = URL(string: "superfinder://settings") else { return }
        if !NSWorkspace.shared.open(url) {
            showError("无法打开 SuperFinder 设置", detail: "请确认 SuperFinder.app 已安装到「应用程序」文件夹。")
        }
    }

    // MARK: - Dispatch

    private func dispatch(_ command: MoveCommand, clearCutAfter: Bool) {
        let commandURL: URL
        do {
            commandURL = try CommandStore.writeFromExtension(command)
        } catch {
            showError("无法把移动请求交给 SuperFinder", detail: error.localizedDescription)
            return
        }

        if isHostRunning() {
            if clearCutAfter {
                cutBuffer.clear()
            }
            return
        }

        launchHost { [weak self] success in
            DispatchQueue.main.async {
                guard let self else { return }
                if success {
                    if clearCutAfter {
                        self.cutBuffer.clear()
                    }
                } else {
                    CommandStore.remove(commandURL)
                    self.showError(
                        "无法启动 SuperFinder",
                        detail: "请确认 SuperFinder.app 已安装到「应用程序」文件夹，或重新安装后再试。"
                    )
                }
            }
        }
    }

    private func isHostRunning() -> Bool {
        !NSRunningApplication.runningApplications(
            withBundleIdentifier: AppConfig.hostBundleID
        ).isEmpty
    }

    private func launchHost(completion: @escaping (Bool) -> Void) {
        let hostURL = hostApplicationURL()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.promptsUserIfNeeded = true

        log.info("Launching host app at \(hostURL.path, privacy: .public)")
        NSWorkspace.shared.openApplication(
            at: hostURL,
            configuration: configuration
        ) { application, error in
            if let error {
                NSLog("SuperFinder extension: failed to launch host: \(error)")
                completion(false)
            } else {
                NSLog("SuperFinder extension: launched host pid=\(application?.processIdentifier ?? -1)")
                completion(true)
            }
        }
    }

    private func hostApplicationURL() -> URL {
        Bundle(for: FinderSync.self).bundleURL
            .deletingLastPathComponent() // PlugIns
            .deletingLastPathComponent() // Contents
            .deletingLastPathComponent() // SuperFinder.app
    }

    private func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    private func playPop() {
        if let sound = NSSound(named: NSSound.Name("Pop")) {
            sound.play()
        }
    }

    private func showError(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "好")

        let present = {
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        if Thread.isMainThread {
            present()
        } else {
            DispatchQueue.main.async(execute: present)
        }
    }
}

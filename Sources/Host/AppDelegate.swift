import AppKit
import Carbon
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: AppConfig.logSubsystem, category: "host")
    private let coordinator = MoveCoordinator()
    private var statusBar: StatusBarController!
    private var watcher: CommandWatcher!
    var instanceLock: InstanceLock?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        CommandStore.ensureSharedDirectory()
        CommandStore.cleanupStaleCommandFiles()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleShowSettingsNotification(_:)),
            name: NSNotification.Name(AppConfig.showSettingsNotification),
            object: nil
        )

        statusBar = StatusBarController()
        coordinator.statusBar = statusBar

        statusBar.onOpenSettings = { [weak self] in
            self?.showSettings()
        }
        statusBar.onReloadFinder = { [weak self] in
            self?.reloadFinder(confirm: true)
        }
        statusBar.onQuit = {
            NSApp.terminate(nil)
        }

        watcher = CommandWatcher(coordinator: coordinator)
        watcher.start()
        statusBar.refreshExtensionStatus()

        log.info("SuperFinder host app started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        watcher?.stop()
        DistributedNotificationCenter.default().removeObserver(self)
        log.info("SuperFinder host app terminating")
    }

    @objc private func handleShowSettingsNotification(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.showSettings()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if coordinator.isBusy {
            coordinator.pendingTerminationReply = true
            return .terminateLater
        }
        return .terminateNow
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    @objc private func handleGetURL(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            switch url.host {
            case "settings":
                self?.showSettings()
            case "quit":
                NSApp.terminate(nil)
            default:
                break
            }
        }
    }

    private func showSettings() {
        SettingsWindowController.shared.show()
    }

    private func reloadFinder(confirm: Bool) {
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
        statusBar.refreshExtensionStatus()
    }
}

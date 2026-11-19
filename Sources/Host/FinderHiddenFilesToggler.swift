import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import os

enum FinderHiddenFilesToggleError: LocalizedError {
    case accessibilityPermissionMissing
    case finderNotRunning
    case finderNotFrontmost

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            return "需要一次「辅助功能」权限，才能不重启 Finder 直接切换隐藏文件。"
        case .finderNotRunning:
            return "Finder 当前没有运行。"
        case .finderNotFrontmost:
            return "没有把 Finder 切到前台，Finder 不会接收快捷键。请回到 Finder 窗口后重试。"
        }
    }
}

/// Toggles Finder's live hidden-file view without quitting it. macOS exposes no
/// public API for this: `AppleShowAllFiles` is only read when Finder launches,
/// and the native `⌘⇧.` shortcut changes the running session without writing
/// that preference. So once the user grants Accessibility, we activate Finder
/// and deliver the same shortcut directly to its process, then persist the new
/// state ourselves for the menu title and the next Finder launch.
enum FinderHiddenFilesToggler {
    private static let log = Logger(subsystem: AppConfig.logSubsystem, category: "finder-hidden-files")

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openAccessibilitySettings()
    }

    static func openAccessibilitySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
        ]
        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    static func toggle(completion: @escaping (Result<Bool, Error>) -> Void) {
        guard AXIsProcessTrusted() else {
            log.error("accessibility permission missing")
            completion(.failure(FinderHiddenFilesToggleError.accessibilityPermissionMissing))
            return
        }
        guard let finder = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.finder"
        ).first else {
            log.error("Finder is not running")
            completion(.failure(FinderHiddenFilesToggleError.finderNotRunning))
            return
        }

        let visibleBefore = FinderHiddenFiles.isVisible()
        let visibleAfter = !visibleBefore
        log.info("toggle requested before=\(visibleBefore, privacy: .public) target=\(visibleAfter, privacy: .public)")

        ensureFrontmost(finder) { frontmost in
            guard frontmost else {
                log.error("Finder is not frontmost; shortcut not sent")
                completion(.failure(FinderHiddenFilesToggleError.finderNotFrontmost))
                return
            }

            // When this command comes from the Finder context menu, Finder is
            // still tearing the menu down. Key equivalents posted during that
            // tracking loop are dropped, so let the menu settle first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier
                    == finder.processIdentifier else {
                    log.error("Finder lost focus before the shortcut was sent")
                    completion(.failure(FinderHiddenFilesToggleError.finderNotFrontmost))
                    return
                }
                postToggleShortcut(to: finder.processIdentifier)
                let persisted = persist(visibleAfter)
                log.info(
                    "posted command-shift-period pid=\(finder.processIdentifier, privacy: .public) visible=\(visibleAfter, privacy: .public) persisted=\(persisted, privacy: .public)"
                )
                completion(.success(visibleAfter))
            }
        }
    }

    /// Brings Finder to the front when the command did not originate from its
    /// context menu. Finder ignores keyboard shortcuts while another app is
    /// active, so this is required before posting `⌘⇧.`.
    private static func ensureFrontmost(
        _ finder: NSRunningApplication,
        completion: @escaping (Bool) -> Void
    ) {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == finder.processIdentifier {
            completion(true)
            return
        }

        log.info("Finder not frontmost; activating with Accessibility")
        _ = finder.activate(options: [.activateAllWindows])
        activateWithAccessibility(pid: finder.processIdentifier)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
                == finder.processIdentifier
            completion(frontmost)
        }
    }

    private static func activateWithAccessibility(pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        let setFrontmost = AXUIElementSetAttributeValue(
            app,
            kAXFrontmostAttribute as CFString,
            kCFBooleanTrue
        )
        log.info("AX set frontmost result=\(setFrontmost.rawValue, privacy: .public)")

        var windowsValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            app,
            kAXWindowsAttribute as CFString,
            &windowsValue
        ) == .success, let windowsValue {
            let windows = windowsValue as! CFArray
            if CFArrayGetCount(windows) > 0 {
                let rawWindow = CFArrayGetValueAtIndex(windows, 0)
                let window = unsafeBitCast(rawWindow, to: AXUIElement.self)
                let raiseResult = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                log.info("AX raise result=\(raiseResult.rawValue, privacy: .public)")
            }
        }
    }

    /// Delivers the key directly to Finder's process. Finder processes menu key
    /// equivalents only while it is active, which is why the caller activates it
    /// first. The Unicode payload keeps the character stable across layouts.
    private static func postToggleShortcut(to pid: pid_t) {
        let source = CGEventSource(stateID: .hidSystemState)
        let characters = Array(".".utf16) // 47 is kVK_ANSI_Period

        for keyDown in [true, false] {
            guard let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: 47,
                keyDown: keyDown
            ) else { continue }
            event.flags = [.maskCommand, .maskShift]
            event.keyboardSetUnicodeString(
                stringLength: characters.count,
                unicodeString: characters
            )
            event.postToPid(pid)
        }
    }

    /// Finder's shortcut is session-only, so persist the state it just switched
    /// to. The extension reads this value to choose the menu title, and Finder
    /// reads it on the next launch.
    private static func persist(_ visible: Bool) -> Bool {
        let result = try? ProcessRunner.run(
            "/usr/bin/defaults",
            [
                "write",
                FinderHiddenFiles.preferenceDomain,
                FinderHiddenFiles.preferenceKey,
                "-bool",
                visible ? "true" : "false"
            ]
        )
        FinderHiddenFiles.refreshPreferenceCache()
        return result?.status == 0
    }
}

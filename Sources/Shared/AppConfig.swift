import Darwin
import Foundation

/// Shared identifiers and locations used by both the host app and the Finder extension.
enum AppConfig {
    static let appName = "SuperFinder"
    static let hostBundleID = "com.shaobt.superfinder"
    static let extensionBundleID = "com.shaobt.superfinder.FinderSync"
    static let launchAgentLabel = "com.shaobt.superfinder"
    static let commandQueuedNotification = "com.shaobt.superfinder.commandQueued"
    static let showSettingsNotification = "com.shaobt.superfinder.showSettings"

    static let sharedSupportDirectoryName = "SuperFinder"
    static let sharedSupportHomeRelativePath = "Library/Application Support/SuperFinder"

    static let maxCommandAge: TimeInterval = 10 * 60
    static let commandPollInterval: TimeInterval = 0.5

    /// The real user home. Inside an App Sandbox `FileManager.homeDirectoryForCurrentUser`
    /// may resolve to the container, so use the passwd entry instead. This is what lets
    /// the extension reach the shared `~/Library/Application Support/SuperFinder` folder
    /// through its temporary-exception entitlement.
    static var homeDirectory: URL {
        if let passwd = getpwuid(getuid()), let home = passwd.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// `~/Library/Application Support/SuperFinder`
    static var sharedSupportDirectory: URL {
        homeDirectory
            .appendingPathComponent(sharedSupportHomeRelativePath, isDirectory: true)
            .standardizedFileURL
    }

    /// `~/Library/Application Support/SuperFinder/commands`
    static var sharedCommandsDirectory: URL {
        sharedSupportDirectory.appendingPathComponent("commands", isDirectory: true)
    }

    /// Fallback command directory inside the sandboxed extension container.
    /// The host app may not always be permitted to read this on newer macOS,
    /// but we scan it when possible.
    static var extensionContainerSupportDirectory: URL {
        homeDirectory
            .appendingPathComponent("Library/Containers/\(extensionBundleID)/Data/Library/Application Support/SuperFinder", isDirectory: true)
            .standardizedFileURL
    }

    static var extensionContainerCommandsDirectory: URL {
        extensionContainerSupportDirectory.appendingPathComponent("commands", isDirectory: true)
    }

    /// Directories scanned by the host app, in priority order.
    static var hostCommandDirectories: [URL] {
        [sharedCommandsDirectory, extensionContainerCommandsDirectory]
    }

    static let installedAppPath = "/Applications/SuperFinder.app"
    static let installedHostExecutablePath = "/Applications/SuperFinder.app/Contents/MacOS/SuperFinder"
    static let installedExtensionPath = "/Applications/SuperFinder.app/Contents/PlugIns/SuperFinderExtension.appex"

    static var launchAgentPlistURL: URL {
        homeDirectory.appendingPathComponent("Library/LaunchAgents/\(launchAgentLabel).plist")
    }

    static var userID: uid_t {
        getuid()
    }

    static var logSubsystem: String { hostBundleID }
}

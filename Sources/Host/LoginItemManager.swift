import Foundation

enum LoginItemError: LocalizedError {
    case failedToWritePlist(Error)
    case failedToEnable(String)
    case failedToDisable(String)

    var errorDescription: String? {
        switch self {
        case .failedToWritePlist(let error):
            return "写入登录项配置失败：\(error.localizedDescription)"
        case .failedToEnable(let message):
            return "启用登录时自动启动失败：\(message)"
        case .failedToDisable(let message):
            return "关闭登录时自动启动失败：\(message)"
        }
    }
}

final class LoginItemManager {
    static let shared = LoginItemManager()

    private let fileManager = FileManager.default

    var isEnabled: Bool {
        guard fileManager.fileExists(atPath: AppConfig.launchAgentPlistURL.path) else {
            return false
        }
        let result = try? ProcessRunner.run(
            "/bin/launchctl",
            ["print", "gui/\(AppConfig.userID)/\(AppConfig.launchAgentLabel)"]
        )
        return result?.status == 0
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try install()
        } else {
            try uninstall()
        }
    }

    private func install() throws {
        let plist: [String: Any] = [
            "Label": AppConfig.launchAgentLabel,
            "ProgramArguments": [
                "/usr/bin/open",
                "-g",
                "-a",
                AppConfig.installedAppPath
            ],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua"
        ]

        do {
            try fileManager.createDirectory(
                at: AppConfig.launchAgentPlistURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0
            )
            try data.write(to: AppConfig.launchAgentPlistURL, options: .atomic)
            try? fileManager.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: AppConfig.launchAgentPlistURL.path
            )
        } catch {
            throw LoginItemError.failedToWritePlist(error)
        }

        let plistPath = AppConfig.launchAgentPlistURL.path
        _ = try? ProcessRunner.run(
            "/bin/launchctl",
            ["bootout", "gui/\(AppConfig.userID)", plistPath]
        )
        _ = try? ProcessRunner.run(
            "/bin/launchctl",
            ["enable", "gui/\(AppConfig.userID)/\(AppConfig.launchAgentLabel)"]
        )
        let result = try ProcessRunner.run(
            "/bin/launchctl",
            ["bootstrap", "gui/\(AppConfig.userID)", plistPath]
        )
        guard result.status == 0 else {
            throw LoginItemError.failedToEnable(result.combinedOutput)
        }
    }

    private func uninstall() throws {
        let plistPath = AppConfig.launchAgentPlistURL.path
        let result = try? ProcessRunner.run(
            "/bin/launchctl",
            ["bootout", "gui/\(AppConfig.userID)", plistPath]
        )
        if let result, result.status != 0 {
            // A missing job is fine; other errors are reported softly.
            NSLog("SuperFinder: launchctl bootout returned \(result.status): \(result.combinedOutput)")
        }
        do {
            if fileManager.fileExists(atPath: plistPath) {
                try fileManager.removeItem(at: AppConfig.launchAgentPlistURL)
            }
        } catch {
            throw LoginItemError.failedToDisable(error.localizedDescription)
        }
    }
}

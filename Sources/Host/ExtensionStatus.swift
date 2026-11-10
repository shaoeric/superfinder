import Foundation
import FinderSync

enum ExtensionStatus {
    enum State: Equatable {
        case enabled
        case disabled
        case notRegistered
        case unknown

        var displayName: String {
            switch self {
            case .enabled:
                return "已启用"
            case .disabled:
                return "已安装但未启用"
            case .notRegistered:
                return "未注册"
            case .unknown:
                return "未知"
            }
        }
    }

    static func current() -> State {
        if #available(macOS 10.14, *), FIFinderSyncController.isExtensionEnabled {
            return .enabled
        }

        guard let result = try? ProcessRunner.run(
            "/usr/bin/pluginkit",
            ["-mAD", "-p", "com.apple.FinderSync"]
        ) else {
            return .unknown
        }

        guard result.status == 0 else {
            return .unknown
        }

        for line in result.standardOutput.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let matchRange = trimmed.range(of: AppConfig.extensionBundleID) else { continue }
            guard matchRange.lowerBound == trimmed.startIndex else { continue }

            if trimmed.hasPrefix("+") {
                return .enabled
            }
            if trimmed.hasPrefix("-") || trimmed.hasPrefix("?") {
                return .disabled
            }
        }
        return .notRegistered
    }

    /// Runs the same election command users would run in Terminal.
    @discardableResult
    static func enable() -> (success: Bool, message: String) {
        guard let result = try? ProcessRunner.run(
            "/usr/bin/pluginkit",
            ["-e", "use", "-i", AppConfig.extensionBundleID]
        ) else {
            return (false, "无法运行 pluginkit。")
        }

        if result.status == 0 {
            return (true, "已向系统申请启用 Finder 扩展。")
        }

        let output = result.combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return (false, output.isEmpty ? "pluginkit 返回退出码 \(result.status)。" : output)
    }
}

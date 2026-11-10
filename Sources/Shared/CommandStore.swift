import Foundation

enum CommandStoreError: LocalizedError {
    case noWritableDirectory
    case writeFailed(URL, Error)

    var errorDescription: String? {
        switch self {
        case .noWritableDirectory:
            return "无法创建命令目录"
        case .writeFailed(let url, let error):
            return "写入命令文件失败：\(url.path)（\(error.localizedDescription)）"
        }
    }
}

enum CommandStore {
    static let fileManager = FileManager.default

    /// Extension side: try the shared Application Support directory first, then
    /// fall back to the extension's own sandbox container.
    static func writeFromExtension(_ command: MoveCommand) throws -> URL {
        let ownDirectory = defaultExtensionSupportDirectory.appendingPathComponent("commands", isDirectory: true)
        var candidates = [AppConfig.sharedCommandsDirectory, ownDirectory]
        var lastError: Error?

        let data = try command.encodedData()
        while let directory = candidates.first {
            candidates.removeFirst()
            do {
                try fileManager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
                let fileURL = directory.appendingPathComponent(command.fileName)
                try data.write(to: fileURL, options: .atomic)
                try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
                return fileURL
            } catch {
                lastError = error
            }
        }

        if let lastError {
            let attempted = AppConfig.sharedCommandsDirectory
            throw CommandStoreError.writeFailed(attempted, lastError)
        }
        throw CommandStoreError.noWritableDirectory
    }

    /// Host side: make sure the shared command directory exists.
    static func ensureSharedDirectory() {
        do {
            try fileManager.createDirectory(
                at: AppConfig.sharedCommandsDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            NSLog("SuperFinder: cannot create shared command directory: \(error)")
        }
    }

    /// Host side: all pending command files, oldest first.
    static func pendingCommandFiles() -> [URL] {
        var result: [URL] = []
        for directory in AppConfig.hostCommandDirectories {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in contents where url.pathExtension.lowercased() == "json" {
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                if values?.isRegularFile == true {
                    result.append(url)
                }
            }
        }
        return result.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Host side: remove files that are definitely unusable or far too old.
    static func cleanupStaleCommandFiles(maxAge: TimeInterval = 24 * 60 * 60) {
        let now = Date()
        for directory in AppConfig.hostCommandDirectories {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for url in contents where url.pathExtension.lowercased() == "json" {
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if let modified, now.timeIntervalSince(modified) > maxAge {
                    try? fileManager.removeItem(at: url)
                }
            }
        }
    }

    static func remove(_ url: URL) {
        try? fileManager.removeItem(at: url)
    }

    private static var defaultExtensionSupportDirectory: URL {
        if let url = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return url.appendingPathComponent(AppConfig.sharedSupportDirectoryName, isDirectory: true)
        }
        return AppConfig.sharedSupportDirectory
    }
}

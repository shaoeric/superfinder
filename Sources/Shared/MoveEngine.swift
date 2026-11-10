import Foundation

enum MoveConflictResolution {
    case keepBoth
    case replace
    case cancel
}

enum MovePlanError: LocalizedError {
    case destinationMissing(URL)
    case destinationNotDirectory(URL)

    var errorDescription: String? {
        switch self {
        case .destinationMissing(let url):
            return "目标文件夹不存在：\(url.path)"
        case .destinationNotDirectory(let url):
            return "目标不是文件夹：\(url.path)"
        }
    }
}

struct MovePlanItem: Equatable {
    let source: URL
    let baseDestination: URL
    let conflict: Bool
    let skip: Bool
    let invalidReason: String?
}

struct MovePlan {
    let destinationDirectory: URL
    let items: [MovePlanItem]

    var itemsNeedingConflictResolution: [MovePlanItem] {
        items.filter { $0.conflict && !$0.skip && $0.invalidReason == nil }
    }

    var validItems: [MovePlanItem] {
        items.filter { !$0.skip && $0.invalidReason == nil }
    }

    var skippedItems: [MovePlanItem] {
        items.filter(\.skip)
    }

    var invalidItems: [MovePlanItem] {
        items.filter { $0.invalidReason != nil }
    }
}

struct MoveFailure: Equatable {
    let source: URL
    let message: String
}

struct MoveOutcome {
    let destinationDirectory: URL
    var moved: [URL] = []
    var skipped: [URL] = []
    var failures: [MoveFailure] = []

    var movedCount: Int { moved.count }
    var failureCount: Int { failures.count }
}

enum MoveEngine {
    static let fileManager = FileManager.default

    // MARK: - Planning

    static func makePlan(sources: [URL], destinationDirectory rawDestination: URL) throws -> MovePlan {
        let destination = rawDestination.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: destination.path, isDirectory: &isDirectory) else {
            throw MovePlanError.destinationMissing(destination)
        }
        guard isDirectory.boolValue else {
            throw MovePlanError.destinationNotDirectory(destination)
        }

        let resolvedDestination = destination.resolvingSymlinksInPath()
        var items: [MovePlanItem] = []

        for rawSource in sources {
            let source = rawSource.standardizedFileURL
            let baseDestination = destination.appendingPathComponent(source.lastPathComponent)

            var sourceIsDirectoryFlag: ObjCBool = false
            guard fileManager.fileExists(atPath: source.path, isDirectory: &sourceIsDirectoryFlag) else {
                items.append(
                    MovePlanItem(
                        source: source,
                        baseDestination: baseDestination,
                        conflict: false,
                        skip: false,
                        invalidReason: "文件已不存在"
                    )
                )
                continue
            }

            let sourceIsDirectory = sourceIsDirectoryFlag.boolValue && !isSymbolicLink(source)
            let resolvedSource = source.resolvingSymlinksInPath()

            // Moving an item into the folder it already lives in is a no-op.
            if source.deletingLastPathComponent().standardizedFileURL.path == destination.path {
                items.append(
                    MovePlanItem(
                        source: source,
                        baseDestination: baseDestination,
                        conflict: false,
                        skip: true,
                        invalidReason: nil
                    )
                )
                continue
            }

            // Never move a folder into itself or one of its descendants.
            if resolvedDestination.path == resolvedSource.path ||
                resolvedDestination.path.hasPrefix(resolvedSource.path + "/") {
                items.append(
                    MovePlanItem(
                        source: source,
                        baseDestination: baseDestination,
                        conflict: false,
                        skip: false,
                        invalidReason: sourceIsDirectory
                            ? "不能把文件夹移动到它自己内部"
                            : "目标路径无效"
                    )
                )
                continue
            }

            let conflict = fileManager.fileExists(atPath: baseDestination.path)
            items.append(
                MovePlanItem(
                    source: source,
                    baseDestination: baseDestination,
                    conflict: conflict,
                    skip: false,
                    invalidReason: nil
                )
            )
        }

        return MovePlan(destinationDirectory: destination, items: items)
    }

    // MARK: - Execution

    static func execute(
        plan: MovePlan,
        resolution: MoveConflictResolution,
        trashItem: (URL) throws -> Void = MoveEngine.trash
    ) -> MoveOutcome {
        var outcome = MoveOutcome(destinationDirectory: plan.destinationDirectory)
        guard resolution != .cancel else {
            outcome.skipped.append(contentsOf: plan.validItems.map(\.source))
            return outcome
        }

        for item in plan.items {
            if item.skip {
                outcome.skipped.append(item.source)
                continue
            }
            if let invalidReason = item.invalidReason {
                outcome.failures.append(MoveFailure(source: item.source, message: invalidReason))
                continue
            }

            var finalDestination = item.baseDestination

            if fileManager.fileExists(atPath: finalDestination.path) {
                switch resolution {
                case .replace:
                    do {
                        try trashItem(finalDestination)
                    } catch {
                        outcome.failures.append(
                            MoveFailure(
                                source: item.source,
                                message: "无法把原有项目移入废纸篓：\(friendly(error))"
                            )
                        )
                        continue
                    }
                case .keepBoth:
                    finalDestination = uniqueDestination(
                        for: item.source,
                        in: plan.destinationDirectory
                    )
                case .cancel:
                    continue
                }
            }

            if resolution == .keepBoth, fileManager.fileExists(atPath: finalDestination.path) {
                finalDestination = uniqueDestination(
                    for: item.source,
                    in: plan.destinationDirectory
                )
            }

            do {
                try fileManager.moveItem(at: item.source, to: finalDestination)
                outcome.moved.append(finalDestination)
            } catch {
                outcome.failures.append(
                    MoveFailure(
                        source: item.source,
                        message: friendly(error)
                    )
                )
            }
        }

        return outcome
    }

    // MARK: - Naming

    static func uniqueDestination(for source: URL, in directory: URL) -> URL {
        let isDirectory = isDirectoryItem(source) && !isSymbolicLink(source)

        if isDirectory {
            let baseName = source.lastPathComponent
            var index = 2
            while index < 10_000 {
                let candidate = directory.appendingPathComponent("\(baseName) \(index)")
                if !fileManager.fileExists(atPath: candidate.path) {
                    return candidate
                }
                index += 1
            }
            return directory.appendingPathComponent("\(baseName) \(UUID().uuidString)")
        }

        let baseName = source.deletingPathExtension().lastPathComponent
        let pathExtension = source.pathExtension
        var index = 2
        while index < 10_000 {
            let name: String
            if pathExtension.isEmpty {
                name = "\(baseName) \(index)"
            } else {
                name = "\(baseName) \(index).\(pathExtension)"
            }
            let candidate = directory.appendingPathComponent(name)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }

        let fallback = "\(baseName) \(UUID().uuidString)" + (pathExtension.isEmpty ? "" : ".\(pathExtension)")
        return directory.appendingPathComponent(fallback)
    }

    static func isDirectoryItem(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    static func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
    }

    static func trash(_ url: URL) throws {
        try fileManager.trashItem(at: url, resultingItemURL: nil)
    }

    private static func friendly(_ error: Error) -> String {
        let nsError = error as NSError
        let base = nsError.localizedDescription
        if base.isEmpty {
            return "未知错误（\(nsError.domain) \(nsError.code)）"
        }
        return base
    }
}

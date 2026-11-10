import Foundation

/// Persisted Windows-style "cut" state, shared by all Finder extension instances.
struct CutBufferState: Codable, Equatable {
    var paths: [String]
    var updatedAt: Date
}

struct CutBufferStore {
    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Default location inside the extension's sandbox container.
    static func defaultStore() -> CutBufferStore {
        let supportDirectory: URL
        if let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            supportDirectory = url.appendingPathComponent(AppConfig.sharedSupportDirectoryName, isDirectory: true)
        } else {
            supportDirectory = AppConfig.sharedSupportDirectory
        }
        return CutBufferStore(fileURL: supportDirectory.appendingPathComponent("cut-buffer.json"))
    }

    func load() -> [String] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(CutBufferState.self, from: data) else { return [] }
        return state.paths.filter { !$0.isEmpty }
    }

    var count: Int {
        load().count
    }

    func save(paths: [String]) {
        var seen = Set<String>()
        let normalized = paths.filter { path in
            guard !path.isEmpty else { return false }
            return seen.insert(path).inserted
        }
        guard !normalized.isEmpty else {
            clear()
            return
        }

        let state = CutBufferState(paths: normalized, updatedAt: Date())
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            let data = try encoder.encode(state)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("SuperFinder: failed to save cut buffer: \(error)")
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

import Foundation

/// A move request written by the Finder extension and consumed by the host app.
/// The JSON file acts as the IPC message; the file queue makes delivery reliable
/// even when the host app is not running yet.
struct MoveCommand: Codable, Equatable {
    enum Action: String, Codable {
        case moveHere
        case moveToFolder
        case openTerminal
    }

    static let currentSchema = 1

    let schema: Int
    let id: String
    let createdAt: Date
    let action: Action
    let sources: [String]
    let destination: String?

    init(action: Action, sources: [String], destination: String?) {
        self.schema = Self.currentSchema
        self.id = UUID().uuidString
        self.createdAt = Date()
        self.action = action
        self.sources = sources
        self.destination = destination
    }

    var isExpired: Bool {
        Date().timeIntervalSince(createdAt) > AppConfig.maxCommandAge
    }

    var fileName: String {
        let millis = Int(createdAt.timeIntervalSince1970 * 1000)
        return "\(millis)-\(id).json"
    }

    func encodedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> MoveCommand {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MoveCommand.self, from: data)
    }

    /// Epoch milliseconds parsed from the leading part of a command file name.
    static func timestamp(fromFileName fileName: String) -> Int64? {
        guard let head = fileName.split(separator: "-").first else { return nil }
        return Int64(head)
    }
}

import Foundation

enum PathFormatter {
    /// Absolute POSIX paths, one per line, preserving the Finder selection order.
    static func absolutePaths(for urls: [URL]) -> String {
        urls.map(\.path).joined(separator: "\n")
    }
}

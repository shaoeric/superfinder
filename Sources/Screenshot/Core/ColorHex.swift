import Foundation

/// Formats a sampled screenshot pixel as the uppercase `#RRGGBB` value that
/// the color picker copies to the pasteboard.
enum ColorHex {
    static func string(r: UInt8, g: UInt8, b: UInt8) -> String {
        String(format: "#%02X%02X%02X", Int(r), Int(g), Int(b))
    }
}

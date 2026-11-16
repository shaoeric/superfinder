import CoreGraphics
import Foundation

/// Safety limits for the screenshot renderer.
///
/// These are deliberately generous: they exist to stop runaway allocations or
/// pathological render loops, not to degrade capture quality. Screenshots are
/// captured at the display's native backing scale and retained at full quality.
enum MemoryBudget {
    /// Absolute safety ceiling for a single full-resolution working bitmap.
    static let absoluteImageLimit = 512 * 1024 * 1024
    static let historyCountLimit = 40
    static let bytesPerPixel = 4

    static func imageBytes(width: Int, height: Int) -> Int {
        max(0, width) * max(0, height) * bytesPerPixel
    }

    static func bytes(width: CGFloat, height: CGFloat) -> Int {
        imageBytes(width: Int(ceil(width)), height: Int(ceil(height)))
    }

    static func pixelSize(forPointSize size: CGSize, scale: CGFloat) -> (width: Int, height: Int) {
        (
            width: max(1, Int((size.width * scale).rounded(.up))),
            height: max(1, Int((size.height * scale).rounded(.up)))
        )
    }
}

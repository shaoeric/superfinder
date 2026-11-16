import CoreGraphics
import Foundation

/// Hard limits for the screenshot working set.
///
/// The feature is deliberately single-display and keeps at most one captured
/// screen image plus (after the eraser has been used) one transparent frozen
/// annotation bitmap. That keeps the working set below 20 MB while still
/// providing a full-screen background for the active display.
enum MemoryBudget {
    static let hardLimit = 20 * 1024 * 1024
    static let baseImageLimit = 2560 * 1024
    static let frozenLayerLimit = 1024 * 1024
    static let pinLimit = 14 * 1024 * 1024
    static let historyByteLimit = 1 * 1024 * 1024
    static let historyCountLimit = 40
    static let bytesPerPixel = 4

    static func imageBytes(width: Int, height: Int) -> Int {
        max(0, width) * max(0, height) * bytesPerPixel
    }

    static func bytes(width: CGFloat, height: CGFloat) -> Int {
        imageBytes(width: Int(ceil(width)), height: Int(ceil(height)))
    }

    /// Scale from screen points to captured pixels. Never upscales above 1x.
    static func workingScale(forPointSize size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 1 }
        let maxScale = sqrt(Double(baseImageLimit - 64 * 1024) / Double(size.width * size.height * CGFloat(bytesPerPixel)))
        return min(1.0, max(0.25, CGFloat(maxScale)))
    }

    static func pixelSize(forPointSize size: CGSize, scale: CGFloat) -> (width: Int, height: Int) {
        (
            width: max(1, Int((size.width * scale).rounded(.up))),
            height: max(1, Int((size.height * scale).rounded(.up)))
        )
    }
}

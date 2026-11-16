import AppKit
import CoreGraphics

enum CapturedScreenError: LocalizedError {
    case cannotCreateContext
    case emptyScreen

    var errorDescription: String? {
        switch self {
        case .cannotCreateContext:
            return "无法创建截屏缓冲区。"
        case .emptyScreen:
            return "截屏区域为空。"
        }
    }
}

/// The single active display captured for an editing session.
///
/// The full-resolution image is authoritative. A smaller display image is used
/// by the overlay to keep Core Animation backing stores small. Pixel sampling
/// uses a 1x1 context, so no second full-screen pixel buffer is retained.
final class CapturedScreen {
    let displayID: CGDirectDisplayID
    let appKitFrame: CGRect
    let screenPointSize: CGSize
    let workingScale: CGFloat
    let pixelWidth: Int
    let pixelHeight: Int
    private(set) var image: CGImage?
    private(set) var displayImage: CGImage?

    init(
        displayID: CGDirectDisplayID,
        appKitFrame: CGRect,
        screenPointSize: CGSize,
        image source: CGImage,
        workingScale: CGFloat? = nil
    ) throws {
        guard screenPointSize.width > 0, screenPointSize.height > 0 else {
            throw CapturedScreenError.emptyScreen
        }
        let scale = workingScale ?? MemoryBudget.workingScale(forPointSize: screenPointSize)
        let pixels = MemoryBudget.pixelSize(forPointSize: screenPointSize, scale: scale)
        guard MemoryBudget.imageBytes(width: pixels.width, height: pixels.height) <= MemoryBudget.baseImageLimit + 64 * 1024 else {
            throw CapturedScreenError.cannotCreateContext
        }

        var finalImage = source
        if source.width != pixels.width || source.height != pixels.height {
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: nil,
                    width: pixels.width,
                    height: pixels.height,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                throw CapturedScreenError.cannotCreateContext
            }
            context.interpolationQuality = .high
            context.draw(source, in: CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height))
            guard let resized = context.makeImage() else {
                throw CapturedScreenError.cannotCreateContext
            }
            finalImage = resized
        }

        self.displayID = displayID
        self.appKitFrame = appKitFrame
        self.screenPointSize = screenPointSize
        self.workingScale = scale
        self.pixelWidth = finalImage.width
        self.pixelHeight = finalImage.height
        self.image = finalImage
        self.displayImage = Self.makeDisplayImage(finalImage, maxPixelBytes: 768 * 1024)
    }

    /// Convenience initializer used by tests and preview tools.
    convenience init(screenFrame: CGRect, image: CGImage, workingScale: CGFloat? = nil) throws {
        try self.init(
            displayID: 0,
            appKitFrame: screenFrame,
            screenPointSize: screenFrame.size,
            image: image,
            workingScale: workingScale
        )
    }

    var pixelSize: CGSize {
        CGSize(width: pixelWidth, height: pixelHeight)
    }

    func releaseDisplayImage() {
        image = nil
        displayImage = nil
    }

    /// Samples the screenshot at a screen-local point.
    func pixelColor(atScreenPoint point: CGPoint) -> (r: UInt8, g: UInt8, b: UInt8)? {
        guard let image,
              point.x >= 0, point.y >= 0,
              point.x < screenPointSize.width, point.y < screenPointSize.height else {
            return nil
        }
        let px = min(pixelWidth - 1, max(0, Int(point.x * workingScale)))
        let py = min(pixelHeight - 1, max(0, Int(point.y * workingScale)))
        guard let crop = image.cropping(to: CGRect(x: px, y: py, width: 1, height: 1)) else {
            return nil
        }

        var bytes = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        bytes.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: 1,
                    height: 1,
                    bitsPerComponent: 8,
                    bytesPerRow: 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return (bytes[0], bytes[1], bytes[2])
    }

    /// Crops the captured screen using screen-local point coordinates.
    func croppedImage(forScreenRect rect: CGRect) -> CGImage? {
        guard let image else { return nil }
        let standardized = rect.standardized.intersection(
            CGRect(origin: .zero, size: screenPointSize)
        )
        guard !standardized.isNull, standardized.width > 0, standardized.height > 0 else {
            return nil
        }

        let x = max(0, Int(floor(standardized.minX * workingScale)))
        let y = max(0, Int(floor(standardized.minY * workingScale)))
        let w = min(pixelWidth - x, Int(ceil(standardized.width * workingScale)))
        let h = min(pixelHeight - y, Int(ceil(standardized.height * workingScale)))
        guard x >= 0, y >= 0, w > 0, h > 0 else { return nil }
        return image.cropping(to: CGRect(x: x, y: y, width: w, height: h))
    }

    private static func makeDisplayImage(_ source: CGImage, maxPixelBytes: Int) -> CGImage? {
        let sourceBytes = MemoryBudget.imageBytes(width: source.width, height: source.height)
        guard sourceBytes > 0 else { return nil }
        let scale = min(1.0, sqrt(Double(maxPixelBytes) / Double(sourceBytes)))
        let width = max(1, Int((Double(source.width) * scale).rounded()))
        let height = max(1, Int((Double(source.height) * scale).rounded()))
        if width == source.width && height == source.height { return source }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return source
        }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

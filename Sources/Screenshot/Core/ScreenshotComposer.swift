import CoreGraphics
import Foundation

enum ScreenshotComposer {
    /// Composes the selection into a fresh bitmap. The captured screen and the
    /// live editing document are left untouched, so a failed save never
    /// corrupts the editor.
    static func composeSelection(
        document: ScreenshotDocument,
        capturedScreen: CapturedScreen
    ) -> CGImage? {
        let scale = capturedScreen.workingScale
        let selection = document.selection.rect
        let selectionWidth = selection.width * scale
        let selectionHeight = selection.height * scale
        guard selectionWidth >= 1, selectionHeight >= 1 else { return nil }

        let width = max(1, Int(selectionWidth.rounded(.up)))
        let height = max(1, Int(selectionHeight.rounded(.up)))
        guard MemoryBudget.imageBytes(width: width, height: height) <= MemoryBudget.absoluteImageLimit,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        if let baseImage = capturedScreen.image,
           let baseCrop = baseImage.cropping(to: CGRect(
            x: selection.minX * scale,
            y: selection.minY * scale,
            width: CGFloat(width),
            height: CGFloat(height)
           )) {
            context.interpolationQuality = .high
            context.draw(baseCrop, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        if let frozen = document.frozenRaster.image {
            context.interpolationQuality = .high
            context.draw(frozen, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        AnnotationRenderer.drawAll(
            document.annotations,
            in: context,
            scale: scale,
            selectionHeight: document.selection.rect.height
        )
        return context.makeImage()
    }
}

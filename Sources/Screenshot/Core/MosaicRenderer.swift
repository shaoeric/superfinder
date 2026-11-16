import CoreGraphics

enum MosaicRenderer {
    /// Produces a small, pixelated image for a screen rectangle. The returned
    /// image is intentionally tiny (down-sampled by `block`) so caching it for
    /// the overlay never adds a full-screen bitmap.
    static func pixelatedImage(
        baseImage: CGImage,
        screenRect: CGRect,
        workingScale: CGFloat,
        block: CGFloat
    ) -> CGImage? {
        let blockPixels = max(2, Int((block * workingScale).rounded()))
        let x = max(0, Int(floor(screenRect.minX * workingScale)))
        let y = max(0, Int(floor(screenRect.minY * workingScale)))
        let w = min(baseImage.width - x, Int(ceil(screenRect.width * workingScale)))
        let h = min(baseImage.height - y, Int(ceil(screenRect.height * workingScale)))
        guard w > 0, h > 0, x + w <= baseImage.width, y + h <= baseImage.height else {
            return nil
        }
        guard let crop = baseImage.cropping(to: CGRect(x: x, y: y, width: w, height: h)) else {
            return nil
        }

        let smallWidth = max(1, w / blockPixels)
        let smallHeight = max(1, h / blockPixels)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil,
                width: smallWidth,
                height: smallHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }
        ctx.interpolationQuality = .none
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: smallWidth, height: smallHeight))
        return ctx.makeImage()
    }

    /// Draws a mosaic image upscaled without smoothing. `rect` is in the
    /// destination context's pixel coordinates.
    static func drawPixelated(
        _ image: CGImage,
        in context: CGContext,
        rect: CGRect
    ) {
        context.saveGState()
        context.interpolationQuality = .none
        context.draw(image, in: rect)
        context.restoreGState()
    }
}

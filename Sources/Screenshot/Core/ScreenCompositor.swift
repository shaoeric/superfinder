import CoreGraphics

/// One pinned image to draw into a full-display capture. `frame` is in the
/// target screen's local, top-left-origin point space.
struct ScreenOverlayImage {
    let frame: CGRect
    let image: CGImage
}

/// Composites existing pinned images into a fresh full-display capture.
///
/// ScreenCaptureKit excludes all windows owned by SuperFinder, including pins,
/// so a new screenshot would otherwise see only the desktop behind a pin. The
/// new screenshot overlay must be on top (so a pin can be selected and shot
/// again), therefore the pins are drawn into the captured base image instead of
/// floating above the overlay.
enum ScreenCompositor {
    static func compositing(
        _ capture: CapturedScreen,
        overlays: [ScreenOverlayImage]
    ) -> CapturedScreen? {
        guard !overlays.isEmpty, let base = capture.image else { return capture }
        let width = capture.pixelWidth
        let height = capture.pixelHeight
        guard width > 0, height > 0,
              MemoryBudget.imageBytes(width: width, height: height) <= MemoryBudget.absoluteImageLimit,
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

        context.interpolationQuality = .high
        context.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))

        let scale = capture.workingScale
        for overlay in overlays where overlay.frame.width > 0 && overlay.frame.height > 0 {
            let rect = CGRect(
                x: overlay.frame.minX * scale,
                y: CGFloat(height) - (overlay.frame.minY + overlay.frame.height) * scale,
                width: overlay.frame.width * scale,
                height: overlay.frame.height * scale
            )
            context.draw(overlay.image, in: rect)
        }

        guard let image = context.makeImage() else { return nil }
        return try? CapturedScreen(
            displayID: capture.displayID,
            appKitFrame: capture.appKitFrame,
            screenPointSize: capture.screenPointSize,
            image: image,
            workingScale: capture.workingScale
        )
    }
}

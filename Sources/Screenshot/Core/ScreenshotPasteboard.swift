import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Writes a composed screenshot to a pasteboard in formats other apps can
/// paste directly. Keeping this in one place lets the editor and pinned images
/// share exactly the same clipboard behavior.
enum ScreenshotPasteboard {
    @discardableResult
    static func copy(image: CGImage, to pasteboard: NSPasteboard = .general) -> Bool {
        guard let png = pngData(for: image) else { return false }
        let tiff = tiffData(for: image)

        let item = NSPasteboardItem()
        guard item.setData(png, forType: .png) else { return false }
        if let tiff {
            item.setData(tiff, forType: .tiff)
        }

        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }

    static func pngData(for image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    static func tiffData(for image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .tiff, properties: [:])
    }
}

import AppKit
import CoreGraphics

_ = NSApplication.shared

var failureCount = 0
var checkCount = 0

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checkCount += 1
    if !condition() {
        failureCount += 1
        print("FAIL: \(message)")
    }
}

func checkEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    checkCount += 1
    if lhs != rhs {
        failureCount += 1
        print("FAIL: \(message): \(lhs) != \(rhs)")
    }
}

extension NSView {
    var allSubviewsRecursively: [NSView] {
        subviews + subviews.flatMap(\.allSubviewsRecursively)
    }
}

func makeImage(width: Int, height: Int) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(NSColor.systemTeal.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

// MARK: - Toolbar swatches

do {
    let toolbar = CaptureToolbar()
    toolbar.contentView?.layoutSubtreeIfNeeded()
    let swatches = toolbar.contentView?.allSubviewsRecursively.compactMap { $0 as? ColorSwatchButton } ?? []
    checkEqual(swatches.count, 3, "toolbar exposes one color swatch per drawing tool")
    check(swatches.allSatisfy { $0.frame.width > 0 && $0.frame.height > 0 }, "toolbar swatches are laid out")
    check(toolbar.canBecomeKey, "screenshot toolbar can become key")
    check(
        toolbar.level.rawValue > NSWindow.Level.screenSaver.rawValue,
        "screenshot toolbar is above the overlay"
    )
    toolbar.orderOut(nil)
}

// MARK: - Color palette

do {
    let palette = ColorPalettePanel.shared
    palette.contentView?.layoutSubtreeIfNeeded()
    let swatches = palette.contentView?.allSubviewsRecursively.compactMap { $0 as? ColorSwatchButton } ?? []
    checkEqual(swatches.count, 12, "palette exposes the preset swatches")
    check(swatches.allSatisfy { $0.frame.width > 0 && $0.frame.height > 0 }, "palette swatches are laid out")
    check(palette.frame.width >= 200, "palette has room for two swatch rows")
    check(
        palette.level.rawValue > NSWindow.Level.screenSaver.rawValue + 1,
        "palette is above the toolbar and overlay"
    )
    check(!palette.isVisible, "palette is hidden until requested")
    palette.dismissAll()
}

// MARK: - Pinned image window

do {
    let source = makeImage(width: 200, height: 120)
    let captured = try! CapturedScreen(
        screenFrame: CGRect(x: 0, y: 0, width: 200, height: 120),
        image: source,
        workingScale: 2
    )
    let selection = CaptureSelection(rect: CGRect(x: 20, y: 20, width: 100, height: 60))
    let document = ScreenshotDocument(selection: selection, workingScale: 2, baseImage: captured.image)
    let session = PinEditingSession(capturedScreen: captured, document: document)
    let pin = PinnedImageWindow(
        image: source,
        pointSize: CGSize(width: 100, height: 60),
        screenFrame: captured.appKitFrame,
        editingSession: session
    )

    check(pin.canBecomeKey, "pin window can become key")
    checkEqual(pin.level, .floating, "pin stays at floating window level")
    check(pin.editingSession === session, "pin keeps the editing session")
    checkEqual(pin.displaySize, CGSize(width: 100, height: 60), "pin starts at the selection size")

    guard let tracking = pin.contentView as? PinTrackingView else {
        print("FAIL: pin content view is not PinTrackingView")
        exit(1)
    }
    var copied = false
    tracking.onCopy = { copied = true }
    let event = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [.command],
        timestamp: 0,
        windowNumber: pin.windowNumber,
        context: nil,
        characters: "c",
        charactersIgnoringModifiers: "c",
        isARepeat: false,
        keyCode: 8
    )!
    let handled = tracking.performKeyEquivalent(with: event)
    check(handled, "pin handles ⌘C as a key equivalent")
    check(copied, "pin routes ⌘C to its copy action")

    pin.setFrameOrigin(CGPoint(x: 100, y: 100))
    let frameBefore = pin.frame
    pin.update(image: source, pointSize: CGSize(width: 120, height: 80), editingSession: session)
    checkEqual(pin.displaySize, CGSize(width: 120, height: 80), "pin updates its display size")
    checkEqual(pin.frame.size, CGSize(width: 120, height: 80), "pin window resizes with the crop")
    checkEqual(
        pin.frame.origin,
        CGPoint(x: frameBefore.minX, y: frameBefore.maxY - 80),
        "pin keeps its top-left corner when resized"
    )
    check(pin.editingSession === session, "pin keeps its session after resize")

    pin.orderOut(nil)
}

print("")
print("UI tests: \(checkCount) checks, \(failureCount) failure(s)")
if failureCount > 0 {
    exit(1)
}
print("ALL UI TESTS PASSED")

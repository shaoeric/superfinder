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

    // The toolbar is a fixed light surface (#EBEBEB) with dark chrome.
    let expectedBackground = CaptureToolbar.backgroundColor.usingColorSpace(.sRGB)
    if let expectedBackground {
        checkEqual(Int((expectedBackground.redComponent * 255).rounded()), 235, "toolbar background is #EBEBEB (red)")
        checkEqual(Int((expectedBackground.greenComponent * 255).rounded()), 235, "toolbar background is #EBEBEB (green)")
        checkEqual(Int((expectedBackground.blueComponent * 255).rounded()), 235, "toolbar background is #EBEBEB (blue)")
    } else {
        check(false, "toolbar background color converts to sRGB")
    }
    if let cg = toolbar.contentView?.layer?.backgroundColor,
       let applied = NSColor(cgColor: cg)?.usingColorSpace(.sRGB) {
        checkEqual(Int((applied.redComponent * 255).rounded()), 235, "toolbar applies the light background")
    } else {
        check(false, "toolbar content view has a light background layer")
    }

    let swatches = toolbar.contentView?.allSubviewsRecursively.compactMap { $0 as? ColorSwatchButton } ?? []
    checkEqual(swatches.count, 3, "toolbar exposes one color swatch per drawing tool")
    check(swatches.allSatisfy { $0.frame.width > 0 && $0.frame.height > 0 }, "toolbar swatches are laid out")
    check(swatches.allSatisfy { $0.title.isEmpty && $0.attributedTitle.string.isEmpty }, "color swatches do not draw a default button title")
    let toolbarButtons = toolbar.contentView?.allSubviewsRecursively.compactMap { $0 as? NSButton } ?? []
    let iconButtons = toolbarButtons.filter { $0.image != nil && !($0 is ColorSwatchButton) }
    check(iconButtons.count >= 11, "toolbar exposes all icon buttons")
    check(iconButtons.allSatisfy { $0.title.isEmpty }, "toolbar icon buttons do not draw default titles")
    if let tint = iconButtons.first?.contentTintColor?.usingColorSpace(.sRGB) {
        check(tint.brightnessComponent < 0.5, "toolbar icons are dark on the light background")
    } else {
        check(false, "toolbar icon buttons have a content tint")
    }
    let fillControls = toolbar.contentView?.allSubviewsRecursively.compactMap { $0 as? NSSegmentedControl } ?? []
    if let fill = fillControls.first(where: { $0.segmentCount == 2 }) {
        check(fill.image(forSegment: 0) != nil, "mode switch has an outline rectangle icon")
        check(fill.image(forSegment: 1) != nil, "mode switch has a filled rectangle icon")
        checkEqual(fill.selectedSegment, 0, "mode switch initially highlights non-filled")
        check(fill.trackingMode == .selectOne, "mode switch highlights the current selection")
    } else {
        check(false, "rectangle properties expose the non-filled/filled switch")
    }
    let defaults = ScreenshotDefaults()
    check(!defaults.rectangleFilled, "rectangles default to non-filled")

    let textIcon = TextToolIcon.make()
    checkEqual(textIcon.size, NSSize(width: 18, height: 18), "text tool has a fixed-size T icon")
    check(textIcon.isTemplate, "text tool T icon follows the button tint")
    if let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 18,
        pixelsHigh: 18,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        textIcon.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
        NSGraphicsContext.restoreGraphicsState()
        if let data = rep.bitmapData {
            var ink = 0
            for pixel in 0..<(18 * 18) where data[pixel * 4 + 3] > 10 {
                ink += 1
            }
            check(ink > 20, "T icon actually draws visible ink")
        } else {
            check(false, "T icon bitmap data")
        }
    } else {
        check(false, "T icon bitmap")
    }
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
    check(swatches.allSatisfy { $0.title.isEmpty && $0.attributedTitle.string.isEmpty }, "palette swatches do not draw a default button title")
    check(palette.frame.width >= 200, "palette has room for two swatch rows")
    check(
        palette.level.rawValue > NSWindow.Level.screenSaver.rawValue + 1,
        "palette is above the toolbar and overlay"
    )
    check(!palette.isVisible, "palette is hidden until requested")
    palette.dismissAll()

    let toast = ScreenshotToast.shared
    check(toast.ignoresMouseEvents, "copy toast never intercepts clicks")
    check(toast.level.rawValue > palette.level.rawValue, "copy toast is above the palette")
    check(!toast.isVisible, "copy toast is hidden until requested")
}

// MARK: - Selection HUD

do {
    let hud = CaptureHUD()
    if let cg = hud.contentView?.layer?.backgroundColor,
       let background = NSColor(cgColor: cg)?.usingColorSpace(.sRGB) {
        checkEqual(
            Int((background.redComponent * 255).rounded()),
            235,
            "selection HUD uses the light #EBEBEB background"
        )
    } else {
        check(false, "selection HUD exposes a light background layer")
    }

    let swatch = hud.contentView?.allSubviewsRecursively.first {
        $0.identifier?.rawValue == "hudColorSwatch"
    }
    check(swatch != nil, "selection HUD exposes a color chip")
    hud.updateColor(NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1))
    if let cg = swatch?.layer?.backgroundColor,
       let color = NSColor(cgColor: cg)?.usingColorSpace(.sRGB) {
        checkEqual(Int((color.redComponent * 255).rounded()), 255, "HUD chip shows the sampled red component")
        checkEqual(Int((color.greenComponent * 255).rounded()), 128, "HUD chip shows the sampled green component")
    } else {
        check(false, "HUD color chip applies a sampled color")
    }
    hud.updateColor(nil)
    if let cg = swatch?.layer?.backgroundColor, let color = NSColor(cgColor: cg) {
        check(color.alphaComponent < 0.01, "HUD color chip clears when no pixel is selected")
    } else {
        check(false, "HUD color chip can be cleared")
    }
    hud.hide()
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
    check(tracking.acceptsFirstMouse(for: nil), "an inactive pin starts dragging on the first click")
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

    pin.setFrameOrigin(CGPoint(x: 300, y: 300))
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

    var pinClosed = false
    pin.onClose = { pinClosed = true }
    let other = PinnedImageWindow(
        image: source,
        pointSize: CGSize(width: 60, height: 40),
        screenFrame: captured.appKitFrame,
        editingSession: session
    )
    let escape = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: pin.windowNumber,
        context: nil,
        characters: "\u{1b}",
        charactersIgnoringModifiers: "\u{1b}",
        isARepeat: false,
        keyCode: 53
    )!
    tracking.keyDown(with: escape)
    check(pinClosed, "Esc closes the focused pin")
    check(!pin.isVisible, "closed pin is ordered out")
    check(pin.image == nil && pin.imageData == nil, "closed pin releases its image data")
    check(pin.editingSession == nil, "closed pin releases its editing session")
    check(other.image != nil && other.editingSession != nil, "closing one pin leaves other pins intact")
    other.close()
}

print("")
print("UI tests: \(checkCount) checks, \(failureCount) failure(s)")
if failureCount > 0 {
    exit(1)
}
print("ALL UI TESTS PASSED")

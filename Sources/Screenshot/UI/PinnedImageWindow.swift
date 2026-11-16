import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

final class PinnedImageWindow: NSPanel, NSWindowDelegate {
    private(set) var image: CGImage?
    private(set) var imageData: Data?
    private(set) var displaySize: CGSize
    private(set) var editingSession: PinEditingSession?
    private let imageLayer = CALayer()
    private let closeButton = NSButton()
    private let trackingView: PinTrackingView
    var onClose: (() -> Void)?
    var onShowToolbar: (() -> Void)?
    private var preOverlayLevel: NSWindow.Level?

    init(
        image: CGImage,
        pointSize: CGSize,
        screenFrame: CGRect,
        editingSession: PinEditingSession? = nil
    ) {
        self.image = image
        self.displaySize = pointSize
        self.editingSession = editingSession
        self.trackingView = PinTrackingView(frame: CGRect(origin: .zero, size: pointSize))
        super.init(
            contentRect: CGRect(origin: Self.initialOrigin(pointSize: pointSize, screenFrame: screenFrame), size: pointSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        isFloatingPanel = true
        delegate = self

        trackingView.wantsLayer = true
        trackingView.layer?.backgroundColor = NSColor.clear.cgColor
        imageLayer.frame = trackingView.bounds
        imageLayer.contents = image
        imageLayer.contentsGravity = .resize
        imageLayer.cornerRadius = 2
        imageLayer.masksToBounds = true
        trackingView.layer?.addSublayer(imageLayer)
        trackingView.onMouseEntered = { [weak self] in self?.closeButton.isHidden = false }
        trackingView.onMouseExited = { [weak self] in self?.closeButton.isHidden = true }
        trackingView.onCopy = { [weak self] in self?.copyToPasteboard() }
        trackingView.onShowToolbar = { [weak self] in self?.onShowToolbar?() }

        closeButton.title = ""
        closeButton.alternateTitle = ""
        closeButton.attributedTitle = NSAttributedString(string: "")
        closeButton.bezelStyle = .circular
        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "关闭贴图")
        closeButton.contentTintColor = .white
        closeButton.target = self
        closeButton.action = #selector(closeAction)
        closeButton.frame = CGRect(x: pointSize.width - 24, y: pointSize.height - 24, width: 18, height: 18)
        closeButton.autoresizingMask = [.minXMargin, .minYMargin]
        closeButton.isHidden = true
        trackingView.addSubview(closeButton)
        contentView = trackingView
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Replaces the displayed bitmap after the pin has been edited again.
    /// The top-left corner stays fixed when the crop size changes.
    func update(image: CGImage, pointSize: CGSize, editingSession: PinEditingSession? = nil) {
        self.image = image
        self.imageData = nil
        self.displaySize = pointSize
        if let editingSession {
            self.editingSession = editingSession
        }
        imageLayer.contents = image

        var newFrame = frame
        let topLeft = CGPoint(x: newFrame.minX, y: newFrame.maxY)
        newFrame.size = pointSize
        newFrame.origin = CGPoint(x: topLeft.x, y: topLeft.y - pointSize.height)
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(newFrame) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            newFrame.origin.x = min(max(newFrame.origin.x, visible.minX + 4), visible.maxX - pointSize.width - 4)
            newFrame.origin.y = min(max(newFrame.origin.y, visible.minY + 4), visible.maxY - pointSize.height - 4)
        }
        setFrame(newFrame, display: true)
        trackingView.frame = CGRect(origin: .zero, size: pointSize)
        imageLayer.frame = trackingView.bounds
        closeButton.frame = CGRect(x: pointSize.width - 24, y: pointSize.height - 24, width: 18, height: 18)
    }

    /// Keeps an existing pin visible above the screenshot overlay while the
    /// user is selecting/annotating. Clicks pass through to the overlay so the
    /// pin never steals a selection drag.
    func setOverlayPassThrough(_ active: Bool) {
        if active {
            if preOverlayLevel == nil {
                preOverlayLevel = level
            }
            level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
            ignoresMouseEvents = true
        } else {
            if let preOverlayLevel {
                level = preOverlayLevel
                self.preOverlayLevel = nil
            }
            ignoresMouseEvents = false
        }
        orderFrontRegardless()
    }

    func copyToPasteboard() {
        guard let image else { return }
        guard ScreenshotPasteboard.copy(image: image) else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        ScreenshotToast.shared.show("已复制到剪贴板", near: frame, on: screen ?? NSScreen.main)
    }

    /// Makes the pin the key window and gives its tracking view first responder
    /// immediately, so ⌘C works right after pinning without an extra click.
    func focusForKeyboard() {
        makeKeyAndOrderFront(nil)
        makeFirstResponder(trackingView)
    }

    func compressAndHide() {
        guard let image else {
            orderOut(nil)
            return
        }
        imageData = Self.pngData(for: image)
        imageLayer.contents = nil
        self.image = nil
        orderOut(nil)
    }

    func restore() {
        if image == nil, let imageData, let source = CGImageSourceCreateWithData(imageData as CFData, nil),
           let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            image = decoded
            imageLayer.contents = decoded
        }
        orderFrontRegardless()
    }

    override func close() {
        orderOut(nil)
        // Drop the heavy backing data immediately, even if AppKit retains the
        // window object briefly. Pins are memory-only and never persisted.
        imageLayer.contents = nil
        image = nil
        imageData = nil
        editingSession = nil
        onClose?()
        onClose = nil
        onShowToolbar = nil
    }

    private static func initialOrigin(pointSize: CGSize, screenFrame: CGRect) -> CGPoint {
        let mouse = NSEvent.mouseLocation
        var x = mouse.x - pointSize.width / 2
        var y = mouse.y - pointSize.height - 20
        x = min(max(x, screenFrame.minX + 8), screenFrame.maxX - pointSize.width - 8)
        y = min(max(y, screenFrame.minY + 8), screenFrame.maxY - pointSize.height - 8)
        return CGPoint(x: x, y: y)
    }

    @objc private func closeAction() {
        close()
    }

    private static func pngData(for image: CGImage) -> Data? {
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
}

final class PinTrackingView: NSView {
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    var onCopy: (() -> Void)?
    var onShowToolbar: (() -> Void)?
    private var trackingAreaRef: NSTrackingArea?
    private var dragStartScreenPoint: CGPoint?
    private var dragStartWindowOrigin: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    /// A click on an inactive pin must both unlock/activate the panel and start
    /// the drag. Without this, AppKit consumes the first click as the window
    /// activation click and the pin only moves on the second drag.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(self)
        let screenPoint = window.convertToScreen(CGRect(origin: event.locationInWindow, size: .zero)).origin
        dragStartScreenPoint = screenPoint
        dragStartWindowOrigin = window.frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window,
              let startScreen = dragStartScreenPoint,
              let startOrigin = dragStartWindowOrigin else { return }
        let current = window.convertToScreen(CGRect(origin: event.locationInWindow, size: .zero)).origin
        window.setFrameOrigin(CGPoint(
            x: startOrigin.x + current.x - startScreen.x,
            y: startOrigin.y + current.y - startScreen.y
        ))
    }

    override func mouseUp(with event: NSEvent) {
        dragStartScreenPoint = nil
        dragStartWindowOrigin = nil
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            (window as? PinnedImageWindow)?.close()
            return
        }
        let isCopy = event.keyCode == 8 || event.charactersIgnoringModifiers?.lowercased() == "c"
        if event.modifierFlags.contains(.command), isCopy {
            onCopy?()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        (window as? PinnedImageWindow)?.close()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let isCopy = event.keyCode == 8 || event.charactersIgnoringModifiers?.lowercased() == "c"
        if event.modifierFlags.contains(.command), isCopy {
            onCopy?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let toolbar = NSMenuItem(title: "显示工具条", action: #selector(showToolbarMenuAction), keyEquivalent: "")
        toolbar.target = self
        menu.addItem(toolbar)

        let copy = NSMenuItem(title: "复制图片", action: #selector(copyMenuAction), keyEquivalent: "c")
        copy.target = self
        menu.addItem(copy)
        menu.addItem(.separator())

        let save = NSMenuItem(title: "保存贴图…", action: #selector(saveMenuAction), keyEquivalent: "")
        save.target = self
        menu.addItem(save)

        let close = NSMenuItem(title: "关闭贴图", action: #selector(closeMenuAction), keyEquivalent: "")
        close.target = self
        menu.addItem(close)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func showToolbarMenuAction() {
        onShowToolbar?()
    }

    @objc private func copyMenuAction() {
        onCopy?()
    }

    @objc private func closeMenuAction() {
        (window as? PinnedImageWindow)?.close()
    }

    @objc private func saveMenuAction() {
        (window as? PinnedImageWindow)?.saveFromContextMenu()
    }
}

private extension PinnedImageWindow {
    func saveFromContextMenu() {
        let data = imageData ?? image.flatMap { Self.pngDataForSave(image: $0) }
        guard let data else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "贴图 \(Self.timestamp()).png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func pngDataForSave(image: CGImage) -> Data? {
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
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: Date())
    }
}

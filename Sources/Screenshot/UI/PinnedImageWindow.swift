import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

final class PinnedImageWindow: NSPanel, NSWindowDelegate {
    private(set) var image: CGImage?
    private(set) var imageData: Data?
    private let imageLayer = CALayer()
    private let closeButton = NSButton()
    private let displaySize: CGSize
    private let trackingView: PinTrackingView
    var onClose: (() -> Void)?

    init(image: CGImage, pointSize: CGSize, screenFrame: CGRect) {
        self.image = image
        self.displaySize = pointSize
        self.trackingView = PinTrackingView(frame: CGRect(origin: .zero, size: pointSize))
        super.init(
            contentRect: CGRect(origin: Self.initialOrigin(pointSize: pointSize, screenFrame: screenFrame), size: pointSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
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

        closeButton.bezelStyle = .circular
        closeButton.isBordered = false
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

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

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
        onClose?()
        onClose = nil
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
    private var trackingAreaRef: NSTrackingArea?

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

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let close = NSMenuItem(title: "关闭贴图", action: #selector(closeMenuAction), keyEquivalent: "")
        close.target = self
        menu.addItem(close)
        let save = NSMenuItem(title: "保存贴图…", action: #selector(saveMenuAction), keyEquivalent: "")
        save.target = self
        menu.addItem(save)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
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
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: Date())
    }
}

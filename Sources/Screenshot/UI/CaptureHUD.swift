import AppKit
import QuartzCore

enum CaptureTool: String, CaseIterable {
    case pointer
    case rectangle
    case line
    case text
    case eraser

    var displayName: String {
        switch self {
        case .pointer: return "选择/移动"
        case .rectangle: return "矩形"
        case .line: return "线段"
        case .text: return "文本标注（点击画面输入）"
        case .eraser: return "橡皮擦"
        }
    }

    var symbolName: String {
        switch self {
        case .pointer: return "arrow.up.left"
        case .rectangle: return "rectangle"
        case .line: return "line.diagonal"
        case .text: return "textbox"
        case .eraser: return "eraser"
        }
    }

    var isDrawingTool: Bool {
        self == .rectangle || self == .line || self == .text
    }
}

final class CaptureHUD: NSPanel {
    private static let backgroundColor = NSColor(
        srgbRed: 235.0 / 255.0,
        green: 235.0 / 255.0,
        blue: 235.0 / 255.0,
        alpha: 1
    )
    private static let textColor = NSColor(white: 0.16, alpha: 1)

    private let label = NSTextField(labelWithString: "")
    private let colorSwatch = NSView()

    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 460, height: 30),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none

        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = Self.backgroundColor.cgColor
        view.layer?.cornerRadius = 6
        view.layer?.borderColor = NSColor.black.withAlphaComponent(0.14).cgColor
        view.layer?.borderWidth = 1

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        label.textColor = Self.textColor
        label.lineBreakMode = .byClipping
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        colorSwatch.identifier = NSUserInterfaceItemIdentifier("hudColorSwatch")
        colorSwatch.wantsLayer = true
        colorSwatch.layer?.cornerRadius = 3
        colorSwatch.layer?.borderWidth = 1
        colorSwatch.layer?.borderColor = NSColor.black.withAlphaComponent(0.24).cgColor
        colorSwatch.layer?.backgroundColor = NSColor.clear.cgColor
        colorSwatch.translatesAutoresizingMaskIntoConstraints = false
        colorSwatch.setAccessibilityLabel("鼠标位置颜色")

        view.addSubview(label)
        view.addSubview(colorSwatch)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 9),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            colorSwatch.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            colorSwatch.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -9),
            colorSwatch.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            colorSwatch.widthAnchor.constraint(equalToConstant: 18),
            colorSwatch.heightAnchor.constraint(equalToConstant: 18)
        ])
        contentView = view
        orderOut(nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        screen: NSScreen,
        selection: CaptureSelection,
        captured: CapturedScreen?
    ) {
        let local = selection.rect
        let scale = captured?.workingScale ?? 1
        let pixelWidth = Int((local.width * scale).rounded())
        let pixelHeight = Int((local.height * scale).rounded())

        // Only the selection size remains as text. The color chip is updated
        // from mouse events without relaying out the label, and no color value
        // text is drawn.
        label.stringValue = "尺寸 \(pixelWidth) × \(pixelHeight) px"
        contentView?.layoutSubtreeIfNeeded()
        let attributes = [NSAttributedString.Key.font: label.font ?? NSFont.systemFont(ofSize: 11)]
        let fitting = ceil((label.stringValue as NSString).size(withAttributes: attributes).width)
            + 9 + 8 + 18 + 9
        let width = min(max(180, fitting), 760)
        setContentSize(CGSize(width: width, height: 30))

        let screenTop = screen.frame.maxY
        let selectionTop = screenTop - local.minY
        var x = screen.frame.minX + local.minX
        var y = selectionTop + 7
        if y + 30 > screen.frame.maxY {
            y = selectionTop - 37
        }
        if y < screen.frame.minY + 4 {
            y = screen.frame.minY + 4
        }
        x = min(max(x, screen.frame.minX + 4), screen.frame.maxX - width - 4)
        setFrameOrigin(CGPoint(x: x, y: y))
        orderFrontRegardless()
    }

    /// Updates only the color chip. The size label is not touched, so moving
    /// the mouse does not re-layout or resize the HUD.
    func updateColor(_ color: NSColor?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        colorSwatch.layer?.backgroundColor = color?.cgColor ?? NSColor.clear.cgColor
        colorSwatch.layer?.borderColor = color == nil
            ? NSColor.black.withAlphaComponent(0.18).cgColor
            : NSColor.black.withAlphaComponent(0.38).cgColor
        CATransaction.commit()
    }

    func hide() {
        orderOut(nil)
    }
}

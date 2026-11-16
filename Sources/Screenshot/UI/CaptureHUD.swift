import AppKit

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
        case .text: return "textformat"
        case .eraser: return "eraser"
        }
    }

    var isDrawingTool: Bool {
        self == .rectangle || self == .line || self == .text
    }
}

final class CaptureHUD: NSPanel {
    private let label = NSTextField(labelWithString: "")

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
        view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        view.layer?.cornerRadius = 6
        view.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        view.layer?.borderWidth = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.lineBreakMode = .byClipping
        label.maximumNumberOfLines = 1
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -9),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
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
        captured: CapturedScreen?,
        mouse: CGPoint
    ) {
        let local = selection.rect
        let scale = captured?.workingScale ?? 1
        let pixelWidth = Int((local.width * scale).rounded())
        let pixelHeight = Int((local.height * scale).rounded())

        let mainFrame = NSScreen.screens.first?.frame ?? screen.frame
        let globalX = Int((screen.frame.minX + local.minX - mainFrame.minX).rounded())
        let globalY = Int((mainFrame.maxY - screen.frame.maxY + local.minY).rounded())

        var rgbText = "RGB --"
        if let captured,
           let color = captured.pixelColor(atScreenPoint: mouse) {
            rgbText = String(
                format: "RGB(%3d,%3d,%3d) #%02X%02X%02X",
                color.r, color.g, color.b, color.r, color.g, color.b
            )
        }

        label.stringValue = "尺寸 \(pixelWidth) × \(pixelHeight) px   坐标 X:\(globalX) Y:\(globalY)   \(rgbText)"
        contentView?.layoutSubtreeIfNeeded()
        let attributes = [NSAttributedString.Key.font: label.font ?? NSFont.systemFont(ofSize: 11)]
        let fitting = ceil((label.stringValue as NSString).size(withAttributes: attributes).width) + 22
        let width = min(max(280, fitting), 760)
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

    func hide() {
        orderOut(nil)
    }
}

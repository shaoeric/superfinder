import AppKit

final class TextEditorWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class TextEditingView: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // Let the input method consume Return/Enter while composing.
        if hasMarkedText() {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == 36 || event.keyCode == 76 {
            if event.modifierFlags.contains(.shift) {
                insertNewline(nil)
            } else {
                onCommit?()
            }
            return
        }
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }
}

final class TextEditorPanel: NSObject, NSTextViewDelegate {
    private let window: TextEditorWindow
    private let textView: TextEditingView
    private var onCommit: ((String) -> Void)?
    private var onCancel: (() -> Void)?
    private var topLeftScreenPoint: CGPoint = .zero
    private var screenFrame: CGRect = .zero
    private var maxWidth: CGFloat = 320
    private var fontSize: CGFloat = 24
    private var fontName: String = ""
    private var isCommitting = false

    override init() {
        window = TextEditorWindow(
            contentRect: CGRect(x: 0, y: 0, width: 260, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        textView = TextEditingView(frame: CGRect(x: 0, y: 0, width: 260, height: 40))
        super.init()

        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.becomesKeyOnlyIfNeeded = false
        window.animationBehavior = .none
        window.contentView = textView
        textView.delegate = self
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.black.withAlphaComponent(0.35)
        textView.textContainerInset = CGSize(width: 4, height: 3)
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainer?.lineFragmentPadding = 2
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = CGSize(width: 260, height: 1000)
        textView.wantsLayer = true
        textView.layer?.cornerRadius = 4
        textView.layer?.borderColor = NSColor.white.withAlphaComponent(0.45).cgColor
        textView.layer?.borderWidth = 1
        textView.insertionPointColor = .white
        textView.onCommit = { [weak self] in self?.commit() }
        textView.onCancel = { [weak self] in self?.cancel() }
        window.orderOut(nil)
    }

    func begin(
        text: String,
        fontName: String,
        fontSize: CGFloat,
        color: NSColor,
        screenPoint: CGPoint,
        screenFrame: CGRect,
        maxWidth: CGFloat,
        onCommit: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.topLeftScreenPoint = screenPoint
        self.screenFrame = screenFrame
        self.maxWidth = max(80, maxWidth)
        self.onCommit = onCommit
        self.onCancel = onCancel
        isCommitting = false

        textView.string = text
        textView.font = TextLayout.font(name: fontName, size: fontSize)
        textView.textColor = color
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        updateFrame()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
    }

    func commitNow() {
        commit()
    }

    func cancelNow() {
        cancel()
    }

    func end() {
        isCommitting = true
        window.orderOut(nil)
        textView.string = ""
        onCommit = nil
        onCancel = nil
        isCommitting = false
    }

    func focus() -> Bool {
        window.isVisible
    }

    var isVisible: Bool { window.isVisible }
    var eventWindow: NSWindow { window }

    func textDidChange(_ notification: Notification) {
        updateFrame()
    }

    private func updateFrame() {
        let measured = TextLayout.size(
            text: textView.string.isEmpty ? " " : textView.string,
            fontName: fontName,
            fontSize: fontSize
        )
        let width = min(max(120, measured.width + 16), maxWidth)
        let height = max(measured.height + 10, fontSize + 16)
        let top = topLeftScreenPoint.y
        let originY = screenFrame.maxY - top - height
        let originX = screenFrame.minX + topLeftScreenPoint.x
        window.setFrame(CGRect(x: originX, y: originY, width: width, height: height), display: true)
        textView.frame = CGRect(x: 0, y: 0, width: width, height: height)
        textView.textContainer?.containerSize = CGSize(width: width - 12, height: 1000)
    }

    private func commit() {
        guard !isCommitting else { return }
        let result = textView.string
        let callback = onCommit
        isCommitting = true
        window.orderOut(nil)
        isCommitting = false
        callback?(result)
    }

    private func cancel() {
        guard !isCommitting else { return }
        let callback = onCancel
        isCommitting = true
        window.orderOut(nil)
        isCommitting = false
        callback?()
    }
}

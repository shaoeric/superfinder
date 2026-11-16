import AppKit

/// A compact, always-on-top color palette used by the screenshot toolbar.
///
/// The system `NSColorPanel` normally opens above normal windows, but the
/// screenshot toolbar and overlay live at the screen-saver window level, which
/// is higher than a regular panel. Depending on the Space and activation state
/// the shared color panel can end up behind the overlay, making the color well
/// look unresponsive. This palette is a real panel at screen-saver + 3, so a
/// click always produces a visible picker; the "更多颜色…" button still opens
/// the system color panel, explicitly raised to the same level for custom
/// colors.
final class ColorSwatchButton: NSButton {
    var swatchColor: RGBAColor = .annotationRed {
        didSet { updateSwatch() }
    }
    var onClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title = ""
        alternateTitle = ""
        attributedTitle = NSAttributedString(string: "")
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageOnly
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.45).cgColor
        translatesAutoresizingMaskIntoConstraints = false
        focusRingType = .none
        toolTip = "选择颜色"
        setAccessibilityLabel("选择颜色")
        updateSwatch()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateSwatch() {
        layer?.backgroundColor = swatchColor.nsColor.cgColor
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 {
            onClick?()
        } else {
            super.keyDown(with: event)
        }
    }
}

final class ColorPalettePanel: NSPanel {
    static let shared = ColorPalettePanel()

    private static let presets: [RGBAColor] = [
        .annotationWhite,
        .annotationBlack,
        .annotationRed,
        RGBAColor(1.00, 0.45, 0.12),
        .annotationYellow,
        RGBAColor(0.20, 0.78, 0.35),
        RGBAColor(0.10, 0.75, 0.85),
        .annotationBlue,
        RGBAColor(0.55, 0.32, 0.95),
        RGBAColor(0.95, 0.32, 0.65),
        RGBAColor(0.58, 0.58, 0.60),
        RGBAColor(0.10, 0.10, 0.10, 0.85)
    ]

    private var onPick: ((RGBAColor) -> Void)?
    private var customPick: ((RGBAColor) -> Void)?
    private var currentColor: RGBAColor = .annotationRed
    private weak var anchorWindow: NSWindow?
    private var outsideMonitor: Any?
    private var deactivateObserver: NSObjectProtocol?
    private var colorPanelCloseObserver: NSObjectProtocol?
    private var swatchButtons: [ColorSwatchButton] = []

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 180, height: 86),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = true
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .none
        buildUI()
        orderOut(nil)
        deactivateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hidePalette(restoreFocus: false)
        }
    }

    deinit {
        if let deactivateObserver {
            NotificationCenter.default.removeObserver(deactivateObserver)
        }
        removeOutsideMonitor()
    }

    // MARK: - Presentation

    func show(anchor: NSView, current: RGBAColor, onPick: @escaping (RGBAColor) -> Void) {
        hidePalette(restoreFocus: false)
        dismissSystemPanel()
        self.onPick = onPick
        self.customPick = onPick
        self.currentColor = current
        anchorWindow = anchor.window

        for button in swatchButtons {
            let selected = button.swatchColor == current
            button.layer?.borderWidth = selected ? 2 : 1
            button.layer?.borderColor = selected
                ? NSColor.white.cgColor
                : NSColor.white.withAlphaComponent(0.45).cgColor
        }

        layoutAndSize()
        position(near: anchor)
        orderFrontRegardless()
        makeKey()

        outsideMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.window !== self {
                self.hidePalette(restoreFocus: false)
            }
            return event
        }
    }

    func hidePalette(restoreFocus: Bool) {
        removeOutsideMonitor()
        onPick = nil
        orderOut(nil)
        if restoreFocus {
            anchorWindow?.makeKeyAndOrderFront(nil)
        }
    }

    /// Called when a screenshot session ends so neither the swatch palette nor
    /// the custom color panel outlives the editor it belongs to.
    func dismissAll() {
        hidePalette(restoreFocus: false)
        dismissSystemPanel()
    }

    // MARK: - Actions

    private func choose(_ color: RGBAColor) {
        let callback = onPick
        hidePalette(restoreFocus: true)
        callback?(color)
    }

    @objc private func customColorAction() {
        openSystemPanel()
    }

    private func openSystemPanel() {
        let callback = customPick
        hidePalette(restoreFocus: false)
        customPick = callback
        guard callback != nil else { return }

        NSApp.activate(ignoringOtherApps: true)
        let panel = NSColorPanel.shared
        panel.showsAlpha = true
        panel.isContinuous = true
        panel.color = currentColor.nsColor
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = true
        panel.setTarget(self)
        panel.setAction(#selector(systemColorChanged(_:)))
        panel.orderFrontRegardless()
        panel.makeKey()
        if let colorPanelCloseObserver {
            NotificationCenter.default.removeObserver(colorPanelCloseObserver)
        }
        colorPanelCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.anchorWindow?.makeKeyAndOrderFront(nil)
        }
    }

    private func dismissSystemPanel() {
        customPick = nil
        if let colorPanelCloseObserver {
            NotificationCenter.default.removeObserver(colorPanelCloseObserver)
            self.colorPanelCloseObserver = nil
        }
        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.orderOut(nil)
    }

    @objc private func systemColorChanged(_ sender: NSColorPanel) {
        guard let customPick else { return }
        let color = sender.color.usingColorSpace(.sRGB) ?? .white
        customPick(RGBAColor(color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent))
    }

    // MARK: - UI

    private func buildUI() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.90).cgColor
        container.layer?.cornerRadius = 10
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        container.layer?.borderWidth = 1

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 7
        root.alignment = .centerX
        root.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(root)

        for rowIndex in 0..<2 {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 7
            row.alignment = .centerY
            for column in 0..<6 {
                let index = rowIndex * 6 + column
                guard index < Self.presets.count else { continue }
                let color = Self.presets[index]
                let button = ColorSwatchButton()
                button.swatchColor = color
                button.toolTip = colorDescription(color)
                button.translatesAutoresizingMaskIntoConstraints = false
                button.widthAnchor.constraint(equalToConstant: 20).isActive = true
                button.heightAnchor.constraint(equalToConstant: 20).isActive = true
                button.onClick = { [weak self] in self?.choose(color) }
                button.setAccessibilityLabel(colorDescription(color))
                swatchButtons.append(button)
                row.addArrangedSubview(button)
            }
            root.addArrangedSubview(row)
        }

        let more = NSButton(title: "更多颜色…", target: self, action: #selector(customColorAction))
        more.isBordered = false
        more.font = .systemFont(ofSize: 11)
        more.contentTintColor = NSColor.white.withAlphaComponent(0.9)
        more.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(more)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            root.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            root.topAnchor.constraint(equalTo: container.topAnchor, constant: 9),
            root.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])
        contentView = container
        layoutAndSize()
    }

    private func layoutAndSize() {
        contentView?.layoutSubtreeIfNeeded()
        guard let contentView else { return }
        let fitting = contentView.fittingSize
        setContentSize(CGSize(width: max(200, fitting.width), height: max(84, fitting.height)))
    }

    private func position(near anchor: NSView) {
        guard let anchorWindow else { return }
        let anchorRectInWindow = anchor.convert(anchor.bounds, to: nil)
        let anchorRectOnScreen = anchorWindow.convertToScreen(anchorRectInWindow)
        let screen = anchorWindow.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? anchorRectOnScreen

        var x = anchorRectOnScreen.midX - frame.width / 2
        var y = anchorRectOnScreen.minY - frame.height - 6
        if y < visible.minY + 4 {
            y = anchorRectOnScreen.maxY + 6
        }
        x = min(max(x, visible.minX + 4), visible.maxX - frame.width - 4)
        y = min(max(y, visible.minY + 4), visible.maxY - frame.height - 4)
        setFrameOrigin(CGPoint(x: x, y: y))
    }

    private func colorDescription(_ color: RGBAColor) -> String {
        String(format: "R%03d G%03d B%03d",
               Int((color.red * 255).rounded()),
               Int((color.green * 255).rounded()),
               Int((color.blue * 255).rounded()))
    }

    private func removeOutsideMonitor() {
        if let outsideMonitor {
            NSEvent.removeMonitor(outsideMonitor)
            self.outsideMonitor = nil
        }
    }
}

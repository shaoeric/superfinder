import AppKit

final class CaptureToolbar: NSPanel {
    var onToolSelected: ((CaptureTool) -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onCancel: (() -> Void)?
    var onPin: (() -> Void)?
    var onSave: (() -> Void)?
    var onColorChanged: ((RGBAColor) -> Void)?
    var onWidthChanged: ((CGFloat) -> Void)?
    var onMosaicChanged: ((CGFloat) -> Void)?
    var onLinePatternChanged: ((LinePattern) -> Void)?
    var onArrowChanged: ((Bool, ArrowStyle) -> Void)?
    var onFontChanged: ((String) -> Void)?
    var onFontSizeChanged: ((CGFloat) -> Void)?
    var onEraserSizeChanged: ((CGFloat) -> Void)?
    var onEraserShapeChanged: ((EraserShape) -> Void)?

    private let rectRow = NSStackView()
    private let lineRow = NSStackView()
    private let textRow = NSStackView()
    private let eraserRow = NSStackView()
    private let propertyContainer = NSStackView()
    private let mainRow = NSStackView()
    private var toolButtons: [CaptureTool: NSButton] = [:]
    private var undoButton: NSButton!
    private var redoButton: NSButton!

    private let rectColorWell = NSColorWell()
    private let rectWidthSlider = NSSlider()
    private let rectWidthLabel = NSTextField(labelWithString: "")
    private let rectMosaicSlider = NSSlider()
    private let rectMosaicLabel = NSTextField(labelWithString: "")

    private let lineColorWell = NSColorWell()
    private let lineWidthSlider = NSSlider()
    private let lineWidthLabel = NSTextField(labelWithString: "")
    private let linePatternPopup = NSPopUpButton()
    private let startArrowPopup = NSPopUpButton()
    private let endArrowPopup = NSPopUpButton()

    private let textColorWell = NSColorWell()
    private let fontPopup = NSPopUpButton()
    private let fontSizeSlider = NSSlider()
    private let fontSizeLabel = NSTextField(labelWithString: "")

    private let eraserShapeControl = NSSegmentedControl(labels: ["圆形", "方形"], trackingMode: .selectOne, target: nil, action: nil)
    private let eraserSizeSlider = NSSlider()
    private let eraserSizeLabel = NSTextField(labelWithString: "")

    private var isRefreshing = false

    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 640, height: 88),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        buildUI()
        orderOut(nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refresh(document: ScreenshotDocument?, tool: CaptureTool, defaults: ScreenshotDefaults) {
        isRefreshing = true
        defer { isRefreshing = false }

        for (buttonTool, button) in toolButtons {
            let selected = buttonTool == tool
            button.state = selected ? .on : .off
            button.layer?.backgroundColor = selected
                ? NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
                : NSColor.clear.cgColor
            button.contentTintColor = selected ? .white : NSColor.white.withAlphaComponent(0.9)
        }

        undoButton.isEnabled = document?.canUndo == true
        redoButton.isEnabled = document?.canRedo == true
        undoButton.alphaValue = undoButton.isEnabled ? 1 : 0.35
        redoButton.alphaValue = redoButton.isEnabled ? 1 : 0.35

        let selected = document?.selectedAnnotation
        var row: NSStackView?
        if let selected {
            switch selected.kind {
            case .rectangle(let shape):
                row = rectRow
                rectColorWell.color = selected.color.nsColor
                rectWidthSlider.doubleValue = Double(selected.lineWidth)
                rectWidthLabel.stringValue = String(format: "%.0f", selected.lineWidth)
                rectMosaicSlider.doubleValue = Double(shape.mosaic)
                rectMosaicLabel.stringValue = String(format: "%.0f", shape.mosaic)
            case .line(let shape):
                row = lineRow
                lineColorWell.color = selected.color.nsColor
                lineWidthSlider.doubleValue = Double(selected.lineWidth)
                lineWidthLabel.stringValue = String(format: "%.0f", selected.lineWidth)
                selectPopup(linePatternPopup, value: shape.pattern.rawValue)
                selectPopup(startArrowPopup, value: shape.startArrow.rawValue)
                selectPopup(endArrowPopup, value: shape.endArrow.rawValue)
            case .text(let shape):
                row = textRow
                textColorWell.color = selected.color.nsColor
                selectFont(shape.fontName)
                fontSizeSlider.doubleValue = Double(shape.fontSize)
                fontSizeLabel.stringValue = String(format: "%.0f", shape.fontSize)
            }
        } else if tool == .rectangle {
            row = rectRow
            rectColorWell.color = defaults.rectangleColor.nsColor
            rectWidthSlider.doubleValue = Double(defaults.rectangleWidth)
            rectWidthLabel.stringValue = String(format: "%.0f", defaults.rectangleWidth)
            rectMosaicSlider.doubleValue = Double(defaults.rectangleMosaic)
            rectMosaicLabel.stringValue = String(format: "%.0f", defaults.rectangleMosaic)
        } else if tool == .line {
            row = lineRow
            lineColorWell.color = defaults.lineColor.nsColor
            lineWidthSlider.doubleValue = Double(defaults.lineWidth)
            lineWidthLabel.stringValue = String(format: "%.0f", defaults.lineWidth)
            selectPopup(linePatternPopup, value: defaults.linePattern.rawValue)
            selectPopup(startArrowPopup, value: defaults.lineStartArrow.rawValue)
            selectPopup(endArrowPopup, value: defaults.lineEndArrow.rawValue)
        } else if tool == .text {
            row = textRow
            textColorWell.color = defaults.textColor.nsColor
            selectFont(defaults.textFontName)
            fontSizeSlider.doubleValue = Double(defaults.textFontSize)
            fontSizeLabel.stringValue = String(format: "%.0f", defaults.textFontSize)
        } else if tool == .eraser {
            row = eraserRow
            eraserShapeControl.selectedSegment = defaults.eraserShape == .circle ? 0 : 1
            eraserSizeSlider.doubleValue = Double(defaults.eraserSize)
            eraserSizeLabel.stringValue = String(format: "%.0f", defaults.eraserSize)
        }

        for candidate in [rectRow, lineRow, textRow, eraserRow] {
            candidate.isHidden = candidate != row
        }
        propertyContainer.isHidden = row == nil
        layoutAndSize()
    }

    func position(below selection: CaptureSelection, on screen: NSScreen, toolbarHeight: CGFloat) {
        layoutAndSize()
        let width = frame.width
        let height = frame.height
        let local = selection.rect
        let screenTop = screen.frame.maxY
        let selectionBottom = screenTop - local.maxY
        var x = screen.frame.minX + local.midX - width / 2
        var y = selectionBottom - height - 8
        if y < screen.frame.minY + 6 {
            let selectionTop = screenTop - local.minY
            y = selectionTop + 8
        }
        if y + height > screen.frame.maxY - 6 {
            y = screen.frame.minY + 6
        }
        x = min(max(x, screen.frame.minX + 6), screen.frame.maxX - width - 6)
        setFrameOrigin(CGPoint(x: x, y: y))
    }

    func hideToolbar() {
        orderOut(nil)
    }

    // MARK: - UI

    private func buildUI() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
        container.layer?.cornerRadius = 10
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        container.layer?.borderWidth = 1

        for stack in [propertyContainer, mainRow] {
            stack.orientation = .horizontal
            stack.spacing = 8
            stack.alignment = .centerY
            stack.translatesAutoresizingMaskIntoConstraints = false
        }
        propertyContainer.spacing = 7

        buildRectRow()
        buildLineRow()
        buildTextRow()
        buildEraserRow()
        for row in [rectRow, lineRow, textRow, eraserRow] {
            row.orientation = .horizontal
            row.spacing = 7
            row.alignment = .centerY
            propertyContainer.addArrangedSubview(row)
        }

        buildMainRow()

        let root = NSStackView(views: [propertyContainer, mainRow])
        root.orientation = .vertical
        root.spacing = 6
        root.alignment = .centerX
        root.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 9),
            root.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -9),
            root.topAnchor.constraint(equalTo: container.topAnchor, constant: 7),
            root.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -7)
        ])
        contentView = container
        layoutAndSize()
    }

    private func buildMainRow() {
        for tool in CaptureTool.allCases {
            let button = makeIconButton(symbol: tool.symbolName, tooltip: tool.displayName)
            button.tag = CaptureTool.allCases.firstIndex(of: tool) ?? 0
            button.target = self
            button.action = #selector(toolButtonAction(_:))
            toolButtons[tool] = button
            mainRow.addArrangedSubview(button)
        }
        mainRow.addArrangedSubview(separator())
        undoButton = makeIconButton(symbol: "arrow.uturn.backward", tooltip: "撤销 (⌘Z)")
        undoButton.target = self
        undoButton.action = #selector(undoAction)
        redoButton = makeIconButton(symbol: "arrow.uturn.forward", tooltip: "重做 (⇧⌘Z)")
        redoButton.target = self
        redoButton.action = #selector(redoAction)
        mainRow.addArrangedSubview(undoButton)
        mainRow.addArrangedSubview(redoButton)
        mainRow.addArrangedSubview(separator())
        let cancel = makeIconButton(symbol: "xmark.circle", tooltip: "取消截图 (Esc)")
        cancel.target = self
        cancel.action = #selector(cancelAction)
        let pin = makeIconButton(symbol: "pin", tooltip: "贴图")
        pin.target = self
        pin.action = #selector(pinAction)
        let save = makeIconButton(symbol: "square.and.arrow.down", tooltip: "保存截图 (⌘S)")
        save.target = self
        save.action = #selector(saveAction)
        save.contentTintColor = .systemBlue
        mainRow.addArrangedSubview(cancel)
        mainRow.addArrangedSubview(pin)
        mainRow.addArrangedSubview(save)
    }

    private func buildRectRow() {
        configureColorWell(rectColorWell, action: #selector(rectColorAction))
        rectRow.addArrangedSubview(label("颜色"))
        rectRow.addArrangedSubview(rectColorWell)
        rectRow.addArrangedSubview(separator())
        rectRow.addArrangedSubview(label("粗细"))
        configureSlider(rectWidthSlider, min: 1, max: 30, action: #selector(rectWidthAction))
        rectRow.addArrangedSubview(rectWidthSlider)
        styleValueLabel(rectWidthLabel)
        rectRow.addArrangedSubview(rectWidthLabel)
        rectRow.addArrangedSubview(separator())
        rectRow.addArrangedSubview(label("马赛克"))
        configureSlider(rectMosaicSlider, min: 0, max: 20, action: #selector(rectMosaicAction))
        rectRow.addArrangedSubview(rectMosaicSlider)
        styleValueLabel(rectMosaicLabel)
        rectRow.addArrangedSubview(rectMosaicLabel)
    }

    private func buildLineRow() {
        configureColorWell(lineColorWell, action: #selector(lineColorAction))
        lineRow.addArrangedSubview(label("颜色"))
        lineRow.addArrangedSubview(lineColorWell)
        lineRow.addArrangedSubview(separator())
        lineRow.addArrangedSubview(label("粗细"))
        configureSlider(lineWidthSlider, min: 1, max: 30, action: #selector(lineWidthAction))
        lineRow.addArrangedSubview(lineWidthSlider)
        styleValueLabel(lineWidthLabel)
        lineRow.addArrangedSubview(lineWidthLabel)
        lineRow.addArrangedSubview(separator())
        configurePopup(linePatternPopup, items: LinePattern.allCases.map { ($0.displayName, $0.rawValue) }, action: #selector(linePatternAction))
        lineRow.addArrangedSubview(linePatternPopup)
        configurePopup(startArrowPopup, items: ArrowStyle.allCases.map { ("起点 " + $0.displayName, $0.rawValue) }, action: #selector(startArrowAction))
        configurePopup(endArrowPopup, items: ArrowStyle.allCases.map { ("终点 " + $0.displayName, $0.rawValue) }, action: #selector(endArrowAction))
        lineRow.addArrangedSubview(startArrowPopup)
        lineRow.addArrangedSubview(endArrowPopup)
    }

    private func buildTextRow() {
        configureColorWell(textColorWell, action: #selector(textColorAction))
        textRow.addArrangedSubview(label("颜色"))
        textRow.addArrangedSubview(textColorWell)
        textRow.addArrangedSubview(separator())
        textRow.addArrangedSubview(label("字体"))
        fontPopup.target = self
        fontPopup.action = #selector(fontAction)
        fontPopup.controlSize = .small
        for option in TextLayout.fontOptions {
            fontPopup.addItem(withTitle: option.displayName)
            fontPopup.lastItem?.representedObject = option.postScriptName ?? ""
        }
        textRow.addArrangedSubview(fontPopup)
        textRow.addArrangedSubview(separator())
        textRow.addArrangedSubview(label("字号"))
        configureSlider(fontSizeSlider, min: 8, max: 120, action: #selector(fontSizeAction))
        textRow.addArrangedSubview(fontSizeSlider)
        styleValueLabel(fontSizeLabel)
        textRow.addArrangedSubview(fontSizeLabel)
    }

    private func buildEraserRow() {
        eraserShapeControl.target = self
        eraserShapeControl.action = #selector(eraserShapeAction)
        eraserShapeControl.controlSize = .small
        eraserRow.addArrangedSubview(label("形状"))
        eraserRow.addArrangedSubview(eraserShapeControl)
        eraserRow.addArrangedSubview(separator())
        eraserRow.addArrangedSubview(label("大小"))
        configureSlider(eraserSizeSlider, min: 4, max: 120, action: #selector(eraserSizeAction))
        eraserRow.addArrangedSubview(eraserSizeSlider)
        styleValueLabel(eraserSizeLabel)
        eraserRow.addArrangedSubview(eraserSizeLabel)
    }

    private func layoutAndSize() {
        contentView?.layoutSubtreeIfNeeded()
        guard let contentView else { return }
        let fitting = contentView.fittingSize
        setContentSize(CGSize(width: max(300, fitting.width), height: max(44, fitting.height)))
    }

    private func makeIconButton(symbol: String, tooltip: String) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.imagePosition = .imageOnly
        button.contentTintColor = NSColor.white.withAlphaComponent(0.9)
        button.toolTip = tooltip
        button.wantsLayer = true
        button.layer?.cornerRadius = 5
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return button
    }

    private func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = NSColor.white.withAlphaComponent(0.75)
        return label
    }

    private func styleValueLabel(_ label: NSTextField) {
        label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        label.textColor = NSColor.white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: 22).isActive = true
    }

    private func configureSlider(_ slider: NSSlider, min: Double, max: Double, action: Selector) {
        slider.minValue = min
        slider.maxValue = max
        slider.isContinuous = true
        slider.controlSize = .small
        slider.target = self
        slider.action = action
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 82).isActive = true
    }

    private func configureColorWell(_ well: NSColorWell, action: Selector) {
        well.target = self
        well.action = action
        well.translatesAutoresizingMaskIntoConstraints = false
        well.widthAnchor.constraint(equalToConstant: 34).isActive = true
        well.heightAnchor.constraint(equalToConstant: 22).isActive = true
    }

    private func configurePopup(_ popup: NSPopUpButton, items: [(String, String)], action: Selector) {
        popup.removeAllItems()
        popup.controlSize = .small
        popup.font = .systemFont(ofSize: 11)
        popup.target = self
        popup.action = action
        for (title, value) in items {
            popup.addItem(withTitle: title)
            popup.lastItem?.representedObject = value
        }
    }

    private func separator() -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: 1).isActive = true
        view.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return view
    }

    private func selectPopup(_ popup: NSPopUpButton, value: String) {
        for item in popup.itemArray {
            if (item.representedObject as? String) == value {
                popup.select(item)
                return
            }
        }
    }

    private func selectFont(_ fontName: String) {
        for (index, option) in TextLayout.fontOptions.enumerated() {
            if (option.postScriptName ?? "") == fontName {
                fontPopup.selectItem(at: index)
                return
            }
        }
        fontPopup.selectItem(at: 0)
    }

    private func selectedRectColor() -> RGBAColor {
        let color = rectColorWell.color.usingColorSpace(.sRGB) ?? .red
        return RGBAColor(color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent)
    }

    private func selectedLineColor() -> RGBAColor {
        let color = lineColorWell.color.usingColorSpace(.sRGB) ?? .red
        return RGBAColor(color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent)
    }

    private func selectedTextColor() -> RGBAColor {
        let color = textColorWell.color.usingColorSpace(.sRGB) ?? .red
        return RGBAColor(color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent)
    }

    // MARK: - Actions

    @objc private func toolButtonAction(_ sender: NSButton) {
        guard !isRefreshing, CaptureTool.allCases.indices.contains(sender.tag) else { return }
        onToolSelected?(CaptureTool.allCases[sender.tag])
    }

    @objc private func undoAction() { guard !isRefreshing else { return }; onUndo?() }
    @objc private func redoAction() { guard !isRefreshing else { return }; onRedo?() }
    @objc private func cancelAction() { guard !isRefreshing else { return }; onCancel?() }
    @objc private func pinAction() { guard !isRefreshing else { return }; onPin?() }
    @objc private func saveAction() { guard !isRefreshing else { return }; onSave?() }

    @objc private func rectColorAction() {
        guard !isRefreshing else { return }
        onColorChanged?(selectedRectColor())
    }

    @objc private func lineColorAction() {
        guard !isRefreshing else { return }
        onColorChanged?(selectedLineColor())
    }

    @objc private func textColorAction() {
        guard !isRefreshing else { return }
        onColorChanged?(selectedTextColor())
    }

    @objc private func rectWidthAction() {
        guard !isRefreshing else { return }
        let value = CGFloat(rectWidthSlider.doubleValue.rounded())
        rectWidthLabel.stringValue = String(format: "%.0f", value)
        onWidthChanged?(value)
    }

    @objc private func lineWidthAction() {
        guard !isRefreshing else { return }
        let value = CGFloat(lineWidthSlider.doubleValue.rounded())
        lineWidthLabel.stringValue = String(format: "%.0f", value)
        onWidthChanged?(value)
    }

    @objc private func rectMosaicAction() {
        guard !isRefreshing else { return }
        let value = CGFloat(rectMosaicSlider.doubleValue.rounded())
        rectMosaicLabel.stringValue = String(format: "%.0f", value)
        onMosaicChanged?(value)
    }

    @objc private func linePatternAction() {
        guard !isRefreshing, let raw = linePatternPopup.selectedItem?.representedObject as? String,
              let pattern = LinePattern(rawValue: raw) else { return }
        onLinePatternChanged?(pattern)
    }

    @objc private func startArrowAction() {
        guard !isRefreshing, let raw = startArrowPopup.selectedItem?.representedObject as? String,
              let style = ArrowStyle(rawValue: raw) else { return }
        onArrowChanged?(true, style)
    }

    @objc private func endArrowAction() {
        guard !isRefreshing, let raw = endArrowPopup.selectedItem?.representedObject as? String,
              let style = ArrowStyle(rawValue: raw) else { return }
        onArrowChanged?(false, style)
    }

    @objc private func fontAction() {
        guard !isRefreshing, let name = fontPopup.selectedItem?.representedObject as? String else { return }
        onFontChanged?(name)
    }

    @objc private func fontSizeAction() {
        guard !isRefreshing else { return }
        let value = CGFloat(fontSizeSlider.doubleValue.rounded())
        fontSizeLabel.stringValue = String(format: "%.0f", value)
        onFontSizeChanged?(value)
    }

    @objc private func eraserShapeAction() {
        guard !isRefreshing else { return }
        onEraserShapeChanged?(eraserShapeControl.selectedSegment == 0 ? .circle : .square)
    }

    @objc private func eraserSizeAction() {
        guard !isRefreshing else { return }
        let value = CGFloat(eraserSizeSlider.doubleValue.rounded())
        eraserSizeLabel.stringValue = String(format: "%.0f", value)
        onEraserSizeChanged?(value)
    }
}

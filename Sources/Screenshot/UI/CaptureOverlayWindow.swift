import AppKit
import QuartzCore

final class CaptureOverlayWindow: NSPanel {
    let targetScreen: NSScreen
    let overlayView: CaptureOverlayView

    init(screen: NSScreen) {
        self.targetScreen = screen
        self.overlayView = CaptureOverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = overlayView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    var desiredCursor: NSCursor {
        get { overlayView.desiredCursor }
        set { overlayView.desiredCursor = newValue }
    }

    func setActive(_ active: Bool) { overlayView.setActive(active) }
    func setCapturedScreen(_ captured: CapturedScreen?) { overlayView.setCapturedScreen(captured) }
    func clearBaseImage() { overlayView.clearBaseImage() }
    func setSession(document: ScreenshotDocument?, selection: CaptureSelection?, tool: CaptureTool) {
        overlayView.setSession(document: document, selection: selection, tool: tool)
    }
    func updateSelection(_ selection: CaptureSelection?) { overlayView.updateSelection(selection) }
    func updateTool(_ tool: CaptureTool) { overlayView.updateTool(tool) }
    func updateSelectionState(selectedID: UUID?, hoveredID: UUID?, editingTextID: UUID?) {
        overlayView.updateSelectionState(selectedID: selectedID, hoveredID: hoveredID, editingTextID: editingTextID)
    }
    func reloadAnnotations() { overlayView.reloadAnnotations() }
    func showPreview(annotation: Annotation?) { overlayView.showPreview(annotation: annotation) }
    func showErasePreview(stroke: EraseStroke?) { overlayView.showErasePreview(stroke: stroke) }
    func showBrushCursor(at point: CGPoint?, size: CGFloat, shape: EraserShape) {
        overlayView.showBrushCursor(at: point, size: size, shape: shape)
    }
}

final class CaptureOverlayView: NSView {
    var onMouseMoved: ((NSPoint) -> Void)?
    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?

    private let baseLayer = CALayer()
    private let dimLayer = CALayer()
    private let dimMaskLayer = CAShapeLayer()
    private let frozenLayer = CALayer()
    private let annotationRoot = CALayer()
    private let chromeRoot = CALayer()
    private let previewRoot = CALayer()
    private var trackingAreaRef: NSTrackingArea?

    private(set) var capturedScreen: CapturedScreen?
    private(set) var selection: CaptureSelection?
    private(set) var document: ScreenshotDocument?
    private(set) var active = false
    private var selectedID: UUID?
    private var hoveredID: UUID?
    private var editingTextID: UUID?
    private var tool: CaptureTool = .pointer

    var desiredCursor: NSCursor = .crosshair {
        didSet { window?.invalidateCursorRects(for: self) }
    }

    private var layersConfigured = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        configureLayersIfNeeded()
        needsLayout = true
    }

    private func configureLayersIfNeeded() {
        guard !layersConfigured, let root = layer else { return }
        layersConfigured = true
        root.backgroundColor = NSColor.clear.cgColor
        root.masksToBounds = true

        baseLayer.contentsGravity = .resize
        baseLayer.frame = bounds
        baseLayer.contents = capturedScreen?.displayImage ?? capturedScreen?.image
        baseLayer.isHidden = !active || capturedScreen == nil

        dimMaskLayer.fillColor = NSColor.white.cgColor
        dimMaskLayer.fillRule = .evenOdd
        dimMaskLayer.frame = bounds
        dimMaskLayer.path = CGPath(rect: bounds, transform: nil)
        dimLayer.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        dimLayer.mask = dimMaskLayer
        dimLayer.frame = bounds

        frozenLayer.contentsGravity = .resize
        frozenLayer.contentsScale = window?.backingScaleFactor ?? 1
        frozenLayer.isHidden = true
        frozenLayer.magnificationFilter = .linear

        annotationRoot.frame = bounds
        chromeRoot.frame = bounds
        previewRoot.frame = bounds

        root.addSublayer(baseLayer)
        root.addSublayer(dimLayer)
        root.addSublayer(frozenLayer)
        root.addSublayer(annotationRoot)
        root.addSublayer(chromeRoot)
        root.addSublayer(previewRoot)

        updateSelectionLayers()
        updateFrozenLayer()
        rebuildAnnotationLayers()
        rebuildChrome()
    }

    override func layout() {
        super.layout()
        configureLayersIfNeeded()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        baseLayer.frame = bounds
        dimLayer.frame = bounds
        dimMaskLayer.frame = bounds
        annotationRoot.frame = bounds
        chromeRoot.frame = bounds
        previewRoot.frame = bounds
        updateSelectionLayers()
        updateFrozenLayer()
        CATransaction.commit()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseMoved(with event: NSEvent) {
        onMouseMoved?(convert(event.locationInWindow, from: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseEntered?()
        onMouseMoved?(convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: desiredCursor)
    }

    // MARK: - State

    func setActive(_ active: Bool) {
        self.active = active
        baseLayer.isHidden = !active || capturedScreen == nil
        annotationRoot.isHidden = !active
        frozenLayer.isHidden = !active || document?.frozenRaster.image == nil
        chromeRoot.isHidden = !active
        previewRoot.isHidden = !active
        if !active {
            dimMaskLayer.path = CGPath(rect: bounds, transform: nil)
        } else {
            updateSelectionLayers()
        }
        needsLayout = true
    }

    func setCapturedScreen(_ captured: CapturedScreen?) {
        capturedScreen = captured
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        baseLayer.contents = captured?.displayImage ?? captured?.image
        baseLayer.isHidden = !active || captured == nil
        CATransaction.commit()
    }

    func clearBaseImage() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        baseLayer.contents = nil
        CATransaction.commit()
    }

    func setSession(document: ScreenshotDocument?, selection: CaptureSelection?, tool: CaptureTool) {
        self.document = document
        self.selection = selection
        self.tool = tool
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateSelectionLayers()
        updateFrozenLayer()
        rebuildAnnotationLayers()
        rebuildChrome()
        CATransaction.commit()
    }

    func updateSelection(_ selection: CaptureSelection?) {
        self.selection = selection
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateSelectionLayers()
        updateFrozenLayer()
        rebuildChrome()
        CATransaction.commit()
    }

    func updateTool(_ tool: CaptureTool) {
        self.tool = tool
        rebuildChrome()
    }

    func updateSelectionState(selectedID: UUID?, hoveredID: UUID?, editingTextID: UUID?) {
        self.selectedID = selectedID
        self.hoveredID = hoveredID
        self.editingTextID = editingTextID
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rebuildChrome()
        CATransaction.commit()
    }

    func reloadAnnotations() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updateFrozenLayer()
        rebuildAnnotationLayers()
        rebuildChrome()
        CATransaction.commit()
    }

    func showPreview(annotation: Annotation?) {
        previewRoot.sublayers?.forEach { $0.removeFromSuperlayer() }
        guard let annotation, let document, let selection else { return }
        let layers = makeVisualLayers(
            for: annotation,
            document: document,
            selectionOrigin: selection.rect.origin,
            preview: true
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in layers {
            previewRoot.addSublayer(layer)
        }
        CATransaction.commit()
    }

    func showErasePreview(stroke: EraseStroke?) {
        previewRoot.sublayers?.forEach { $0.removeFromSuperlayer() }
        guard let stroke, let selection else { return }
        let path = CGMutablePath()
        let origin = selection.rect.origin
        let height = bounds.height
        func point(_ p: CGPoint) -> CGPoint {
            CGPoint(x: origin.x + p.x, y: height - (origin.y + p.y))
        }
        if stroke.points.count == 1 {
            let c = point(stroke.points[0])
            let r = stroke.brushSize / 2
            if stroke.shape == .circle {
                path.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            } else {
                path.addRect(CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            }
        } else {
            path.move(to: point(stroke.points[0]))
            for p in stroke.points.dropFirst() {
                path.addLine(to: point(p))
            }
        }
        let layer = CAShapeLayer()
        layer.frame = bounds
        layer.path = path
        layer.fillColor = NSColor.white.withAlphaComponent(0.18).cgColor
        layer.strokeColor = NSColor.white.withAlphaComponent(0.7).cgColor
        layer.lineWidth = max(1, stroke.brushSize)
        layer.lineCap = stroke.shape == .circle ? .round : .square
        layer.lineJoin = .round
        layer.fillRule = .evenOdd
        if stroke.points.count == 1 {
            layer.fillColor = NSColor.white.withAlphaComponent(0.3).cgColor
        }
        previewRoot.addSublayer(layer)
    }

    func showBrushCursor(at point: CGPoint?, size: CGFloat, shape: EraserShape) {
        // The brush cursor shares previewRoot with gesture previews. This is
        // updated only on mouse events, never by a timer.
        guard let point else {
            if previewRoot.sublayers?.first?.name == "brushCursor" {
                previewRoot.sublayers?.first?.removeFromSuperlayer()
            }
            return
        }
        previewRoot.sublayers?.filter { $0.name == "brushCursor" }.forEach { $0.removeFromSuperlayer() }
        let c = CGPoint(x: point.x, y: bounds.height - point.y)
        let r = size / 2
        let path: CGPath
        if shape == .circle {
            path = CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2), transform: nil)
        } else {
            path = CGPath(rect: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2), transform: nil)
        }
        let layer = CAShapeLayer()
        layer.name = "brushCursor"
        layer.frame = bounds
        layer.path = path
        layer.fillColor = NSColor.clear.cgColor
        layer.strokeColor = NSColor.white.cgColor
        layer.lineWidth = 1
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.8
        layer.shadowRadius = 1
        layer.shadowOffset = .zero
        previewRoot.addSublayer(layer)
    }

    // MARK: - Layers

    private func updateSelectionLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard let selection, active else {
            dimMaskLayer.path = CGPath(rect: bounds, transform: nil)
            return
        }

        let viewRect = self.viewRect(forScreenRect: selection.rect)
        let maskPath = CGMutablePath()
        maskPath.addRect(bounds)
        maskPath.addRect(viewRect)
        dimMaskLayer.path = maskPath
        dimMaskLayer.fillRule = .evenOdd
        updateFrozenLayer()
    }

    private func updateFrozenLayer() {
        guard let selection, active, let frozen = document?.frozenRaster.displayImage ?? document?.frozenRaster.image else {
            frozenLayer.isHidden = true
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frozenLayer.frame = viewRect(forScreenRect: selection.rect)
        frozenLayer.contents = frozen
        frozenLayer.isHidden = false
        CATransaction.commit()
    }

    private func rebuildAnnotationLayers() {
        annotationRoot.sublayers?.forEach { $0.removeFromSuperlayer() }
        guard let document, active, let selection else { return }
        for annotation in document.annotations {
            if annotation.id == editingTextID { continue }
            for layer in makeVisualLayers(
                for: annotation,
                document: document,
                selectionOrigin: selection.rect.origin,
                preview: false
            ) {
                annotationRoot.addSublayer(layer)
            }
        }
    }

    private func makeVisualLayers(
        for annotation: Annotation,
        document: ScreenshotDocument,
        selectionOrigin: CGPoint,
        preview: Bool
    ) -> [CALayer] {
        guard let captured = capturedScreen else { return [] }
        let scale = captured.workingScale
        var layers: [CALayer] = []

        switch annotation.kind {
        case .rectangle(let shape):
            let selectionRect = CGRect(origin: selectionOrigin, size: document.selection.rect.size)
            let screenCenter = AnnotationSpace.screen(fromLocal: shape.center, selection: selectionRect)
            if shape.mosaic > 0,
               let baseImage = captured.image,
               let mosaic = MosaicRenderer.pixelatedImage(
                baseImage: baseImage,
                screenRect: CGRect(
                    x: screenCenter.x - shape.size.width / 2,
                    y: screenCenter.y - shape.size.height / 2,
                    width: shape.size.width,
                    height: shape.size.height
                ),
                workingScale: scale,
                block: shape.mosaic * 2
               ) {
                let imageLayer = CALayer()
                let rect = viewRect(forScreenRect: CGRect(
                    x: screenCenter.x - shape.size.width / 2,
                    y: screenCenter.y - shape.size.height / 2,
                    width: shape.size.width,
                    height: shape.size.height
                ))
                imageLayer.frame = rect
                imageLayer.contents = mosaic
                imageLayer.contentsGravity = .resize
                imageLayer.magnificationFilter = .nearest
                imageLayer.transform = CATransform3DMakeRotation(-shape.angle, 0, 0, 1)
                imageLayer.opacity = preview ? 0.85 : 1
                layers.append(imageLayer)
            }

            let path = CGMutablePath()
            let corners = shape.corners.map {
                viewPoint(forScreenPoint: AnnotationSpace.screen(fromLocal: $0, selection: selectionRect))
            }
            path.addLines(between: corners)
            path.closeSubpath()
            let outline = CAShapeLayer()
            outline.frame = bounds
            outline.path = path
            outline.fillColor = NSColor.clear.cgColor
            outline.strokeColor = annotation.color.nsColor.cgColor
            outline.lineWidth = max(1, annotation.lineWidth)
            outline.lineJoin = .miter
            layers.append(outline)

        case .line(let shape):
            let selectionRect = CGRect(origin: selectionOrigin, size: document.selection.rect.size)
            let start = viewPoint(forScreenPoint: AnnotationSpace.screen(fromLocal: shape.start, selection: selectionRect))
            let end = viewPoint(forScreenPoint: AnnotationSpace.screen(fromLocal: shape.end, selection: selectionRect))
            let linePath = CGMutablePath()
            linePath.move(to: start)
            linePath.addLine(to: end)
            let line = CAShapeLayer()
            line.frame = bounds
            line.path = linePath
            line.fillColor = NSColor.clear.cgColor
            line.strokeColor = annotation.color.nsColor.cgColor
            line.lineWidth = max(1, annotation.lineWidth)
            line.lineCap = .butt
            line.lineDashPattern = dashPattern(for: shape.pattern, lineWidth: annotation.lineWidth)
            layers.append(line)

            let arrowPath = CGMutablePath()
            appendArrow(to: arrowPath, at: start, from: end, style: shape.startArrow, lineWidth: annotation.lineWidth)
            appendArrow(to: arrowPath, at: end, from: start, style: shape.endArrow, lineWidth: annotation.lineWidth)
            if !arrowPath.isEmpty {
                let arrows = CAShapeLayer()
                arrows.frame = bounds
                arrows.path = arrowPath
                arrows.fillColor = annotation.color.nsColor.cgColor
                arrows.strokeColor = annotation.color.nsColor.cgColor
                arrows.lineWidth = max(1, annotation.lineWidth * 0.8)
                arrows.lineCap = .round
                arrows.lineJoin = .round
                layers.append(arrows)
            }

        case .text(let shape):
            let size = TextLayout.size(text: shape.text, fontName: shape.fontName, fontSize: shape.fontSize)
            let selectionRect = CGRect(origin: selectionOrigin, size: document.selection.rect.size)
            let screenOrigin = AnnotationSpace.screen(fromLocal: shape.origin, selection: selectionRect)
            let frame = viewRect(forScreenRect: CGRect(origin: screenOrigin, size: size))
            let textLayer = CATextLayer()
            textLayer.frame = frame
            textLayer.string = TextLayout.attributedString(
                text: shape.text,
                fontName: shape.fontName,
                fontSize: shape.fontSize,
                color: annotation.color.nsColor
            )
            textLayer.contentsScale = window?.backingScaleFactor ?? 2
            textLayer.isWrapped = false
            textLayer.alignmentMode = .left
            textLayer.truncationMode = .none
            textLayer.opacity = preview ? 0.85 : 1
            layers.append(textLayer)
        }
        return layers
    }

    private func rebuildChrome() {
        chromeRoot.sublayers?.forEach { $0.removeFromSuperlayer() }
        guard active, let selection, let document else { return }

        let selectionRect = viewRect(forScreenRect: selection.rect)
        let border = CAShapeLayer()
        border.frame = bounds
        border.path = CGPath(rect: selectionRect, transform: nil)
        border.fillColor = NSColor.clear.cgColor
        border.strokeColor = NSColor.white.withAlphaComponent(0.95).cgColor
        border.lineWidth = 1.5
        chromeRoot.addSublayer(border)

        if tool == .pointer && selectedID == nil {
            let handlePath = CGMutablePath()
            for (_, center) in selection.handleCenters {
                let p = viewPoint(forScreenPoint: center)
                handlePath.addEllipse(in: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
            }
            let handles = CAShapeLayer()
            handles.frame = bounds
            handles.path = handlePath
            handles.fillColor = NSColor.white.cgColor
            handles.strokeColor = NSColor.black.withAlphaComponent(0.6).cgColor
            handles.lineWidth = 1
            chromeRoot.addSublayer(handles)
        }

        if let selectedID, let annotation = document.annotations.first(where: { $0.id == selectedID }) {
            addSelectionChrome(for: annotation, document: document)
        } else if let hoveredID, let annotation = document.annotations.first(where: { $0.id == hoveredID }) {
            let points = annotation.selectionOutlinePoints().map {
                viewPoint(forScreenPoint: AnnotationSpace.screen(fromLocal: $0, selection: selection.rect))
            }
            let path = CGMutablePath()
            path.addLines(between: points)
            path.closeSubpath()
            let layer = CAShapeLayer()
            layer.frame = bounds
            layer.path = path
            layer.fillColor = NSColor.clear.cgColor
            layer.strokeColor = NSColor.systemBlue.withAlphaComponent(0.8).cgColor
            layer.lineWidth = 1
            layer.lineDashPattern = [4, 3]
            chromeRoot.addSublayer(layer)
        }
    }

    private func addSelectionChrome(for annotation: Annotation, document: ScreenshotDocument) {
        guard let selection else { return }
        let origin = selection.rect.origin
        let outline = annotation.selectionOutlinePoints()
        let viewPoints = outline.map {
            viewPoint(forScreenPoint: CGPoint(x: origin.x + $0.x, y: origin.y + $0.y))
        }
        let outlinePath = CGMutablePath()
        outlinePath.addLines(between: viewPoints)
        outlinePath.closeSubpath()
        let outlineLayer = CAShapeLayer()
        outlineLayer.frame = bounds
        outlineLayer.path = outlinePath
        outlineLayer.fillColor = NSColor.clear.cgColor
        outlineLayer.strokeColor = NSColor.white.cgColor
        outlineLayer.lineWidth = 1
        outlineLayer.lineDashPattern = [4, 3]
        chromeRoot.addSublayer(outlineLayer)

        let handlePoints = annotation.handlesForEditing().map {
            viewPoint(forScreenPoint: CGPoint(x: origin.x + $0.x, y: origin.y + $0.y))
        }
        let handlePath = CGMutablePath()
        for p in handlePoints {
            handlePath.addEllipse(in: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
        }
        let handles = CAShapeLayer()
        handles.frame = bounds
        handles.path = handlePath
        handles.fillColor = NSColor.white.cgColor
        handles.strokeColor = NSColor.black.withAlphaComponent(0.6).cgColor
        handles.lineWidth = 1
        chromeRoot.addSublayer(handles)

        let deletePoint = viewPoint(forScreenPoint: CGPoint(
            x: origin.x + annotation.deleteHandlePoint().x,
            y: origin.y + annotation.deleteHandlePoint().y
        ))
        let deleteLayer = CAShapeLayer()
        deleteLayer.frame = bounds
        let circle = CGMutablePath()
        circle.addEllipse(in: CGRect(x: deletePoint.x - 8, y: deletePoint.y - 8, width: 16, height: 16))
        let xPath = CGMutablePath()
        xPath.move(to: CGPoint(x: deletePoint.x - 3.5, y: deletePoint.y - 3.5))
        xPath.addLine(to: CGPoint(x: deletePoint.x + 3.5, y: deletePoint.y + 3.5))
        xPath.move(to: CGPoint(x: deletePoint.x + 3.5, y: deletePoint.y - 3.5))
        xPath.addLine(to: CGPoint(x: deletePoint.x - 3.5, y: deletePoint.y + 3.5))
        deleteLayer.path = circle
        deleteLayer.fillColor = NSColor.systemRed.withAlphaComponent(0.92).cgColor
        deleteLayer.strokeColor = NSColor.clear.cgColor
        chromeRoot.addSublayer(deleteLayer)
        let xLayer = CAShapeLayer()
        xLayer.frame = bounds
        xLayer.path = xPath
        xLayer.fillColor = NSColor.clear.cgColor
        xLayer.strokeColor = NSColor.white.cgColor
        xLayer.lineWidth = 1.5
        chromeRoot.addSublayer(xLayer)

        if let rotatePoint = annotation.rotationHandlePoint() {
            let p = viewPoint(forScreenPoint: CGPoint(x: origin.x + rotatePoint.x, y: origin.y + rotatePoint.y))
            let rotate = CAShapeLayer()
            rotate.frame = bounds
            let path = CGMutablePath()
            path.addEllipse(in: CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16))
            path.move(to: CGPoint(x: p.x - 4, y: p.y + 1))
            path.addArc(center: p, radius: 5, startAngle: -0.4, endAngle: 2.2, clockwise: false)
            rotate.path = path
            rotate.fillColor = NSColor.black.withAlphaComponent(0.55).cgColor
            rotate.strokeColor = NSColor.white.cgColor
            rotate.lineWidth = 1.5
            chromeRoot.addSublayer(rotate)
        }
    }

    // MARK: - Geometry

    func viewPoint(forScreenPoint point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: bounds.height - point.y)
    }

    func viewRect(forScreenRect rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: bounds.height - rect.minY - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    private func dashPattern(for pattern: LinePattern, lineWidth: CGFloat) -> [NSNumber]? {
        switch pattern {
        case .solid:
            return nil
        case .dashed:
            return [NSNumber(value: max(4, lineWidth * 3)), NSNumber(value: max(3, lineWidth * 2))]
        case .dashDot:
            return [
                NSNumber(value: max(5, lineWidth * 4)),
                NSNumber(value: max(3, lineWidth * 2)),
                NSNumber(value: max(1.5, lineWidth)),
                NSNumber(value: max(3, lineWidth * 2))
            ]
        }
    }

    private func appendArrow(
        to path: CGMutablePath,
        at point: CGPoint,
        from other: CGPoint,
        style: ArrowStyle,
        lineWidth: CGFloat
    ) {
        guard style != .none else { return }
        let dx = point.x - other.x
        let dy = point.y - other.y
        let length = max(0.1, hypot(dx, dy))
        let ux = dx / length
        let uy = dy / length
        let size = max(8, lineWidth * 4.5)
        let angle = atan2(uy, ux)
        let spread = CGFloat.pi / 7
        let p1 = CGPoint(
            x: point.x - cos(angle - spread) * size,
            y: point.y - sin(angle - spread) * size
        )
        let p2 = CGPoint(
            x: point.x - cos(angle + spread) * size,
            y: point.y - sin(angle + spread) * size
        )
        if style == .thin {
            path.move(to: p1)
            path.addLine(to: point)
            path.addLine(to: p2)
        } else {
            path.move(to: point)
            path.addLine(to: p1)
            path.addLine(to: p2)
            path.closeSubpath()
        }
    }
}

extension CGMutablePath {
    func addLines(between points: [CGPoint]) {
        guard let first = points.first else { return }
        move(to: first)
        for point in points.dropFirst() {
            addLine(to: point)
        }
    }

}

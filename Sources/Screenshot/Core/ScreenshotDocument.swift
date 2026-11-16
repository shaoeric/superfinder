import AppKit
import CoreGraphics

/// Transparent bitmap derived from frozen annotations plus erase strokes.
/// It is a cache, never part of history, and is released when there is no
/// frozen annotation.
final class FrozenRaster {
    private(set) var context: CGContext?
    private(set) var image: CGImage?
    private(set) var displayImage: CGImage?
    private(set) var pixelWidth = 0
    private(set) var pixelHeight = 0
    private(set) var scale: CGFloat = 1

    var byteCount: Int {
        MemoryBudget.imageBytes(width: pixelWidth, height: pixelHeight)
    }

    func release() {
        context = nil
        image = nil
        displayImage = nil
        pixelWidth = 0
        pixelHeight = 0
    }

    func rebuild(
        selectionSize: CGSize,
        scale: CGFloat,
        frozen: [Annotation],
        strokes: [EraseStroke],
        baseImage: CGImage?,
        selectionOrigin: CGPoint
    ) {
        guard !frozen.isEmpty || !strokes.isEmpty else {
            release()
            return
        }
        let maxFrozenScale = sqrt(
            Double(MemoryBudget.frozenLayerLimit) /
            Double(max(1, selectionSize.width * selectionSize.height * CGFloat(MemoryBudget.bytesPerPixel)))
        )
        let frozenScale = min(scale, CGFloat(maxFrozenScale))
        let pixels = MemoryBudget.pixelSize(forPointSize: selectionSize, scale: frozenScale)
        guard MemoryBudget.imageBytes(width: pixels.width, height: pixels.height) <= MemoryBudget.frozenLayerLimit + 64 * 1024 else {
            release()
            return
        }

        if context == nil || pixelWidth != pixels.width || pixelHeight != pixels.height || self.scale != frozenScale {
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let newContext = CGContext(
                    data: nil,
                    width: pixels.width,
                    height: pixels.height,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                release()
                return
            }
            context = newContext
            pixelWidth = pixels.width
            pixelHeight = pixels.height
            self.scale = frozenScale
            image = nil
            displayImage = nil
        }

        guard let context else { return }
        context.clear(CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height))
        AnnotationRenderer.drawAll(
            frozen,
            in: context,
            scale: frozenScale,
            selectionHeight: selectionSize.height,
            selectionOrigin: selectionOrigin,
            baseImage: baseImage
        )
        AnnotationRenderer.drawEraseStrokes(
            strokes,
            in: context,
            scale: frozenScale,
            selectionHeight: selectionSize.height
        )
        image = context.makeImage()
        displayImage = image.map { Self.downscaled($0, maxBytes: 384 * 1024) ?? $0 }
    }

    private static func downscaled(_ image: CGImage, maxBytes: Int) -> CGImage? {
        let sourceBytes = MemoryBudget.imageBytes(width: image.width, height: image.height)
        guard sourceBytes > maxBytes else { return image }
        let ratio = sqrt(Double(maxBytes) / Double(sourceBytes))
        let width = max(1, Int(Double(image.width) * ratio))
        let height = max(1, Int(Double(image.height) * ratio))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

struct ScreenshotDocumentSnapshot: Equatable {
    var annotations: [Annotation]
    var frozenAnnotations: [Annotation]
    var eraseStrokes: [EraseStroke]
    var selectedID: UUID?
}

final class ScreenshotDocument {
    var selection: CaptureSelection
    let workingScale: CGFloat
    var selectionOrigin: CGPoint
    var baseImage: CGImage?
    let frozenRaster = FrozenRaster()

    private(set) var annotations: [Annotation] = []
    private(set) var frozenAnnotations: [Annotation] = []
    private(set) var eraseStrokes: [EraseStroke] = []
    var selectedID: UUID?
    var onChange: (() -> Void)?

    private var undoStack: [ScreenshotDocumentSnapshot] = []
    private var redoStack: [ScreenshotDocumentSnapshot] = []
    private var coalescingKey: String?
    private var lastCoalescedAt: Date = .distantPast

    init(selection: CaptureSelection, workingScale: CGFloat, selectionOrigin: CGPoint, baseImage: CGImage?) {
        self.selection = selection
        self.workingScale = workingScale
        self.selectionOrigin = selectionOrigin
        self.baseImage = baseImage
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    var selectedAnnotation: Annotation? {
        guard let selectedID else { return nil }
        return annotations.first { $0.id == selectedID }
    }

    var allVisibleAnnotations: [Annotation] {
        annotations
    }

    func updateSelection(_ selection: CaptureSelection) {
        self.selection = selection
        self.selectionOrigin = selection.rect.origin
        rebuildFrozen()
        onChange?()
    }

    func setSelected(_ id: UUID?) {
        selectedID = id
        onChange?()
    }

    func selectAnnotation(at point: CGPoint) -> Annotation? {
        for annotation in annotations.reversed() where annotation.hitTest(point) {
            selectedID = annotation.id
            onChange?()
            return annotation
        }
        selectedID = nil
        onChange?()
        return nil
    }

    func hitAnnotation(at point: CGPoint) -> Annotation? {
        annotations.reversed().first { $0.hitTest(point) }
    }

    func beginChange(coalescingKey: String? = nil) {
        pushUndo(coalescingKey: coalescingKey)
    }

    func add(_ annotation: Annotation, pushHistory: Bool = true) {
        if pushHistory { pushUndo() }
        annotations.append(annotation)
        selectedID = annotation.id
        onChange?()
    }

    func removeSelected() {
        guard let selectedID, let index = annotations.firstIndex(where: { $0.id == selectedID }) else {
            return
        }
        pushUndo()
        annotations.remove(at: index)
        self.selectedID = nil
        onChange?()
    }

    func moveAnnotation(id: UUID, by delta: CGPoint, commit: Bool) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[index].move(by: delta)
        selectedID = id
        if commit {
            onChange?()
        }
    }

    func resizeAnnotation(id: UUID, handleIndex: Int, by delta: CGPoint) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[index].resize(handleIndex: handleIndex, by: delta)
        onChange?()
    }

    func rotateAnnotation(id: UUID, angle: CGFloat) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[index].setRotation(angle)
        onChange?()
    }

    func updateSelected(
        color: RGBAColor? = nil,
        lineWidth: CGFloat? = nil,
        mosaic: CGFloat? = nil,
        fontName: String? = nil,
        fontSize: CGFloat? = nil,
        pushHistory: Bool = true
    ) {
        guard let selectedID, let index = annotations.firstIndex(where: { $0.id == selectedID }) else {
            return
        }
        if pushHistory { pushUndo(coalescingKey: "style-\(selectedID.uuidString)") }
        if let color { annotations[index].color = color }
        if let lineWidth { annotations[index].lineWidth = max(1, lineWidth) }
        switch annotations[index].kind {
        case .rectangle(var shape):
            if let mosaic { shape.mosaic = max(0, mosaic); annotations[index].kind = .rectangle(shape) }
        case .line:
            break
        case .text(var shape):
            if let fontName { shape.fontName = fontName; annotations[index].kind = .text(shape) }
            if let fontSize { shape.fontSize = max(8, fontSize); annotations[index].kind = .text(shape) }
        }
        onChange?()
    }

    func updateLineStyle(
        pattern: LinePattern? = nil,
        startArrow: ArrowStyle? = nil,
        endArrow: ArrowStyle? = nil
    ) {
        guard let selectedID, let index = annotations.firstIndex(where: { $0.id == selectedID }) else { return }
        guard case .line(var shape) = annotations[index].kind else { return }
        pushUndo(coalescingKey: "line-\(selectedID.uuidString)")
        if let pattern { shape.pattern = pattern }
        if let startArrow { shape.startArrow = startArrow }
        if let endArrow { shape.endArrow = endArrow }
        annotations[index].kind = .line(shape)
        onChange?()
    }

    func updateText(_ text: String) {
        guard let selectedID, let index = annotations.firstIndex(where: { $0.id == selectedID }) else { return }
        guard case .text(var shape) = annotations[index].kind else { return }
        shape.text = text
        annotations[index].kind = .text(shape)
        self.selectedID = annotations[index].id
        onChange?()
    }

    func commitEraseStroke(_ stroke: EraseStroke) {
        guard !stroke.points.isEmpty else { return }
        pushUndo()
        let toolCenter = stroke.points.last ?? .zero
        let radius = stroke.brushSize / 2
        var remaining: [Annotation] = []
        for annotation in annotations {
            if annotation.intersectsBrush(center: toolCenter, radius: radius) ||
                stroke.points.contains(where: { annotation.intersectsBrush(center: $0, radius: radius) }) {
                frozenAnnotations.append(annotation)
            } else {
                remaining.append(annotation)
            }
        }
        annotations = remaining
        eraseStrokes.append(stroke)
        selectedID = nil
        rebuildFrozen()
        onChange?()
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        let current = snapshotOfCurrent()
        redoStack.append(current)
        restore(snapshot)
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        let current = snapshotOfCurrent()
        undoStack.append(current)
        restore(snapshot)
    }

    func rebuildFrozen() {
        frozenRaster.rebuild(
            selectionSize: selection.rect.size,
            scale: workingScale,
            frozen: frozenAnnotations,
            strokes: eraseStrokes,
            baseImage: baseImage,
            selectionOrigin: selectionOrigin
        )
    }

    func releaseBaseImage() {
        baseImage = nil
    }

    func release() {
        undoStack.removeAll()
        redoStack.removeAll()
        annotations.removeAll()
        frozenAnnotations.removeAll()
        eraseStrokes.removeAll()
        baseImage = nil
        frozenRaster.release()
        onChange = nil
    }

    private func pushUndo(coalescingKey: String? = nil) {
        if let coalescingKey,
           self.coalescingKey == coalescingKey,
           Date().timeIntervalSince(lastCoalescedAt) < 0.5 {
            lastCoalescedAt = Date()
            return
        }
        undoStack.append(snapshotOfCurrent())
        if undoStack.count > MemoryBudget.historyCountLimit {
            undoStack.removeFirst(undoStack.count - MemoryBudget.historyCountLimit)
        }
        redoStack.removeAll()
        self.coalescingKey = coalescingKey
        lastCoalescedAt = Date()
    }

    private func snapshotOfCurrent() -> ScreenshotDocumentSnapshot {
        ScreenshotDocumentSnapshot(
            annotations: annotations,
            frozenAnnotations: frozenAnnotations,
            eraseStrokes: eraseStrokes,
            selectedID: selectedID
        )
    }

    private func restore(_ snapshot: ScreenshotDocumentSnapshot) {
        annotations = snapshot.annotations
        frozenAnnotations = snapshot.frozenAnnotations
        eraseStrokes = snapshot.eraseStrokes
        selectedID = snapshot.selectedID
        rebuildFrozen()
        onChange?()
    }
}

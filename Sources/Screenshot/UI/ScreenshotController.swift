import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import os

final class ScreenshotController {
    private enum State {
        case idle
        case capturing
        case selecting
        case editing
        case saving
    }

    private enum DragMode {
        case selecting
        case moveSelection
        case resizeSelection(SelectionHandle)
        case createRectangle(UUID)
        case createLine(UUID)
        case moveAnnotation(UUID)
        case resizeAnnotation(UUID, Int)
        case rotateAnnotation(UUID, CGPoint, CGFloat)
        case erase
    }

    weak var statusBar: StatusBarController?
    var canStart: (() -> Bool)?
    var onActiveChanged: ((Bool) -> Void)?

    private let log = Logger(subsystem: AppConfig.logSubsystem, category: "screenshot")
    private let captureService = ScreenCaptureService()
    private var state: State = .idle
    private var overlays: [CaptureOverlayWindow] = []
    private var activeOverlay: CaptureOverlayWindow?
    private var activeScreen: NSScreen?
    private var captured: CapturedScreen?
    private var selection: CaptureSelection?
    private var document: ScreenshotDocument?
    private var tool: CaptureTool = .pointer
    private var defaults = ScreenshotDefaults()
    private var hud: CaptureHUD?
    private var toolbar: CaptureToolbar?
    private var textEditor: TextEditorPanel?
    private var eventMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var pins: [PinnedImageWindow] = []
    private var editingPin: PinnedImageWindow?

    private var dragMode: DragMode?
    private var dragStartPoint: CGPoint = .zero
    private var dragLastPoint: CGPoint = .zero
    private var dragHistoryPushed = false
    private var previewAnnotation: Annotation?
    private var eraseStroke: EraseStroke?
    private var editingTextID: UUID?
    private var newTextOrigin: CGPoint?
    private var hoveredID: UUID?
    private var sessionScreenSignature: String = ""
    private var mouseScreenLocal: CGPoint = .zero

    var isActive: Bool { state != .idle }

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Lifecycle

    func beginCapture() {
        guard state == .idle else { return }
        if let canStart, !canStart() {
            NSSound.beep()
            return
        }

        previousApp = NSWorkspace.shared.frontmostApplication
        guard ensureScreenRecordingPermission() else {
            restorePreviousApp()
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        sessionScreenSignature = Self.screenSignature()
        state = .capturing
        installEventMonitor()
        createChromeIfNeeded()
        ScreenshotToast.shared.hide()

        let mouse = NSEvent.mouseLocation
        let screen = screen(containing: mouse) ?? NSScreen.main ?? NSScreen.screens[0]
        createOverlays()
        activateScreen(screen)
        onActiveChanged?(true)

        captureService.capture(screen: screen) { [weak self] result in
            guard let self, self.state == .capturing, !self.screensDiffer(screen, self.activeScreen) else { return }
            switch result {
            case .success(let captured):
                self.captured = self.compositePins(into: captured, on: screen)
                self.state = .selecting
                self.activateScreen(screen)
                self.log.info("Screenshot capture ready: \(captured.pixelWidth)x\(captured.pixelHeight, privacy: .public)")
                if let current = self.screen(containing: NSEvent.mouseLocation),
                   !self.sameScreen(current, screen),
                   let target = self.overlays.first(where: { self.sameScreen($0.targetScreen, current) }) {
                    self.switchActiveScreen(to: target)
                }
            case .failure(let error):
                self.log.error("Screenshot capture failed: \(error.localizedDescription, privacy: .public)")
                self.cleanup(restoreApp: true)
                self.showError("无法完成截屏", detail: error.localizedDescription)
            }
        }
    }

    func cancelSession() {
        if let pin = editingPin {
            finishPinEditing(pin: pin, apply: false)
        } else {
            cleanup(restoreApp: true)
        }
    }

    func shutdown() {
        cleanup(restoreApp: false)
        textEditor?.end()
        textEditor = nil
        for pin in pins {
            pin.orderOut(nil)
        }
        pins.removeAll()
    }

    private func cleanup(restoreApp: Bool) {
        if state == .idle { return }
        let pinnedEditor = editingPin
        captureService.cancel()
        removeEventMonitor()
        textEditor?.end()
        textEditor = nil
        activeOverlay?.showCrosshair(at: nil)
        hud?.hide()
        toolbar?.hideToolbar()
        ColorPalettePanel.shared.dismissAll()
        ScreenshotToast.shared.hide()
        NSColorPanel.shared.orderOut(nil)
        NSColorPanel.shared.level = .floating
        for overlay in overlays {
            overlay.clearBaseImage()
            overlay.orderOut(nil)
        }
        overlays.removeAll()
        if pinnedEditor == nil {
            document?.release()
            captured?.releaseDisplayImage()
        } else {
            document?.onChange = nil
        }
        document = nil
        captured = nil
        selection = nil
        activeOverlay = nil
        activeScreen = nil
        previewAnnotation = nil
        dragMode = nil
        eraseStroke = nil
        editingTextID = nil
        editingPin = nil
        state = .idle
        onActiveChanged?(false)
        if restoreApp {
            restorePreviousApp()
        }
        pinnedEditor?.orderFrontRegardless()
    }

    private func restorePreviousApp() {
        guard let previousApp,
              previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !previousApp.isTerminated else {
            return
        }
        previousApp.activate(options: [.activateIgnoringOtherApps])
    }

    private func ensureScreenRecordingPermission() -> Bool {
        if ScreenRecordingPermission.isGranted { return true }
        log.error("Screen recording permission is not granted; requesting it once")

        // Asking once registers SuperFinder in the Screen Recording list and
        // shows the system prompt on a first run. If the user already answered
        // "don't allow", macOS returns false immediately and only the system
        // settings toggle can change it, so the alert below explains that path.
        _ = ScreenRecordingPermission.request()
        if ScreenRecordingPermission.isGranted { return true }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "需要屏幕录制权限"
        alert.informativeText = "SuperFinder 需要「屏幕录制」权限才能截屏。请在「系统设置 → 隐私与安全性 → 屏幕录制」中允许 SuperFinder，然后重新启动应用再试。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            ScreenRecordingPermission.openSettings()
        }
        return false
    }

    // MARK: - Overlays and screen switching

    private func createOverlays() {
        for overlay in overlays { overlay.orderOut(nil) }
        overlays = NSScreen.screens.map { screen in
            let window = CaptureOverlayWindow(screen: screen)
            window.overlayView.onMouseMoved = { [weak self, weak window] point in
                guard let self, let window else { return }
                self.mouseMoved(over: window, viewPoint: point)
            }
            window.overlayView.onMouseEntered = { [weak self, weak window] in
                guard let self, let window else { return }
                self.mouseEntered(over: window)
            }
            window.overlayView.onMouseExited = { [weak self, weak window] in
                guard let self, let window else { return }
                self.mouseExited(over: window)
            }
            window.orderFrontRegardless()
            return window
        }
    }

    private func overlay(for screen: NSScreen) -> CaptureOverlayWindow? {
        overlays.first { sameScreen($0.targetScreen, screen) }
    }

    private func activateScreen(_ screen: NSScreen) {
        activeScreen = screen
        activeOverlay = overlay(for: screen)
        for overlay in overlays {
            let active = overlay === activeOverlay
            overlay.overlayView.setActive(active)
            if active {
                overlay.overlayView.setCapturedScreen(captured)
                overlay.orderFrontRegardless()
                overlay.makeKey()
            } else {
                overlay.overlayView.setCapturedScreen(nil)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        activeOverlay?.makeKeyAndOrderFront(nil)
        refreshActiveOverlay()
        updateHUD()
        updateCrosshairForCurrentPointer(on: screen)
    }

    private func switchActiveScreen(to window: CaptureOverlayWindow) {
        guard state == .selecting, selection == nil, document == nil,
              !sameScreen(window.targetScreen, activeScreen) else { return }
        captureService.cancel()
        captured = nil
        state = .capturing
        activeOverlay?.overlayView.setCapturedScreen(nil)
        activeOverlay?.overlayView.setActive(false)
        activeOverlay = window
        activeScreen = window.targetScreen
        window.overlayView.setActive(true)
        window.overlayView.setCapturedScreen(nil)
        window.makeKeyAndOrderFront(nil)
        activeOverlay?.showCrosshair(at: nil)
        hud?.hide()
        toolbar?.hideToolbar()

        let screen = window.targetScreen
        captureService.capture(screen: screen) { [weak self, weak window] result in
            guard let self, let window, self.state == .capturing, window === self.activeOverlay else { return }
            switch result {
            case .success(let captured):
                self.captured = self.compositePins(into: captured, on: screen)
                self.state = .selecting
                self.activateScreen(screen)
            case .failure(let error):
                self.cleanup(restoreApp: true)
                self.showError("无法完成截屏", detail: error.localizedDescription)
            }
        }
    }

    private func mouseEntered(over window: CaptureOverlayWindow) {
        guard sameScreen(window.targetScreen, activeScreen) else {
            if state == .selecting, selection == nil, document == nil {
                switchActiveScreen(to: window)
            }
            return
        }
        guard state == .selecting || state == .editing else { return }
        window.makeKeyAndOrderFront(nil)
    }

    private func mouseExited(over window: CaptureOverlayWindow) {
        guard window === activeOverlay else { return }
        window.showCrosshair(at: nil)
    }

    private func mouseMoved(over window: CaptureOverlayWindow, viewPoint: CGPoint) {
        guard window === activeOverlay, let screen = activeScreen else { return }
        let local = CGPoint(x: viewPoint.x, y: screen.frame.height - viewPoint.y)
        mouseScreenLocal = local
        switch state {
        case .selecting:
            // The guide follows the pointer; the HUD is intentionally not
            // touched here, so moving the mouse does not relayout live text.
            window.showCrosshair(at: local)
        case .editing:
            window.showCrosshair(at: nil)
            updateHover(at: local)
            updateBrushCursor(at: local)
        case .idle, .capturing, .saving:
            window.showCrosshair(at: nil)
        }
    }

    /// Positions the selection guide immediately when an overlay becomes
    /// active, without waiting for the first mouse-move event.
    private func updateCrosshairForCurrentPointer(on screen: NSScreen) {
        guard state == .selecting, let overlay = activeOverlay else {
            activeOverlay?.showCrosshair(at: nil)
            return
        }
        let global = NSEvent.mouseLocation
        guard screen.frame.contains(global) else {
            overlay.showCrosshair(at: nil)
            return
        }
        overlay.showCrosshair(at: CGPoint(
            x: global.x - screen.frame.minX,
            y: screen.frame.maxY - global.y
        ))
    }

    // MARK: - Event monitor

    private func installEventMonitor() {
        removeEventMonitor()
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .keyDown, .scrollWheel]
        ) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    private func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard state != .idle, state != .saving else { return event }

        if event.type == .keyDown {
            if textEditor?.isVisible == true { return event }
            // The color panel has its own hex fields and keyboard handling.
            // Do not steal Cmd+C / Delete / letter shortcuts from it.
            if event.window === NSColorPanel.shared { return event }
            if event.window === ColorPalettePanel.shared {
                if event.keyCode == 53 {
                    ColorPalettePanel.shared.hidePalette(restoreFocus: true)
                    return nil
                }
                return event
            }
            return handleKey(event) ? nil : event
        }

        if event.type == .scrollWheel {
            guard let activeOverlay, event.window === activeOverlay else { return event }
            handleScroll(event)
            return nil
        }

        if event.type == .leftMouseDown,
           let textEditor, textEditor.isVisible,
           event.window !== textEditor.eventWindow {
            // Commit only on a new click outside the editor. The mouse-up of
            // the click that created the text box must not commit it: the
            // editor would flash open and immediately close with empty text.
            textEditor.commitNow()
            // Clicking the toolbar or another panel must still reach that
            // control (for example the color swatch). Clicking the overlay
            // itself only commits, so a stray click does not start drawing.
            if event.window === activeOverlay {
                activeOverlay?.makeKeyAndOrderFront(nil)
                return nil
            }
            return event
        }

        if event.type == .leftMouseDown {
            guard let activeOverlay, event.window === activeOverlay else { return event }
            handleMouseDown(event)
            return nil
        }

        if event.type == .leftMouseDragged {
            guard dragMode != nil else { return event }
            if let local = screenLocalPoint(of: event) {
                handleDrag(at: local, modifiers: event.modifierFlags)
            }
            return nil
        }

        if event.type == .leftMouseUp {
            guard dragMode != nil else { return event }
            let local = screenLocalPoint(of: event) ?? dragLastPoint
            // Use the release event's own location for the final delta. Never
            // sample the live pointer here: it may already have moved on to
            // the next gesture, which is exactly the post-release jump this
            // path used to produce.
            handleDrag(at: local, modifiers: event.modifierFlags)
            handleMouseUp(at: local)
            return nil
        }
        return event
    }

    // MARK: - Mouse down / drag / up

    private func handleMouseDown(_ event: NSEvent) {
        guard let local = screenLocalPoint(of: event) else { return }
        mouseScreenLocal = local

        if state == .selecting {
            selection = CaptureSelection(anchor: local, current: local)
            dragMode = .selecting
            dragStartPoint = local
            dragLastPoint = local
            activeOverlay?.updateSelection(selection)
            updateHUD()
            return
        }

        guard state == .editing, let document, let selection else { return }
        let annotationLocal = annotationPoint(fromScreenLocal: local)

        // Resize handles sit on (and just outside) the selection border, so the
        // handle test must run before the "outside the selection" early return.
        if tool == .pointer, let handle = selection.handle(at: local) {
            dragMode = .resizeSelection(handle)
            dragStartPoint = local
            dragLastPoint = local
            return
        }

        if !selection.contains(local) && tool == .pointer {
            // Clicking outside the selection simply clears annotation selection.
            document.setSelected(nil)
            tool = .pointer
            activeOverlay?.updateTool(tool)
            activeOverlay?.updateSelectionState(selectedID: nil, hoveredID: hoveredID, editingTextID: editingTextID)
            updateHUD()
            return
        }

        switch tool {
        case .pointer:
            handlePointerDown(
                screenLocal: local,
                annotationLocal: annotationLocal,
                event: event,
                document: document
            )
        case .text:
            if let hit = document.hitAnnotation(at: annotationLocal) {
                if case .text = hit.kind {
                    beginEditingText(annotation: hit)
                    return
                }
            }
            guard selection.contains(local) else { return }
            beginNewText(at: annotationLocal)
        case .eraser:
            guard selection.contains(local) else { return }
            beginErase(at: annotationLocal)
        case .rectangle:
            guard selection.contains(local) else { return }
            beginNewRectangle(at: annotationLocal)
        case .line:
            guard selection.contains(local) else { return }
            beginNewLine(at: annotationLocal)
        }
    }

    private func handlePointerDown(
        screenLocal: CGPoint,
        annotationLocal: CGPoint,
        event: NSEvent,
        document: ScreenshotDocument
    ) {
        if let selected = document.selectedAnnotation {
            // Order matters: rotation and resize handles win over delete, so a
            // near-corner drag never accidentally deletes the annotation.
            if let rotation = selected.rotationHandlePoint(),
               hypot(annotationLocal.x - rotation.x, annotationLocal.y - rotation.y) <= 12 {
                if case .rectangle(let shape) = selected.kind {
                    let center = shape.center
                    let startAngle = atan2(annotationLocal.y - center.y, annotationLocal.x - center.x)
                    dragMode = .rotateAnnotation(selected.id, center, shape.angle - startAngle)
                    dragStartPoint = screenLocal
                    dragLastPoint = screenLocal
                    dragHistoryPushed = false
                }
                return
            }
            for (index, handle) in selected.handlesForEditing().enumerated() {
                if hypot(annotationLocal.x - handle.x, annotationLocal.y - handle.y) <= 12 {
                    document.beginChange()
                    dragMode = .resizeAnnotation(selected.id, index)
                    dragStartPoint = screenLocal
                    dragLastPoint = screenLocal
                    dragHistoryPushed = true
                    return
                }
            }
            if hypot(annotationLocal.x - selected.deleteHandlePoint().x, annotationLocal.y - selected.deleteHandlePoint().y) <= 9 {
                document.removeSelected()
                refreshAfterDocumentChange()
                return
            }
            if selected.hitTest(annotationLocal) {
                document.setSelected(selected.id)
                dragMode = .moveAnnotation(selected.id)
                dragStartPoint = screenLocal
                dragLastPoint = screenLocal
                dragHistoryPushed = false
                activeOverlay?.updateSelectionState(selectedID: selected.id, hoveredID: nil, editingTextID: nil)
                return
            }
        }

        if let handle = selection?.handle(at: screenLocal) {
            dragMode = .resizeSelection(handle)
            dragStartPoint = screenLocal
            dragLastPoint = screenLocal
            return
        }

        if let hit = document.hitAnnotation(at: annotationLocal) {
            document.setSelected(hit.id)
            if event.clickCount >= 2, case .text = hit.kind {
                beginEditingText(annotation: hit)
                return
            }
            dragMode = .moveAnnotation(hit.id)
            dragStartPoint = screenLocal
            dragLastPoint = screenLocal
            dragHistoryPushed = false
            activeOverlay?.updateSelectionState(selectedID: hit.id, hoveredID: nil, editingTextID: nil)
            refreshToolbar()
            return
        }

        if selection?.contains(screenLocal) == true {
            dragMode = .moveSelection
            dragStartPoint = screenLocal
            dragLastPoint = screenLocal
        }
    }

    private func handleDrag(at local: CGPoint, modifiers: NSEvent.ModifierFlags) {
        guard let screen = activeScreen else { return }
        mouseScreenLocal = local
        defer { dragLastPoint = local }

        guard let dragMode else { return }
        let annotationLocal = annotationPoint(fromScreenLocal: local)
        switch dragMode {
        case .selecting:
            let updated = CaptureSelection(anchor: dragStartPoint, current: local)
            self.selection = updated
            activeOverlay?.updateSelection(updated)
            updateHUD()
            updateBrushCursor(at: local)

        case .moveSelection:
            guard var selection else { return }
            let delta = CGPoint(x: local.x - dragLastPoint.x, y: local.y - dragLastPoint.y)
            selection.move(by: delta, within: CGRect(origin: .zero, size: screen.frame.size))
            self.selection = selection
            document?.updateSelection(selection)
            activeOverlay?.updateSelection(selection)
            refreshToolbar()
            updateHUD()

        case .resizeSelection(let handle):
            guard var selection else { return }
            let delta = CGPoint(x: local.x - dragLastPoint.x, y: local.y - dragLastPoint.y)
            selection.resize(handle: handle, by: delta, within: CGRect(origin: .zero, size: screen.frame.size))
            self.selection = selection
            document?.updateSelection(selection)
            activeOverlay?.updateSelection(selection)
            refreshToolbar()
            updateHUD()

        case .createRectangle(let id):
            guard var annotation = previewAnnotation, annotation.id == id,
                  case .rectangle(var shape) = annotation.kind else { return }
            let rect = CGRect(
                x: min(dragStartPoint.x, annotationLocal.x),
                y: min(dragStartPoint.y, annotationLocal.y),
                width: abs(annotationLocal.x - dragStartPoint.x),
                height: abs(annotationLocal.y - dragStartPoint.y)
            )
            shape.center = CGPoint(x: rect.midX, y: rect.midY)
            shape.size = rect.size
            annotation.kind = .rectangle(shape)
            previewAnnotation = annotation
            activeOverlay?.showPreview(annotation: annotation)
            updateHUD()

        case .createLine(let id):
            guard var annotation = previewAnnotation, annotation.id == id,
                  case .line(var shape) = annotation.kind else { return }
            shape.end = annotationLocal
            annotation.kind = .line(shape)
            previewAnnotation = annotation
            activeOverlay?.showPreview(annotation: annotation)
            updateHUD()

        case .moveAnnotation(let id):
            guard let document else { return }
            if !dragHistoryPushed {
                document.beginChange()
                dragHistoryPushed = true
            }
            let delta = CGPoint(x: local.x - dragLastPoint.x, y: local.y - dragLastPoint.y)
            document.moveAnnotation(id: id, by: delta, commit: true)

        case .resizeAnnotation(let id, let handleIndex):
            guard let document else { return }
            if !dragHistoryPushed {
                document.beginChange()
                dragHistoryPushed = true
            }
            let delta = CGPoint(x: local.x - dragLastPoint.x, y: local.y - dragLastPoint.y)
            document.resizeAnnotation(id: id, handleIndex: handleIndex, by: delta)

        case .rotateAnnotation(let id, let center, let offset):
            guard let document else { return }
            if !dragHistoryPushed {
                document.beginChange()
                dragHistoryPushed = true
            }
            var angle = atan2(annotationLocal.y - center.y, annotationLocal.x - center.x) + offset
            if modifiers.contains(.shift) {
                let step = CGFloat.pi / 12
                angle = (angle / step).rounded() * step
            }
            document.rotateAnnotation(id: id, angle: angle)

        case .erase:
            var stroke = eraseStroke ?? EraseStroke(points: [annotationLocal], brushSize: defaults.eraserSize, shape: defaults.eraserShape)
            let last = stroke.points.last ?? annotationLocal
            if hypot(annotationLocal.x - last.x, annotationLocal.y - last.y) >= max(1, defaults.eraserSize / 8) {
                stroke.points.append(annotationLocal)
                eraseStroke = stroke
                activeOverlay?.showErasePreview(stroke: stroke)
                activeOverlay?.showBrushCursor(at: local, size: defaults.eraserSize, shape: defaults.eraserShape)
            }
            updateHUD()
        }
    }

    private func handleMouseUp(at local: CGPoint) {
        guard let mode = dragMode else { return }
        dragMode = nil
        mouseScreenLocal = local

        switch mode {
        case .selecting:
            guard let selection, selection.isUsable else {
                self.selection = nil
                activeOverlay?.updateSelection(nil)
                hud?.hide()
                return
            }
            self.selection = selection
            createDocumentIfNeeded(selection: selection)
            state = .editing
            activeOverlay?.showCrosshair(at: nil)
            tool = .pointer
            activeOverlay?.setSession(document: document, selection: selection, tool: tool)
            activeOverlay?.updateSelectionState(selectedID: nil, hoveredID: nil, editingTextID: nil)
            showToolbar()
            updateHUD()
            updateCursor(at: mouseScreenLocal)

        case .createRectangle, .createLine:
            guard let annotation = previewAnnotation else { return }
            activeOverlay?.showPreview(annotation: nil)
            previewAnnotation = nil
            guard annotation.bounds.width >= 3 || annotation.bounds.height >= 3 else { return }
            document?.add(annotation)
            refreshAfterDocumentChange()
            showToolbar()
            updateHUD()

        case .erase:
            if var stroke = eraseStroke, !stroke.points.isEmpty {
                if stroke.points.count == 1 {
                    stroke.points.append(stroke.points[0])
                }
                document?.commitEraseStroke(stroke)
                eraseStroke = nil
                activeOverlay?.showErasePreview(stroke: nil)
                activeOverlay?.showBrushCursor(at: local, size: defaults.eraserSize, shape: defaults.eraserShape)
                refreshAfterDocumentChange()
                updateHUD()
            }

        default:
            document?.onChange?()
            refreshToolbar()
            updateHUD()
        }

    }

    // MARK: - Creation

    private func createDocumentIfNeeded(selection: CaptureSelection) {
        guard document == nil, let captured else { return }
        let document = ScreenshotDocument(
            selection: selection,
            workingScale: captured.workingScale,
            baseImage: captured.image
        )
        document.onChange = { [weak self] in
            self?.refreshAfterDocumentChange()
        }
        self.document = document
    }

    private func beginNewRectangle(at point: CGPoint) {
        let id = UUID()
        let annotation = Annotation(
            id: id,
            kind: .rectangle(RectangleShape(
                center: point,
                size: CGSize(width: 1, height: 1),
                angle: 0,
                filled: defaults.rectangleFilled
            )),
            color: defaults.rectangleColor,
            lineWidth: defaults.rectangleWidth
        )
        previewAnnotation = annotation
        dragMode = .createRectangle(id)
        dragStartPoint = point
        dragLastPoint = point
        activeOverlay?.showPreview(annotation: annotation)
    }

    private func beginNewLine(at point: CGPoint) {
        let id = UUID()
        let annotation = Annotation(
            id: id,
            kind: .line(LineShape(
                start: point,
                end: point,
                pattern: defaults.linePattern,
                startArrow: defaults.lineStartArrow,
                endArrow: defaults.lineEndArrow
            )),
            color: defaults.lineColor,
            lineWidth: defaults.lineWidth
        )
        previewAnnotation = annotation
        dragMode = .createLine(id)
        dragStartPoint = point
        dragLastPoint = point
        activeOverlay?.showPreview(annotation: annotation)
    }

    private func beginErase(at point: CGPoint) {
        eraseStroke = EraseStroke(
            points: [point],
            brushSize: defaults.eraserSize,
            shape: defaults.eraserShape
        )
        dragMode = .erase
        dragStartPoint = point
        dragLastPoint = point
        activeOverlay?.showErasePreview(stroke: eraseStroke)
        activeOverlay?.showBrushCursor(at: point, size: defaults.eraserSize, shape: defaults.eraserShape)
    }

    private func beginNewText(at point: CGPoint) {
        guard let screen = activeScreen, let selection else { return }
        editingTextID = nil
        newTextOrigin = point
        textEditor?.begin(
            text: "",
            fontName: defaults.textFontName,
            fontSize: defaults.textFontSize,
            color: defaults.textColor.nsColor,
            screenPoint: AnnotationSpace.screen(fromLocal: point, selection: selection.rect),
            screenFrame: screen.frame,
            maxWidth: max(80, selection.rect.width - point.x)
        ) { [weak self] text in
            self?.commitNewText(text)
        } onCancel: { [weak self] in
            self?.cancelTextEditing()
        }
    }

    private func beginEditingText(annotation: Annotation) {
        guard let screen = activeScreen, let selection, case .text(let shape) = annotation.kind else { return }
        document?.setSelected(annotation.id)
        editingTextID = annotation.id
        activeOverlay?.updateSelectionState(
            selectedID: annotation.id,
            hoveredID: nil,
            editingTextID: annotation.id
        )
        textEditor?.begin(
            text: shape.text,
            fontName: shape.fontName,
            fontSize: shape.fontSize,
            color: annotation.color.nsColor,
            screenPoint: AnnotationSpace.screen(fromLocal: shape.origin, selection: selection.rect),
            screenFrame: screen.frame,
            maxWidth: max(80, selection.rect.maxX - shape.origin.x)
        ) { [weak self] text in
            self?.commitEditedText(text, id: annotation.id)
        } onCancel: { [weak self] in
            self?.cancelTextEditing()
        }
    }

    private func commitNewText(_ text: String) {
        defer {
            editingTextID = nil
            newTextOrigin = nil
            textEditor?.end()
            activeOverlay?.updateSelectionState(
                selectedID: document?.selectedID,
                hoveredID: hoveredID,
                editingTextID: nil
            )
            activeOverlay?.makeKeyAndOrderFront(nil)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let origin = newTextOrigin else { return }
        let annotation = Annotation(
            kind: .text(TextShape(
                origin: origin,
                text: trimmed,
                fontName: defaults.textFontName,
                fontSize: defaults.textFontSize
            )),
            color: defaults.textColor,
            lineWidth: defaults.lineWidth
        )
        document?.add(annotation)
        refreshAfterDocumentChange()
        showToolbar()
        updateHUD()
    }

    private func commitEditedText(_ text: String, id: UUID) {
        defer {
            editingTextID = nil
            textEditor?.end()
            activeOverlay?.updateSelectionState(
                selectedID: document?.selectedID,
                hoveredID: hoveredID,
                editingTextID: nil
            )
            activeOverlay?.makeKeyAndOrderFront(nil)
        }
        guard let document else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            document.setSelected(id)
            document.removeSelected()
        } else {
            document.setSelected(id)
            document.beginChange()
            document.updateText(trimmed)
        }
        refreshAfterDocumentChange()
        showToolbar()
        updateHUD()
    }

    private func cancelTextEditing() {
        editingTextID = nil
        textEditor?.end()
        activeOverlay?.reloadAnnotations()
        activeOverlay?.updateSelectionState(
            selectedID: document?.selectedID,
            hoveredID: hoveredID,
            editingTextID: nil
        )
        activeOverlay?.makeKeyAndOrderFront(nil)
        refreshToolbar()
    }

    // MARK: - Hover, cursor, brush

    private func updateHover(at point: CGPoint) {
        guard state == .editing, let document else {
            hoveredID = nil
            updateCursor(at: point)
            return
        }
        let annotationLocal = annotationPoint(fromScreenLocal: point)
        if tool == .pointer {
            hoveredID = document.hitAnnotation(at: annotationLocal)?.id
        } else {
            hoveredID = nil
        }
        activeOverlay?.updateSelectionState(
            selectedID: document.selectedID,
            hoveredID: hoveredID,
            editingTextID: editingTextID
        )
        updateCursor(at: point)
    }

    private func updateCursor(at point: CGPoint) {
        guard let document, let selection else {
            activeOverlay?.desiredCursor = .crosshair
            return
        }
        let annotationLocal = annotationPoint(fromScreenLocal: point)
        var cursor: NSCursor = .crosshair
        switch tool {
        case .eraser:
            cursor = .crosshair
        case .rectangle, .line, .text:
            cursor = .crosshair
        case .pointer:
            if let selected = document.selectedAnnotation {
                if let rotation = selected.rotationHandlePoint(),
                   hypot(annotationLocal.x - rotation.x, annotationLocal.y - rotation.y) <= 12 {
                    cursor = .pointingHand
                } else if let handle = nearestHandle(of: selected, to: annotationLocal) {
                    cursor = cursorFor(handle: handle.index, selection: false)
                } else if hypot(annotationLocal.x - selected.deleteHandlePoint().x, annotationLocal.y - selected.deleteHandlePoint().y) <= 9 {
                    cursor = .pointingHand
                } else if selected.hitTest(annotationLocal) {
                    cursor = .openHand
                } else if selection.contains(point) {
                    cursor = .arrow
                }
            } else if let handle = selection.handle(at: point) {
                cursor = cursorFor(handle: handle, selection: true)
            } else if document.hitAnnotation(at: annotationLocal) != nil {
                cursor = .pointingHand
            } else if selection.contains(point) {
                cursor = .openHand
            } else {
                cursor = .arrow
            }
        }
        activeOverlay?.desiredCursor = cursor
    }

    private func cursorFor(handle: SelectionHandle, selection: Bool) -> NSCursor {
        switch handle {
        case .topLeft, .bottomRight:
            return .crosshair
        case .topRight, .bottomLeft:
            return .crosshair
        case .top, .bottom:
            return .resizeUpDown
        case .left, .right:
            return .resizeLeftRight
        }
    }

    private func cursorFor(handle: Int, selection: Bool) -> NSCursor {
        switch handle {
        case 0, 2:
            return .crosshair
        case 1, 3:
            return .crosshair
        default:
            return .crosshair
        }
    }

    private func nearestHandle(of annotation: Annotation, to point: CGPoint) -> (index: Int, point: CGPoint)? {
        for (index, handle) in annotation.handlesForEditing().enumerated() {
            if hypot(point.x - handle.x, point.y - handle.y) <= 12 {
                return (index, handle)
            }
        }
        return nil
    }

    private func updateBrushCursor(at point: CGPoint) {
        guard tool == .eraser, state == .editing, let overlay = activeOverlay else {
            activeOverlay?.showBrushCursor(at: nil, size: defaults.eraserSize, shape: defaults.eraserShape)
            return
        }
        overlay.showBrushCursor(at: point, size: defaults.eraserSize, shape: defaults.eraserShape)
    }

    // MARK: - Toolbar

    private func refreshActiveOverlay() {
        guard let activeOverlay else { return }
        activeOverlay.overlayView.setActive(true)
        activeOverlay.overlayView.setSession(document: document, selection: selection, tool: tool)
        activeOverlay.overlayView.updateSelectionState(
            selectedID: document?.selectedID,
            hoveredID: hoveredID,
            editingTextID: editingTextID
        )
    }

    private func createChromeIfNeeded() {
        if hud == nil { hud = CaptureHUD() }
        if toolbar == nil {
            let toolbar = CaptureToolbar()
            toolbar.onToolSelected = { [weak self] tool in self?.selectTool(tool) }
            toolbar.onUndo = { [weak self] in self?.undo() }
            toolbar.onRedo = { [weak self] in self?.redo() }
            toolbar.onCopy = { [weak self] in self?.copySelectionToPasteboard() }
            toolbar.onCancel = { [weak self] in self?.cancelSession() }
            toolbar.onPin = { [weak self] in self?.pinSelection() }
            toolbar.onSave = { [weak self] in self?.saveSelection() }
            toolbar.onColorChanged = { [weak self] color in self?.applyColor(color) }
            toolbar.onWidthChanged = { [weak self] width in self?.applyWidth(width) }
            toolbar.onFilledChanged = { [weak self] filled in self?.applyFilled(filled) }
            toolbar.onLinePatternChanged = { [weak self] pattern in self?.applyLinePattern(pattern) }
            toolbar.onArrowChanged = { [weak self] isStart, style in self?.applyArrow(isStart: isStart, style: style) }
            toolbar.onFontChanged = { [weak self] name in self?.applyFont(name) }
            toolbar.onFontSizeChanged = { [weak self] size in self?.applyFontSize(size) }
            toolbar.onEraserSizeChanged = { [weak self] size in self?.applyEraserSize(size) }
            toolbar.onEraserShapeChanged = { [weak self] shape in self?.applyEraserShape(shape) }
            self.toolbar = toolbar
        }
        if textEditor == nil { textEditor = TextEditorPanel() }
        NSColorPanel.shared.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        hud?.hide()
        toolbar?.hideToolbar()
    }

    private func showToolbar() {
        guard state == .editing, let selection, let screen = activeScreen, let document else {
            toolbar?.hideToolbar()
            return
        }
        toolbar?.refresh(document: document, tool: tool, defaults: defaults)
        toolbar?.position(below: selection, on: screen, toolbarHeight: toolbar?.frame.height ?? 0)
        toolbar?.orderFrontRegardless()
    }

    private func refreshToolbar() {
        guard state == .editing, let selection, let screen = activeScreen, let document else { return }
        toolbar?.refresh(document: document, tool: tool, defaults: defaults)
        toolbar?.position(below: selection, on: screen, toolbarHeight: toolbar?.frame.height ?? 0)
        toolbar?.orderFrontRegardless()
    }

    private func selectTool(_ newTool: CaptureTool) {
        if textEditor?.isVisible == true { textEditor?.commitNow() }
        tool = newTool
        document?.setSelected(nil)
        hoveredID = nil
        activeOverlay?.updateTool(tool)
        activeOverlay?.updateSelectionState(selectedID: nil, hoveredID: nil, editingTextID: editingTextID)
        refreshToolbar()
        updateCursor(at: mouseScreenLocal)
        updateBrushCursor(at: mouseScreenLocal)
    }

    private func applyColor(_ color: RGBAColor) {
        // A color picked for an existing annotation is also the latest color
        // for everything drawn afterwards, regardless of the tool.
        defaults.rectangleColor = color
        defaults.lineColor = color
        defaults.textColor = color
        if let document, document.selectedAnnotation != nil {
            document.updateSelected(color: color)
        }
        refreshToolbar()
    }

    private func applyWidth(_ width: CGFloat) {
        if let document, let selected = document.selectedAnnotation {
            switch selected.kind {
            case .rectangle, .line:
                document.updateSelected(lineWidth: width)
            case .text:
                return
            }
        } else {
            switch tool {
            case .rectangle: defaults.rectangleWidth = width
            case .line: defaults.lineWidth = width
            default: return
            }
        }
        refreshToolbar()
    }

    private func applyFilled(_ filled: Bool) {
        defaults.rectangleFilled = filled
        if let document, let selected = document.selectedAnnotation, case .rectangle = selected.kind {
            document.updateSelected(filled: filled)
        }
        refreshToolbar()
    }

    private func applyLinePattern(_ pattern: LinePattern) {
        if let document, let selected = document.selectedAnnotation, case .line = selected.kind {
            document.updateLineStyle(pattern: pattern)
        } else {
            defaults.linePattern = pattern
        }
        refreshToolbar()
    }

    private func applyArrow(isStart: Bool, style: ArrowStyle) {
        if let document, let selected = document.selectedAnnotation, case .line = selected.kind {
            if isStart {
                document.updateLineStyle(startArrow: style)
            } else {
                document.updateLineStyle(endArrow: style)
            }
        } else {
            if isStart { defaults.lineStartArrow = style } else { defaults.lineEndArrow = style }
        }
        refreshToolbar()
    }

    private func applyFont(_ name: String) {
        if let document, let selected = document.selectedAnnotation, case .text = selected.kind {
            document.updateSelected(fontName: name)
        } else {
            defaults.textFontName = name
        }
        refreshToolbar()
        activeOverlay?.reloadAnnotations()
    }

    private func applyFontSize(_ size: CGFloat) {
        if let document, let selected = document.selectedAnnotation, case .text = selected.kind {
            document.updateSelected(fontSize: size)
        } else {
            defaults.textFontSize = size
        }
        refreshToolbar()
        activeOverlay?.reloadAnnotations()
    }

    private func applyEraserSize(_ size: CGFloat) {
        defaults.eraserSize = max(4, min(120, size))
        refreshToolbar()
        updateBrushCursor(at: mouseScreenLocal)
    }

    private func applyEraserShape(_ shape: EraserShape) {
        defaults.eraserShape = shape
        refreshToolbar()
        updateBrushCursor(at: mouseScreenLocal)
    }

    private func refreshAfterDocumentChange() {
        guard state == .editing else { return }
        activeOverlay?.reloadAnnotations()
        activeOverlay?.updateSelectionState(
            selectedID: document?.selectedID,
            hoveredID: hoveredID,
            editingTextID: editingTextID
        )
        refreshToolbar()
        updateHUD()
    }

    // MARK: - Keyboard / wheel

    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.keyCode

        if key == 53 {
            cancelSession()
            return true
        }

        if flags.contains(.command) {
            switch key {
            case 8: // C
                copySelectionToPasteboard()
                return true
            case 6: // Z
                if flags.contains(.shift) { redo() } else { undo() }
                return true
            case 1: // S
                saveSelection()
                return true
            default:
                break
            }
        }

        if key == 51 || key == 117 {
            if state == .editing, let document, document.selectedAnnotation != nil {
                document.removeSelected()
                refreshAfterDocumentChange()
                return true
            }
        }

        if let chars = event.charactersIgnoringModifiers?.lowercased(),
           !flags.contains(.command),
           !flags.contains(.control),
           !flags.contains(.option) {
            switch chars {
            case "v": selectTool(.pointer); return true
            case "r": selectTool(.rectangle); return true
            case "l": selectTool(.line); return true
            case "t": selectTool(.text); return true
            case "e": selectTool(.eraser); return true
            default: break
            }
        }
        return false
    }

    private func handleScroll(_ event: NSEvent) {
        let delta = event.scrollingDeltaY
        guard abs(delta) > 0.01 else { return }
        let step: CGFloat = delta > 0 ? 1 : -1
        if let document, let selected = document.selectedAnnotation {
            switch selected.kind {
            case .rectangle:
                document.updateSelected(lineWidth: max(1, min(30, selected.lineWidth + step)))
            case .line:
                document.updateSelected(lineWidth: max(1, min(30, selected.lineWidth + step)))
            case .text(let shape):
                document.updateSelected(fontSize: max(8, min(120, shape.fontSize + step)))
            }
            refreshToolbar()
            activeOverlay?.reloadAnnotations()
            return
        }
        switch tool {
        case .rectangle:
            defaults.rectangleWidth = max(1, min(30, defaults.rectangleWidth + step))
        case .line:
            defaults.lineWidth = max(1, min(30, defaults.lineWidth + step))
        case .text:
            defaults.textFontSize = max(8, min(120, defaults.textFontSize + step))
        case .eraser:
            defaults.eraserSize = max(4, min(120, defaults.eraserSize + step))
            updateBrushCursor(at: mouseScreenLocal)
        case .pointer:
            return
        }
        refreshToolbar()
    }

    private func undo() {
        guard let document else { return }
        document.undo()
        refreshAfterDocumentChange()
    }

    private func redo() {
        guard let document else { return }
        document.redo()
        refreshAfterDocumentChange()
    }

    private func updateHUD() {
        guard state == .editing || state == .selecting,
              let selection, let screen = activeScreen, let captured else {
            hud?.hide()
            return
        }
        hud?.update(screen: screen, selection: selection, captured: captured)
    }

    // MARK: - Save / pin

    private func hideChromeForModal() {
        if textEditor?.isVisible == true { textEditor?.commitNow() }
        ColorPalettePanel.shared.dismissAll()
        ScreenshotToast.shared.hide()
        for overlay in overlays { overlay.orderOut(nil) }
        hud?.hide()
        toolbar?.hideToolbar()
        NSColorPanel.shared.orderOut(nil)
    }

    private func showChromeAfterModal() {
        guard state == .editing || state == .selecting else { return }
        for overlay in overlays { overlay.orderFrontRegardless() }
        activeOverlay?.makeKeyAndOrderFront(nil)
        showToolbar()
        updateHUD()
    }

    private func copySelectionToPasteboard() {
        guard state == .editing, let document, let captured else { return }
        document.rebuildFrozen()
        guard let image = ScreenshotComposer.composeSelection(
            document: document,
            capturedScreen: captured
        ) else {
            return
        }
        guard ScreenshotPasteboard.copy(image: image) else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        showCopyToast()
        statusBar?.showTransientTooltip("已复制到剪贴板")
    }

    private func showCopyToast() {
        guard let selection, let screen = activeScreen else { return }
        let rect = CGRect(
            x: screen.frame.minX + selection.rect.minX,
            y: screen.frame.maxY - selection.rect.maxY,
            width: selection.rect.width,
            height: selection.rect.height
        )
        ScreenshotToast.shared.show("已复制到剪贴板", near: rect, on: screen)
    }

    private func saveSelection() {
        guard state == .editing, let document, let captured else { return }
        let pin = editingPin
        state = .saving
        hideChromeForModal()

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = (pin == nil ? "截屏 " : "贴图 ") + "\(Self.timestamp()).png"
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else {
            state = .editing
            showChromeAfterModal()
            return
        }

        document.rebuildFrozen()
        guard let image = ScreenshotComposer.composeSelection(
            document: document,
            capturedScreen: captured
        ) else {
            state = .editing
            showChromeAfterModal()
            showError("保存失败", detail: "无法生成截图图像。")
            return
        }
        do {
            try Self.write(image: image, to: url)
            if let pin {
                let session = PinEditingSession(capturedScreen: captured, document: document)
                pin.update(image: image, pointSize: document.selection.rect.size, editingSession: session)
            }
            cleanup(restoreApp: pin == nil)
            if let pin {
                presentPin(pin)
            }
            statusBar?.showTransientTooltip(pin == nil ? "截图已保存" : "贴图已保存并更新")
        } catch {
            state = .editing
            showChromeAfterModal()
            showError("保存失败", detail: error.localizedDescription)
        }
    }

    private func pinSelection() {
        guard state == .editing, let document, let captured, let selection, let screen = activeScreen else { return }

        if let pin = editingPin {
            finishPinEditing(pin: pin, apply: true)
            return
        }

        document.rebuildFrozen()
        hideChromeForModal()
        guard let image = ScreenshotComposer.composeSelection(
            document: document,
            capturedScreen: captured
        ) else {
            cleanup(restoreApp: true)
            showError("无法贴图", detail: "无法生成贴图图像。")
            return
        }

        let session = PinEditingSession(capturedScreen: captured, document: document)
        let pin = PinnedImageWindow(
            image: image,
            pointSize: selection.rect.size,
            screenFrame: screen.frame,
            editingSession: session
        )
        let origin = CGPoint(
            x: screen.frame.minX + selection.rect.minX,
            y: screen.frame.maxY - selection.rect.minY - selection.rect.height
        )
        pin.setFrameOrigin(origin)
        pin.onClose = { [weak self, weak pin] in
            guard let self, let pin else { return }
            self.pins.removeAll { $0 === pin }
        }
        pin.onShowToolbar = { [weak self, weak pin] in
            guard let self, let pin else { return }
            self.beginEditing(pin: pin)
        }
        pins.append(pin)

        // Ownership of the capture and annotation document moves to the pin
        // session. Detach them first so cleanup does not release the data the
        // pin needs for "显示工具条".
        document.onChange = nil
        self.document = nil
        self.captured = nil
        cleanup(restoreApp: false)
        presentPin(pin)
        statusBar?.showTransientTooltip("贴图已固定，⌘C 复制")
    }

    private func beginEditing(pin: PinnedImageWindow) {
        guard state == .idle else {
            NSSound.beep()
            return
        }
        if let canStart, !canStart() {
            NSSound.beep()
            return
        }
        guard let session = pin.editingSession else {
            showError("无法继续编辑贴图", detail: "这张贴图没有保留原始截图数据。")
            return
        }
        guard let screen = NSScreen.screens.first(where: { $0.frame.equalTo(session.screenFrame) }) else {
            showError("无法继续编辑贴图", detail: "原截图所在的显示器已不可用，请重新截屏。")
            return
        }
        guard session.capturedScreen.screenPointSize == screen.frame.size else {
            showError("无法继续编辑贴图", detail: "原截图所在显示器的分辨率已变化，请重新截屏。")
            return
        }

        let workingDocument = session.document.copyForEditing()
        previousApp = NSWorkspace.shared.frontmostApplication
        editingPin = pin
        pin.orderOut(nil)

        captured = session.capturedScreen
        document = workingDocument
        workingDocument.onChange = { [weak self] in self?.refreshAfterDocumentChange() }
        selection = workingDocument.selection
        mouseScreenLocal = CGPoint(
            x: workingDocument.selection.rect.midX,
            y: workingDocument.selection.rect.midY
        )
        tool = .pointer
        dragMode = nil
        previewAnnotation = nil
        eraseStroke = nil
        editingTextID = nil
        hoveredID = nil
        sessionScreenSignature = Self.screenSignature()
        state = .editing

        NSApp.activate(ignoringOtherApps: true)
        installEventMonitor()
        createChromeIfNeeded()
        ScreenshotToast.shared.hide()
        createOverlays()
        activateScreen(screen)
        refreshActiveOverlay()
        showToolbar()
        updateHUD()
        onActiveChanged?(true)
    }

    private func finishPinEditing(pin: PinnedImageWindow, apply: Bool) {
        var didApply = !apply
        if apply, let document, let captured {
            document.rebuildFrozen()
            if let image = ScreenshotComposer.composeSelection(
                document: document,
                capturedScreen: captured
            ) {
                let session = PinEditingSession(capturedScreen: captured, document: document)
                pin.update(
                    image: image,
                    pointSize: document.selection.rect.size,
                    editingSession: session
                )
                didApply = true
            }
        }
        cleanup(restoreApp: !apply)
        if apply {
            presentPin(pin)
        }
        if apply {
            statusBar?.showTransientTooltip(didApply ? "贴图已更新，⌘C 复制" : "无法生成贴图图像")
        } else {
            statusBar?.showTransientTooltip("已取消编辑")
        }
    }

    /// Pins are excluded from ScreenCaptureKit, so draw them into the captured
    /// base image ourselves. The new overlay stays above the live pins and the
    /// user can select a pinned image to screenshot it again.
    private func compositePins(into captured: CapturedScreen, on screen: NSScreen) -> CapturedScreen {
        let orderedPins = NSApp.orderedWindows.compactMap { $0 as? PinnedImageWindow }
        guard !orderedPins.isEmpty else { return captured }

        var overlays: [ScreenOverlayImage] = []
        for pin in orderedPins.reversed() where pin.isVisible {
            guard let image = pin.image else { continue }
            let frame = pin.frame
            guard frame.intersects(screen.frame) else { continue }
            let localFrame = CGRect(
                x: frame.minX - screen.frame.minX,
                y: screen.frame.maxY - frame.maxY,
                width: frame.width,
                height: frame.height
            )
            overlays.append(ScreenOverlayImage(frame: localFrame, image: image))
        }
        guard !overlays.isEmpty else { return captured }
        return ScreenCompositor.compositing(captured, overlays: overlays) ?? captured
    }

    private func presentPin(_ pin: PinnedImageWindow) {
        pin.orderFrontRegardless()
        pin.focusForKeyboard()
    }

    private func showError(_ title: String, detail: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    // MARK: - Helpers

    private func annotationPoint(fromScreenLocal point: CGPoint) -> CGPoint {
        guard let selection else { return point }
        return AnnotationSpace.local(fromScreen: point, selection: selection.rect)
    }

    private func screenLocalPoint(of event: NSEvent) -> CGPoint? {
        guard let screen = activeScreen,
              let overlay = activeOverlay,
              event.window === overlay else { return nil }
        return PointerGeometry.screenLocalPoint(
            eventLocationInWindow: event.locationInWindow,
            windowFrame: overlay.frame,
            screenFrame: screen.frame
        )
    }

    private func localPoint(for screen: NSScreen, global: CGPoint) -> CGPoint {
        CGPoint(x: global.x - screen.frame.minX, y: screen.frame.maxY - global.y)
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    private func sameScreen(_ a: NSScreen?, _ b: NSScreen?) -> Bool {
        guard let a, let b else { return false }
        return a.frame.equalTo(b.frame)
    }

    private func screensDiffer(_ a: NSScreen, _ b: NSScreen?) -> Bool {
        !sameScreen(a, b)
    }

    @objc private func screenParametersChanged(_ notification: Notification) {
        guard state != .idle else { return }
        guard Self.screenSignature() != sessionScreenSignature else { return }
        cleanup(restoreApp: true)
        statusBar?.showTransientTooltip("屏幕配置已变化，请重新截屏")
    }

    private static func screenSignature() -> String {
        NSScreen.screens
            .map { "\(Int($0.frame.minX)),\(Int($0.frame.minY)),\(Int($0.frame.width)),\(Int($0.frame.height)),\($0.backingScaleFactor)" }
            .sorted()
            .joined(separator: "|")
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: Date())
    }

    private static func write(image: CGImage, to url: URL) throws {
        let type: UTType
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": type = .jpeg
        default: type = .png
        }
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            type.identifier as CFString,
            1,
            nil
        ) else {
            throw NSError(domain: "SuperFinder.Screenshot", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "无法创建图片文件。"
            ])
        }
        var properties: CFDictionary?
        if type == .jpeg {
            properties = [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        }
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "SuperFinder.Screenshot", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "写入图片失败。"
            ])
        }
    }
}

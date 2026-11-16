import Foundation
import AppKit
import CoreGraphics

_ = NSApplication.shared

var failureCount = 0
var checkCount = 0

func check(_ condition: @autoclosure () -> Bool, _ message: String, file: String = #file, line: Int = #line) {
    checkCount += 1
    if !condition() {
        failureCount += 1
        print("FAIL [\(file.split(separator: "/").last ?? "?"):\(line)] \(message)")
    }
}

func checkEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String, file: String = #file, line: Int = #line) {
    checkCount += 1
    if lhs != rhs {
        failureCount += 1
        print("FAIL [\(file.split(separator: "/").last ?? "?"):\(line)] \(message): \(lhs) != \(rhs)")
    }
}

let fileManager = FileManager.default
let root = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
    .appendingPathComponent("build/.test-tmp/test-\(UUID().uuidString)", isDirectory: true)

func makeDirectory(_ url: URL) {
    try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
}

func writeFile(_ url: URL, contents: String) {
    makeDirectory(url.deletingLastPathComponent())
    try? contents.data(using: .utf8)?.write(to: url)
}

func readFile(_ url: URL) -> String? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return String(data: data, encoding: .utf8)
}

makeDirectory(root)

// MARK: - Path formatting

do {
    let a = URL(fileURLWithPath: "/Users/example/Desktop/报表 1.pdf")
    let b = URL(fileURLWithPath: "/Users/example/项目/源码")
    checkEqual(
        PathFormatter.absolutePaths(for: [a, b]),
        "/Users/example/Desktop/报表 1.pdf\n/Users/example/项目/源码",
        "multi path formatting"
    )
    checkEqual(PathFormatter.absolutePaths(for: [a]), a.path, "single path formatting")
    checkEqual(PathFormatter.absolutePaths(for: []), "", "empty path formatting")
}

// MARK: - Command codec

do {
    let command = MoveCommand(
        action: .moveHere,
        sources: ["/tmp/a.txt", "/tmp/b c.txt"],
        destination: "/tmp/target"
    )
    let data = try! command.encodedData()
    let decoded = try! MoveCommand.decode(data)
    checkEqual(decoded.schema, 1, "command schema")
    checkEqual(decoded.action, .moveHere, "command action")
    checkEqual(decoded.sources, command.sources, "command sources")
    checkEqual(decoded.destination, command.destination, "command destination")
    check(decoded.fileName.hasSuffix(".json"), "command file name suffix")
    check(decoded.fileName.contains(command.id), "command file name id")
    check(MoveCommand.timestamp(fromFileName: decoded.fileName) != nil, "command timestamp parse")
    check(decoded.isExpired == false, "fresh command not expired")

    let terminalCommand = MoveCommand(
        action: .openTerminal,
        sources: ["/tmp"],
        destination: nil
    )
    let terminalDecoded = try! MoveCommand.decode(try! terminalCommand.encodedData())
    checkEqual(terminalDecoded.action, .openTerminal, "terminal command action")
    checkEqual(terminalDecoded.sources, ["/tmp"], "terminal command source")
    checkEqual(terminalDecoded.destination, nil, "terminal command destination")
}

// MARK: - Cut buffer

do {
    let bufferURL = root.appendingPathComponent("cut/cut-buffer.json")
    let store = CutBufferStore(fileURL: bufferURL)

    checkEqual(store.load(), [], "empty cut buffer")
    store.save(paths: ["/tmp/a", "/tmp/b", "/tmp/a"])
    checkEqual(store.load(), ["/tmp/a", "/tmp/b"], "cut buffer dedupe")
    checkEqual(store.count, 2, "cut buffer count")

    try? "not json".data(using: .utf8)?.write(to: bufferURL)
    checkEqual(store.load(), [], "corrupt cut buffer")

    store.save(paths: [])
    checkEqual(store.load(), [], "cleared cut buffer")
}

// MARK: - Menu model

do {
    let items = MenuModel.itemsMenu(selectedCount: 2, cutCount: 0)
    checkEqual(items.count, 3, "items menu without cut buffer")
    check(items.contains { $0.action == .cutSelection && $0.enabled }, "cut item")
    check(items.contains { $0.action == .copySelectedPaths && $0.enabled }, "copy paths item")
    check(!items.contains { $0.action == .moveCutItemsHere }, "no move-here item without cut buffer")
    check(!items.contains { $0.action == .openTerminalForSelection }, "no terminal item with multi selection")

    let itemsSingle = MenuModel.itemsMenu(selectedCount: 1, cutCount: 0)
    checkEqual(itemsSingle.count, 4, "items menu single selection")
    check(itemsSingle.contains { $0.action == .openTerminalForSelection && $0.enabled }, "terminal item for single selection")

    let itemsWithCut = MenuModel.itemsMenu(selectedCount: 1, cutCount: 3)
    checkEqual(itemsWithCut.count, 5, "items menu with cut buffer and single selection")
    check(itemsWithCut.contains { $0.action == .moveCutItemsHere && $0.title.contains("3") }, "move to selected folder item")
    check(itemsWithCut.contains { $0.action == .openTerminalForSelection }, "terminal item with cut buffer")

    let itemsMulti = MenuModel.itemsMenu(selectedCount: 2, cutCount: 3)
    check(!itemsMulti.contains { $0.action == .moveCutItemsHere }, "no move-to-selected-folder with multi selection")
    check(!itemsMulti.contains { $0.action == .openTerminalForSelection }, "no terminal item with multi selection")

    let containerEmpty = MenuModel.containerMenu(cutCount: 0, hasTargetedURL: true)
    checkEqual(containerEmpty.count, 4, "container menu empty cut buffer")
    check(containerEmpty.first?.enabled == false, "move item disabled when buffer empty")
    check(containerEmpty.contains { $0.action == .copyTargetedPath && $0.enabled }, "copy current directory item")
    check(containerEmpty.contains { $0.action == .openTerminalHere && $0.enabled }, "open terminal here item")
    check(containerEmpty.last?.action == .openSettings, "settings item in container menu")

    let containerWithCut = MenuModel.containerMenu(cutCount: 2, hasTargetedURL: true)
    checkEqual(containerWithCut.count, 5, "container menu with cut buffer")
    check(containerWithCut[0].title.contains("2") && containerWithCut[0].enabled, "move here enabled")
    check(containerWithCut[1].action == .clearCutBuffer, "clear cut item")
    check(containerWithCut.contains { $0.action == .openTerminalHere && $0.enabled }, "terminal item with cut buffer")
    check(containerWithCut.last?.action == .openSettings, "settings item with cut buffer")

    let containerNoTarget = MenuModel.containerMenu(cutCount: 2, hasTargetedURL: false)
    check(containerNoTarget[0].enabled == false, "move here disabled without target")
    check(containerNoTarget.contains { $0.action == .copyTargetedPath && !$0.enabled }, "copy current dir disabled without target")
    check(containerNoTarget.contains { $0.action == .openTerminalHere && !$0.enabled }, "terminal item disabled without target")
    check(containerNoTarget.contains { $0.action == .openSettings && $0.enabled }, "settings enabled without target")
}

// MARK: - Move engine

func createBaseline() -> (root: URL, source: URL, destination: URL) {
    let base = root.appendingPathComponent("case-\(UUID().uuidString)", isDirectory: true)
    let source = base.appendingPathComponent("source", isDirectory: true)
    let destination = base.appendingPathComponent("destination", isDirectory: true)
    makeDirectory(source)
    makeDirectory(destination)
    return (base, source, destination)
}

do {
    let (_, source, destination) = createBaseline()
    let file = source.appendingPathComponent("a.txt")
    writeFile(file, contents: "hello")

    let plan = try! MoveEngine.makePlan(sources: [file], destinationDirectory: destination)
    checkEqual(plan.validItems.count, 1, "plan valid item count")
    checkEqual(plan.itemsNeedingConflictResolution.count, 0, "plan no conflicts")

    let outcome = MoveEngine.execute(plan: plan, resolution: .keepBoth)
    checkEqual(outcome.movedCount, 1, "move file count")
    check(!fileManager.fileExists(atPath: file.path), "file moved away")
    checkEqual(readFile(destination.appendingPathComponent("a.txt")), "hello", "moved file contents")
}

do {
    let (_, source, destination) = createBaseline()
    let folder = source.appendingPathComponent("folder", isDirectory: true)
    makeDirectory(folder)
    writeFile(folder.appendingPathComponent("nested/b.txt"), contents: "nested")

    let plan = try! MoveEngine.makePlan(sources: [folder], destinationDirectory: destination)
    let outcome = MoveEngine.execute(plan: plan, resolution: .keepBoth)
    checkEqual(outcome.movedCount, 1, "move folder count")
    checkEqual(
        readFile(destination.appendingPathComponent("folder/nested/b.txt")),
        "nested",
        "moved folder contents"
    )
    check(!fileManager.fileExists(atPath: folder.path), "folder moved away")
}

do {
    let (_, source, destination) = createBaseline()
    let file = source.appendingPathComponent("a.txt")
    writeFile(file, contents: "new")
    writeFile(destination.appendingPathComponent("a.txt"), contents: "old")

    let plan = try! MoveEngine.makePlan(sources: [file], destinationDirectory: destination)
    checkEqual(plan.itemsNeedingConflictResolution.count, 1, "conflict detected")

    let outcome = MoveEngine.execute(plan: plan, resolution: .keepBoth)
    checkEqual(outcome.movedCount, 1, "keep both moved")
    checkEqual(readFile(destination.appendingPathComponent("a.txt")), "old", "keep both original intact")
    checkEqual(readFile(destination.appendingPathComponent("a 2.txt")), "new", "keep both renamed destination")
}

do {
    let (_, source, destination) = createBaseline()
    let file = source.appendingPathComponent("a.txt")
    writeFile(file, contents: "new")
    writeFile(destination.appendingPathComponent("a.txt"), contents: "old")

    let plan = try! MoveEngine.makePlan(sources: [file], destinationDirectory: destination)
    var trashed: [URL] = []
    let outcome = MoveEngine.execute(plan: plan, resolution: .replace) { url in
        trashed.append(url)
        try fileManager.removeItem(at: url)
    }
    checkEqual(outcome.movedCount, 1, "replace moved")
    checkEqual(trashed.count, 1, "replace trashed existing item")
    checkEqual(readFile(destination.appendingPathComponent("a.txt")), "new", "replace destination content")
}

do {
    let (_, source, _) = createBaseline()
    let file = source.appendingPathComponent("a.txt")
    writeFile(file, contents: "hello")

    let plan = try! MoveEngine.makePlan(sources: [file], destinationDirectory: source)
    checkEqual(plan.skippedItems.count, 1, "same-parent skip")
    let outcome = MoveEngine.execute(plan: plan, resolution: .keepBoth)
    check(fileManager.fileExists(atPath: file.path), "same-parent file stays")
    checkEqual(outcome.skipped.count, 1, "same-parent outcome skipped")
}

do {
    let (_, source, _) = createBaseline()
    let folder = source.appendingPathComponent("folder", isDirectory: true)
    makeDirectory(folder)
    let subfolder = folder.appendingPathComponent("sub", isDirectory: true)
    makeDirectory(subfolder)

    let plan = try! MoveEngine.makePlan(sources: [folder], destinationDirectory: subfolder)
    checkEqual(plan.invalidItems.count, 1, "folder inside itself rejected")
    let outcome = MoveEngine.execute(plan: plan, resolution: .keepBoth)
    checkEqual(outcome.failureCount, 1, "folder inside itself failure")
    check(fileManager.fileExists(atPath: folder.path), "source folder untouched")
}

do {
    let (_, source, destination) = createBaseline()
    let missing = source.appendingPathComponent("missing.txt")
    let plan = try! MoveEngine.makePlan(sources: [missing], destinationDirectory: destination)
    checkEqual(plan.invalidItems.count, 1, "missing source invalid")
    let outcome = MoveEngine.execute(plan: plan, resolution: .keepBoth)
    checkEqual(outcome.failureCount, 1, "missing source failure")
}

do {
    let (_, source, destination) = createBaseline()
    let notDirectory = destination.appendingPathComponent("file.txt")
    writeFile(notDirectory, contents: "x")
    let file = source.appendingPathComponent("a.txt")
    writeFile(file, contents: "a")

    do {
        _ = try MoveEngine.makePlan(sources: [file], destinationDirectory: notDirectory)
        check(false, "destination file should throw")
    } catch {
        check(error is MovePlanError, "destination file error type")
    }
}

do {
    let (_, source, destination) = createBaseline()
    let file = source.appendingPathComponent("a.txt")
    writeFile(file, contents: "a")
    writeFile(destination.appendingPathComponent("a.txt"), contents: "x")
    let unique = MoveEngine.uniqueDestination(for: file, in: destination)
    checkEqual(unique.lastPathComponent, "a 2.txt", "unique file name")

    let folder = source.appendingPathComponent("folder.txt", isDirectory: true)
    makeDirectory(folder)
    makeDirectory(destination.appendingPathComponent("folder.txt"))
    let uniqueFolder = MoveEngine.uniqueDestination(for: folder, in: destination)
    checkEqual(uniqueFolder.lastPathComponent, "folder.txt 2", "unique directory name")
}

do {
    let (_, source, destination) = createBaseline()
    let file = source.appendingPathComponent("a.txt")
    writeFile(file, contents: "a")
    let missing = source.appendingPathComponent("missing.txt")

    let plan = try! MoveEngine.makePlan(sources: [file, missing], destinationDirectory: destination)
    let outcome = MoveEngine.execute(plan: plan, resolution: .keepBoth)
    checkEqual(outcome.movedCount, 1, "partial move success count")
    checkEqual(outcome.failureCount, 1, "partial move failure count")
}

do {
    let (_, source, destination) = createBaseline()
    let target = source.appendingPathComponent("target.txt")
    writeFile(target, contents: "target")
    let link = source.appendingPathComponent("link.txt")
    try? fileManager.createSymbolicLink(atPath: link.path, withDestinationPath: target.path)

    let plan = try! MoveEngine.makePlan(sources: [link], destinationDirectory: destination)
    let outcome = MoveEngine.execute(plan: plan, resolution: .keepBoth)
    checkEqual(outcome.movedCount, 1, "symlink moved")
    let movedLink = destination.appendingPathComponent("link.txt")
    check((try? fileManager.destinationOfSymbolicLink(atPath: movedLink.path)) != nil, "moved item is still a symlink")
    check(readFile(target) == "target", "symlink target untouched")
}


// MARK: - Screenshot geometry and memory

func makeTestImage(width: Int, height: Int) -> CGImage {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.setFillColor(NSColor.red.cgColor)
    ctx.fill(CGRect(x: 0, y: height / 2, width: width, height: height - height / 2))
    ctx.setFillColor(NSColor.blue.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
    return ctx.makeImage()!
}

func sampledColor(_ image: CGImage, x: Int, y: Int) -> (UInt8, UInt8, UInt8)? {
    guard let captured = try? CapturedScreen(
        screenFrame: CGRect(x: 0, y: 0, width: image.width, height: image.height),
        image: image,
        workingScale: 1
    ) else { return nil }
    guard let color = captured.pixelColor(atScreenPoint: CGPoint(x: x, y: y)) else { return nil }
    return (color.r, color.g, color.b)
}

do {
    checkEqual(MemoryBudget.hardLimit, 20 * 1024 * 1024, "20 MB hard working-set limit")
    check(MemoryBudget.baseImageLimit <= 3 * 1024 * 1024, "base screenshot bitmap capped")
    check(MemoryBudget.frozenLayerLimit <= 2 * 1024 * 1024, "frozen annotation bitmap capped")
    let scale = MemoryBudget.workingScale(forPointSize: CGSize(width: 1920, height: 1080))
    let pixels = MemoryBudget.pixelSize(forPointSize: CGSize(width: 1920, height: 1080), scale: scale)
    check(MemoryBudget.imageBytes(width: pixels.width, height: pixels.height) <= MemoryBudget.baseImageLimit, "1920x1080 working bitmap under 7MB")
    let retinaScale = MemoryBudget.workingScale(forPointSize: CGSize(width: 1280, height: 832))
    check(retinaScale > 0 && retinaScale <= 1, "Retina logical screen scale is capped at 1x")
}

do {
    let source = makeTestImage(width: 100, height: 80)
    let captured = try! CapturedScreen(
        screenFrame: CGRect(x: 0, y: 0, width: 100, height: 80),
        image: source,
        workingScale: 1
    )
    let top = captured.pixelColor(atScreenPoint: CGPoint(x: 10, y: 10))
    let bottom = captured.pixelColor(atScreenPoint: CGPoint(x: 10, y: 70))
    check(top?.r ?? 0 > 200 && top?.b ?? 255 < 50, "captured top-left is red")
    check(bottom?.b ?? 0 > 200 && bottom?.r ?? 255 < 50, "captured bottom is blue")

    let crop = captured.croppedImage(forScreenRect: CGRect(x: 0, y: 0, width: 50, height: 20))
    check(crop != nil, "cropped image exists")
    if let crop, let color = sampledColor(crop, x: 10, y: 10) {
        check(color.0 > 200 && color.2 < 50, "cropped top-left stays red")
    } else {
        check(false, "cropped image sampling")
    }
}

do {
    var selection = CaptureSelection(anchor: CGPoint(x: 100, y: 100), current: CGPoint(x: 50, y: 80))
    checkEqual(selection.rect, CGRect(x: 50, y: 80, width: 50, height: 20), "selection normalized from any direction")
    check(selection.handle(at: CGPoint(x: 50, y: 80)) == .topLeft, "top-left handle hit")
    selection.resize(handle: .bottomRight, by: CGPoint(x: 10, y: 5), within: CGRect(x: 0, y: 0, width: 300, height: 300))
    checkEqual(selection.rect, CGRect(x: 50, y: 80, width: 60, height: 25), "selection resize")
    selection.move(by: CGPoint(x: -100, y: -100), within: CGRect(x: 0, y: 0, width: 300, height: 300))
    checkEqual(selection.rect.origin, CGPoint(x: 0, y: 0), "selection move clamps to screen")
}

do {
    var rect = RectangleShape(center: CGPoint(x: 100, y: 100), size: CGSize(width: 80, height: 40), angle: .pi / 4, mosaic: 0)
    let annotation = Annotation(kind: .rectangle(rect), color: .annotationBlue, lineWidth: 3)
    check(annotation.hitTest(rect.center), "rotated rectangle center hit")
    check(!annotation.hitTest(CGPoint(x: 300, y: 300)), "rotated rectangle far miss")
    let line = Annotation(kind: .line(LineShape(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 100, y: 10), pattern: .solid, startArrow: .none, endArrow: .none)))
    check(line.hitTest(CGPoint(x: 50, y: 12)), "line hit near stroke")
    check(!line.hitTest(CGPoint(x: 50, y: 60)), "line miss far away")
    rect.angle = 0
    _ = rect
}

do {
    let text = TextShape(origin: .zero, text: "第一行\nsecond line", fontName: "", fontSize: 20)
    let size = TextLayout.size(text: text.text, fontName: text.fontName, fontSize: text.fontSize)
    check(size.height > 30, "multiline text measures more than one line")
    check(size.width > 40, "text measures width")
}

// MARK: - Screenshot eraser and history

do {
    let source = makeTestImage(width: 200, height: 120)
    let captured = try! CapturedScreen(
        screenFrame: CGRect(x: 0, y: 0, width: 200, height: 120),
        image: source,
        workingScale: 1
    )
    let selection = CaptureSelection(rect: CGRect(x: 0, y: 0, width: 200, height: 120))
    let document = ScreenshotDocument(selection: selection, workingScale: 1, selectionOrigin: .zero, baseImage: captured.image)
    document.add(Annotation(kind: .line(LineShape(
        start: CGPoint(x: 20, y: 60),
        end: CGPoint(x: 180, y: 60),
        pattern: .solid,
        startArrow: .none,
        endArrow: .none
    )), color: .annotationBlue, lineWidth: 4))
    checkEqual(document.annotations.count, 1, "line added")
    check(document.canUndo, "add created undo entry")

    document.commitEraseStroke(EraseStroke(
        points: [CGPoint(x: 100, y: 60), CGPoint(x: 101, y: 60)],
        brushSize: 16,
        shape: .circle
    ))
    checkEqual(document.annotations.count, 0, "erased line leaves editable list")
    checkEqual(document.frozenAnnotations.count, 1, "erased line is frozen")
    check(document.frozenRaster.image != nil, "frozen raster rendered")
    check(document.frozenRaster.byteCount <= MemoryBudget.frozenLayerLimit, "frozen raster under limit")

    document.undo()
    checkEqual(document.annotations.count, 1, "undo restores editable line")
    checkEqual(document.frozenAnnotations.count, 0, "undo clears frozen line")
    check(document.frozenRaster.image == nil, "undo releases frozen raster")

    document.redo()
    checkEqual(document.annotations.count, 0, "redo freezes line again")
    checkEqual(document.frozenAnnotations.count, 1, "redo restores frozen line")
}

// MARK: - Screenshot composition

do {
    let source = makeTestImage(width: 200, height: 120)
    let captured = try! CapturedScreen(
        screenFrame: CGRect(x: 0, y: 0, width: 200, height: 120),
        image: source,
        workingScale: 1
    )
    let selection = CaptureSelection(rect: CGRect(x: 0, y: 0, width: 100, height: 50))
    let document = ScreenshotDocument(selection: selection, workingScale: 1, selectionOrigin: .zero, baseImage: captured.image)
    let composed = ScreenshotComposer.composeSelection(document: document, capturedScreen: captured)
    check(composed != nil, "composition image exists")
    if let composed {
        checkEqual(composed.width, 100, "composition crop width")
        checkEqual(composed.height, 50, "composition crop height")
        if let color = sampledColor(composed, x: 10, y: 10) {
            check(color.0 > 200 && color.2 < 50, "composition preserves top red crop orientation")
        } else {
            check(false, "composition color sampling")
        }
    }
}

// MARK: - Summary

try? fileManager.removeItem(at: root)

print("")
print("Tests: \(checkCount) checks, \(failureCount) failure(s)")
if failureCount > 0 {
    exit(1)
}
print("ALL TESTS PASSED")

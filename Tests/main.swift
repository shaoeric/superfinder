import Foundation

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

// MARK: - Summary

try? fileManager.removeItem(at: root)

print("")
print("Tests: \(checkCount) checks, \(failureCount) failure(s)")
if failureCount > 0 {
    exit(1)
}
print("ALL TESTS PASSED")

import AppKit
import Foundation
import os

final class MoveCoordinator {
    private let log = Logger(subsystem: AppConfig.logSubsystem, category: "move")
    private let workQueue = DispatchQueue(label: "com.shaobt.superfinder.move", qos: .userInitiated)

    weak var statusBar: StatusBarController?
    private(set) var isBusy = false
    var pendingTerminationReply = false

    // MARK: - Entry point

    func handle(command: MoveCommand, commandFile: URL) {
        guard !isBusy else { return }
        isBusy = true
        CommandStore.remove(commandFile)

        log.info("Handling command \(command.id, privacy: .public) action=\(command.action.rawValue, privacy: .public)")

        if command.action == .openTerminal {
            handleOpenTerminal(command)
            return
        }

        let destination: URL
        switch command.action {
        case .moveHere:
            guard let rawDestination = command.destination, !rawDestination.isEmpty else {
                finishWithoutMove(message: "移动命令缺少目标目录。")
                return
            }
            destination = URL(fileURLWithPath: rawDestination, isDirectory: true)
        case .moveToFolder:
            guard let chosen = chooseDestinationFolder() else {
                finishWithoutMove(message: nil)
                return
            }
            destination = chosen
        case .openTerminal:
            return
        }

        let sources = command.sources
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0) }

        guard !sources.isEmpty else {
            finishWithoutMove(message: "没有可移动的项目。")
            return
        }

        executeMove(sources: sources, destination: destination)
    }

    // MARK: - Open Terminal

    private func handleOpenTerminal(_ command: MoveCommand) {
        guard let rawPath = command.sources.first, !rawPath.isEmpty else {
            finishWithoutMove(message: "没有指定要打开的目录。")
            return
        }

        let selectedURL = URL(fileURLWithPath: rawPath).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: selectedURL.path, isDirectory: &isDirectory) else {
            finishWithoutMove(message: "目录不存在：\(selectedURL.path)")
            return
        }

        // If a file was selected, open its containing folder. For a folder,
        // open the folder itself.
        let directory = isDirectory.boolValue
            ? selectedURL
            : selectedURL.deletingLastPathComponent()

        openTerminal(at: directory)
        finishWithoutMove(message: nil)
    }

    private func openTerminal(at directory: URL) {
        do {
            let result = try ProcessRunner.run(
                "/usr/bin/open",
                ["-a", "Terminal", directory.path]
            )
            if result.status != 0 {
                presentOpenTerminalError(result.combinedOutput)
            }
        } catch {
            presentOpenTerminalError(error.localizedDescription)
        }
    }

    private func presentOpenTerminalError(_ detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "无法在终端中打开"
        alert.informativeText = detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "请确认系统自带 Terminal.app 可用。"
            : detail
        alert.addButton(withTitle: "好")
        present(alert)
    }

    // MARK: - Destination picker

    private func chooseDestinationFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "移动到这里"
        panel.message = "选择要移动到的文件夹"

        activateForUI()
        let response = panel.runModal()
        deactivateAfterUI()

        guard response == .OK else { return nil }
        return panel.url
    }

    // MARK: - Move

    private func executeMove(sources: [URL], destination: URL) {
        let plan: MovePlan
        do {
            plan = try MoveEngine.makePlan(sources: sources, destinationDirectory: destination)
        } catch {
            finishWithoutMove(message: error.localizedDescription)
            return
        }

        if plan.validItems.isEmpty {
            let outcome = MoveEngine.execute(plan: plan, resolution: .keepBoth)
            finish(outcome: outcome)
            return
        }

        var resolution: MoveConflictResolution = .keepBoth
        if !plan.itemsNeedingConflictResolution.isEmpty {
            guard let chosen = askConflictResolution(for: plan.itemsNeedingConflictResolution) else {
                finishWithoutMove(message: nil)
                return
            }
            resolution = chosen
        }

        statusBar?.setBusy(true)
        log.info("Starting move of \(plan.validItems.count, privacy: .public) item(s) to \(plan.destinationDirectory.path, privacy: .public)")

        let destinationName = plan.destinationDirectory.lastPathComponent
        workQueue.async { [weak self] in
            let outcome = MoveEngine.execute(plan: plan, resolution: resolution)
            DispatchQueue.main.async {
                guard let self else { return }
                self.log.info(
                    "Move finished: moved=\(outcome.movedCount, privacy: .public) failures=\(outcome.failureCount, privacy: .public) destination=\(destinationName, privacy: .public)"
                )
                self.finish(outcome: outcome)
            }
        }
    }

    // MARK: - Conflicts

    private func askConflictResolution(for items: [MovePlanItem]) -> MoveConflictResolution? {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "目标位置已有同名项目"

        let names = items.prefix(8).map { $0.source.lastPathComponent }
        var lines = names.map { "• \($0)" }
        if items.count > names.count {
            lines.append("…等 \(items.count) 项")
        }
        let detail = lines.joined(separator: "\n")
        alert.informativeText = "\(detail)\n\n请选择处理方式。替换会把原有项目移入废纸篓，可恢复。"

        alert.addButton(withTitle: "保留两者")
        alert.addButton(withTitle: "替换（旧项目移入废纸篓）")
        alert.addButton(withTitle: "取消")

        activateForUI()
        let response = alert.runModal()
        deactivateAfterUI()

        switch response {
        case .alertFirstButtonReturn:
            return .keepBoth
        case .alertSecondButtonReturn:
            return .replace
        default:
            return nil
        }
    }

    // MARK: - Completion

    private func finish(outcome: MoveOutcome) {
        statusBar?.setBusy(false)

        if outcome.movedCount > 0 {
            statusBar?.flashSuccess(count: outcome.movedCount)
        } else if outcome.failureCount == 0 {
            statusBar?.showTransientTooltip(
                outcome.skipped.isEmpty ? "没有可移动的项目" : "项目已经在目标位置"
            )
        }

        if !outcome.failures.isEmpty {
            presentFailureAlert(outcome)
        }

        isBusy = false
        replyToTerminationIfNeeded()
    }

    private func finishWithoutMove(message: String?) {
        statusBar?.setBusy(false)
        if let message, !message.isEmpty {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "无法完成移动"
            alert.informativeText = message
            alert.addButton(withTitle: "好")
            present(alert)
        }
        isBusy = false
        replyToTerminationIfNeeded()
    }

    private func presentFailureAlert(_ outcome: MoveOutcome) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "移动完成，但有 \(outcome.failureCount) 项失败"

        let failures = outcome.failures.prefix(8).map { failure in
            "• \(failure.source.lastPathComponent)：\(failure.message)"
        }
        var lines = Array(failures)
        if outcome.failureCount > failures.count {
            lines.append("…等 \(outcome.failureCount) 项")
        }
        if outcome.movedCount > 0 {
            lines.insert("已成功移动 \(outcome.movedCount) 项。", at: 0)
        }
        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: "好")
        present(alert)
    }

    private func present(_ alert: NSAlert) {
        activateForUI()
        alert.runModal()
        deactivateAfterUI()
    }

    private func replyToTerminationIfNeeded() {
        guard pendingTerminationReply else { return }
        pendingTerminationReply = false
        NSApp.reply(toApplicationShouldTerminate: true)
    }

    // MARK: - Activation

    private func activateForUI() {
        NSApp.activate(ignoringOtherApps: true)
    }

    private func deactivateAfterUI() {
        let hasVisibleDocumentWindow = NSApp.windows.contains { window in
            window.isVisible && window.styleMask.contains(.titled)
        }
        if !hasVisibleDocumentWindow {
            NSApp.hide(nil)
        }
    }
}

import Foundation
import os

final class CommandWatcher {
    private let coordinator: MoveCoordinator
    private let log = Logger(subsystem: AppConfig.logSubsystem, category: "watcher")
    private var timer: Timer?
    private var activity: NSObjectProtocol?
    private var tickCount = 0

    init(coordinator: MoveCoordinator) {
        self.coordinator = coordinator
    }

    func start() {
        CommandStore.ensureSharedDirectory()
        CommandStore.cleanupStaleCommandFiles()

        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "SuperFinder waits for Finder move commands"
        )

        let timer = Timer(timeInterval: AppConfig.commandPollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    private func tick() {
        guard !coordinator.isBusy else { return }

        tickCount += 1
        if tickCount % 120 == 0 {
            CommandStore.cleanupStaleCommandFiles(maxAge: 24 * 60 * 60)
        }

        guard let fileURL = CommandStore.pendingCommandFiles().first else { return }

        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        if let size = attributes?[.size] as? NSNumber, size.intValue > 2 * 1024 * 1024 {
            log.error("Dropping oversized command file: \(fileURL.lastPathComponent, privacy: .public)")
            CommandStore.remove(fileURL)
            return
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            log.error("Cannot read command file: \(error.localizedDescription, privacy: .public)")
            CommandStore.remove(fileURL)
            return
        }

        guard let command = try? MoveCommand.decode(data),
              command.schema == MoveCommand.currentSchema else {
            log.error("Dropping malformed command file: \(fileURL.lastPathComponent, privacy: .public)")
            CommandStore.remove(fileURL)
            return
        }

        guard !command.sources.isEmpty, !command.isExpired else {
            log.info("Dropping empty or expired command: \(fileURL.lastPathComponent, privacy: .public)")
            CommandStore.remove(fileURL)
            return
        }

        coordinator.handle(command: command, commandFile: fileURL)
    }
}

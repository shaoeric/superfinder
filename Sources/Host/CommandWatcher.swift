import Darwin
import Dispatch
import Foundation
import os

/// Watches the command directories without polling. The Finder extension writes
/// a command file and posts a distributed notification; directory file system
/// sources catch commands written by anything else. Bursts of events are
/// coalesced into a single main-queue pass.
final class CommandWatcher {
    private let coordinator: MoveCoordinator
    private let log = Logger(subsystem: AppConfig.logSubsystem, category: "watcher")

    private var notificationObserver: NSObjectProtocol?
    private var directorySources: [String: any DispatchSourceFileSystemObject] = [:]
    private var isRunning = false
    private var passScheduled = false
    private var pendingWhileSuspended = false

    /// Set by the host while the screen-capture overlay is on screen. Command
    /// files stay on disk and are processed after `resumeProcessing()`.
    var isSuspended: Bool = false

    init(coordinator: MoveCoordinator) {
        self.coordinator = coordinator
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        CommandStore.ensureSharedDirectory()
        CommandStore.cleanupStaleCommandFiles()

        coordinator.onIdle = { [weak self] in
            self?.scheduleProcessing()
        }

        notificationObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(AppConfig.commandQueuedNotification),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.refreshDirectoryWatchers()
            self.scheduleProcessing()
        }

        refreshDirectoryWatchers()

        // Scan once at launch. After this, processing is purely event driven.
        processPendingCommands()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        if let notificationObserver {
            DistributedNotificationCenter.default().removeObserver(notificationObserver)
            self.notificationObserver = nil
        }

        for source in directorySources.values {
            source.cancel()
        }
        directorySources.removeAll()

        passScheduled = false
        pendingWhileSuspended = false
    }

    /// Resumes command processing after the screen-capture overlay closes.
    func resumeProcessing() {
        isSuspended = false
        pendingWhileSuspended = false
        scheduleProcessing()
    }

    // MARK: - Directory watchers

    private func refreshDirectoryWatchers() {
        guard isRunning else { return }
        installDirectoryWatcher(for: AppConfig.sharedCommandsDirectory)
        installDirectoryWatcher(for: AppConfig.extensionContainerCommandsDirectory)
    }

    private func installDirectoryWatcher(for directory: URL) {
        let path = directory.path
        guard directorySources[path] == nil else { return }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return
        }

        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else {
            log.error("Cannot watch command directory: \(path, privacy: .public)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .rename, .delete, .attrib],
            queue: .main
        )

        source.setEventHandler { [weak self, weak source] in
            guard let self, let source, self.directorySources[path] === source else { return }

            let events = source.data
            if events.contains(.delete) || events.contains(.rename) {
                self.rebuildDirectoryWatcher(for: directory)
            }
            self.scheduleProcessing()
        }

        source.setCancelHandler {
            close(descriptor)
        }

        directorySources[path] = source
        source.resume()
    }

    private func rebuildDirectoryWatcher(for directory: URL) {
        let path = directory.path
        directorySources.removeValue(forKey: path)?.cancel()
        installDirectoryWatcher(for: directory)
    }

    // MARK: - Coalesced processing

    private func scheduleProcessing() {
        guard isRunning else { return }

        guard !isSuspended else {
            pendingWhileSuspended = true
            return
        }

        guard !passScheduled else { return }
        passScheduled = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.passScheduled = false

            guard self.isRunning else { return }
            guard !self.isSuspended else {
                self.pendingWhileSuspended = true
                return
            }

            self.processPendingCommands()
        }
    }

    private func processPendingCommands() {
        guard isRunning else { return }

        guard !isSuspended else {
            pendingWhileSuspended = true
            return
        }

        pendingWhileSuspended = false
        guard !coordinator.isBusy else { return }

        // Loop over unusable files; once a valid command is handed to the
        // coordinator, wait for its onIdle callback before the next pass.
        while true {
            guard let fileURL = CommandStore.pendingCommandFiles().first else { return }

            let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let size = attributes?[.size] as? NSNumber, size.intValue > 2 * 1024 * 1024 {
                log.error("Dropping oversized command file: \(fileURL.lastPathComponent, privacy: .public)")
                CommandStore.remove(fileURL)
                continue
            }

            let data: Data
            do {
                data = try Data(contentsOf: fileURL)
            } catch {
                log.error("Cannot read command file: \(error.localizedDescription, privacy: .public)")
                CommandStore.remove(fileURL)
                continue
            }

            guard let command = try? MoveCommand.decode(data),
                  command.schema == MoveCommand.currentSchema else {
                log.error("Dropping malformed command file: \(fileURL.lastPathComponent, privacy: .public)")
                CommandStore.remove(fileURL)
                continue
            }

            guard command.hasMinimumPayload, !command.isExpired else {
                log.info("Dropping command without required payload or expired: \(fileURL.lastPathComponent, privacy: .public)")
                CommandStore.remove(fileURL)
                continue
            }

            coordinator.handle(command: command, commandFile: fileURL)
            return
        }
    }
}

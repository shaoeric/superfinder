import Darwin
import Foundation

/// Ensures only one SuperFinder host process runs at a time.
///
/// Uses a POSIX `flock` on `~/Library/Application Support/SuperFinder/SuperFinder.lock`.
/// The kernel releases the lock automatically when the process exits, so a crash
/// does not leave a stale lock behind.
final class InstanceLock {
    enum AcquireResult {
        case acquired(InstanceLock)
        /// Another process owns the lock.
        case alreadyRunning
        /// We could not create/open/lock the file. The caller may fall back to
        /// a running-application check and should not silently refuse to start.
        case failed
    }

    private static let lockFileName = "SuperFinder.lock"

    private let fileDescriptor: Int32
    private let path: String

    private init(fileDescriptor: Int32, path: String) {
        self.fileDescriptor = fileDescriptor
        self.path = path
    }

    deinit {
        _ = flock(fileDescriptor, LOCK_UN)
        _ = close(fileDescriptor)
    }

    static func acquire() -> AcquireResult {
        do {
            try FileManager.default.createDirectory(
                at: AppConfig.sharedSupportDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            NSLog("SuperFinder: cannot create support directory for instance lock: \(error)")
        }

        let path = AppConfig.sharedSupportDirectory
            .appendingPathComponent(lockFileName)
            .path
        let fileDescriptor = open(path, O_CREAT | O_RDWR, mode_t(0o600))
        guard fileDescriptor >= 0 else {
            NSLog("SuperFinder: cannot open instance lock at \(path)")
            return .failed
        }

        if flock(fileDescriptor, LOCK_EX | LOCK_NB) != 0 {
            if errno == EWOULDBLOCK {
                _ = close(fileDescriptor)
                return .alreadyRunning
            }
            NSLog("SuperFinder: flock failed at \(path), errno=\(errno)")
            _ = close(fileDescriptor)
            return .failed
        }

        // Best-effort diagnostics; the lock itself is what matters.
        _ = ftruncate(fileDescriptor, 0)
        let pidLine = "\(getpid())\n"
        _ = pidLine.withCString { pointer in
            write(fileDescriptor, pointer, strlen(pointer))
        }

        return .acquired(InstanceLock(fileDescriptor: fileDescriptor, path: path))
    }

    /// Asks the already-running instance to open its settings window.
    static func notifyExistingInstance() {
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name(AppConfig.showSettingsNotification),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}

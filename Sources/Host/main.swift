import AppKit

var instanceLock: InstanceLock?
var duplicateInstanceDetected = false

switch InstanceLock.acquire() {
case .acquired(let lock):
    instanceLock = lock
case .alreadyRunning:
    duplicateInstanceDetected = true
case .failed:
    // The lock file may be inaccessible in an unusual launch environment.
    // Fall back to the running-application check before allowing a second copy.
    let others = NSRunningApplication.runningApplications(
        withBundleIdentifier: AppConfig.hostBundleID
    ).filter { $0.processIdentifier != getpid() }
    duplicateInstanceDetected = !others.isEmpty
}

if duplicateInstanceDetected {
    InstanceLock.notifyExistingInstance()
    exit(0)
}

let application = NSApplication.shared
let delegate = AppDelegate()
delegate.instanceLock = instanceLock
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()

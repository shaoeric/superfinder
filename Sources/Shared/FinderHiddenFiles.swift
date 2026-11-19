import Foundation

/// Reads Finder's global "show hidden files" preference. The Finder Sync
/// extension is sandboxed, so its entitlement file grants read-only access to
/// the `com.apple.finder` preference domain. The host app is unsandboxed and
/// either sends Finder its native shortcut or, as an explicit fallback, writes
/// the preference before restarting Finder.
enum FinderHiddenFiles {
    static let preferenceDomain = "com.apple.finder"
    static let preferenceKey = "AppleShowAllFiles"

    static func isVisible() -> Bool {
        let value = CFPreferencesCopyAppValue(
            preferenceKey as CFString,
            preferenceDomain as CFString
        )
        return isVisible(preferenceValue: value)
    }

    /// Refreshes the host process's cfprefsd cache after Finder changes the
    /// preference itself through ⌘⇧. The Finder extension does not need this
    /// (and is sandboxed read-only), so it stays host-only in practice.
    static func refreshPreferenceCache() {
        CFPreferencesAppSynchronize(preferenceDomain as CFString)
    }

    /// Kept separate from the preference lookup so the value interpretation can
    /// be tested without touching the current user's Finder settings.
    static func isVisible(preferenceValue: Any?) -> Bool {
        guard let value = preferenceValue else { return false }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let string = value as? String {
            return (string as NSString).boolValue
        }
        return false
    }
}

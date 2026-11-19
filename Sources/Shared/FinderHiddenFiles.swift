import Foundation

/// Reads Finder's global "show hidden files" preference. The Finder Sync
/// extension is sandboxed, so its entitlement file grants read-only access to
/// the `com.apple.finder` preference domain. The host app is unsandboxed and
/// updates the same preference before restarting Finder.
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

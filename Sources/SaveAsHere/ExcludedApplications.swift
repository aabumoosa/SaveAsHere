import Foundation

/// Applications the user has taken out of automatic mode.
///
/// Exclusion is per application rather than global because the reason to exclude is
/// always specific to one: an application whose panel the agent misreads, or one the
/// user simply wants to steer by hand. The hotkey keeps working in an excluded
/// application, so exclusion narrows the agent rather than switching it off.
struct ExcludedApplications {

    private static let key = "excludedBundleIdentifiers"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var all: Set<String> {
        Set(defaults.stringArray(forKey: Self.key) ?? [])
    }

    func contains(_ bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return all.contains(bundleIdentifier)
    }

    /// Returns the state after the change, so the caller can report it.
    @discardableResult
    func toggle(_ bundleIdentifier: String) -> Bool {
        var current = all
        let nowExcluded = current.insert(bundleIdentifier).inserted
        if !nowExcluded { current.remove(bundleIdentifier) }
        defaults.set(Array(current).sorted(), forKey: Self.key)
        return nowExcluded
    }
}

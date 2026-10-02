import Foundation

/// Decides whether an appearing panel should be acted on without the user asking.
///
/// Separate from `SafetyPolicy`, which answers a different question: that one asks
/// whether *this panel* can be moved safely, and applies to the hotkey too. This one
/// asks only whether an unrequested notification deserves attention at all, and its
/// answers are almost always no — every window and sheet an application creates
/// arrives here.
///
/// Pure by design: no accessibility type crosses into this layer. The caller performs
/// the element comparison and passes the result in as `isRepeat`.
public enum AutoTriggerPolicy {

    public enum IgnoreReason: String, Equatable, Sendable {
        case notASavePanel
        case alreadyHandled
        case disabledByUser
        case applicationExcluded
    }

    public enum Decision: Equatable {
        case act
        case ignore(IgnoreReason)
    }

    /// The identifier a native save panel reports. Confirmed present already when
    /// the notification fires — see `app-support.md` §8.
    public static let savePanelIdentifier = "save-panel"

    /// Ordered so the overwhelmingly common case is settled first. Nearly every
    /// notification is for something that is not a save panel, and answering those
    /// with any other reason would fill the log with noise about panels that never
    /// existed.
    public static func decide(
        identifier: String?,
        isRepeat: Bool,
        isEnabled: Bool,
        bundleIdentifier: String?,
        excludedBundles: Set<String>
    ) -> Decision {

        guard identifier == savePanelIdentifier else {
            return .ignore(.notASavePanel)
        }
        guard isEnabled else {
            return .ignore(.disabledByUser)
        }
        // A missing bundle identifier cannot appear in the exclusion list. Treating
        // it as excluded would silently disable the agent for applications the user
        // never named.
        if let bundleIdentifier, excludedBundles.contains(bundleIdentifier) {
            return .ignore(.applicationExcluded)
        }
        guard !isRepeat else {
            return .ignore(.alreadyHandled)
        }
        return .act
    }
}

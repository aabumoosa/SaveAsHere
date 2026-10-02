import CoreGraphics
import Carbon.HIToolbox

/// The only two synthetic keystrokes this application is permitted to produce.
///
/// Deliberately offers no general "send keys" facility. There is no
/// `send(key:)`, so no future change can introduce a third keystroke without
/// adding a named function here and being noticed in review.
///
/// `returnKey()` is dangerous by nature — Return delivered to a save panel means
/// "Save". Callers must satisfy `PanelNavigator`'s gate first; that requirement
/// is enforced in `PanelNavigator`, not here, because only the navigator can
/// observe the panel's state.
public enum AXKeystroke {

    /// How the synthetic event is delivered. Which of these actually works is a
    /// Phase 0 finding, not something to assume: modifier flags on a synthesised
    /// event can be overridden by the real hardware modifier state depending on
    /// the event source used.
    public enum Delivery {
        /// Session-wide tap, hardware event source.
        case hidTap
        /// Session-wide tap, private event source — isolated from real modifiers.
        case privateSourceTap
        /// Delivered directly to one process.
        case toProcess(pid_t)
    }

    public static func commandShiftG(via delivery: Delivery = .privateSourceTap) {
        let stateID: CGEventSourceStateID
        switch delivery {
        case .hidTap:            stateID = .hidSystemState
        case .privateSourceTap:  stateID = .privateState
        case .toProcess:         stateID = .privateState
        }

        let source = CGEventSource(stateID: stateID)
        let key = CGKeyCode(kVK_ANSI_G)
        let flags: CGEventFlags = [.maskCommand, .maskShift]

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return }

        down.flags = flags
        up.flags = flags

        // Critical on non-Latin keyboard layouts. macOS matches a key equivalent
        // against the characters the event carries, and under an Arabic layout the
        // ANSI "G" key produces an Arabic character — so a Command-Shift-G built
        // from the keycode alone never matches "Go to folder". Stating the
        // character explicitly makes the event layout-independent.
        var g: UniChar = 0x0067  // "g"
        down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &g)
        up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &g)

        switch delivery {
        case .hidTap, .privateSourceTap:
            down.post(tap: CGEventTapLocation.cghidEventTap)
            up.post(tap: CGEventTapLocation.cghidEventTap)
        case .toProcess(let pid):
            down.postToPid(pid)
            up.postToPid(pid)
        }
    }

    /// Sends Return. **Only** to confirm an open goto sheet, and only after
    /// `PanelNavigator`'s gate has passed.
    ///
    /// Return carries no modifiers, so the keyboard-layout problem that affects
    /// ⌘⇧G does not apply — Return is a physical key, not a character equivalent.
    public static func returnKey(via delivery: Delivery = .privateSourceTap) {
        let stateID: CGEventSourceStateID
        switch delivery {
        case .hidTap:            stateID = .hidSystemState
        case .privateSourceTap:  stateID = .privateState
        case .toProcess:         stateID = .privateState
        }

        let source = CGEventSource(stateID: stateID)
        let key = CGKeyCode(kVK_Return)

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else { return }

        down.flags = []
        up.flags = []

        switch delivery {
        case .hidTap, .privateSourceTap:
            down.post(tap: CGEventTapLocation.cghidEventTap)
            up.post(tap: CGEventTapLocation.cghidEventTap)
        case .toProcess(let pid):
            down.postToPid(pid)
            up.postToPid(pid)
        }
    }
}

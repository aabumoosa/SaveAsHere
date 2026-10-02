import ApplicationServices

/// Locates menu items by their keyboard equivalent rather than their title.
///
/// Titles are localised; key equivalents are not. "Save As…" is "حفظ باسم…" on an
/// Arabic system, but its shortcut is ⌘⇧S either way. Recon uses this to open a
/// save panel without depending on which application happens to be frontmost,
/// and without needing the Automation permission that System Events would.
public enum AXMenuSearch {

    /// Bit values used by `AXMenuItemCmdModifiers`. Command is implied unless
    /// bit 3 is set, so ⌘⇧S is represented as `shift` alone.
    public struct CmdModifiers {
        public static let shift = 1
        public static let option = 2
        public static let control = 4
        public static let noCommand = 8
    }

    /// Finds the first enabled menu item whose command character and modifier
    /// mask match, searching the application's whole menu bar.
    public static func findItem(
        cmdChar: String,
        modifiers: Int,
        inAppWithPID pid: pid_t
    ) -> AXElement? {
        let app = AXElement.application(pid: pid)
        guard let menuBar = app.element("AXMenuBar") else { return nil }
        return search(menuBar, cmdChar: cmdChar, modifiers: modifiers, depth: 0)
    }

    private static func search(
        _ element: AXElement, cmdChar: String, modifiers: Int, depth: Int
    ) -> AXElement? {
        if depth > 0,
           let char = element.string("AXMenuItemCmdChar"),
           char.compare(cmdChar, options: .caseInsensitive) == .orderedSame,
           let mask = element.attribute("AXMenuItemCmdModifiers") as? Int,
           mask == modifiers,
           element.bool(kAXEnabledAttribute) != false {
            return element
        }
        guard depth < 6 else { return nil }
        for child in element.children {
            if let found = search(
                child, cmdChar: cmdChar, modifiers: modifiers, depth: depth + 1) {
                return found
            }
        }
        return nil
    }
}

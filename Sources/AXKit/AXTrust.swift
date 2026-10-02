import ApplicationServices

/// Accessibility permission state.
///
/// Note on how macOS attributes this permission: a command-line binary launched
/// from a terminal is not itself the subject of the grant — the *responsible*
/// process is, which is normally the terminal application. A bundled app
/// launched from Finder is its own responsible process. Phase 0 records which
/// applies on this machine.
public enum AXTrust {

    public static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}

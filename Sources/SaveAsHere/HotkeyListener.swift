import AppKit
import Carbon.HIToolbox

/// Registers ⌃⌥⌘F as a system-wide hotkey.
///
/// `RegisterEventHotKey` is used rather than a global `NSEvent` monitor because an
/// event monitor additionally requires the Input Monitoring permission. This keeps
/// the application to a single permission request.
///
/// It also sidesteps the keyboard-layout problem entirely: hotkey registration is
/// by virtual keycode, so it does not depend on which characters the active layout
/// produces — unlike the synthesised ⌘⇧G, which had to state its character
/// explicitly (see `docs/findings/app-support.md` §3).
final class HotkeyListener {

    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let onPress: () -> Void

    /// Four-character signature identifying this application's hotkeys ('SvAs').
    private static let signature: OSType = 0x53764173

    init(onPress: @escaping () -> Void) {
        self.onPress = onPress
    }

    func register() -> Bool {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()

        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                Unmanaged<HotkeyListener>.fromOpaque(userData)
                    .takeUnretainedValue()
                    .onPress()
                return noErr
            },
            1, &spec, context, &handler
        )
        guard installed == noErr else { return false }

        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let modifiers = UInt32(cmdKey | optionKey | controlKey)
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_F), modifiers, id,
            GetApplicationEventTarget(), 0, &reference
        )
        return status == noErr
    }

    /// A second, independent path to the same action.
    ///
    /// Carbon registration reports success but its handler was not observed to
    /// fire, and rather than keep guessing at why, this monitor provides a route
    /// that does not depend on Carbon dispatch at all. It needs Accessibility,
    /// which this agent already requires, so it costs no extra permission.
    ///
    /// Matched on `keyCode`, not on characters — the same reason ⌘⇧G had to state
    /// its Unicode string explicitly: under a non-Latin layout the character for
    /// this key is not "f".
    private var monitor: Any?

    func startGlobalMonitor() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard event.keyCode == UInt16(kVK_ANSI_F) else { return }
            let active = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Required modifiers must be present, and Shift must not be — but
            // incidental bits such as Caps Lock or Function are ignored. Strict
            // equality here would make the hotkey fail for anyone with Caps Lock on.
            guard active.isSuperset(of: [.command, .option, .control]),
                  !active.contains(.shift) else { return }
            self?.onPress()
        }
        return monitor != nil
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}

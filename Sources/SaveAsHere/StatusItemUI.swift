import AppKit

/// Menu-bar presence: current state, an on/off switch, a per-application exclusion,
/// and the last outcome.
///
/// The last outcome matters more than it sounds. This agent deliberately does
/// nothing in many situations, and without somewhere to look, "nothing happened"
/// is indistinguishable from "it is broken". Automatic mode sharpens that: there is
/// no keypress to correlate with, so this line is the only visible sign it ran.
final class StatusItemUI: NSObject, NSMenuDelegate {

    /// The application automatic mode would act on, and whether it is excluded.
    /// Supplied by the delegate rather than read here, because clicking a menu-bar
    /// item can change which application the system considers frontmost.
    typealias Target = (name: String, excluded: Bool)

    private var item: NSStatusItem?
    private let statusLine = NSMenuItem(title: "Ready", action: nil, keyEquivalent: "")
    private let toggleItem = NSMenuItem(title: "Enabled", action: nil, keyEquivalent: "")
    private let excludeItem = NSMenuItem(title: "Automatic here", action: nil, keyEquivalent: "")
    private let onToggle: (Bool) -> Void
    private let target: () -> Target?
    private let onToggleExclusion: () -> Void
    private(set) var isEnabled = true

    init(
        onToggle: @escaping (Bool) -> Void,
        target: @escaping () -> Target?,
        onToggleExclusion: @escaping () -> Void
    ) {
        self.onToggle = onToggle
        self.target = target
        self.onToggleExclusion = onToggleExclusion
        super.init()
    }

    func show(trusted: Bool) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⤓"
        item.button?.toolTip =
            "SaveAsHere — points a save panel at the document's folder"

        let menu = NSMenu()
        menu.delegate = self
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        toggleItem.target = self
        toggleItem.action = #selector(toggle)
        toggleItem.state = .on
        menu.addItem(toggleItem)

        excludeItem.target = self
        excludeItem.action = #selector(toggleExclusion)
        menu.addItem(excludeItem)

        if !trusted {
            let warn = NSMenuItem(
                title: "Grant Accessibility permission…",
                action: #selector(openAccessibilitySettings),
                keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Quit SaveAsHere",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        menu.addItem(quit)

        item.menu = menu
        self.item = item
        update(trusted ? "Ready — save panels move on their own"
                       : "Accessibility permission required")
    }

    func update(_ text: String) {
        statusLine.title = text
    }

    /// The exclusion item names an application, so its title is only correct at the
    /// moment the menu opens.
    func menuWillOpen(_ menu: NSMenu) {
        guard let target = target() else {
            excludeItem.title = "Automatic mode"
            excludeItem.isEnabled = false
            excludeItem.state = .off
            return
        }
        excludeItem.title = "Automatic in \(target.name)"
        excludeItem.isEnabled = isEnabled
        excludeItem.state = target.excluded ? .off : .on
    }

    @objc private func toggle() {
        isEnabled.toggle()
        toggleItem.state = isEnabled ? .on : .off
        update(isEnabled ? "Enabled" : "Disabled — nothing will move")
        onToggle(isEnabled)
    }

    @objc private func toggleExclusion() {
        onToggleExclusion()
    }

    @objc private func openAccessibilitySettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }
}

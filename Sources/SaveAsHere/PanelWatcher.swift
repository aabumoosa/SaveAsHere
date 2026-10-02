import AppKit
import ApplicationServices
import AXKit
import SaveAsCore

/// Watches one application for a save panel appearing, and reports it once.
///
/// Subscribes on the application element, so a panel that does not exist yet is
/// still covered (`app-support.md` §8). Two notifications are subscribed because
/// TextEdit presents the panel as a sheet while an application with no document
/// window may present it as a standalone window; §8 records what each application
/// actually emits.
///
/// The panel is delivered exactly once. That is a requirement rather than a
/// precaution: TextEdit was measured emitting both `AXSheetCreated` and
/// `AXFocusedWindowChanged` for the same panel, and acting on each would move it
/// twice.
final class PanelWatcher {

    /// Called with a panel that the policy has already accepted.
    typealias OnPanel = (AXElement) -> Void

    private let pid: pid_t
    private let onPanel: OnPanel
    private let decide: (String?, Bool) -> AutoTriggerPolicy.Decision
    private var observer: AXObserverBox?
    private var lastHandled: AXUIElement?

    /// `decide` is injected so the delegate keeps ownership of the enabled flag and
    /// the exclusion list; this type holds no policy of its own.
    init(
        pid: pid_t,
        decide: @escaping (String?, Bool) -> AutoTriggerPolicy.Decision,
        onPanel: @escaping OnPanel
    ) {
        self.pid = pid
        self.decide = decide
        self.onPanel = onPanel
    }

    /// Returns whether a notification path was established. False means this
    /// application has no automatic mode and the hotkey remains its only route.
    @discardableResult
    func start() -> Bool {
        let observer = AXObserverBox(pid: pid) { [weak self] _, element in
            self?.handle(element)
        }
        guard let observer else { return false }

        var subscribed = false
        for notification in [kAXSheetCreatedNotification,
                             kAXWindowCreatedNotification,
                             kAXFocusedWindowChangedNotification] {
            subscribed = observer.subscribe(notification) || subscribed
        }
        guard subscribed else { return false }

        observer.start()
        self.observer = observer

        // A panel that opened before this observer existed would otherwise never be
        // seen — an application that raises one as it activates is exactly that case.
        catchUp()
        return true
    }

    func stop() {
        observer?.stop()
        observer = nil
        lastHandled = nil
    }

    private func catchUp() {
        guard let panel = SavePanelLocator.findSavePanel(inAppWithPID: pid) else { return }
        handle(panel)
    }

    private func handle(_ element: AXElement) {
        let isRepeat = lastHandled.map { CFEqual($0, element.raw) } ?? false

        switch decide(element.identifier, isRepeat) {
        case .ignore(let reason):
            // Only a panel is worth a line; every other window and sheet the
            // application creates arrives here too, and logging those would bury
            // the entries that matter.
            if reason != .notASavePanel {
                Diagnostics.log("auto: ignored — \(reason.rawValue)")
            }
        case .act:
            lastHandled = element.raw
            onPanel(element)
        }
    }

    deinit {
        stop()
    }
}

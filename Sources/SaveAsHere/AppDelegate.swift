import AppKit
import ApplicationServices
import AXKit
import SaveAsCore

/// Wiring only — no policy decisions live here.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let tracker = DocumentTracker()
    private let action: SaveAsAction
    private var hotkey: HotkeyListener?
    private var status: StatusItemUI?
    private var enabled = true

    /// One watcher at a time, for the frontmost application. Save panels appear in
    /// the application the user is working in; observing every running application
    /// would multiply the machinery for a case that does not arise.
    private var watcher: PanelWatcher?
    private let excluded = ExcludedApplications()

    /// Remembered because the menu names it. Reading the frontmost application when
    /// the menu is open would name the wrong one — this agent may be frontmost by
    /// then.
    private var watchedApp: NSRunningApplication?

    override init() {
        action = SaveAsAction(
            tracker: tracker,
            navigator: PanelNavigator(waiter: RunLoopWaiter()),
            probe: RealFileSystemProbe()
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let trusted = AXTrust.isTrusted(prompt: true)

        let status = StatusItemUI(
            onToggle: { [weak self] on in self?.enabled = on },
            target: { [weak self] in
                guard let self, let app = self.watchedApp,
                      let bundle = app.bundleIdentifier else { return nil }
                return (app.localizedName ?? bundle, self.excluded.contains(bundle))
            },
            onToggleExclusion: { [weak self] in self?.toggleExclusionForWatchedApp() })
        status.show(trusted: trusted)
        self.status = status

        let hotkey = HotkeyListener { [weak self] in self?.handleHotkey() }
        let registered = hotkey.register()
        let monitoring = hotkey.startGlobalMonitor()
        if !registered && !monitoring {
            status.update("Hotkey unavailable — no delivery path")
        }
        self.hotkey = hotkey

        // Written to a file as well as the log: diagnosing a background agent
        // that appears to do nothing is otherwise guesswork.
        Diagnostics.log(
            "launched trusted=\(trusted) carbonHotkey=\(registered) globalMonitor=\(monitoring)")

        observeApplications()
        recordFrontmostDocument()
        watchFrontmostApplication()
    }

    /// The tracker is a fallback for applications that drop `AXDocument` once the
    /// panel takes focus. It is fed on activation so a value is already on hand.
    private func observeApplications() {
        let centre = NSWorkspace.shared.notificationCenter

        centre.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.recordFrontmostDocument()
            self?.watchFrontmostApplication()
        }

        centre.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
            self?.tracker.forget(pid: app.processIdentifier)
        }
    }

    private func recordFrontmostDocument() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let pid = app.processIdentifier
        let focused = AXElement.application(pid: pid).element(kAXFocusedWindowAttribute)
        tracker.record(pid: pid, axDocument: focused?.string("AXDocument"))
    }

    /// Re-points the watcher at whichever application is now frontmost.
    ///
    /// The previous watcher is stopped rather than kept: its subscriptions belong to
    /// an application the user has left, and a panel appearing there is not something
    /// they are looking at.
    private func watchFrontmostApplication(retriesLeft: Int = 2) {
        watcher?.stop()
        watcher = nil

        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return }
        watchedApp = app
        let bundle = app.bundleIdentifier

        let watcher = PanelWatcher(
            pid: app.processIdentifier,
            decide: { [weak self] identifier, isRepeat in
                AutoTriggerPolicy.decide(
                    identifier: identifier,
                    isRepeat: isRepeat,
                    isEnabled: self?.enabled ?? false,
                    bundleIdentifier: bundle,
                    excludedBundles: self?.excluded.all ?? [])
            },
            onPanel: { [weak self] panel in
                self?.handlePanelAppeared(panel, in: app)
            })

        if watcher.start() {
            self.watcher = watcher
            return
        }

        // An application that has only just launched may not answer accessibility
        // requests yet. Measured: VS Code failed here on launch and succeeded a
        // moment later, so without a retry it would have had no automatic mode for
        // the rest of its session — precisely when the user is most likely to save.
        guard retriesLeft > 0 else {
            // No path after retrying means this application publishes none. That is
            // a fact about the application, not a failure: the hotkey still works
            // there. Recorded so a silent application stays diagnosable.
            Diagnostics.log("auto: no notification path for \(bundle ?? "?")")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            // Only if the user is still in that application and nothing else has
            // claimed the watcher in the meantime.
            guard let self, self.watcher == nil,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier
                    == app.processIdentifier
            else { return }
            self.watchFrontmostApplication(retriesLeft: retriesLeft - 1)
        }
    }

    private func toggleExclusionForWatchedApp() {
        guard let bundle = watchedApp?.bundleIdentifier else { return }
        let name = watchedApp?.localizedName ?? bundle
        let nowExcluded = excluded.toggle(bundle)
        status?.update(nowExcluded
            ? "\(name): automatic off — ⌃⌥⌘F still works"
            : "\(name): automatic on")
        Diagnostics.log("exclusion: \(bundle) excluded=\(nowExcluded)")
    }

    private func handlePanelAppeared(_ panel: AXElement, in app: NSRunningApplication) {
        // Called straight from the notification, so `total` in the logged result is
        // measured from the moment the panel appeared. That figure is the window
        // during which the user could type into a panel the agent is moving — the
        // measurement that would settle the typing race if it ever proves real. It
        // is recorded, not enforced: no deadline is imposed.
        let result = action.perform(on: app, panel: panel)
        status?.update(result.description)
        Diagnostics.log("auto: \(result.description)")
    }

    private func handleHotkey() {
        guard enabled else {
            status?.update("Disabled — hotkey ignored")
            return
        }
        let result = action.perform(on: NSWorkspace.shared.frontmostApplication)
        status?.update(result.description)
        Diagnostics.log("hotkey: \(result.description)")
    }
}

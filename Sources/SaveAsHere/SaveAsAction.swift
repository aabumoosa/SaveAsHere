import AppKit
import ApplicationServices
import AXKit
import SaveAsCore

/// The one thing this application does, in one place.
///
/// Shared by the hotkey handler and the `run-once` diagnostic so that both
/// exercise exactly the same path — a diagnostic that tested a different code
/// path would be worthless.
struct SaveAsAction {

    let tracker: DocumentTracker
    let navigator: PanelNavigator
    let probe: FileSystemProbe

    /// Where the wall-clock time went. Kept because this agent talks to another
    /// process over an IPC-backed API, where a careless tree walk costs far more
    /// than the code makes it look.
    struct Timings {
        var locate: TimeInterval = 0
        var resolve: TimeInterval = 0
        var navigate: TimeInterval = 0

        var total: TimeInterval { locate + resolve + navigate }

        var description: String {
            func ms(_ t: TimeInterval) -> String { String(format: "%.0fms", t * 1000) }
            return "total \(ms(total)) [locate \(ms(locate)), resolve \(ms(resolve)), "
                 + "navigate \(ms(navigate))]"
        }
    }

    enum Result {
        case skipped(SkipReason, Timings)
        case outcome(PanelNavigator.Outcome, folder: URL, Timings)

        var timings: Timings {
            switch self {
            case .skipped(_, let t):      return t
            case .outcome(_, _, let t):   return t
            }
        }

        var description: String {
            "\(summary)  ·  \(timings.description)"
        }

        var summary: String {
            switch self {
            case .skipped(let reason, _):
                return "no change: \(reason.rawValue)"
            case .outcome(let outcome, let folder, _):
                switch outcome {
                case .navigated:
                    return "moved to \(folder.lastPathComponent)"
                case .navigatedUnverified:
                    return "attempted \(folder.lastPathComponent) (unverified)"
                case .skipped(let reason):
                    return "no change: \(reason.rawValue)"
                case .failed(let reason):
                    return "failed: \(reason.rawValue)"
                }
            }
        }
    }

    /// `overrideFolder` exists only for diagnostics, so a tester can move a panel
    /// to a known-wrong folder and then verify the agent brings it back. The agent
    /// itself never supplies it.
    func perform(
        on app: NSRunningApplication?, overrideFolder: URL? = nil
    ) -> Result {
        var timings = Timings()
        guard let app else { return .skipped(.noFrontmostApp, timings) }
        let pid = app.processIdentifier

        let mark = Date()
        let panelElement = SavePanelLocator.findSavePanel(inAppWithPID: pid)
        timings.locate = Date().timeIntervalSince(mark)

        guard let panelElement else { return .skipped(.noSavePanel, timings) }
        return perform(
            pid: pid, panel: panelElement,
            overrideFolder: overrideFolder, timings: timings)
    }

    /// Entry point for the automatic trigger, where the notification already carries
    /// the panel. Locating it again would pay for a second tree walk and, worse,
    /// could find a different panel from the one that raised the notification.
    ///
    /// `locate` stays zero here, truthfully: nothing was searched for.
    func perform(on app: NSRunningApplication, panel: AXElement) -> Result {
        perform(
            pid: app.processIdentifier, panel: panel,
            overrideFolder: nil, timings: Timings())
    }

    private func perform(
        pid: pid_t, panel panelElement: AXElement,
        overrideFolder: URL?, timings: Timings
    ) -> Result {
        var timings = timings
        let panel = AXSavePanel(panel: panelElement)

        var mark = Date()
        let folder = overrideFolder ?? AXDocumentResolver.folder(
            forPanel: panelElement, pid: pid, tracker: tracker)
        timings.resolve = Date().timeIntervalSince(mark)

        mark = Date()
        switch SafetyPolicy.evaluate(panel: panel, targetFolder: folder, probe: probe) {
        case .skip(let reason):
            timings.navigate = Date().timeIntervalSince(mark)
            return .skipped(reason, timings)
        case .proceed(let target):
            let outcome = navigator.navigate(panel: panel, to: target)
            timings.navigate = Date().timeIntervalSince(mark)
            return .outcome(outcome, folder: target, timings)
        }
    }
}

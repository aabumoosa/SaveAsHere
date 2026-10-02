import Foundation

/// Performs the navigation sequence, verifying between every step.
///
/// Phase 0 established that the goto sheet has no confirm button and cannot be
/// confirmed by any accessibility action, so confirmation is a Return keystroke.
/// Because a Return that reaches the *save panel* means "Save", it is sent only
/// through a gate — see `confirmGate` below. That gate is this type's reason for
/// existing; everything else is sequencing around it.
public final class PanelNavigator {

    public enum FailureReason: String, Equatable, Sendable {
        case gotoSheetNeverAppeared
        case pathWriteRejected
        case pathReadBackMismatch
        /// The sheet disappeared after the write, so Return would hit the panel.
        case gotoSheetVanished
        /// Keyboard focus was not in the goto sheet's path field, or unreadable,
        /// so Return could have reached the panel's Save button.
        case pathFieldNotFocused
        case filenameFieldChanged
    }

    public enum Outcome: Equatable {
        /// Folder changed and the change was confirmed.
        case navigated
        /// Everything was performed but the folder could not be confirmed.
        /// Reported honestly rather than as success. Never retried.
        case navigatedUnverified
        case skipped(SkipReason)
        case failed(FailureReason)
    }

    private let waiter: Waiter
    private let sheetTimeout: TimeInterval
    private let folderTimeout: TimeInterval
    private let pollInterval: TimeInterval
    /// Receives a label and duration for each phase. Defaults to doing nothing.
    /// Present because the two waits here are the agent's whole latency budget,
    /// and attributing that latency by guesswork wastes optimisation effort on
    /// the wrong half.
    private let trace: (String, TimeInterval) -> Void

    /// The poll interval is small because each check is now a single attribute
    /// read. It was 25 ms when a check meant re-walking the panel's subtree; with
    /// cached control elements the cost is negligible, and a shorter interval means
    /// less time spent overshooting a condition that has already become true.
    public init(
        waiter: Waiter,
        sheetTimeout: TimeInterval = 0.6,
        folderTimeout: TimeInterval = 0.8,
        pollInterval: TimeInterval = 0.008,
        trace: @escaping (String, TimeInterval) -> Void = { _, _ in }
    ) {
        self.waiter = waiter
        self.sheetTimeout = sheetTimeout
        self.folderTimeout = folderTimeout
        self.pollInterval = pollInterval
        self.trace = trace
    }

    private func timed<T>(_ label: String, _ body: () -> T) -> T {
        let start = Date()
        let value = body()
        trace(label, Date().timeIntervalSince(start))
        return value
    }

    public func navigate(panel: SavePanelAccess, to folder: URL) -> Outcome {

        // Retain the suggested filename before touching anything, so any change
        // can be detected afterwards.
        guard let originalFilename = panel.filenameFieldValue else {
            return .skipped(.filenameFieldUnreadable)
        }

        panel.sendGoToFolderShortcut()

        let appeared = timed("awaitSheet") {
            waiter.poll(interval: pollInterval, limit: sheetTimeout) {
                panel.gotoSheet() != nil
            }
        }

        guard appeared, let sheet = panel.gotoSheet() else {
            return .failed(.gotoSheetNeverAppeared)
        }

        let path = folder.path
        guard sheet.setPathValue(path) else {
            return fail(.pathWriteRejected, dismissing: sheet)
        }
        guard sheet.pathValue == path else {
            return fail(.pathReadBackMismatch, dismissing: sheet)
        }

        switch confirmGate(sheet: sheet) {
        case .some(let reason):
            return fail(reason, dismissing: sheet)
        case .none:
            break
        }

        sheet.sendConfirmKey()

        // Normalised: the panel wraps right-to-left folder names in Unicode
        // bidirectional marks, so a direct comparison would never confirm a move
        // into a folder with a non-Latin name.
        let expected = folder.lastPathComponent
        let confirmed = timed("awaitFolder") {
            waiter.poll(interval: pollInterval, limit: folderTimeout) {
                FolderName.matches(panel.displayedFolderName, expected)
            }
        }

        guard panel.filenameFieldValue == originalFilename else {
            return .failed(.filenameFieldChanged)
        }
        return confirmed ? .navigated : .navigatedUnverified
    }

    /// The Return gate, per spec invariant 1. Returns the reason Return must not
    /// be sent, or nil when all conditions hold.
    ///
    /// Checked as late as possible — immediately before the keystroke — because
    /// its whole purpose is to describe the state at that instant.
    private func confirmGate(sheet: GotoSheetAccess) -> FailureReason? {
        // (a) The sheet must still be there, or Return lands on the panel.
        guard sheet.isPresent else { return .gotoSheetVanished }
        // (b) Focus must be confirmed in the path field, so Return lands there.
        //     An unreadable focus is unsafe, not permission.
        guard sheet.isPathFieldFocused == true else { return .pathFieldNotFocused }
        return nil
    }

    private func fail(
        _ reason: FailureReason, dismissing sheet: GotoSheetAccess
    ) -> Outcome {
        _ = sheet.dismiss()
        return .failed(reason)
    }
}

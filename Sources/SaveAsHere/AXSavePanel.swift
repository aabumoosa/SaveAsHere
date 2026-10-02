import AppKit
import ApplicationServices
import AXKit
import SaveAsCore

/// `SavePanelAccess` backed by the real Accessibility API.
///
/// The control *elements* are resolved once and held; their *values* are always
/// read fresh. That distinction is the whole performance story: element identity
/// is stable for the life of a panel, but the navigator polls values in a loop, and
/// re-finding an element on every poll meant re-walking the panel's sidebar and
/// file listing each time — measured at seconds per invocation.
final class AXSavePanel: SavePanelAccess {

    private let panel: AXElement
    private let controls: [String: AXElement]

    init(panel: AXElement) {
        self.panel = panel
        self.controls = SavePanelLocator.collect(
            [
                SavePanelLocator.ID.filenameField,
                SavePanelLocator.ID.wherePopup,
                SavePanelLocator.ID.cancelButton,
            ],
            in: panel,
            maxDepth: SavePanelLocator.controlDepth
        )
    }

    var filenameFieldValue: String? {
        controls[SavePanelLocator.ID.filenameField]?.string(kAXValueAttribute)
    }

    /// The panel shows its current folder in a popup button whose value is the
    /// folder's *name* only — never a full path. A known weakness, spec §6.2.
    /// The name also arrives wrapped in bidirectional marks for right-to-left
    /// names; `FolderName` handles that at the comparison sites.
    var displayedFolderName: String? {
        controls[SavePanelLocator.ID.wherePopup]?.string(kAXValueAttribute)
    }

    func sendGoToFolderShortcut() {
        AXKeystroke.commandShiftG()
    }

    /// The goto sheet is a *direct child* of the panel, and its path field a direct
    /// child of the sheet, so this stays a shallow search even though it must run
    /// on every poll while waiting for the sheet to appear.
    func gotoSheet() -> GotoSheetAccess? {
        guard let sheet = SavePanelLocator.firstDescendant(
                withIdentifier: SavePanelLocator.ID.gotoSheet, in: panel, maxDepth: 1),
              let field = SavePanelLocator.firstDescendant(
                withIdentifier: SavePanelLocator.ID.gotoPathField, in: sheet, maxDepth: 2)
        else { return nil }
        return AXGotoSheet(panel: panel, sheet: sheet, field: field)
    }

    /// Dismisses the panel without saving. Presses `CancelButton` only — never
    /// `OKButton`.
    @discardableResult
    func cancel() -> Bool {
        guard let cancel = controls[SavePanelLocator.ID.cancelButton] else { return false }
        return cancel.perform(kAXPressAction)
    }
}

/// `GotoSheetAccess` backed by the real Accessibility API.
final class AXGotoSheet: GotoSheetAccess {

    private let panel: AXElement
    private let sheet: AXElement
    private let field: AXElement

    init(panel: AXElement, sheet: AXElement, field: AXElement) {
        self.panel = panel
        self.sheet = sheet
        self.field = field
    }

    /// Re-queried from the panel rather than trusting the retained element, so a
    /// sheet that has closed is reported absent even though we still hold a
    /// reference to it. This is what makes the gate's presence check meaningful,
    /// and it is a one-level lookup.
    var isPresent: Bool {
        SavePanelLocator.firstDescendant(
            withIdentifier: SavePanelLocator.ID.gotoSheet, in: panel, maxDepth: 1) != nil
    }

    var pathValue: String? {
        field.string(kAXValueAttribute)
    }

    /// Half of the Return gate: true only when a Return sent now would reach the
    /// path field. That needs two things — the owning application is frontmost,
    /// because synthesised keys go to the frontmost application, and that
    /// application's focused element *is* this field.
    ///
    /// Read at application level, not system-wide: on macOS 27 the system-wide
    /// focused element came back empty in both TextEdit and sandboxed Preview,
    /// while the application's matched the field exactly in both (§10).
    var isPathFieldFocused: Bool? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(field.raw, &pid) == .success else { return nil }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            return false
        }
        guard let focused = AXElement.application(pid: pid)
            .element(kAXFocusedUIElementAttribute) else { return nil }
        return CFEqual(focused.raw, field.raw)
    }

    func setPathValue(_ path: String) -> Bool {
        field.setValue(path, forAttribute: kAXValueAttribute)
    }

    /// Phase 0 ruled out every alternative: the sheet has no confirm button,
    /// `AXDefaultButton` is advertised but empty, and both `AXConfirm` on this
    /// field and `AXOpen` on the path table succeed while doing nothing.
    func sendConfirmKey() {
        AXKeystroke.returnKey()
    }

    /// On macOS 27 the close button only *clears* the field while it holds text;
    /// a second press closes the sheet. One press left the sheet open and empty
    /// after every failed run, so this presses until the sheet is confirmed gone.
    /// Three presses is one more than has ever been needed.
    func dismiss() -> Bool {
        guard let close = SavePanelLocator.firstDescendant(
            withIdentifier: SavePanelLocator.ID.gotoCloseButton, in: sheet, maxDepth: 2)
        else { return false }
        let waiter = RunLoopWaiter()
        for _ in 0..<3 {
            guard close.perform(kAXPressAction) else { return false }
            if waiter.poll(interval: 0.01, limit: 0.3, until: { !isPresent }) { return true }
        }
        return false
    }
}

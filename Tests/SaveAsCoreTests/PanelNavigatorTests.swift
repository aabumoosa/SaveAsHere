import XCTest
@testable import SaveAsCore

final class PanelNavigatorTests: XCTestCase {

    private let book = URL(fileURLWithPath: "/Users/u/Projects/Book")

    private func navigate(_ panel: FakePanel) -> PanelNavigator.Outcome {
        PanelNavigator(waiter: ImmediateWaiter()).navigate(panel: panel, to: book)
    }

    // MARK: Success

    func test_happyPath_navigatesAndPreservesFilename() {
        let panel = FakePanel()
        XCTAssertEqual(navigate(panel), .navigated)
        XCTAssertEqual(panel.filenameFieldValue, "Chapter1.docx")
        XCTAssertEqual(panel.displayedFolderName, "Book")
    }

    func test_folderNeverChanges_reportsUnverified() {
        let panel = FakePanel()
        panel.folderAfterConfirm = nil
        XCTAssertEqual(navigate(panel), .navigatedUnverified)
    }

    /// Regression: a panel reporting a right-to-left folder name wraps it in
    /// Unicode bidirectional marks. Before normalisation this reported
    /// `navigatedUnverified` even though the move had succeeded.
    func test_rightToLeftFolderName_isConfirmedNotReportedUnverified() {
        let arabic = URL(fileURLWithPath: "/Users/u/مشاريع/ميزانية 2026")
        let panel = FakePanel()
        panel.displayedFolderName = "Documents"
        panel.folderAfterConfirm = "\u{200E}\u{2066}ميزانية 2026\u{2069}"
        let outcome = PanelNavigator(waiter: ImmediateWaiter())
            .navigate(panel: panel, to: arabic)
        XCTAssertEqual(outcome, .navigated)
    }

    // MARK: Adversarial failures

    func test_gotoSheetNeverAppears_fails() {
        XCTAssertEqual(
            navigate(FakePanel(sheetAppears: false)),
            .failed(.gotoSheetNeverAppeared))
    }

    func test_pathWriteRejected_failsAndDismissesSheet() {
        let panel = FakePanel()
        panel.sheet?.acceptWrites = false
        XCTAssertEqual(navigate(panel), .failed(.pathWriteRejected))
        XCTAssertTrue(panel.log.events.contains(.dismissSheet))
        XCTAssertFalse(panel.log.events.contains(.returnKey))
    }

    func test_readBackMismatch_failsAndDismissesSheet() {
        let panel = FakePanel()
        panel.sheet?.readBackOverride = "/somewhere/else"
        XCTAssertEqual(navigate(panel), .failed(.pathReadBackMismatch))
        XCTAssertTrue(panel.log.events.contains(.dismissSheet))
        XCTAssertFalse(panel.log.events.contains(.returnKey))
    }

    func test_filenameMangled_isReportedAsFailure() {
        let panel = FakePanel()
        panel.filenameAfterConfirm = "Untitled.docx"
        XCTAssertEqual(navigate(panel), .failed(.filenameFieldChanged))
    }

    func test_unreadableFilenameField_skipsAndSendsNothing() {
        let panel = FakePanel()
        panel.filenameFieldValue = nil
        XCTAssertEqual(navigate(panel), .skipped(.filenameFieldUnreadable))
        XCTAssertTrue(panel.log.events.isEmpty)
    }

    // MARK: The Return gate (spec invariant 1)

    /// Gate condition (b): Return goes wherever keyboard focus is. If focus has
    /// left the path field, the Return could reach the panel's Save button —
    /// which macOS 27 leaves enabled while the sheet is open. Nothing may be sent.
    func test_gate_focusOutsidePathField_refusesToSendReturn() {
        let panel = FakePanel()
        panel.sheet?.pathFieldFocused = false
        XCTAssertEqual(navigate(panel), .failed(.pathFieldNotFocused))
        XCTAssertFalse(panel.log.events.contains(.returnKey))
        XCTAssertTrue(panel.log.events.contains(.dismissSheet))
    }

    /// Unreadable focus is treated as unsafe, not as permission.
    func test_gate_unreadableFocus_refusesToSendReturn() {
        let panel = FakePanel()
        panel.sheet?.pathFieldFocused = nil
        XCTAssertEqual(navigate(panel), .failed(.pathFieldNotFocused))
        XCTAssertFalse(panel.log.events.contains(.returnKey))
    }

    /// Gate condition (a): the sheet vanishing after the write means a Return
    /// would land on the panel itself. Nothing may be sent.
    func test_gate_sheetVanishesAfterWrite_refusesToSendReturn() {
        let panel = FakePanel()
        panel.sheet?.vanishBeforeConfirm = true
        XCTAssertEqual(navigate(panel), .failed(.gotoSheetVanished))
        XCTAssertFalse(panel.log.events.contains(.returnKey))
    }

    /// Invariant 4: across every scenario, at most one ⌘⇧G and at most one Return.
    func test_acrossAllScenarios_keystrokeCountsAreBounded() {
        let scenarios: [(String, () -> FakePanel)] = [
            ("happy", { FakePanel() }),
            ("no sheet", { FakePanel(sheetAppears: false) }),
            ("write rejected", { let p = FakePanel(); p.sheet?.acceptWrites = false; return p }),
            ("mismatch", { let p = FakePanel(); p.sheet?.readBackOverride = "/x"; return p }),
            ("focus elsewhere", { let p = FakePanel(); p.sheet?.pathFieldFocused = false; return p }),
            ("focus unknown", { let p = FakePanel(); p.sheet?.pathFieldFocused = nil; return p }),
            ("sheet vanished", { let p = FakePanel(); p.sheet?.vanishBeforeConfirm = true; return p }),
            ("folder stuck", { let p = FakePanel(); p.folderAfterConfirm = nil; return p }),
            ("filename mangled", { let p = FakePanel(); p.filenameAfterConfirm = "X"; return p }),
        ]
        for (name, makePanel) in scenarios {
            let panel = makePanel()
            _ = navigate(panel)
            let shortcuts = panel.log.events.filter { $0 == .commandShiftG }.count
            let returns = panel.log.events.filter { $0 == .returnKey }.count
            XCTAssertLessThanOrEqual(shortcuts, 1, "\(name): too many ⌘⇧G")
            XCTAssertLessThanOrEqual(returns, 1, "\(name): too many Return")
        }
    }

    /// Return is only ever sent when the full gate held.
    func test_returnIsOnlySentWhenGateHeld() {
        let scenarios: [() -> FakePanel] = [
            { FakePanel() },
            { FakePanel(sheetAppears: false) },
            { let p = FakePanel(); p.sheet?.acceptWrites = false; return p },
            { let p = FakePanel(); p.sheet?.readBackOverride = "/x"; return p },
            { let p = FakePanel(); p.sheet?.pathFieldFocused = false; return p },
            { let p = FakePanel(); p.sheet?.pathFieldFocused = nil; return p },
            { let p = FakePanel(); p.sheet?.vanishBeforeConfirm = true; return p },
        ]
        for makePanel in scenarios {
            let panel = makePanel()
            // Read before navigating: a successful confirm removes the sheet.
            let focusedBefore = panel.sheet?.pathFieldFocused
            _ = navigate(panel)
            if panel.log.events.contains(.returnKey) {
                XCTAssertEqual(focusedBefore, true,
                               "Return sent while focus was not confirmed in the path field")
            }
        }
    }
}

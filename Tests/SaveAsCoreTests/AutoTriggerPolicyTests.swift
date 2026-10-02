import XCTest
@testable import SaveAsCore

final class AutoTriggerPolicyTests: XCTestCase {

    private func decide(
        identifier: String? = "save-panel",
        isRepeat: Bool = false,
        isEnabled: Bool = true,
        bundleIdentifier: String? = "com.apple.TextEdit",
        excluded: Set<String> = []
    ) -> AutoTriggerPolicy.Decision {
        AutoTriggerPolicy.decide(
            identifier: identifier,
            isRepeat: isRepeat,
            isEnabled: isEnabled,
            bundleIdentifier: bundleIdentifier,
            excludedBundles: excluded)
    }

    func test_savePanelNotification_acts() {
        XCTAssertEqual(decide(), .act)
    }

    func test_someOtherSheet_isIgnored() {
        XCTAssertEqual(decide(identifier: "AlertSheet"), .ignore(.notASavePanel))
    }

    /// The go-to sheet this agent opens is itself a newly created sheet, so it
    /// arrives as a notification. Acting on it would make the agent retrigger
    /// itself.
    func test_ownGoToSheet_isIgnored() {
        XCTAssertEqual(decide(identifier: "GoToWindow"), .ignore(.notASavePanel))
    }

    func test_elementWithoutIdentifier_isIgnored() {
        XCTAssertEqual(decide(identifier: nil), .ignore(.notASavePanel))
    }

    /// Measured, not hypothetical: TextEdit emits both `AXSheetCreated` and
    /// `AXFocusedWindowChanged` for one panel. See `app-support.md` §8.
    func test_secondNotificationForTheSamePanel_isIgnored() {
        XCTAssertEqual(decide(isRepeat: true), .ignore(.alreadyHandled))
    }

    func test_disabledFromTheMenu_isIgnored() {
        XCTAssertEqual(decide(isEnabled: false), .ignore(.disabledByUser))
    }

    func test_excludedApplication_isIgnored() {
        XCTAssertEqual(
            decide(bundleIdentifier: "com.apple.TextEdit", excluded: ["com.apple.TextEdit"]),
            .ignore(.applicationExcluded))
    }

    func test_exclusionAppliesOnlyToTheNamedApplication() {
        XCTAssertEqual(
            decide(bundleIdentifier: "com.apple.Preview", excluded: ["com.apple.TextEdit"]),
            .act)
    }

    /// An application without a bundle identifier cannot be named in the exclusion
    /// list, so it cannot be excluded — it must not be silently blocked either.
    func test_applicationWithoutBundleIdentifier_acts() {
        XCTAssertEqual(decide(bundleIdentifier: nil, excluded: ["com.apple.TextEdit"]), .act)
    }

    /// Every ignore reason must be distinguishable in the log; a shared or empty
    /// string would make "nothing happened" undiagnosable.
    func test_ignoreReasonsAreDistinct() {
        let reasons: [AutoTriggerPolicy.IgnoreReason] =
            [.notASavePanel, .alreadyHandled, .disabledByUser, .applicationExcluded]
        XCTAssertEqual(Set(reasons.map(\.rawValue)).count, reasons.count)
        XCTAssertFalse(reasons.contains { $0.rawValue.isEmpty })
    }
}

import Foundation
@testable import SaveAsCore

/// Records every synthetic input so tests can assert on the complete set.
final class InputLog {
    enum Event: Equatable {
        case commandShiftG
        case returnKey
        case setPath(String)
        case dismissSheet
    }
    var events: [Event] = []
}

final class FakeGotoSheet: GotoSheetAccess {
    let log: InputLog
    var storedPath: String?
    var acceptWrites = true
    var readBackOverride: String?
    /// Simulates the sheet vanishing between the write and the gate check.
    var vanishBeforeConfirm = false
    var present = true
    /// Where keyboard focus sits: true means a Return would land in the path
    /// field, the real sheet's behaviour right after ⌘⇧G. nil means unreadable.
    var pathFieldFocused: Bool? = true
    /// Invoked when Return is sent, so the panel can move.
    var onConfirm: (() -> Void)?

    init(log: InputLog) { self.log = log }

    var isPresent: Bool {
        if vanishBeforeConfirm { return false }
        return present
    }

    var pathValue: String? { readBackOverride ?? storedPath }

    var isPathFieldFocused: Bool? { pathFieldFocused }

    func setPathValue(_ path: String) -> Bool {
        log.events.append(.setPath(path))
        guard acceptWrites else { return false }
        storedPath = path
        return true
    }

    func sendConfirmKey() {
        log.events.append(.returnKey)
        onConfirm?()
    }

    func dismiss() -> Bool {
        log.events.append(.dismissSheet)
        present = false
        return true
    }
}

final class FakePanel: SavePanelAccess {
    let log = InputLog()

    var filenameFieldValue: String? = "Chapter1.docx"
    var displayedFolderName: String? = "Documents"

    var sheet: FakeGotoSheet?
    /// Folder name adopted once Return is sent; nil means navigation silently fails.
    var folderAfterConfirm: String? = "Book"
    /// Simulates an application that mangles the filename field.
    var filenameAfterConfirm: String?

    init(sheetAppears: Bool = true) {
        if sheetAppears {
            let s = FakeGotoSheet(log: log)
            s.onConfirm = { [weak self] in
                guard let self else { return }
                if let folder = self.folderAfterConfirm { self.displayedFolderName = folder }
                if let name = self.filenameAfterConfirm { self.filenameFieldValue = name }
                self.sheet = nil
            }
            sheet = s
        }
    }

    func sendGoToFolderShortcut() { log.events.append(.commandShiftG) }

    func gotoSheet() -> GotoSheetAccess? { sheet }
}

struct FakeProbe: FileSystemProbe {
    var existing: Set<String> = []
    var directories: Set<String> = []
    func exists(_ url: URL) -> Bool { existing.contains(url.path) }
    func isDirectory(_ url: URL) -> Bool { directories.contains(url.path) }
}

/// Evaluates the condition a bounded number of times with no real waiting.
struct ImmediateWaiter: Waiter {
    var attempts = 3
    func poll(
        interval: TimeInterval, limit: TimeInterval, until condition: () -> Bool
    ) -> Bool {
        for _ in 0..<attempts where condition() { return true }
        return condition()
    }
}

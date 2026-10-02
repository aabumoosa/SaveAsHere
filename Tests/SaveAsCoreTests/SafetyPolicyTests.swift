import XCTest
@testable import SaveAsCore

final class SafetyPolicyTests: XCTestCase {

    private let book = URL(fileURLWithPath: "/Users/u/Projects/Book")

    private func probe(existing: Bool = true, directory: Bool = true) -> FakeProbe {
        FakeProbe(
            existing: existing ? [book.path] : [],
            directories: directory ? [book.path] : []
        )
    }

    func test_validFolderAndPanel_proceeds() {
        let panel = FakePanel()
        panel.displayedFolderName = "Documents"
        XCTAssertEqual(
            SafetyPolicy.evaluate(panel: panel, targetFolder: book, probe: probe()),
            .proceed(folder: book))
    }

    func test_nilTargetFolder_skips() {
        XCTAssertEqual(
            SafetyPolicy.evaluate(panel: FakePanel(), targetFolder: nil, probe: probe()),
            .skip(.unknownDocumentFolder))
    }

    func test_missingFolder_skips() {
        XCTAssertEqual(
            SafetyPolicy.evaluate(
                panel: FakePanel(), targetFolder: book, probe: probe(existing: false)),
            .skip(.folderMissing))
    }

    func test_folderThatIsAFile_skips() {
        XCTAssertEqual(
            SafetyPolicy.evaluate(
                panel: FakePanel(), targetFolder: book, probe: probe(directory: false)),
            .skip(.folderNotDirectory))
    }

    func test_panelAlreadyShowingTargetFolder_skips() {
        let panel = FakePanel()
        panel.displayedFolderName = "Book"
        XCTAssertEqual(
            SafetyPolicy.evaluate(panel: panel, targetFolder: book, probe: probe()),
            .skip(.alreadyShowingFolder))
    }

    func test_unreadableFilenameField_skips() {
        let panel = FakePanel()
        panel.filenameFieldValue = nil
        XCTAssertEqual(
            SafetyPolicy.evaluate(panel: panel, targetFolder: book, probe: probe()),
            .skip(.filenameFieldUnreadable))
    }
}

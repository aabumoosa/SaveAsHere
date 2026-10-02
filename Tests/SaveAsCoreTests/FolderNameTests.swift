import XCTest
@testable import SaveAsCore

/// These cases come from a real observation, not imagination: the save panel in
/// Pages reported its current folder as "\u{200E}\u{2066}ميزانية 2026\u{2069}"
/// — the Arabic name wrapped in Unicode bidirectional control marks that do not
/// exist in the filesystem path component. Without normalisation, every folder
/// with a non-Latin name compares as different from itself.
final class FolderNameTests: XCTestCase {

    func test_plainNameIsUnchanged() {
        XCTAssertEqual(FolderName.normalize("Book"), "Book")
    }

    func test_arabicNameWrappedInBidiMarks_matchesPlainName() {
        let fromPanel = "\u{200E}\u{2066}ميزانية 2026\u{2069}"
        XCTAssertEqual(FolderName.normalize(fromPanel), "ميزانية 2026")
    }

    func test_allBidiControlsAreStripped() {
        let wrapped = "\u{200E}\u{200F}\u{061C}\u{202A}\u{202B}\u{202C}\u{202D}"
            + "\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}Book"
        XCTAssertEqual(FolderName.normalize(wrapped), "Book")
    }

    func test_surroundingWhitespaceIsTrimmed() {
        XCTAssertEqual(FolderName.normalize("  Book \u{2069} "), "Book")
    }

    func test_nilIsPropagated() {
        XCTAssertNil(FolderName.normalize(nil))
    }

    func test_matchesComparesNormalizedForms() {
        XCTAssertTrue(FolderName.matches("\u{2066}ميزانية 2026\u{2069}", "ميزانية 2026"))
        XCTAssertFalse(FolderName.matches("Documents", "Book"))
        XCTAssertFalse(FolderName.matches(nil, "Book"))
    }
}

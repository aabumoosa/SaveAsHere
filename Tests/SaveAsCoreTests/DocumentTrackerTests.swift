import XCTest
@testable import SaveAsCore

final class DocumentTrackerTests: XCTestCase {

    func test_recordedFolderIsRetrievableAfterFocusMovesAway() {
        let tracker = DocumentTracker()
        tracker.record(pid: 42, axDocument: "file:///Users/u/Book/Chapter1.docx")
        // The panel is now focused and exposes no document at all.
        tracker.record(pid: 42, axDocument: nil)
        XCTAssertEqual(tracker.folder(for: 42)?.path, "/Users/u/Book")
    }

    func test_unknownPidReturnsNil() {
        XCTAssertNil(DocumentTracker().folder(for: 99))
    }

    func test_unparseableDocumentDoesNotOverwriteGoodEntry() {
        let tracker = DocumentTracker()
        tracker.record(pid: 7, axDocument: "file:///Users/u/Book/Ch.docx")
        tracker.record(pid: 7, axDocument: "not-a-path")
        XCTAssertEqual(tracker.folder(for: 7)?.path, "/Users/u/Book")
    }

    func test_newDocumentReplacesPrevious() {
        let tracker = DocumentTracker()
        tracker.record(pid: 7, axDocument: "file:///Users/u/Book/Ch.docx")
        tracker.record(pid: 7, axDocument: "file:///Users/u/Notes/N.txt")
        XCTAssertEqual(tracker.folder(for: 7)?.path, "/Users/u/Notes")
    }

    func test_forgetRemovesEntry() {
        let tracker = DocumentTracker()
        tracker.record(pid: 7, axDocument: "file:///Users/u/Book/Ch.docx")
        tracker.forget(pid: 7)
        XCTAssertNil(tracker.folder(for: 7))
    }

    func test_cacheIsBounded() {
        let tracker = DocumentTracker(limit: 2)
        tracker.record(pid: 1, axDocument: "file:///a/one/f.txt")
        tracker.record(pid: 2, axDocument: "file:///a/two/f.txt")
        tracker.record(pid: 3, axDocument: "file:///a/three/f.txt")
        XCTAssertNil(tracker.folder(for: 1), "oldest entry evicted")
        XCTAssertEqual(tracker.folder(for: 3)?.path, "/a/three")
    }
}

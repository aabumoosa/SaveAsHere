import XCTest
@testable import SaveAsCore

final class DocumentPathTests: XCTestCase {

    func test_fileURL_yieldsParentFolder() {
        let result = DocumentPath.parentFolder(
            fromAXDocument: "file:///Users/u/Projects/Book/Chapter1.docx")
        XCTAssertEqual(result?.path, "/Users/u/Projects/Book")
    }

    func test_percentEncodedFileURL_isDecoded() {
        let result = DocumentPath.parentFolder(
            fromAXDocument: "file:///Users/u/My%20Book/Ch%201.docx")
        XCTAssertEqual(result?.path, "/Users/u/My Book")
    }

    func test_plainPOSIXPath_isAccepted() {
        let result = DocumentPath.parentFolder(
            fromAXDocument: "/Users/u/Projects/Book/Chapter1.docx")
        XCTAssertEqual(result?.path, "/Users/u/Projects/Book")
    }

    func test_nonFileScheme_isRejected() {
        XCTAssertNil(DocumentPath.parentFolder(
            fromAXDocument: "https://example.com/a/b.docx"))
    }

    func test_relativeString_isRejected() {
        XCTAssertNil(DocumentPath.parentFolder(fromAXDocument: "Chapter1.docx"))
    }

    func test_nilAndEmpty_areRejected() {
        XCTAssertNil(DocumentPath.parentFolder(fromAXDocument: nil))
        XCTAssertNil(DocumentPath.parentFolder(fromAXDocument: ""))
    }

    func test_fileAtRoot_isRejected() {
        // A document directly at "/" gives a parent of "/", which is never a
        // useful place to point a save panel.
        XCTAssertNil(DocumentPath.parentFolder(fromAXDocument: "/Chapter1.docx"))
    }
}

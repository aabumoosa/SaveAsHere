import ApplicationServices
import AXKit
import SaveAsCore

/// Determines which folder a save panel should be pointed at.
///
/// Phase 0 showed the save panel is a *sheet on the document window*, and that the
/// window retains its `AXDocument` while the panel is open. So the path can be read
/// directly from the panel's owning window — more reliable than remembering it,
/// because it cannot go stale.
///
/// The tracker remains as a fallback for applications that drop `AXDocument` once a
/// panel takes focus, and for those where the panel is not parented to the document
/// window at all.
enum AXDocumentResolver {

    static func folder(
        forPanel panel: AXElement,
        pid: pid_t,
        tracker: DocumentTracker
    ) -> URL? {
        if let fromAncestor = folderFromAncestors(of: panel) {
            return fromAncestor
        }
        if let fromWindows = folderFromWindows(pid: pid) {
            return fromWindows
        }
        return tracker.folder(for: pid)
    }

    /// Walks the parent chain, since the panel's owning window holds the document.
    private static func folderFromAncestors(of panel: AXElement) -> URL? {
        var current: AXElement? = panel
        var hops = 0
        while let element = current, hops < 8 {
            if let folder = DocumentPath.parentFolder(
                fromAXDocument: element.string("AXDocument")) {
                return folder
            }
            current = element.element(kAXParentAttribute)
            hops += 1
        }
        return nil
    }

    /// Any window of the application that still advertises a document.
    private static func folderFromWindows(pid: pid_t) -> URL? {
        let app = AXElement.application(pid: pid)
        var candidates: [AXElement] = []
        if let focused = app.element(kAXFocusedWindowAttribute) {
            candidates.append(focused)
        }
        candidates.append(contentsOf: app.elements(kAXWindowsAttribute))
        for window in candidates {
            if let folder = DocumentPath.parentFolder(
                fromAXDocument: window.string("AXDocument")) {
                return folder
            }
        }
        return nil
    }
}

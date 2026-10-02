import ApplicationServices
import AXKit
import SaveAsCore

/// Finds a native save panel and its controls.
///
/// Identification is by `AXIdentifier`, established in Phase 0. Identifiers are not
/// localised, so this works regardless of the user's language — unlike title
/// matching, which would break on the Arabic system this was developed on.
///
/// Searches are **breadth-first with a depth cap**, which matters for speed rather
/// than correctness. Everything wanted here is shallow — the panel sits two levels
/// below the application, and its controls two or three below that — while the
/// panel's deep subtrees hold the sidebar and the whole file listing. A depth-first
/// walk descends into those before reaching the controls; measured, that made each
/// lookup cost tens of milliseconds, and the navigator performs lookups in a poll
/// loop.
public enum SavePanelLocator {

    /// Identifiers observed on macOS 26.6. See `docs/findings/app-support.md` §2.
    public enum ID {
        /// Defined in `SaveAsCore` because the automatic trigger matches on it
        /// before any of this module's code runs. Kept in one place: two copies
        /// that drift would make the agent look at a panel it cannot recognise.
        public static let panel = AutoTriggerPolicy.savePanelIdentifier
        public static let filenameField = "saveAsNameTextField"
        public static let wherePopup = "where popup"
        public static let cancelButton = "CancelButton"
        public static let saveButton = "OKButton"
        public static let gotoSheet = "GoToWindow"
        public static let gotoPathField = "PathTextField"
        public static let gotoCloseButton = "CloseButton"
    }

    /// The panel is a sheet on a document window: application > window > sheet.
    /// A little slack is allowed in case an application nests it differently.
    private static let panelDepth = 4
    /// Panel controls sat two to three levels below the panel in both TextEdit
    /// and Pages.
    static let controlDepth = 5

    public static func findSavePanel(inAppWithPID pid: pid_t) -> AXElement? {
        let app = AXElement.application(pid: pid)
        return firstDescendant(withIdentifier: ID.panel, in: app, maxDepth: panelDepth)
    }

    /// Breadth-first search for one identifier.
    public static func firstDescendant(
        withIdentifier identifier: String, in root: AXElement, maxDepth: Int
    ) -> AXElement? {
        collect([identifier], in: root, maxDepth: maxDepth)[identifier]
    }

    /// Collects several identifiers in a **single** traversal.
    ///
    /// The navigator needs three or four controls at once; resolving them with a
    /// walk each multiplied the cost for no reason.
    static func collect(
        _ identifiers: [String], in root: AXElement, maxDepth: Int
    ) -> [String: AXElement] {
        var wanted = Set(identifiers)
        var found: [String: AXElement] = [:]
        var frontier = [root]
        var depth = 0

        while !frontier.isEmpty, depth <= maxDepth, !wanted.isEmpty {
            var next: [AXElement] = []
            for element in frontier {
                if let id = element.identifier, wanted.contains(id) {
                    found[id] = element
                    wanted.remove(id)
                    if wanted.isEmpty { return found }
                }
                next.append(contentsOf: element.children)
            }
            frontier = next
            depth += 1
        }
        return found
    }
}

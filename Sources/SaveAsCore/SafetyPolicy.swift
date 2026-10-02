import Foundation

public enum SkipReason: String, Equatable, Sendable {
    case noFrontmostApp
    case noSavePanel
    case unknownDocumentFolder
    case folderMissing
    case folderNotDirectory
    case alreadyShowingFolder
    case filenameFieldUnreadable
    case disabledByUser
}

public enum NavigationDecision: Equatable {
    case proceed(folder: URL)
    case skip(SkipReason)
}

/// Collects every condition under which this application does nothing at all.
///
/// Ordering matters: cheaper and more conclusive checks come first, and the
/// filename field is read last because it is the most expensive query.
public enum SafetyPolicy {

    public static func evaluate(
        panel: SavePanelAccess,
        targetFolder: URL?,
        probe: FileSystemProbe
    ) -> NavigationDecision {

        guard let folder = targetFolder else {
            return .skip(.unknownDocumentFolder)
        }
        guard probe.exists(folder) else {
            return .skip(.folderMissing)
        }
        guard probe.isDirectory(folder) else {
            return .skip(.folderNotDirectory)
        }
        // The panel exposes only the displayed folder's name, not its path, so
        // this comparison can be fooled by two folders sharing a name. Being
        // fooled here means declining to act, which is the safe direction.
        //
        // Normalised because the panel wraps right-to-left names in Unicode
        // bidirectional marks that never appear in a path component.
        if FolderName.matches(panel.displayedFolderName, folder.lastPathComponent) {
            return .skip(.alreadyShowingFolder)
        }
        guard panel.filenameFieldValue != nil else {
            return .skip(.filenameFieldUnreadable)
        }
        return .proceed(folder: folder)
    }
}

import Foundation

/// Converts the raw value of an accessibility `AXDocument` attribute into the
/// folder a save panel should be pointed at.
///
/// The attribute is documented as a URL string, but applications are
/// inconsistent: some supply a `file://` URL, some a bare POSIX path. Anything
/// else is rejected outright — guessing a folder is worse than doing nothing,
/// because a wrong guess silently sends the user's file somewhere unintended.
public enum DocumentPath {

    public static func parentFolder(fromAXDocument value: String?) -> URL? {
        guard let value, !value.isEmpty else { return nil }

        let fileURL: URL
        if value.hasPrefix("file://") {
            guard let parsed = URL(string: value), parsed.isFileURL else { return nil }
            fileURL = parsed
        } else if value.hasPrefix("/") {
            fileURL = URL(fileURLWithPath: value)
        } else {
            return nil
        }

        let parent = fileURL.deletingLastPathComponent().standardizedFileURL
        guard parent.path != "/", !parent.path.isEmpty else { return nil }
        return parent
    }
}

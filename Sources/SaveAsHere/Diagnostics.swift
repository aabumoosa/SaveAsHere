import Foundation

/// Appends to a log file under `~/Library/Logs`.
///
/// A background agent with no window is otherwise undiagnosable: when it does
/// nothing, there is no way to distinguish "declined on purpose" from "never
/// received the hotkey" from "crashed". The menu bar shows the last outcome; this
/// keeps the history.
enum Diagnostics {

    private static let fileURL: URL = {
        let logs = FileManager.default.urls(
            for: .libraryDirectory, in: .userDomainMask
        )[0].appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs.appendingPathComponent("SaveAsHere.log")
    }()

    static var path: String { fileURL.path }

    static func log(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp)  \(message)\n"
        NSLog("SaveAsHere: %@", message)
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)
        }
    }
}

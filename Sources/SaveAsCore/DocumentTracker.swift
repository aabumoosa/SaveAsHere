import Foundation

/// Remembers the folder of the last real document seen per application.
///
/// Only successfully parsed documents are stored. A `nil` or unparseable value
/// leaves the previous entry intact — that is the entire point of the type: once
/// the save panel takes focus it exposes no document, and must not erase what we
/// already knew.
public final class DocumentTracker {

    private var folders: [pid_t: URL] = [:]
    private var order: [pid_t] = []
    private let limit: Int

    public init(limit: Int = 16) {
        self.limit = max(1, limit)
    }

    public func record(pid: pid_t, axDocument: String?) {
        guard let folder = DocumentPath.parentFolder(fromAXDocument: axDocument) else {
            return
        }
        if folders[pid] == nil {
            order.append(pid)
        }
        folders[pid] = folder
        evictIfNeeded()
    }

    public func folder(for pid: pid_t) -> URL? {
        folders[pid]
    }

    public func forget(pid: pid_t) {
        folders[pid] = nil
        order.removeAll { $0 == pid }
    }

    private func evictIfNeeded() {
        while order.count > limit, let oldest = order.first {
            order.removeFirst()
            folders[oldest] = nil
        }
    }
}

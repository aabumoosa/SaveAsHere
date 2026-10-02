import Foundation

/// The "Go to folder" sheet a save panel presents.
///
/// Shaped by Phase 0: this sheet has no confirm button, so confirmation is a gated
/// Return rather than a button press. See `docs/findings/app-support.md` §4.
public protocol GotoSheetAccess: AnyObject {
    /// Whether the sheet is still present. Checked immediately before confirming.
    var isPresent: Bool { get }
    /// Current text in the path field, or nil if unreadable.
    var pathValue: String? { get }
    /// Whether keyboard focus is in this sheet's path field — that is, whether a
    /// Return sent now would land there rather than on the panel.
    ///
    /// This is the load-bearing half of the Return gate. It replaced a check that
    /// the panel's Save button was disabled: that held on macOS 26.6, but macOS 27
    /// leaves Save enabled while the sheet is open (`docs/findings/app-support.md`
    /// §10). `nil` means focus could not be read, which is treated as unsafe.
    var isPathFieldFocused: Bool? { get }
    /// Writes the path field directly. Returns false if the write was rejected.
    func setPathValue(_ path: String) -> Bool
    /// Sends Return. Callers must satisfy the gate in `PanelNavigator` first.
    func sendConfirmKey()
    /// Dismisses the sheet without navigating, used to clean up after a failure.
    /// Returns true only once the sheet is confirmed gone.
    func dismiss() -> Bool
}

/// A native save panel belonging to some application.
public protocol SavePanelAccess: AnyObject {
    /// The filename the application suggested. Must survive every invocation.
    var filenameFieldValue: String? { get }
    /// The folder name the panel currently displays. The panel exposes only the
    /// name, never a full path, so comparisons are last-path-component only.
    var displayedFolderName: String? { get }
    /// Synthesises one ⌘⇧G.
    func sendGoToFolderShortcut()
    /// The goto sheet, if it is currently present.
    func gotoSheet() -> GotoSheetAccess?
}

public protocol FileSystemProbe {
    func exists(_ url: URL) -> Bool
    func isDirectory(_ url: URL) -> Bool
}

/// Polls a condition without blocking. Implementations must not sleep the main
/// thread; tests supply one that evaluates immediately.
public protocol Waiter {
    /// Returns true if `condition` became true within `limit` seconds.
    func poll(interval: TimeInterval, limit: TimeInterval, until condition: () -> Bool) -> Bool
}

public struct RealFileSystemProbe: FileSystemProbe {
    public init() {}

    public func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        let found = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return found && isDir.boolValue
    }
}

/// Polls by spinning the run loop in short slices, so the agent stays responsive.
public struct RunLoopWaiter: Waiter {
    public init() {}

    public func poll(
        interval: TimeInterval, limit: TimeInterval, until condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(limit)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(interval))
        }
        return condition()
    }
}

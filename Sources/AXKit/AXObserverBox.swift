import ApplicationServices
import Foundation

/// A thin, non-throwing wrapper over the accessibility *notification* API.
///
/// Mirrors `AXElement`'s contract: creating or subscribing returns nil or false
/// rather than an error, because every failure here means the same thing to this
/// application — no notification will arrive, so there is no automatic trigger and
/// the hotkey remains the only path.
///
/// Notifications are registered on the **application** element, not on individual
/// windows, so a window or sheet that does not exist yet is still covered.
public final class AXObserverBox {

    public typealias Handler = (_ notification: String, _ element: AXElement) -> Void

    private let observer: AXObserver
    private let application: AXElement
    private let handler: Handler
    private var subscribed: [String] = []
    private var running = false

    public init?(pid: pid_t, handler: @escaping Handler) {
        var created: AXObserver?
        guard AXObserverCreate(pid, axObserverBoxCallback, &created) == .success,
              let created
        else { return nil }
        self.observer = created
        self.application = AXElement.application(pid: pid)
        self.handler = handler
    }

    /// The pointer handed to the C callback is unretained: the caller owns this
    /// object, and `deinit` unsubscribes before it can dangle.
    @discardableResult
    public func subscribe(_ notification: String) -> Bool {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = AXObserverAddNotification(
            observer, application.raw, notification as CFString, context)
        guard status == .success else { return false }
        subscribed.append(notification)
        return true
    }

    public func start() {
        guard !running else { return }
        CFRunLoopAddSource(
            CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        running = true
    }

    public func stop() {
        if running {
            CFRunLoopRemoveSource(
                CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
            running = false
        }
        for notification in subscribed {
            AXObserverRemoveNotification(
                observer, application.raw, notification as CFString)
        }
        subscribed = []
    }

    fileprivate func deliver(notification: String, element: AXElement) {
        handler(notification, element)
    }

    deinit {
        stop()
    }
}

/// Free function because a C function pointer cannot carry captured state; the
/// object arrives through the context pointer instead.
private func axObserverBoxCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ context: UnsafeMutableRawPointer?
) {
    guard let context else { return }
    Unmanaged<AXObserverBox>.fromOpaque(context)
        .takeUnretainedValue()
        .deliver(notification: notification as String, element: AXElement(element))
}

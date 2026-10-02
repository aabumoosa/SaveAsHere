import ApplicationServices

/// A thin, non-throwing wrapper over `AXUIElement`.
///
/// Every accessor returns `nil` rather than an error: a missing attribute and a
/// failed query are the same thing to this application — a reason to do nothing.
public struct AXElement {

    public let raw: AXUIElement

    public init(_ raw: AXUIElement) {
        self.raw = raw
    }

    /// Applies the messaging timeout, so an unresponsive target application can
    /// never block this agent.
    ///
    /// Called on the application element only — deliberately *not* from `init`.
    /// Doing it per element added one IPC round trip for every node created, and
    /// a tree walk creates thousands, which measurably dominated the cost.
    public static func application(pid: pid_t) -> AXElement {
        let element = AXElement(AXUIElementCreateApplication(pid))
        AXUIElementSetMessagingTimeout(element.raw, 0.5)
        return element
    }

    public func setMessagingTimeout(_ seconds: Float) {
        AXUIElementSetMessagingTimeout(raw, seconds)
    }

    public func attribute(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(raw, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    public func string(_ name: String) -> String? {
        attribute(name) as? String
    }

    public func bool(_ name: String) -> Bool? {
        attribute(name) as? Bool
    }

    public func element(_ name: String) -> AXElement? {
        guard let value = attribute(name),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return AXElement(unsafeDowncast(value as AnyObject, to: AXUIElement.self))
    }

    public func elements(_ name: String) -> [AXElement] {
        guard let values = attribute(name) as? [AXUIElement] else { return [] }
        return values.map(AXElement.init)
    }

    public func attributeNames() -> [String] {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(raw, &names) == .success,
              let list = names as? [String] else { return [] }
        return list
    }

    public func isSettable(_ name: String) -> Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(raw, name as CFString, &settable) == .success
        else { return false }
        return settable.boolValue
    }

    public func actionNames() -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(raw, &names) == .success,
              let list = names as? [String] else { return [] }
        return list
    }

    @discardableResult
    public func perform(_ action: String) -> Bool {
        AXUIElementPerformAction(raw, action as CFString) == .success
    }

    @discardableResult
    public func setValue(_ value: String, forAttribute name: String) -> Bool {
        AXUIElementSetAttributeValue(raw, name as CFString, value as CFString) == .success
    }

    public var role: String? { string(kAXRoleAttribute) }
    public var subrole: String? { string(kAXSubroleAttribute) }
    public var identifier: String? { string("AXIdentifier") }
    public var title: String? { string(kAXTitleAttribute) }
    public var children: [AXElement] { elements(kAXChildrenAttribute) }
}

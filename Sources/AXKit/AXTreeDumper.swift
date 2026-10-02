import ApplicationServices

/// Renders an accessibility subtree as indented text. Read-only by construction:
/// it calls only copy-attribute APIs, never set or perform.
public enum AXTreeDumper {

    /// Attributes worth printing for every node. Anything else is listed by name
    /// only, so the output stays readable while still revealing what exists.
    private static let interesting = [
        kAXRoleAttribute, kAXSubroleAttribute, "AXIdentifier",
        kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute,
        kAXPlaceholderValueAttribute, kAXEnabledAttribute, kAXFocusedAttribute,
        "AXDocument", "AXURL", "AXFilename",
    ]

    public static func dump(_ element: AXElement, maxDepth: Int = 12) -> String {
        var output = ""
        walk(element, depth: 0, maxDepth: maxDepth, into: &output)
        return output
    }

    private static func walk(
        _ element: AXElement, depth: Int, maxDepth: Int, into output: inout String
    ) {
        let pad = String(repeating: "  ", count: depth)
        let names = Set(element.attributeNames())

        var parts: [String] = [element.role ?? "?"]
        for name in interesting where names.contains(name) {
            guard name != kAXRoleAttribute else { continue }
            if let value = element.attribute(name) {
                let text = String(describing: value)
                    .replacingOccurrences(of: "\n", with: "\\n")
                parts.append("\(name)=\(text.prefix(120))")
            }
        }
        output += pad + parts.joined(separator: " ") + "\n"

        // Reveal structural attributes we may need but have not hard-coded,
        // e.g. AXSheets, AXDefaultButton, AXCancelButton.
        let structural = names.filter {
            $0.hasSuffix("Button") || $0 == "AXSheets" || $0 == "AXWindows"
        }
        if !structural.isEmpty {
            output += pad + "  [structural: \(structural.sorted().joined(separator: ", "))]\n"
        }
        let actions = element.actionNames()
        if !actions.isEmpty {
            output += pad + "  [actions: \(actions.joined(separator: ", "))]\n"
        }

        guard depth < maxDepth else {
            output += pad + "  …depth limit\n"
            return
        }
        for child in element.children {
            walk(child, depth: depth + 1, maxDepth: maxDepth, into: &output)
        }
    }
}

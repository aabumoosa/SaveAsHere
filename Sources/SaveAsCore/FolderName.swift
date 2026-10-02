import Foundation

/// Compares folder names as reported by a save panel against names taken from the
/// filesystem.
///
/// The two are not the same string. A save panel renders its current folder for
/// display, and for a right-to-left name macOS wraps it in Unicode bidirectional
/// control characters so it lays out correctly next to Latin text. Those marks are
/// invisible, carry no meaning here, and never appear in a path component.
///
/// Observed in Pages: the folder `ميزانية 2026` was reported as
/// `\u{200E}\u{2066}ميزانية 2026\u{2069}`. Comparing that to the path component
/// directly fails, so every folder with a non-Latin name would look different from
/// itself — the panel would never be recognised as already correct, and every
/// successful move would be reported as unverified.
public enum FolderName {

    /// Unicode bidirectional formatting characters: marks, embeddings, overrides
    /// and isolates. All are presentational.
    private static let bidiControls: Set<Character> = [
        "\u{200E}",  // LEFT-TO-RIGHT MARK
        "\u{200F}",  // RIGHT-TO-LEFT MARK
        "\u{061C}",  // ARABIC LETTER MARK
        "\u{202A}",  // LEFT-TO-RIGHT EMBEDDING
        "\u{202B}",  // RIGHT-TO-LEFT EMBEDDING
        "\u{202C}",  // POP DIRECTIONAL FORMATTING
        "\u{202D}",  // LEFT-TO-RIGHT OVERRIDE
        "\u{202E}",  // RIGHT-TO-LEFT OVERRIDE
        "\u{2066}",  // LEFT-TO-RIGHT ISOLATE
        "\u{2067}",  // RIGHT-TO-LEFT ISOLATE
        "\u{2068}",  // FIRST STRONG ISOLATE
        "\u{2069}",  // POP DIRECTIONAL ISOLATE
    ]

    public static func normalize(_ name: String?) -> String? {
        guard let name else { return nil }
        let stripped = String(name.filter { !bidiControls.contains($0) })
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether a name reported by a panel refers to the same folder name as one
    /// taken from a path. Nil on either side is never a match.
    public static func matches(_ displayed: String?, _ pathComponent: String) -> Bool {
        guard let displayed = normalize(displayed) else { return false }
        return displayed == normalize(pathComponent)
    }
}

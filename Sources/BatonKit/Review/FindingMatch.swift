/// Deterministic, dependency-free fuzzy matching of finding titles, used by
/// ``CrossTaskDedup`` to decide whether two findings on the same `(file, line)`
/// describe the same issue despite differing phrasing.
public enum FindingMatch {
    /// Titles whose token-set Jaccard similarity is at or above this threshold are
    /// treated as the same finding. Tuned to fold near-identical phrasings
    /// ("Data race on `foo`" vs "data race: foo") without merging distinct issues.
    public static let titleThreshold = 0.6

    /// Lowercase, map every non-alphanumeric character to a space, collapse runs of
    /// whitespace, and trim. Idempotent.
    public static func normalizeTitle(_ title: String) -> String {
        let mapped = title.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : " "
        }
        return String(mapped).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Stable, deduplicated, sorted token set of a normalized title.
    public static func tokenSet(_ title: String) -> [String] {
        let tokens = normalizeTitle(title).split(separator: " ").map(String.init)
        return Set(tokens).sorted()
    }

    /// Jaccard similarity of two token sets, in `[0, 1]`. Two empty sets count as
    /// identical (`1.0`) so two blank titles on the same location still merge.
    public static func jaccard(_ lhs: [String], _ rhs: [String]) -> Double {
        let left = Set(lhs)
        let right = Set(rhs)
        if left.isEmpty, right.isEmpty { return 1.0 }
        let union = left.union(right).count
        guard union > 0 else { return 1.0 }
        return Double(left.intersection(right).count) / Double(union)
    }

    /// Whether two titles describe the same finding under the configured threshold.
    public static func titlesMatch(_ lhs: String, _ rhs: String) -> Bool {
        jaccard(tokenSet(lhs), tokenSet(rhs)) >= titleThreshold
    }
}

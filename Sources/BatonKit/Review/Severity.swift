/// The severity of a review finding, ordered `low < medium < high`.
public enum Severity: String, Codable, CaseIterable, Comparable, Sendable {
    case low
    case medium
    case high

    /// Numeric rank used for ordering and threshold comparisons.
    public var rank: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        }
    }

    public static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.rank < rhs.rank
    }
}

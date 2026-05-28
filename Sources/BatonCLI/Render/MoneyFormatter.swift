import Foundation

/// Renders USD amounts for stats / history / show in a way that surfaces
/// micro-costs without losing meaning at higher totals.
public enum MoneyFormatter {
    /// `nil` → "—" (em dash), otherwise:
    ///   * < $0.01 → 4-decimal: "$0.0034"
    ///   * < $10   → 3-decimal: "$0.123"
    ///   * else    → 2-decimal: "$12.45"
    public static func format(_ value: Double?) -> String {
        guard let value else { return "—" }
        if abs(value) < 0.01 {
            return String(format: "$%.4f", value)
        }
        if abs(value) < 10 {
            return String(format: "$%.3f", value)
        }
        return String(format: "$%.2f", value)
    }

    /// Render `nil` as `—` for arbitrary integer-shaped counters (tokens).
    public static func formatTokens(_ value: Int?) -> String {
        guard let value else { return "—" }
        return TextTable.formatNumber(value)
    }
}

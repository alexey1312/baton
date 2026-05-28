import Foundation

/// Lightweight text-formatting helpers shared by stats / history / show.
///
/// Ported from the `zc stat` command's `pad`/`lpad`/bar-chart helpers so that
/// every text table in Baton looks the same. Noora gives us colours; this gives
/// us widths.
public enum TextTable {
    /// Right-pad `value` with spaces to fit `width`. No-op when already wider.
    public static func pad(_ value: String, _ width: Int) -> String {
        guard value.count < width else { return value }
        return value + String(repeating: " ", count: width - value.count)
    }

    /// Left-pad `value` with spaces to fit `width`. No-op when already wider.
    public static func lpad(_ value: String, _ width: Int) -> String {
        guard value.count < width else { return value }
        return String(repeating: " ", count: width - value.count) + value
    }

    /// Truncate `value` to `width`, appending `…` when something was cut.
    public static func truncate(_ value: String, _ width: Int) -> String {
        guard value.count > width else { return value }
        guard width > 1 else { return String(value.prefix(width)) }
        return String(value.prefix(width - 1)) + "…"
    }

    /// Render a horizontal bar chart cell using full-block characters.
    /// `value` and `max` should be ≥0; max==0 returns "".
    public static func bar(value: Int, max: Int, width: Int = 20) -> String {
        guard max > 0, width > 0 else { return "" }
        let length = max == 0 ? 0 : value * width / max
        return String(repeating: "█", count: length)
    }

    /// Group integers with a thin-space-style separator (`,`) so `12345`
    /// renders as `12,345`. Locale-independent (we want stable CI output).
    public static func formatNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

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
    /// Negative `value` and `max == 0` both render as an empty cell so the
    /// caller doesn't have to special-case "no data" rows.
    public static func bar(value: Int, max: Int, width: Int = 20) -> String {
        guard max > 0, width > 0, value > 0 else { return "" }
        let length = min(width, value * width / max)
        return String(repeating: "█", count: length)
    }

    /// Group integers with a comma separator so `12345` renders as `12,345`.
    /// Locale-independent (we want stable CI output regardless of host locale).
    public static func formatNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

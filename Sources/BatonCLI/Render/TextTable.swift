import Foundation

/// Lightweight text-formatting helpers shared by stats / history / show.
///
/// Ported from the `zc stat` command's `pad`/`lpad`/bar-chart helpers so that
/// every text table in Baton looks the same. Noora gives us colours; this gives
/// us widths.
public enum TextTable {
    /// Right-pad `value` with spaces to fit `width`. No-op when already wider.
    public static func pad(_ value: String, _ width: Int) -> String {
        let w = displayWidth(value)
        guard w < width else { return value }
        return value + String(repeating: " ", count: width - w)
    }

    /// Left-pad `value` with spaces to fit `width`. No-op when already wider.
    public static func lpad(_ value: String, _ width: Int) -> String {
        let w = displayWidth(value)
        guard w < width else { return value }
        return String(repeating: " ", count: width - w) + value
    }

    /// Truncate `value` to `width` display columns, appending `…` when cut.
    public static func truncate(_ value: String, _ width: Int) -> String {
        guard displayWidth(value) > width else { return value }
        guard width > 1 else { return String(value.prefix(width)) }
        var result = ""
        var used = 0
        for char in value {
            let cw = charWidth(char)
            if used + cw > width - 1 { break } // reserve one column for the ellipsis
            result.append(char)
            used += cw
        }
        return result + "…"
    }

    // MARK: - Display width

    /// Approximate terminal display width: East-Asian Wide/Fullwidth scalars and
    /// emoji occupy two columns; combining/zero-width marks occupy none. Counting
    /// grapheme clusters (`String.count`) would misalign such cells.
    public static func displayWidth(_ value: String) -> Int {
        value.reduce(0) { $0 + charWidth($1) }
    }

    private static func charWidth(_ char: Character) -> Int {
        let scalars = char.unicodeScalars.filter { !isZeroWidth($0) }
        if scalars.isEmpty { return 0 }
        return scalars.contains(where: isWide) ? 2 : 1
    }

    private static func isZeroWidth(_ s: Unicode.Scalar) -> Bool {
        switch s.value {
        case 0x200B, 0x200C, 0x200D, 0xFE00 ... 0xFE0F: true // ZW(S/NJ/J), variation selectors
        default: s.properties.generalCategory == .nonspacingMark
        }
    }

    private static func isWide(_ s: Unicode.Scalar) -> Bool {
        if s.properties.isEmojiPresentation { return true }
        switch s.value {
        case 0x1100 ... 0x115F, // Hangul Jamo
             0x2E80 ... 0xA4CF, // CJK radicals … Yi
             0xAC00 ... 0xD7A3, // Hangul syllables
             0xF900 ... 0xFAFF, // CJK compatibility ideographs
             0xFE30 ... 0xFE4F, // CJK compatibility forms
             0xFF00 ... 0xFF60, 0xFFE0 ... 0xFFE6, // fullwidth forms
             0x1F300 ... 0x1FAFF, // emoji & pictographs
             0x20000 ... 0x3FFFD: // CJK Ext B+
            return true
        default:
            return false
        }
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

@testable import BatonCLI
import Testing

struct TextTableTests {
    @Test("bar returns empty string when max is zero")
    func barZeroMax() {
        #expect(TextTable.bar(value: 5, max: 0, width: 20).isEmpty)
    }

    @Test("bar clamps negative ratios to empty string (no crash on String(repeating:count:))")
    func barNegativeValue() {
        // value < 0 would yield a negative `count` inside String(repeating:count:),
        // which traps. The guard must keep us off that path.
        #expect(TextTable.bar(value: -1, max: 10, width: 20).isEmpty)
    }

    @Test("bar renders proportional full-block string")
    func barProportional() {
        #expect(TextTable.bar(value: 5, max: 10, width: 20) == String(repeating: "█", count: 10))
    }

    @Test("truncate appends ellipsis when width is large enough, raw prefix otherwise")
    func truncateBoundary() {
        #expect(TextTable.truncate("abcdef", 4) == "abc…")
        #expect(TextTable.truncate("abcdef", 1) == "a")
        #expect(TextTable.truncate("abcdef", 0).isEmpty)
    }

    @Test("formatNumber is locale-independent and groups with commas")
    func formatNumberLocale() {
        #expect(TextTable.formatNumber(1000) == "1,000")
        #expect(TextTable.formatNumber(-1000) == "-1,000")
        #expect(TextTable.formatNumber(0) == "0")
    }
}

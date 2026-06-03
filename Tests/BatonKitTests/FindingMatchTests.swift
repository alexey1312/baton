@testable import BatonKit
import Testing

struct FindingMatchTests {
    @Test("normalizeTitle lowercases, strips punctuation, and collapses whitespace")
    func normalize() {
        #expect(FindingMatch.normalizeTitle("Data race on `foo`!") == "data race on foo")
        #expect(FindingMatch.normalizeTitle("  Multiple   spaces\t\n here ") == "multiple spaces here")
        #expect(FindingMatch.normalizeTitle("SQL-injection: query") == "sql injection query")
    }

    @Test("normalizeTitle is idempotent")
    func normalizeIdempotent() {
        let once = FindingMatch.normalizeTitle("Data race: on FOO!!")
        #expect(FindingMatch.normalizeTitle(once) == once)
    }

    @Test("jaccard is 1 for identical sets, 0 for disjoint, and exact for partial overlap")
    func jaccard() {
        #expect(FindingMatch.jaccard(["a", "b"], ["a", "b"]) == 1.0)
        #expect(FindingMatch.jaccard(["a"], ["b"]) == 0.0)
        // {a,b,c} vs {b,c,d}: intersection 2, union 4 → 0.5
        #expect(FindingMatch.jaccard(["a", "b", "c"], ["b", "c", "d"]) == 0.5)
        // Two empty token sets count as identical.
        #expect(FindingMatch.jaccard([], []) == 1.0)
    }

    @Test("titlesMatch folds near-identical phrasings but separates distinct issues")
    func titlesMatch() {
        #expect(FindingMatch.titlesMatch("Data race on foo", "data race: foo"))
        #expect(!FindingMatch.titlesMatch("Data race on foo", "Force unwrap on bar"))
    }

    @Test("titlesMatch respects the threshold boundary")
    func threshold() {
        // {data,race,on,shared,state} vs {data,race}: 2/5 = 0.4 < 0.6 → no match.
        #expect(!FindingMatch.titlesMatch("data race on shared state", "data race"))
        // {data,race,here} vs {data,race}: 2/3 ≈ 0.67 ≥ 0.6 → match.
        #expect(FindingMatch.titlesMatch("data race here", "data race"))
    }
}

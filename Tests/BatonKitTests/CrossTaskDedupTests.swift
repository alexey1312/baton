@testable import BatonKit
import Testing

struct CrossTaskDedupTests {
    private func finding(
        _ title: String,
        line: Int? = 1,
        severity: Severity = .medium,
        file: String = "a.swift"
    ) -> Finding {
        Finding(file: file, line: line, severity: severity, title: title, body: "body")
    }

    private func result(_ review: String, failOn: Severity = .high, _ findings: [Finding]) -> ReviewTaskResult {
        ReviewTaskResult(scope: "", review: review, findings: findings, failOn: failOn)
    }

    @Test("fuzzy-equal findings on the same location merge into one confirmed finding")
    func mergesDuplicates() {
        let merged = CrossTaskDedup.merge([
            result("style", [finding("Data race on foo", severity: .low)]),
            result("concurrency", [finding("data race: foo", severity: .medium)]),
        ])
        let all = merged.flatMap(\.findings)
        #expect(all.count == 1)
        #expect(all[0].severity == .medium) // raised to the group max
        #expect(all[0].confirmedBy == ["concurrency", "style"]) // distinct, sorted
        #expect(merged[1].findings.isEmpty) // duplicate removed from the sibling
    }

    @Test("findings on different locations are never merged")
    func differentLocations() {
        let merged = CrossTaskDedup.merge([
            result("a", [finding("race", line: 1)]),
            result("b", [finding("race", line: 2)]),
        ])
        let findings = merged.flatMap(\.findings)
        #expect(findings.count == 2)
        let allUnconfirmed = findings.allSatisfy(\.confirmedBy.isEmpty)
        #expect(allUnconfirmed)
    }

    @Test("titles below the similarity threshold are not merged")
    func dissimilarTitles() {
        let merged = CrossTaskDedup.merge([
            result("a", [finding("data race on shared mutable state")]),
            result("b", [finding("force unwrap of optional")]),
        ])
        #expect(merged.flatMap(\.findings).count == 2)
    }

    @Test("a single review's own findings on one line are not folded together")
    func sameReviewNotFolded() {
        let merged = CrossTaskDedup.merge([
            result("style", [finding("data race here"), finding("data race here too")]),
        ])
        // Cross-task only: one task's two findings stay separate, output unchanged.
        #expect(merged[0].findings.count == 2)
        let allUnconfirmed = merged[0].findings.allSatisfy(\.confirmedBy.isEmpty)
        #expect(allUnconfirmed)
    }

    @Test("merge never softens the exit code when a crossing finding moves to a sibling")
    func exitSemanticsPreserved() {
        // Representative (kept) is the lenient review; the strict review loses its copy.
        let lenient = result("style", failOn: .high, [finding("race foo", severity: .low)])
        let strict = result("security", failOn: .low, [finding("race foo bar", severity: .medium)])
        let before = ReviewOutcome(results: [lenient, strict])
        #expect(before.shouldFailExit) // strict: .medium >= .low

        let merged = CrossTaskDedup.merge([lenient, strict])
        let after = ReviewOutcome(results: merged)
        #expect(after.shouldFailExit == before.shouldFailExit)
        // The strict review lost its threshold-crossing copy but stays failed via the guard.
        #expect(merged[1].findings.isEmpty)
        #expect(merged[1].removedCrossingFindings)
        #expect(merged[1].failed)
    }

    @Test("merge is a no-op for a single task")
    func singleTaskNoOp() {
        let input = [result("style", [finding("a"), finding("b", line: 2)])]
        let merged = CrossTaskDedup.merge(input)
        #expect(merged.flatMap(\.findings).count == 2)
        #expect(merged[0].findings.map(\.title) == ["a", "b"])
    }

    @Test("merge content is invariant under input reordering")
    func reorderInvariant() {
        let a = result("style", [finding("data race foo", severity: .low)])
        let b = result("concurrency", [finding("data race: foo", severity: .high)])
        let forward = CrossTaskDedup.merge([a, b]).flatMap(\.findings)
        let backward = CrossTaskDedup.merge([b, a]).flatMap(\.findings)
        #expect(forward.count == 1)
        #expect(backward.count == 1)
        #expect(forward[0].severity == .high)
        #expect(backward[0].severity == .high)
        #expect(Set(forward[0].confirmedBy) == Set(backward[0].confirmedBy))
    }
}

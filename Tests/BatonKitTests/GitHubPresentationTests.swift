@testable import BatonKit
import Testing

struct GitHubPresentationTests {
    private func finding(_ severity: Severity, instructions: String? = nil) -> Finding {
        Finding(file: "a.swift", line: 1, severity: severity, title: "t", body: "b", aiInstructions: instructions)
    }

    @Test("conclusion is high-gated, independent of fail_on")
    func conclusion() {
        #expect(GitHubPresentation.conclusion(for: []) == .success)
        #expect(GitHubPresentation.conclusion(for: [finding(.low), finding(.medium)]) == .neutral)
        #expect(GitHubPresentation.conclusion(for: [finding(.low), finding(.high)]) == .failure)
    }

    @Test("inline comment carries the marker, AI block, and reaction affordance")
    func inlineComment() {
        let body = GitHubPresentation.inlineCommentBody(finding(.high, instructions: "fix it"))
        #expect(body.contains(BatonMarker.finding))
        #expect(body.contains("Instructions for AI agents"))
        #expect(body.contains("fix it"))
        #expect(body.contains("👍"))
        #expect(body.contains("🔴"))
    }

    @Test("summary body aggregates findings and handles the empty case")
    func summary() {
        let empty = GitHubPresentation.summaryBody(scope: "ios", review: "sec", findings: [])
        #expect(empty.contains("No findings"))
        let full = GitHubPresentation.summaryBody(scope: "", review: "sec", findings: [finding(.medium)])
        #expect(full.contains("(root)"))
        #expect(full.contains(BatonMarker.finding))
    }

    @Test("last-reviewed marker round-trips")
    func lastReviewed() {
        let marker = BatonMarker.lastReviewed("abc123")
        let body = "Some review body.\n\(marker)\n"
        #expect(BatonMarker.parseLastReviewed(from: body) == "abc123")
        #expect(BatonMarker.parseLastReviewed(from: "no marker") == nil)
    }
}

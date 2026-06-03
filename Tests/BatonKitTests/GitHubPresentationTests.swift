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

    @Test("auto-resolve reply carries its own marker and never the finding marker")
    func autoResolvedReply() {
        let body = BatonMarker.autoResolvedReplyBody(reason: "the finding's anchor is outdated")
        #expect(body.contains(BatonMarker.autoResolved))
        #expect(!body.contains(BatonMarker.finding)) // must stay invisible to dedupe + finding parsing
        #expect(body.contains("outdated"))
    }

    @Test("last-reviewed marker round-trips")
    func lastReviewed() {
        let marker = BatonMarker.lastReviewed("abc123")
        let body = "Some review body.\n\(marker)\n"
        #expect(BatonMarker.parseLastReviewed(from: body) == "abc123")
        #expect(BatonMarker.parseLastReviewed(from: "no marker") == nil)
    }

    @Test("parseFinding recovers identity from an inline comment body")
    func parseFindingRoundTrip() throws {
        let body = GitHubPresentation.inlineCommentBody(
            Finding(file: "x", line: 9, severity: .high, title: "SQL injection", body: "b", aiInstructions: nil)
        )
        let identity = try #require(BatonMarker.parseFinding(body: body, file: "x.swift", line: 9))
        #expect(identity.title == "SQL injection")
        #expect(identity.severity == .high)
        #expect(identity.file == "x.swift")
        #expect(identity.line == 9)
    }

    @Test("confirmation note appears only for multi-review findings")
    func confirmationNote() {
        let single = Finding(file: "a", line: 1, severity: .low, title: "t", body: "b")
        #expect(GitHubPresentation.confirmationNote(single) == nil)
        let confirmed = Finding(
            file: "a", line: 1, severity: .low, title: "t", body: "b",
            confirmedBy: ["concurrency", "style"]
        )
        let note = GitHubPresentation.confirmationNote(confirmed)
        #expect(note == "Confirmed by 2 reviews: concurrency, style")
    }

    @Test("confirmation note rides in the comment body without breaking finding identity")
    func confirmationNoteParseable() throws {
        let finding = Finding(
            file: "x", line: 9, severity: .high, title: "SQL injection", body: "b",
            confirmedBy: ["security", "style"]
        )
        let body = GitHubPresentation.inlineCommentBody(finding)
        #expect(body.contains("Confirmed by 2 reviews"))
        let identity = try #require(BatonMarker.parseFinding(body: body, file: "x.swift", line: 9))
        #expect(identity.title == "SQL injection") // header/marker contract intact
        #expect(identity.severity == .high)
    }

    @Test("parseFinding returns nil without the marker, header, or a title")
    func parseFindingRejectsNonFindings() {
        #expect(BatonMarker.parseFinding(body: "plain comment", file: "a", line: 1) == nil)
        // Marker present but no `—` header line.
        #expect(BatonMarker.parseFinding(body: "no header\n\(BatonMarker.finding)", file: "a", line: 1) == nil)
        // Header present but the title after the separator is empty.
        #expect(BatonMarker.parseFinding(body: "**🔴 high — **\n\(BatonMarker.finding)", file: "a", line: 1) == nil)
    }

    @Test("parseFinding falls back to medium when no severity token matches")
    func parseFindingSeverityFallback() throws {
        let body = "**Note — something happened**\n\(BatonMarker.finding)"
        let identity = try #require(BatonMarker.parseFinding(body: body, file: "a", line: nil))
        #expect(identity.severity == .medium)
        #expect(identity.title == "something happened")
    }
}

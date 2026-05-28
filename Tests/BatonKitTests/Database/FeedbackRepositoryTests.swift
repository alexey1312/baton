@testable import BatonKit
import Foundation
import Testing

struct FeedbackRepositoryTests {
    private func repo() throws -> FeedbackRepository {
        let db = try BatonDatabase.openInMemory()
        return FeedbackRepository(connection: db.connection)
    }

    private func candidate(file: String, title: String, weight: Int, threads: Int = 1) -> RuleCandidate {
        RuleCandidate(
            finding: FindingIdentity(file: file, line: 1, title: title, severity: .high),
            weight: weight,
            threadCount: threads
        )
    }

    @Test("upsert is idempotent: re-writing the same finding does not accumulate")
    func upsertIdempotent() throws {
        let feedback = try repo()
        let c = candidate(file: "ios/A.swift", title: "rule", weight: -3, threads: 2)
        try feedback.upsert(c, repoId: "r1")
        try feedback.upsert(c, repoId: "r1") // same observation again

        let down = try feedback.mostDownvoted(repoId: "r1")
        #expect(down.count == 1)
        #expect(down.first?.weight == -3)
        #expect(down.first?.threadCount == 2)
    }

    @Test("most-downvoted and most-upvoted are split by sign and ordered by weight")
    func downAndUp() throws {
        let feedback = try repo()
        try feedback.upsertAll([
            candidate(file: "a", title: "worst", weight: -5),
            candidate(file: "b", title: "bad", weight: -2),
            candidate(file: "c", title: "good", weight: 4),
            candidate(file: "d", title: "neutral", weight: 0),
        ], repoId: "r1")

        let down = try feedback.mostDownvoted(repoId: "r1")
        #expect(down.map(\.title) == ["worst", "bad"]) // ascending, negatives only
        let up = try feedback.mostUpvoted(repoId: "r1")
        #expect(up.map(\.title) == ["good"]) // positives only
    }

    @Test("the cache is keyed per repository")
    func perRepo() throws {
        let feedback = try repo()
        try feedback.upsert(candidate(file: "a", title: "x", weight: -1), repoId: "r1")
        try feedback.upsert(candidate(file: "a", title: "x", weight: -9), repoId: "r2")
        #expect(try feedback.mostDownvoted(repoId: "r1").first?.weight == -1)
        #expect(try feedback.mostDownvoted(repoId: "r2").first?.weight == -9)
    }
}

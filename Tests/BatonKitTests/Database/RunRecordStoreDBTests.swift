@testable import BatonKit
import Foundation
import SQLite
import Testing

@Suite(.serialized)
struct RunRecordStoreDBTests {
    @Test("write with a DatabaseHook persists rows to the per-repo SQLite database")
    func writeAlsoPersistsRows() throws {
        let repoRoot = makeTempDir()
        defer { try? FileManager.default.removeItem(at: repoRoot); BatonDatabase._resetForTesting() }

        let store = RunRecordStore(repoRoot: repoRoot)
        // .perRepo only — avoids the shared globalDirectoryOverride mutation.
        let database = RunDatabaseStore(location: .perRepo(repoRoot: repoRoot))
        let hook = RunRecordStore.DatabaseHook(
            store: database,
            repo: RepoIdentity.resolve(repoRoot: repoRoot),
            status: .success,
            cliVersion: "test"
        )
        let task = CompletedTask(
            result: ReviewTaskResult(
                scope: "ios",
                review: "security",
                findings: [Finding(file: "a.swift", line: 1, severity: .high, title: "t", body: "b")],
                failOn: .high,
                durationMs: 1234,
                usage: AgentUsage(inputTokens: 1000, outputTokens: 200, totalCostUSD: 0.01, source: .agentEnvelope),
                agentKind: "claude",
                model: "claude-sonnet-4-6"
            ),
            prompt: "p",
            rawOutput: "raw"
        )

        let runId = RunRecordStore.newRunId()
        try store.write(
            runId: runId, base: "origin/main", headSHA: "sha", tasks: [task], database: hook
        )
        #expect(database.lastErrors().isEmpty)

        let perRepo = try BatonDatabase.open(at: DatabasePathResolver.perRepoDatabaseURL(repoRoot: repoRoot))
        let connection = perRepo.connection
        let runCount = try connection.scalar("SELECT COUNT(*) FROM runs WHERE run_id = ?", runId) as? Int64
        let cost = try connection.scalar("SELECT total_cost_usd FROM runs WHERE run_id = ?", runId) as? Double
        #expect(runCount == 1)
        #expect(cost.map { abs($0 - 0.01) < 0.0001 } == true)
    }

    @Test("newRunId carries the 6-hex collision-avoidance suffix")
    func newRunIdSuffix() {
        let runId = RunRecordStore.newRunId()
        // Shape: 8 + 1 + 6 + 1 + 6 = 22 chars.
        #expect(runId.count == 22)
        let suffix = String(runId.suffix(6))
        #expect(suffix.allSatisfy { $0.isHexDigit })
    }

    // MARK: - Helpers

    private func makeTempDir() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("baton-rr-db-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

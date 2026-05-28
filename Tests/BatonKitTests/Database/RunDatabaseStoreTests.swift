@testable import BatonKit
import Foundation
import SQLite
import Testing

@Suite(.serialized)
struct RunDatabaseStoreTests {
    @Test("recordRun inserts a run, its tasks, and findings; totals aggregate correctly")
    func roundTrip() throws {
        let tempRoot = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        defer { BatonDatabase._resetForTesting() }

        let store = RunDatabaseStore(location: .perRepo(repoRoot: tempRoot))
        let errors = store.recordRun(makeRoundTripInput())
        #expect(errors.isEmpty)

        let database = try BatonDatabase.open(at: DatabasePathResolver.perRepoDatabaseURL(repoRoot: tempRoot))
        let connection = database.connection

        let runCount = try connection.scalar("SELECT COUNT(*) FROM runs") as? Int64
        let taskCount = try connection.scalar("SELECT COUNT(*) FROM tasks") as? Int64
        let findingCount = try connection.scalar("SELECT COUNT(*) FROM findings") as? Int64
        #expect(runCount == 1)
        #expect(taskCount == 2)
        #expect(findingCount == 2)

        let totalsSQL = """
        SELECT total_tasks, total_findings, total_input_tokens,
               total_output_tokens, total_cost_usd, duration_ms, agent_kind
        FROM runs WHERE run_id = ?
        """
        let totals = try #require(
            connection.prepare(totalsSQL, "20260528-143012-aabbcc").makeIterator().next()
        )
        #expect(totals[0] as? Int64 == 2)
        #expect(totals[1] as? Int64 == 2)
        #expect(totals[2] as? Int64 == 1500)
        #expect(totals[3] as? Int64 == 300)
        #expect((totals[4] as? Double).map { abs($0 - 0.018) < 0.0001 } == true)
        #expect(totals[5] as? Int64 == 2034)
        #expect(totals[6] as? String == "claude")
    }

    private func makeRoundTripInput() -> RunRecordInput {
        let identity = RepoIdentity.resolve(repoRoot: URL(fileURLWithPath: "/tmp/example"))
        let iosTask = TaskRecordInput(
            scope: "ios", review: "security", agentKind: "claude", model: "claude-sonnet-4-6",
            durationMs: 1234, inputTokens: 1000, outputTokens: 200, costUSD: 0.012,
            failOn: "high",
            findings: [
                Finding(file: "a.swift", line: 1, severity: .high, title: "boom", body: "..."),
                Finding(file: "b.swift", line: 2, severity: .medium, title: "meh", body: "..."),
            ]
        )
        let webTask = TaskRecordInput(
            scope: "web", review: "lint", agentKind: "claude", model: "claude-sonnet-4-6",
            durationMs: 800, inputTokens: 500, outputTokens: 100, costUSD: 0.006,
            failOn: "medium"
        )
        return RunRecordInput(
            runId: "20260528-143012-aabbcc",
            repo: identity,
            baseRef: "origin/main",
            headSHA: "deadbeef",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            status: .success,
            tasks: [iosTask, webTask],
            cliVersion: "test"
        )
    }

    @Test("recordRun with mixed agent kinds reports 'mixed' on the run")
    func mixedAgentKinds() throws {
        let tempRoot = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        defer { BatonDatabase._resetForTesting() }

        let store = RunDatabaseStore(location: .perRepo(repoRoot: tempRoot))
        let identity = RepoIdentity.resolve(repoRoot: URL(fileURLWithPath: "/tmp/example"))
        let input = RunRecordInput(
            runId: "run-mixed",
            repo: identity,
            baseRef: "main",
            headSHA: "sha",
            createdAt: Date(),
            status: .success,
            tasks: [
                TaskRecordInput(scope: "", review: "a", agentKind: "claude", failOn: "high"),
                TaskRecordInput(scope: "", review: "b", agentKind: "codex", failOn: "high"),
            ]
        )
        let errors = store.recordRun(input)
        #expect(errors.isEmpty)
        let database = try BatonDatabase.open(at: DatabasePathResolver.perRepoDatabaseURL(repoRoot: tempRoot))
        let sql = "SELECT agent_kind FROM runs WHERE run_id = ?"
        let agent = try database.connection.scalar(sql, "run-mixed") as? String
        #expect(agent == "mixed")
    }

    @Test("makeFindingId is stable for the same dedupe key and changes with severity")
    func stableFindingIds() {
        let base = Finding(file: "a.swift", line: 1, severity: .high, title: "t", body: "b")
        let bumped = Finding(file: "a.swift", line: 1, severity: .medium, title: "t", body: "b")
        let id1 = RunDatabaseStore.makeFindingId(taskId: "T", finding: base)
        let id2 = RunDatabaseStore.makeFindingId(taskId: "T", finding: base)
        let id3 = RunDatabaseStore.makeFindingId(taskId: "T", finding: bumped)
        #expect(id1 == id2)
        #expect(id1 != id3)
    }

    // MARK: - Helpers

    private func makeTempDir() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("baton-db-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

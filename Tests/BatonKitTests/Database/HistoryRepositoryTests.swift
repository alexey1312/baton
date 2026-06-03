@testable import BatonKit
import Foundation
import SQLite
import Testing

struct HistoryRepositoryTests {
    @Test("recentRuns returns rows newest-first and honours the limit")
    func recentRuns() throws {
        let database = try BatonDatabase.openInMemory()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        try insertRun(db: database.connection, runId: "r1", createdAt: base)
        try insertRun(db: database.connection, runId: "r2", createdAt: base.addingTimeInterval(60))
        try insertRun(db: database.connection, runId: "r3", createdAt: base.addingTimeInterval(120))

        let history = HistoryRepository(connection: database.connection)
        let runs = try history.recentRuns(repoId: nil, limit: 2)
        #expect(runs.map(\.runId) == ["r3", "r2"])
    }

    @Test("detail returns nil for an unknown runId and the tasks+findings for a known one")
    func detail() throws {
        let database = try BatonDatabase.openInMemory()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        try insertRun(db: database.connection, runId: "r1", createdAt: createdAt)
        try database.connection.run(
            """
            INSERT INTO tasks(task_id, run_id, scope, review, agent_kind, fail_on, finding_count)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            "r1:t1", "r1", "", "security", "claude", "high", Int64(1)
        )
        try database.connection.run(
            """
            INSERT INTO findings(finding_id, task_id, run_id, file, severity, title, body)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            "f1", "r1:t1", "r1", "auth.swift", "high", "boom", "..."
        )

        let history = HistoryRepository(connection: database.connection)
        #expect(try history.detail(runId: "nope") == nil)

        let detail = try #require(try history.detail(runId: "r1"))
        #expect(detail.tasks.count == 1)
        #expect(detail.tasks[0].findings.count == 1)
        #expect(detail.tasks[0].findings[0].severity == "high")
    }

    @Test("detail decodes the confirmed_by JSON column into FindingRow.confirmedBy")
    func confirmedByRoundTrip() throws {
        let database = try BatonDatabase.openInMemory()
        try insertRun(db: database.connection, runId: "r1", createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        try database.connection.run(
            """
            INSERT INTO tasks(task_id, run_id, scope, review, agent_kind, fail_on, finding_count)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            "r1:t1", "r1", "", "security", "claude", "high", Int64(1)
        )
        try database.connection.run(
            """
            INSERT INTO findings(finding_id, task_id, run_id, file, severity, title, body, confirmed_by)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            "f1", "r1:t1", "r1", "auth.swift", "high", "boom", "...", #"["concurrency","style"]"#
        )

        let history = HistoryRepository(connection: database.connection)
        let detail = try #require(try history.detail(runId: "r1"))
        #expect(detail.tasks[0].findings[0].confirmedBy == ["concurrency", "style"])
    }

    private func insertRun(db: Connection, runId: String, createdAt: Date) throws {
        try db.run(
            """
            INSERT INTO runs(run_id, repo_id, repo_root, base_ref, head_sha,
                created_at, status)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            runId, "repo", "/tmp/repo", "main", "sha", createdAt.timeIntervalSince1970, "success"
        )
    }
}

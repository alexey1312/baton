@testable import BatonKit
import Foundation
import SQLite
import Testing

struct StatsRepositoryTests {
    @Test("summary aggregates totals across all runs when no filter is set")
    func summaryAll() throws {
        let database = try BatonDatabase.openInMemory()
        try seedThreeRuns(database.connection)
        let stats = StatsRepository(connection: database.connection)

        let summary = try stats.summary(filter: StatsFilter())
        #expect(summary.totalRuns == 3)
        #expect(summary.totalTasks == 4)
        #expect(summary.totalFindings == 3)
        #expect(summary.totalCostUSD.map { abs($0 - 0.06) < 0.0001 } == true)
    }

    @Test("summary narrows by repoId")
    func summaryByRepo() throws {
        let database = try BatonDatabase.openInMemory()
        try seedThreeRuns(database.connection)
        let stats = StatsRepository(connection: database.connection)

        let summary = try stats.summary(filter: StatsFilter(repoId: "repo-A"))
        #expect(summary.totalRuns == 2)
        #expect(summary.totalCostUSD.map { abs($0 - 0.03) < 0.0001 } == true)
    }

    @Test("byReview groups tasks by review name and counts distinct runs")
    func byReview() throws {
        let database = try BatonDatabase.openInMemory()
        try seedThreeRuns(database.connection)
        let stats = StatsRepository(connection: database.connection)

        let byReview = try stats.byReview(filter: StatsFilter())
        let security = try #require(byReview.first { $0.review == "security" })
        #expect(security.runs == 2)
        #expect(security.findings == 2)
    }

    @Test("bySeverity orders high → medium → low")
    func bySeverity() throws {
        let database = try BatonDatabase.openInMemory()
        try seedThreeRuns(database.connection)
        let stats = StatsRepository(connection: database.connection)

        let bySeverity = try stats.bySeverity(filter: StatsFilter())
        #expect(bySeverity.first?.severity == "high")
    }

    @Test("topFiles surfaces files by finding count")
    func topFiles() throws {
        let database = try BatonDatabase.openInMemory()
        try seedThreeRuns(database.connection)
        let stats = StatsRepository(connection: database.connection)

        let top = try stats.topFiles(filter: StatsFilter(), limit: 5)
        #expect(top.first?.file == "auth.swift")
    }

    // MARK: - Fixtures

    private func seedThreeRuns(_ db: Connection) throws {
        // run-1: repo-A, 1 task (security), 1 finding (high), $0.02
        try insertRun(db: db, RunSeed(runId: "r1", repoId: "repo-A", cost: 0.02, findings: 1, tasks: 1))
        try insertTask(db: db, TaskSeed(
            taskId: "r1:t1", runId: "r1", review: "security", cost: 0.02, findings: 1
        ))
        try insertFinding(db: db, FindingSeed(
            findingId: "f1", taskId: "r1:t1", runId: "r1", file: "auth.swift", severity: "high"
        ))

        // run-2: repo-A, 1 task (security), 1 finding (medium), $0.01
        try insertRun(db: db, RunSeed(runId: "r2", repoId: "repo-A", cost: 0.01, findings: 1, tasks: 1))
        try insertTask(db: db, TaskSeed(
            taskId: "r2:t1", runId: "r2", review: "security", cost: 0.01, findings: 1
        ))
        try insertFinding(db: db, FindingSeed(
            findingId: "f2", taskId: "r2:t1", runId: "r2", file: "auth.swift", severity: "medium"
        ))

        // run-3: repo-B, 2 tasks (lint+style), 1 finding (low), $0.03
        try insertRun(db: db, RunSeed(runId: "r3", repoId: "repo-B", cost: 0.03, findings: 1, tasks: 2))
        try insertTask(db: db, TaskSeed(taskId: "r3:t1", runId: "r3", review: "lint", cost: 0.02, findings: 1))
        try insertTask(db: db, TaskSeed(taskId: "r3:t2", runId: "r3", review: "style", cost: 0.01))
        try insertFinding(db: db, FindingSeed(
            findingId: "f3", taskId: "r3:t1", runId: "r3", file: "view.swift", severity: "low"
        ))
    }

    private struct RunSeed {
        var runId: String
        var repoId: String
        var cost: Double
        var findings: Int
        var tasks: Int
    }

    private struct TaskSeed {
        var taskId: String
        var runId: String
        var review: String
        var cost: Double
        var findings: Int = 0
    }

    private struct FindingSeed {
        var findingId: String
        var taskId: String
        var runId: String
        var file: String
        var severity: String
    }

    private func insertRun(db: Connection, _ seed: RunSeed) throws {
        try db.run(
            """
            INSERT INTO runs(run_id, repo_id, repo_root, base_ref, head_sha,
                created_at, status, total_tasks, total_findings, total_cost_usd, agent_kind)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            seed.runId, seed.repoId, "/tmp/\(seed.repoId)", "main", "sha",
            Date().timeIntervalSince1970, "success",
            Int64(seed.tasks), Int64(seed.findings), seed.cost, "claude"
        )
    }

    private func insertTask(db: Connection, _ seed: TaskSeed) throws {
        try db.run(
            """
            INSERT INTO tasks(task_id, run_id, scope, review, agent_kind, fail_on,
                              cost_usd, duration_ms, finding_count)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            seed.taskId, seed.runId, "", seed.review, "claude", "high",
            seed.cost, Int64(1000), Int64(seed.findings)
        )
    }

    private func insertFinding(db: Connection, _ seed: FindingSeed) throws {
        try db.run(
            """
            INSERT INTO findings(finding_id, task_id, run_id, file, severity, title, body)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            seed.findingId, seed.taskId, seed.runId, seed.file, seed.severity, "t", "b"
        )
    }
}

@testable import BatonKit
import Foundation
import SQLite
import Testing

struct BatonDatabaseTests {
    @Test("openInMemory bootstraps schema v1 with all expected tables and indices")
    func openInMemoryBootstrapsSchema() throws {
        let db = try BatonDatabase.openInMemory()

        let tables = try tableNames(db.connection)
        #expect(tables.contains("meta"))
        #expect(tables.contains("runs"))
        #expect(tables.contains("tasks"))
        #expect(tables.contains("findings"))

        let indices = try indexNames(db.connection)
        for expected in [
            "idx_runs_repo_created",
            "idx_runs_created",
            "idx_tasks_run",
            "idx_tasks_review",
            "idx_tasks_scope",
            "idx_findings_task",
            "idx_findings_run",
            "idx_findings_sev",
            "idx_findings_file",
        ] {
            #expect(indices.contains(expected), "missing index \(expected)")
        }

        #expect(try db.schemaVersion() == 1)
    }

    @Test("foreign_keys pragma is on after open")
    func foreignKeysOn() throws {
        let db = try BatonDatabase.openInMemory()
        let value = try #require(
            db.connection.prepare("PRAGMA foreign_keys").makeIterator().next().flatMap { $0[0] as? Int64 }
        )
        #expect(value == 1)
    }

    @Test("severity CHECK constraint rejects unknown values")
    func severityCheckConstraint() throws {
        let db = try BatonDatabase.openInMemory()
        try seedMinimalRunAndTask(db.connection)

        // Inserting a finding with an unknown severity must fail.
        var threw = false
        do {
            try db.connection.run(
                """
                INSERT INTO findings(finding_id, task_id, run_id, file, severity, title, body)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                "f1", "t1", "r1", "x.swift", "critical", "t", "b"
            )
        } catch {
            threw = true
        }
        #expect(threw)
    }

    @Test("ON DELETE CASCADE removes child rows when a run is deleted")
    func cascadeDeletesChildren() throws {
        let db = try BatonDatabase.openInMemory()
        try seedMinimalRunAndTask(db.connection)
        try db.connection.run(
            """
            INSERT INTO findings(finding_id, task_id, run_id, file, severity, title, body)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            "f1", "t1", "r1", "x.swift", "high", "title", "body"
        )

        try db.connection.run("DELETE FROM runs WHERE run_id = ?", "r1")

        let taskCount = try db.connection.scalar("SELECT COUNT(*) FROM tasks") as? Int64
        let findingCount = try db.connection.scalar("SELECT COUNT(*) FROM findings") as? Int64
        #expect(taskCount == 0)
        #expect(findingCount == 0)
    }

    // MARK: - Helpers

    private func tableNames(_ db: Connection) throws -> Set<String> {
        var names: Set<String> = []
        for row in try db.prepare("SELECT name FROM sqlite_master WHERE type='table'") {
            if let value = row[0] as? String { names.insert(value) }
        }
        return names
    }

    private func indexNames(_ db: Connection) throws -> Set<String> {
        var names: Set<String> = []
        for row in try db.prepare("SELECT name FROM sqlite_master WHERE type='index'") {
            if let value = row[0] as? String { names.insert(value) }
        }
        return names
    }

    private func seedMinimalRunAndTask(_ db: Connection) throws {
        try db.run(
            """
            INSERT INTO runs(run_id, repo_id, repo_root, base_ref, head_sha, created_at, status)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            "r1", "repo-id", "/tmp/repo", "origin/main", "sha", 1.0, "success"
        )
        try db.run(
            """
            INSERT INTO tasks(task_id, run_id, scope, review, agent_kind, fail_on)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            "t1", "r1", "", "security", "claude", "high"
        )
    }
}

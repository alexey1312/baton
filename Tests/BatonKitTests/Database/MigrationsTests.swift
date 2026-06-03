@testable import BatonKit
import Foundation
import SQLite
import Testing

struct MigrationsTests {
    @Test("currentVersion returns 0 on a fresh connection and creates the meta table")
    func currentVersionOnFreshDB() throws {
        let db = try Connection(.inMemory)
        #expect(try Migrations.currentVersion(db) == 0)

        // meta table now exists
        let sql = "SELECT name FROM sqlite_master WHERE type='table' AND name='meta'"
        let row = try db.prepare(sql).makeIterator().next()
        #expect(row != nil)
    }

    @Test("run applies all migrations once and is idempotent on a second call")
    func idempotent() throws {
        let db = try Connection(.inMemory)
        let latest = Migrations.all.map(\.version).max() ?? 0
        try Migrations.run(on: db)
        #expect(try Migrations.currentVersion(db) == latest)

        // Running again must be a no-op (no throw, no version bump).
        try Migrations.run(on: db)
        #expect(try Migrations.currentVersion(db) == latest)
    }

    @Test("the feedback cache table is created by v2")
    func feedbackTableExists() throws {
        let db = try Connection(.inMemory)
        try Migrations.run(on: db)
        let sql = "SELECT name FROM sqlite_master WHERE type='table' AND name='feedback'"
        #expect(try db.prepare(sql).makeIterator().next() != nil)
    }

    @Test("v3 adds the confirmed_by column defaulting to an empty JSON array")
    func confirmedByColumn() throws {
        let db = try Connection(.inMemory)
        try Migrations.run(on: db)
        let columns = try db.prepare("PRAGMA table_info(findings)").compactMap { $0[1] as? String }
        #expect(columns.contains("confirmed_by"))

        try db.run(
            """
            INSERT INTO runs(run_id, repo_id, repo_root, base_ref, head_sha, created_at, status)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            "r", "repo", "/tmp", "main", "sha", 1.0, "success"
        )
        try db.run(
            "INSERT INTO tasks(task_id, run_id, scope, review, agent_kind, fail_on) VALUES (?, ?, ?, ?, ?, ?)",
            "r:t", "r", "", "sec", "claude", "high"
        )
        // An insert that omits confirmed_by (a legacy-shaped write) gets the default.
        try db.run(
            """
            INSERT INTO findings(finding_id, task_id, run_id, file, severity, title, body)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            "f", "r:t", "r", "a.swift", "high", "t", "b"
        )
        let row = try db.prepare("SELECT confirmed_by FROM findings WHERE finding_id = 'f'").makeIterator().next()
        #expect((row?[0] as? String) == "[]")
    }

    @Test("currentVersion throws when schema_version is not an integer")
    func currentVersionRejectsGarbage() throws {
        let db = try Connection(.inMemory)
        // Create the meta table and seed a garbage value.
        _ = try Migrations.currentVersion(db) // ensures meta exists
        try db.run("INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)", "schema_version", "ten")

        #expect(throws: BatonDatabaseError.self) {
            _ = try Migrations.currentVersion(db)
        }
    }
}

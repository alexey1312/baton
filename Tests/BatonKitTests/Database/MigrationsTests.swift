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

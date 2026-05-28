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
        let row = try db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='meta'").makeIterator().next()
        #expect(row != nil)
    }

    @Test("run applies v1 once and is idempotent on a second call")
    func idempotent() throws {
        let db = try Connection(.inMemory)
        try Migrations.run(on: db)
        #expect(try Migrations.currentVersion(db) == 1)

        // Running again must be a no-op (no throw, no version bump).
        try Migrations.run(on: db)
        #expect(try Migrations.currentVersion(db) == 1)
    }
}

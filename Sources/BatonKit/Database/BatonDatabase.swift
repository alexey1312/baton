import Foundation
import SQLite

/// SQLite-backed database that stores Baton run history.
///
/// Thread-safety: SQLite.swift's `Connection` serializes calls internally.
/// We additionally guard the process-wide connection cache with an `NSLock`,
/// so concurrent callers requesting the same path get the same `Connection`.
/// WAL journal mode plus a 3 s `busy_timeout` handle cross-process access
/// (e.g. CI and developer running `baton review` simultaneously).
public final class BatonDatabase: @unchecked Sendable {
    public let path: String
    public let connection: Connection

    private init(path: String, connection: Connection) {
        self.path = path
        self.connection = connection
    }

    // MARK: - Cached open

    private nonisolated(unsafe) static var cache: [String: BatonDatabase] = [:]
    private static let cacheLock = NSLock()

    /// Open (or fetch the cached handle for) the database at `url`.
    /// Runs pragmas and migrations on first open.
    public static func open(at url: URL) throws -> BatonDatabase {
        let path = url.path
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let cached = cache[path] { return cached }

        do {
            try DatabasePathResolver.ensureDirectory(for: url)
            let connection = try Connection(path)
            try applyPragmas(connection)
            try Migrations.run(on: connection)
            let database = BatonDatabase(path: path, connection: connection)
            cache[path] = database
            return database
        } catch let error as BatonDatabaseError {
            throw error
        } catch {
            throw BatonDatabaseError.openFailed(path: path, underlying: "\(error)")
        }
    }

    /// Open an in-memory database (test-only).
    public static func openInMemory() throws -> BatonDatabase {
        do {
            let connection = try Connection(.inMemory)
            try applyPragmas(connection)
            try Migrations.run(on: connection)
            // In-memory databases are not cached: each open gets a fresh instance.
            return BatonDatabase(path: ":memory:", connection: connection)
        } catch let error as BatonDatabaseError {
            throw error
        } catch {
            throw BatonDatabaseError.openFailed(path: ":memory:", underlying: "\(error)")
        }
    }

    /// Drop every cached connection. For tests only.
    public static func _resetForTesting() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        cache.removeAll()
    }

    // MARK: - Pragmas

    private static func applyPragmas(_ db: Connection) throws {
        try db.execute("PRAGMA journal_mode=WAL")
        try db.execute("PRAGMA busy_timeout=3000")
        try db.execute("PRAGMA foreign_keys=ON")
        try db.execute("PRAGMA synchronous=NORMAL")
    }

    // MARK: - Convenience

    /// Current schema version stored in the `meta` table.
    public func schemaVersion() throws -> Int {
        try Migrations.currentVersion(connection)
    }
}

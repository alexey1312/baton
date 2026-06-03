import Foundation
import SQLite

/// A single forward-only schema migration.
public struct Migration: Sendable {
    public let version: Int
    public let sql: String

    public init(version: Int, sql: String) {
        self.version = version
        self.sql = sql
    }
}

/// Versioned migration runner. The `meta` key/value table stores
/// `schema_version` so migrations stay idempotent.
public enum Migrations {
    /// All known migrations, in ascending version order.
    public static let all: [Migration] = [
        Migration(version: 1, sql: ddlV1),
        Migration(version: 2, sql: ddlV2),
        Migration(version: 3, sql: ddlV3),
    ]

    /// Reads the current schema version from `meta`, or `0` if no row exists.
    /// Throws ``BatonDatabaseError.migrationFailed`` when the stored value is
    /// present but not parseable as an `Int` — silently returning `0` in that
    /// case would re-apply every migration over data that the schema_version
    /// row implies has been migrated, producing data loss.
    public static func currentVersion(_ db: Connection) throws -> Int {
        try db.execute("""
        CREATE TABLE IF NOT EXISTS meta(
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        )
        """)
        guard let row = try db.prepare("SELECT value FROM meta WHERE key = 'schema_version'")
            .makeIterator().next()
        else {
            return 0
        }
        guard let value = row[0] as? String else {
            throw BatonDatabaseError.migrationFailed(
                version: -1,
                underlying: "schema_version is not a string"
            )
        }
        guard let version = Int(value) else {
            throw BatonDatabaseError.migrationFailed(
                version: -1,
                underlying: "schema_version is not an integer: \(value)"
            )
        }
        return version
    }

    /// Apply every pending migration in a single transaction per step.
    /// Idempotent: a no-op when the database is already at the latest version.
    public static func run(on db: Connection) throws {
        let current = try currentVersion(db)
        for migration in all where migration.version > current {
            do {
                try db.transaction {
                    try db.execute(migration.sql)
                    try db.run(
                        "INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)",
                        "schema_version", String(migration.version)
                    )
                }
            } catch {
                throw BatonDatabaseError.migrationFailed(version: migration.version, underlying: "\(error)")
            }
        }
    }

    /// Schema v1: runs/tasks/findings plus indices. `events` is deferred to v2.
    private static let ddlV1: String = """
    CREATE TABLE IF NOT EXISTS runs(
        run_id              TEXT PRIMARY KEY,
        repo_id             TEXT NOT NULL,
        repo_root           TEXT NOT NULL,
        repo_label          TEXT,
        base_ref            TEXT NOT NULL,
        head_sha            TEXT NOT NULL,
        created_at          REAL NOT NULL,
        finished_at         REAL,
        duration_ms         INTEGER,
        status              TEXT NOT NULL CHECK(status IN ('success','failed','empty')),
        total_tasks         INTEGER NOT NULL DEFAULT 0,
        total_findings      INTEGER NOT NULL DEFAULT 0,
        total_input_tokens  INTEGER,
        total_output_tokens INTEGER,
        total_cost_usd      REAL,
        agent_kind          TEXT,
        cli_version         TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_runs_repo_created ON runs(repo_id, created_at DESC);
    CREATE INDEX IF NOT EXISTS idx_runs_created ON runs(created_at DESC);

    CREATE TABLE IF NOT EXISTS tasks(
        task_id               TEXT PRIMARY KEY,
        run_id                TEXT NOT NULL REFERENCES runs(run_id) ON DELETE CASCADE,
        scope                 TEXT NOT NULL,
        review                TEXT NOT NULL,
        agent_kind            TEXT NOT NULL,
        model                 TEXT,
        started_at            REAL,
        duration_ms           INTEGER,
        input_tokens          INTEGER,
        output_tokens         INTEGER,
        cost_usd              REAL,
        finding_count         INTEGER NOT NULL DEFAULT 0,
        failed                INTEGER NOT NULL DEFAULT 0,
        error_message         TEXT,
        truncated_files_count INTEGER NOT NULL DEFAULT 0,
        warnings_count        INTEGER NOT NULL DEFAULT 0,
        fail_on               TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_tasks_run ON tasks(run_id);
    CREATE INDEX IF NOT EXISTS idx_tasks_review ON tasks(review);
    CREATE INDEX IF NOT EXISTS idx_tasks_scope ON tasks(scope);

    CREATE TABLE IF NOT EXISTS findings(
        finding_id      TEXT PRIMARY KEY,
        task_id         TEXT NOT NULL REFERENCES tasks(task_id) ON DELETE CASCADE,
        run_id          TEXT NOT NULL REFERENCES runs(run_id) ON DELETE CASCADE,
        file            TEXT NOT NULL,
        line            INTEGER,
        severity        TEXT NOT NULL CHECK(severity IN ('low','medium','high')),
        title           TEXT NOT NULL,
        body            TEXT NOT NULL,
        ai_instructions TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_findings_task ON findings(task_id);
    CREATE INDEX IF NOT EXISTS idx_findings_run ON findings(run_id);
    CREATE INDEX IF NOT EXISTS idx_findings_sev ON findings(severity);
    CREATE INDEX IF NOT EXISTS idx_findings_file ON findings(file);
    """

    /// Schema v2: the optional, non-authoritative `learn` feedback cache, keyed by
    /// finding identity `hash(file, line, title, severity)` per repository. Powers
    /// `baton stats` trends only — never required by a `learn` run.
    private static let ddlV2: String = """
    CREATE TABLE IF NOT EXISTS feedback(
        repo_id      TEXT NOT NULL,
        finding_id   TEXT NOT NULL,
        file         TEXT NOT NULL,
        line         INTEGER,
        title        TEXT NOT NULL,
        severity     TEXT NOT NULL CHECK(severity IN ('low','medium','high')),
        weight       INTEGER NOT NULL DEFAULT 0,
        thread_count INTEGER NOT NULL DEFAULT 0,
        last_seen_at REAL NOT NULL,
        PRIMARY KEY (repo_id, finding_id)
    );
    CREATE INDEX IF NOT EXISTS idx_feedback_repo_weight ON feedback(repo_id, weight);
    """

    /// Schema v3: records the reviews that cross-task dedup folded into a finding,
    /// stored as a JSON array of review names. `'[]'` for single-review findings and
    /// for every row that predates this column.
    private static let ddlV3: String = """
    ALTER TABLE findings ADD COLUMN confirmed_by TEXT NOT NULL DEFAULT '[]';
    """
}

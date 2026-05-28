import Foundation

/// Errors raised by the SQLite-backed run database.
public enum BatonDatabaseError: BatonError {
    case openFailed(path: String, underlying: String)
    case migrationFailed(version: Int, underlying: String)
    case queryFailed(operation: String, underlying: String)

    public var errorDescription: String? {
        switch self {
        case let .openFailed(path, underlying):
            "Failed to open Baton database at \(path): \(underlying)"
        case let .migrationFailed(version, underlying):
            "Failed to migrate Baton database to schema v\(version): \(underlying)"
        case let .queryFailed(operation, underlying):
            "Database operation '\(operation)' failed: \(underlying)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .openFailed:
            "Check that the parent directory is writable and that no other process holds an exclusive lock."
        case .migrationFailed:
            "Inspect the schema_version in the meta table and remove the database file to recreate it."
        case .queryFailed:
            "Re-run with --verbose, or remove the database file to recreate it from scratch."
        }
    }
}

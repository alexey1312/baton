import Foundation

/// Resolves on-disk paths for the run database.
///
/// Tests should set ``globalDirectoryOverride`` (via ``setGlobalDirectoryOverride``)
/// to point at a temp directory so they never touch the real
/// `~/.config/baton/baton.db`.
public enum DatabasePathResolver {
    private nonisolated(unsafe) static var _globalDirectoryOverride: URL?
    private static let overrideLock = NSLock()

    /// Override the global config directory (used by tests).
    public static func setGlobalDirectoryOverride(_ url: URL?) {
        overrideLock.lock()
        defer { overrideLock.unlock() }
        _globalDirectoryOverride = url
    }

    /// Directory containing the per-user global database. Defaults to
    /// `~/.config/baton`. Tests may override via ``setGlobalDirectoryOverride``.
    public static var globalDirectory: URL {
        overrideLock.lock()
        let override = _globalDirectoryOverride
        overrideLock.unlock()
        if let override { return override }
        return FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("baton", isDirectory: true)
    }

    /// Per-user global database file (`~/.config/baton/baton.db`).
    public static var globalDatabaseURL: URL {
        globalDirectory.appendingPathComponent("baton.db")
    }

    /// Per-repo database file (`<repoRoot>/.baton/baton.db`).
    public static func perRepoDatabaseURL(repoRoot: URL) -> URL {
        repoRoot
            .appendingPathComponent(".baton", isDirectory: true)
            .appendingPathComponent("baton.db")
    }

    /// Resolves the set of database files implied by a ``DatabaseLocation``.
    public static func writeTargets(for location: DatabaseLocation) -> [URL] {
        switch location {
        case .global:
            [globalDatabaseURL]
        case let .perRepo(repoRoot):
            [perRepoDatabaseURL(repoRoot: repoRoot)]
        case let .both(repoRoot):
            [globalDatabaseURL, perRepoDatabaseURL(repoRoot: repoRoot)]
        }
    }

    /// Ensures the parent directory exists for a given database file.
    public static func ensureDirectory(for fileURL: URL) throws {
        let dir = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}

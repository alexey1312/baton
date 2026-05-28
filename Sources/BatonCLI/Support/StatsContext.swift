import BatonKit
import Foundation

/// Resolves the database location and repository identity for read-only stats
/// commands (`baton stats`, `history`, `show`).
///
/// Default behaviour: open the per-user global database
/// (`~/.config/baton/baton.db`) and filter by the current repository id.
/// `--all-repos` opens the global database without a repo filter and skips the
/// git-root check (the command may run anywhere).
enum StatsContext {
    /// Resolve the inputs for a stats-family command.
    static func resolve(repo: String?, allRepos: Bool) throws -> Resolved {
        if allRepos {
            // No repo filter, no git check; the global database is the only target.
            let database = try BatonDatabase.open(at: DatabasePathResolver.globalDatabaseURL)
            return Resolved(database: database, repoId: nil, repoRoot: nil)
        }

        let root = try CLISupport.resolveRepoRoot(repo)
        let identity = RepoIdentity.resolve(repoRoot: root)
        let database = try BatonDatabase.open(at: DatabasePathResolver.globalDatabaseURL)
        return Resolved(database: database, repoId: identity.id, repoRoot: root)
    }

    struct Resolved {
        let database: BatonDatabase
        let repoId: String?
        let repoRoot: URL?
    }
}

import Foundation

/// Where the run database lives.
///
/// Baton supports a hybrid layout: a per-user global database under
/// `~/.config/baton/baton.db` (for cross-repo aggregation) and a per-repository
/// database under `<repoRoot>/.baton/baton.db` (for repo-local stats). Most
/// operations write to ``both`` and read from ``global`` by default.
public enum DatabaseLocation: Sendable, Equatable {
    /// Single per-user database at `~/.config/baton/baton.db`.
    case global
    /// Single per-repository database at `<repoRoot>/.baton/baton.db`.
    case perRepo(repoRoot: URL)
    /// Both databases. Writes go to both; reads pick ``global`` unless overridden.
    case both(repoRoot: URL)
}

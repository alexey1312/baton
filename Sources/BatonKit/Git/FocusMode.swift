/// Focus-mode diff: re-runs in CI focus only on changes since the previous Baton
/// review's head SHA on the same pull request.
///
/// Recovering the previous SHA from the PR (Baton-authored Check Runs / review-body
/// marker) is the `github-publish` capability's responsibility — this module simply
/// uses a supplied SHA to compute the focus diff, falling back when the SHA is
/// unreachable in the local repository (e.g. after a force-push).
public enum FocusMode {
    public struct Result: Sendable {
        public var diff: RepoDiff?
        /// Fallback warning when `previousSHA` is missing.
        public var warning: String?
    }

    /// Compute the focus diff against `previousSHA`. Returns `(nil, warning)` when
    /// the SHA is unreachable so the caller can fall back to the full base diff.
    public static func focusDiff(previousSHA: String, git: GitRunner) -> Result {
        if !git.refExists(previousSHA) {
            let msg = "Previous review SHA \(previousSHA) is unreachable; "
                + "falling back to the full base diff."
            return Result(diff: nil, warning: msg)
        }
        do {
            let diff = try DiffCollector(git: git).collect(base: previousSHA, includeUntracked: false)
            return Result(diff: diff, warning: nil)
        } catch {
            let msg = "Failed to compute focus diff: \(error.localizedDescription); "
                + "falling back to the full base diff."
            return Result(diff: nil, warning: msg)
        }
    }
}

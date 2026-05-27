import BatonKit

/// A code-hosting platform Baton can publish a review to.
///
/// The MVP ships a single `GitHubForge` (via the `gh` CLI). The protocol exists so
/// non-GitHub forges (GitLab/Bitbucket) can be added later without touching the
/// orchestration layer. Fleshed out by the `github-publish` capability (Phase 7).
public protocol Forge: Sendable {
    /// Verify the forge's CLI/credentials are usable before publishing.
    func preflight() async throws
}

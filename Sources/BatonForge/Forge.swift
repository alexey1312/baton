import BatonKit

/// A code-hosting platform Baton can publish a review to.
///
/// The MVP ships a single ``GitHubForge`` (via the `gh` CLI). The protocol exists so
/// non-GitHub forges (GitLab/Bitbucket) can be added later without touching the
/// orchestration layer.
public protocol Forge: Sendable {
    /// Verify the forge's CLI/credentials are usable before publishing.
    func preflight() async throws

    /// Publish a saved run to `context`, returning a report of what was posted.
    func publish(run: LoadedRun, context: PublishContext) async throws -> PublishReport
}

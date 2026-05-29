import BatonKit

/// Errors raised while publishing a saved run to a GitHub pull request.
///
/// Every case conforms to ``BatonError`` and carries an actionable
/// ``recoverySuggestion`` so the CLI can render a `→ …` hint.
public enum ForgeError: BatonError {
    /// The `gh` CLI was not found in `PATH`.
    case ghNotFound
    /// `gh` is present but `gh auth status` reports no authenticated session.
    case ghUnauthenticated
    /// Neither overrides nor the environment provided a repository slug + head SHA.
    case repoOrShaUnresolvable
    /// The token lacks write permission for the PR (e.g. a fork PR).
    case writePermissionDenied(detail: String)
    /// The token cannot create Check Runs (a PAT, not a GitHub App token).
    case checkRunForbidden(detail: String)
    /// The token cannot post the auto-resolve reply or invoke `resolveReviewThread`.
    /// Degradable: auto-resolution is best-effort and never fails a publish.
    case threadResolveForbidden(detail: String)
    /// GitHub returned a rate-limit response and retries were exhausted.
    case rateLimited(detail: String)
    /// GitHub returned a 5xx response and retries were exhausted.
    case serverError(detail: String)
    /// A publish step failed for some other reason.
    case publishFailed(detail: String)

    public var errorDescription: String? {
        switch self {
        case .ghNotFound:
            "The `gh` CLI was not found in PATH."
        case .ghUnauthenticated:
            "The `gh` CLI is not authenticated."
        case .repoOrShaUnresolvable:
            "Could not determine the target repository and head SHA."
        case let .writePermissionDenied(detail):
            "GitHub rejected the publish: write permission denied (\(detail))."
        case let .checkRunForbidden(detail):
            "GitHub rejected creating Check Runs: \(detail)."
        case let .threadResolveForbidden(detail):
            "GitHub rejected auto-resolving a review thread: \(detail)."
        case let .rateLimited(detail):
            "GitHub rate-limited the publish after retries (\(detail))."
        case let .serverError(detail):
            "GitHub returned a server error after retries (\(detail))."
        case let .publishFailed(detail):
            "Publishing to GitHub failed: \(detail)."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .ghNotFound:
            "Install the GitHub CLI (https://cli.github.com) so `gh` is on your PATH, then re-run."
        case .ghUnauthenticated:
            "Authenticate with `gh auth login`, or set a token via the GH_TOKEN / GITHUB_TOKEN env var."
        case .repoOrShaUnresolvable:
            "Pass --gh-repo owner/repo and --head-sha <sha>, or run inside GitHub Actions on a PR event."
        case .writePermissionDenied:
            "The token lacks write access — pull requests from forks cannot post comments or Check Runs " +
                "with the default token. Run from a trusted context with a write-scoped token."
        case .checkRunForbidden:
            "The Checks API requires a GitHub App token (the Actions GITHUB_TOKEN). A plain PAT used " +
                "locally cannot create Check Runs; the PR review was still posted."
        case .threadResolveForbidden:
            "The token lacks permission to reply to or resolve review threads; auto-resolution was " +
                "skipped and the review and Check Runs were still posted."
        case .rateLimited:
            "Wait for the rate-limit window to reset (a few minutes) and re-run `baton publish`."
        case .serverError:
            "GitHub may be having an incident — check https://www.githubstatus.com and re-run later."
        case .publishFailed:
            "Inspect the gh error detail above, verify the repo/PR exist, and re-run `baton publish`."
        }
    }
}

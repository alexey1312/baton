import BatonKit
import Foundation

/// Explicit publish overrides, typically sourced from CLI flags
/// (`--gh-repo`, `--head-sha`, `--pr`).
public struct PublishOverrides: Sendable, Equatable {
    public var ghRepo: String?
    public var headSHA: String?
    public var pr: Int?

    public init(ghRepo: String? = nil, headSHA: String? = nil, pr: Int? = nil) {
        self.ghRepo = ghRepo
        self.headSHA = headSHA
        self.pr = pr
    }
}

/// The resolved target of a publish: which repository, commit, and (optionally) PR.
///
/// A repository slug + head SHA with no PR number is valid — only per-`(scope,
/// review)` Check Runs are posted in that case. A missing repository or head SHA is
/// an error (``ForgeError/repoOrShaUnresolvable``).
public struct PublishContext: Sendable, Equatable {
    /// `owner/repo` slug.
    public var repo: String
    /// The head commit SHA to anchor Check Runs (and resolvable comments) to.
    public var headSHA: String
    /// The pull-request number, or `nil` when only Check Runs can be posted.
    public var prNumber: Int?

    public init(repo: String, headSHA: String, prNumber: Int?) {
        self.repo = repo
        self.headSHA = headSHA
        self.prNumber = prNumber
    }

    /// `owner` half of the repo slug.
    public var owner: String {
        String(repo.split(separator: "/").first ?? "")
    }

    /// `repo` half of the repo slug.
    public var name: String {
        String(repo.split(separator: "/").last ?? "")
    }

    /// Whether a PR is known (so a review with inline comments can be posted).
    public var hasPR: Bool {
        prNumber != nil
    }

    /// Resolve the publish target from explicit `overrides`, falling back to the
    /// GitHub Actions `env` context for any field not overridden.
    ///
    /// - Throws: ``ForgeError/repoOrShaUnresolvable`` when a repository slug or head
    ///   SHA cannot be determined from either source.
    public static func resolve(
        overrides: PublishOverrides,
        env: GitHubActionsContext?
    ) throws -> PublishContext {
        let repo = nonEmpty(overrides.ghRepo) ?? nonEmpty(env?.repository)
        let headSHA = nonEmpty(overrides.headSHA) ?? nonEmpty(env?.headSHA)
        let prNumber = overrides.pr ?? env?.prNumber

        guard let repo, let headSHA else {
            throw ForgeError.repoOrShaUnresolvable
        }
        return PublishContext(repo: repo, headSHA: headSHA, prNumber: prNumber)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}

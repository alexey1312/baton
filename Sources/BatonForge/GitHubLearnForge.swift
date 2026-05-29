import BatonKit
import Foundation

/// Reads `learn` usefulness signal from GitHub through the injected ``GHRunning``:
/// merged pull requests in the window, review-thread resolution/outdated state and
/// the resolving actor via GraphQL, and 👍/👎 reactions via the Reactions API.
///
/// Conforms to ``LearnSignalSource`` so the analysis stays testable with a
/// recording `gh` mock — exactly like ``GitHubForge`` publishing.
public struct GitHubLearnForge: LearnSignalSource {
    /// Tuning knobs.
    public struct Options: Sendable {
        public var maxAttempts: Int
        /// Logins whose thread resolution counts as Baton automation, not human
        /// signal. A `[bot]`-suffixed login is also treated as automation.
        public var automationActors: Set<String>

        public init(maxAttempts: Int = 3, automationActors: Set<String> = []) {
            self.maxAttempts = maxAttempts
            self.automationActors = automationActors
        }
    }

    private let gh: GHRunning
    private let repo: String
    private let options: Options
    private let now: @Sendable () -> Date

    public init(
        gh: GHRunning = LiveGHRunner(),
        repo: String,
        options: Options = Options(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.gh = gh
        self.repo = repo
        self.options = options
        self.now = now
    }

    private var owner: String {
        String(repo.split(separator: "/").first ?? "")
    }

    private var name: String {
        String(repo.split(separator: "/").last ?? "")
    }

    // MARK: - Merged pull requests

    public func mergedPullRequests(lookbackDays: Int) async throws -> [MergedPullRequest] {
        let cutoff = now().addingTimeInterval(-Double(lookbackDays) * 86400)
        let path = "/repos/\(repo)/pulls?state=closed&sort=updated&direction=desc&per_page=100"
        let result = try await api(method: "GET", path: path, paginate: true)
        let closed = try LearnAPIBodies.decode([LearnAPIBodies.ClosedPR].self, from: result.stdout)
        return closed.compactMap { pr in
            guard let merged = pr.mergedAt, merged >= cutoff else { return nil }
            return MergedPullRequest(number: pr.number, author: pr.user?.login ?? "", mergedAt: merged)
        }
    }

    // MARK: - Thread signal

    public func threadSignals(for pullRequest: MergedPullRequest) async throws -> [ReviewThreadSignal] {
        let body = try LearnAPIBodies.json(LearnAPIBodies.ReviewThreadsRequest(
            owner: owner, name: name, number: pullRequest.number
        ))
        let result = try await graphql(body)
        let decoded = try LearnAPIBodies.decode(LearnAPIBodies.ThreadsResponse.self, from: result.stdout)
        if let errors = decoded.errors, !errors.isEmpty {
            throw ForgeError.publishFailed(
                detail: "GitHub GraphQL error: " + errors.map(\.message).joined(separator: "; ")
            )
        }
        guard let pr = decoded.data?.repository?.pullRequest else {
            throw ForgeError.publishFailed(detail: "GitHub GraphQL response omitted the pull request payload")
        }
        let prAuthor = pr.author?.login ?? pullRequest.author

        var signals: [ReviewThreadSignal] = []
        for node in pr.reviewThreads.nodes {
            guard let signal = try await makeSignal(node: node, pr: pullRequest, prAuthor: prAuthor) else {
                continue
            }
            signals.append(signal)
        }
        return signals
    }

    private func makeSignal(
        node: LearnAPIBodies.ThreadsResponse.ThreadNode,
        pr: MergedPullRequest,
        prAuthor: String
    ) async throws -> ReviewThreadSignal? {
        guard let comment = node.comments.nodes.first, let file = comment.path else { return nil }
        let body = comment.body ?? ""
        let isBaton = body.contains(BatonMarker.finding)
        let resolution: ThreadResolution = node.isOutdated ? .outdated : (node.isResolved ? .resolved : .unresolved)
        let actor = node.resolvedBy?.login

        var reactions: [Reaction] = []
        if isBaton, let id = comment.databaseId {
            reactions = try await fetchReactions(commentId: id)
        }
        return ReviewThreadSignal(
            threadId: node.id,
            pullRequest: pr.number,
            prAuthor: prAuthor,
            file: file,
            line: comment.line,
            isBatonAuthored: isBaton,
            resolution: resolution,
            resolutionActor: actor,
            resolvedByAutomation: isAutomation(actor),
            reactions: reactions,
            finding: isBaton ? BatonMarker.parseFinding(body: body, file: file, line: comment.line) : nil
        )
    }

    // MARK: - Reactions

    private func fetchReactions(commentId: Int) async throws -> [Reaction] {
        let path = "/repos/\(repo)/pulls/comments/\(commentId)/reactions"
        let result = try await api(method: "GET", path: path, paginate: true)
        let raw = try LearnAPIBodies.decode([LearnAPIBodies.ReactionResponse].self, from: result.stdout)
        return raw.compactMap { reaction in
            let kind: ReactionKind? = switch reaction.content {
            case "+1": .thumbsUp
            case "-1": .thumbsDown
            default: nil
            }
            guard let kind, let login = reaction.user?.login else { return nil }
            return Reaction(kind: kind, author: login)
        }
    }

    // MARK: - Helpers

    private func isAutomation(_ login: String?) -> Bool {
        guard let login else { return false }
        return options.automationActors.contains(login) || login.hasSuffix("[bot]")
    }

    private var client: GHApiClient {
        GHApiClient(gh: gh, maxAttempts: options.maxAttempts)
    }

    private func api(method: String, path: String, paginate: Bool) async throws -> GHResult {
        var args = ["api", "--method", method, path]
        if paginate { args.append("--paginate") }
        return try await client.run(args, stdin: nil, mapError: Self.terminalError)
    }

    private func graphql(_ body: String) async throws -> GHResult {
        try await client.run(["api", "graphql", "--input", "-"], stdin: body, mapError: Self.terminalError)
    }

    /// Signal reads have no degrade path: any terminal failure is a hard error.
    private static func terminalError(_ result: GHResult) -> ForgeError {
        .publishFailed(detail: GHApiClient.errorText(result))
    }
}

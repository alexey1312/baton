import Foundation

/// A 👍 / 👎 reaction left on a Baton finding comment.
public enum ReactionKind: String, Sendable, Equatable, Codable {
    case thumbsUp
    case thumbsDown
}

/// One reaction with its author login, so a pull-request author's own reaction
/// can be excluded from the usefulness signal.
public struct Reaction: Sendable, Equatable, Codable {
    public var kind: ReactionKind
    public var author: String

    public init(kind: ReactionKind, author: String) {
        self.kind = kind
        self.author = author
    }
}

/// The GitHub resolution state of a review thread. `outdated` takes precedence
/// over resolved/unresolved when GitHub flags a thread's anchor as outdated.
public enum ThreadResolution: String, Sendable, Equatable, Codable {
    case resolved
    case unresolved
    case outdated
}

/// Identity of a finding the way `learn` reasons about a "rule": the file, line,
/// title, and severity of the Baton finding a thread was anchored to. Also the
/// key used by the optional local feedback cache.
public struct FindingIdentity: Sendable, Equatable, Hashable, Codable {
    public var file: String
    public var line: Int?
    public var title: String
    public var severity: Severity

    public init(file: String, line: Int?, title: String, severity: Severity) {
        self.file = file
        self.line = line
        self.title = title
        self.severity = severity
    }

    /// Stable identity hash over `(file, line, title, severity)` used to key the
    /// optional local feedback cache.
    public var cacheKey: String {
        let lineText = line.map(String.init) ?? "_"
        let raw = "\(file)|\(lineText)|\(title)|\(severity.rawValue)"
        return RepoIdentity.leftPadHex(FNV1a.hash(raw), width: 16)
    }
}

/// A merged pull request inside the lookback window.
public struct MergedPullRequest: Sendable, Equatable {
    public var number: Int
    public var author: String
    public var mergedAt: Date

    public init(number: Int, author: String, mergedAt: Date) {
        self.number = number
        self.author = author
        self.mergedAt = mergedAt
    }
}

/// One review thread observed on a merged pull request: either Baton-authored
/// (identified by the `<!-- baton:finding -->` marker) or human-authored.
public struct ReviewThreadSignal: Sendable, Equatable {
    public var threadId: String
    public var pullRequest: Int
    /// The login of the pull request's author, so self-reactions can be excluded.
    public var prAuthor: String
    public var file: String
    public var line: Int?
    /// Whether the thread's comment carries the `<!-- baton:finding -->` marker.
    public var isBatonAuthored: Bool
    public var resolution: ThreadResolution
    /// The login that resolved the thread (nil when unresolved), captured so a
    /// resolution produced by Baton's own automation can be excluded.
    public var resolutionActor: String?
    /// True when the resolution was produced by Baton's own `resolveReviewThread`
    /// automation rather than a human actor.
    public var resolvedByAutomation: Bool
    public var reactions: [Reaction]
    /// The Baton finding this thread anchored to, when parseable.
    public var finding: FindingIdentity?

    public init(
        threadId: String,
        pullRequest: Int,
        prAuthor: String,
        file: String,
        line: Int?,
        isBatonAuthored: Bool,
        resolution: ThreadResolution,
        resolutionActor: String? = nil,
        resolvedByAutomation: Bool = false,
        reactions: [Reaction] = [],
        finding: FindingIdentity? = nil
    ) {
        self.threadId = threadId
        self.pullRequest = pullRequest
        self.prAuthor = prAuthor
        self.file = file
        self.line = line
        self.isBatonAuthored = isBatonAuthored
        self.resolution = resolution
        self.resolutionActor = resolutionActor
        self.resolvedByAutomation = resolvedByAutomation
        self.reactions = reactions
        self.finding = finding
    }

    /// Net reaction weight (+1 per 👍, −1 per 👎), excluding the pull request
    /// author's own reactions so a self-reaction cannot manufacture signal.
    public var netReactionWeight: Int {
        reactions.reduce(0) { total, reaction in
            guard reaction.author != prAuthor else { return total }
            return total + (reaction.kind == .thumbsUp ? 1 : -1)
        }
    }
}

/// Reads usefulness signal from a code-hosting platform. Implemented by
/// `BatonForge.GitHubLearnForge` and abstracted here so the `learn` analysis
/// stays unit-testable without the network (mirrors `ReviewAgentRunning`).
public protocol LearnSignalSource: Sendable {
    /// Pull requests merged within the last `lookbackDays` days.
    func mergedPullRequests(lookbackDays: Int) async throws -> [MergedPullRequest]

    /// Review-thread signal for one merged pull request.
    func threadSignals(for pullRequest: MergedPullRequest) async throws -> [ReviewThreadSignal]
}

public extension LearnSignalSource {
    /// Collect every thread signal across all PRs merged within the window.
    func collectSignal(lookbackDays: Int) async throws -> [ReviewThreadSignal] {
        let prs = try await mergedPullRequests(lookbackDays: lookbackDays)
        var signals: [ReviewThreadSignal] = []
        for pr in prs {
            signals += try await threadSignals(for: pr)
        }
        return signals
    }
}

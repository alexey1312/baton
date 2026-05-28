import Foundation

/// The inputs for opening or updating the single rolling `learn` pull request.
public struct LearnDeliveryRequest: Sendable, Equatable {
    public var repo: String
    public var branch: String
    public var base: String?
    public var title: String
    public var body: String
    public var draft: Bool
    public var reviewers: [String]
    public var teamReviewers: [String]
    public var labels: [String]

    public init(
        repo: String,
        branch: String,
        base: String? = nil,
        title: String,
        body: String,
        draft: Bool = true,
        reviewers: [String] = [],
        teamReviewers: [String] = [],
        labels: [String] = []
    ) {
        self.repo = repo
        self.branch = branch
        self.base = base
        self.title = title
        self.body = body
        self.draft = draft
        self.reviewers = reviewers
        self.teamReviewers = teamReviewers
        self.labels = labels
    }
}

/// What a delivery attempt did. The outcomes are mutually exclusive, so they are
/// modeled as a sum type rather than independent booleans that could contradict
/// each other (e.g. both `created` and `updated`).
public struct LearnDeliveryReport: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        case created(Int)
        case updated(Int)
        /// The token could not open/update the PR and the run fell back to preview.
        case degradedToPreview
    }

    public var outcome: Outcome
    public var warnings: [String]

    public init(outcome: Outcome, warnings: [String] = []) {
        self.outcome = outcome
        self.warnings = warnings
    }

    public var pullRequestNumber: Int? {
        switch outcome {
        case let .created(number), let .updated(number): number
        case .degradedToPreview: nil
        }
    }

    public var created: Bool {
        if case .created = outcome { true } else { false }
    }

    public var updated: Bool {
        if case .updated = outcome { true } else { false }
    }

    public var degradedToPreview: Bool {
        if case .degradedToPreview = outcome { true } else { false }
    }
}

/// Opens or updates the rolling `learn` pull request. Implemented by
/// `BatonForge.GitHubLearnDelivery`; abstracted here so the delivery decision
/// (create vs. update vs. degrade) stays unit-testable without the network.
public protocol LearnDelivering: Sendable {
    func deliver(_ request: LearnDeliveryRequest) async throws -> LearnDeliveryReport
}

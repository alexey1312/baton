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

/// What a delivery attempt did.
public struct LearnDeliveryReport: Sendable, Equatable {
    public var pullRequestNumber: Int?
    public var created: Bool
    public var updated: Bool
    /// True when the token could not open/update the PR and the run degraded to preview.
    public var degradedToPreview: Bool
    public var warnings: [String]

    public init(
        pullRequestNumber: Int? = nil,
        created: Bool = false,
        updated: Bool = false,
        degradedToPreview: Bool = false,
        warnings: [String] = []
    ) {
        self.pullRequestNumber = pullRequestNumber
        self.created = created
        self.updated = updated
        self.degradedToPreview = degradedToPreview
        self.warnings = warnings
    }
}

/// Opens or updates the rolling `learn` pull request. Implemented by
/// `BatonForge.GitHubLearnDelivery`; abstracted here so the delivery decision
/// (create vs. update vs. degrade) stays unit-testable without the network.
public protocol LearnDelivering: Sendable {
    func deliver(_ request: LearnDeliveryRequest) async throws -> LearnDeliveryReport
}

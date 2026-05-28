/// A summary of what a publish posted to a pull request.
public struct PublishReport: Sendable, Equatable {
    /// Inline review comments posted in the single PR review.
    public var inlineCommentsPosted: Int
    /// Inline comments skipped because an identical Baton comment already existed.
    public var inlineCommentsDeduped: Int
    /// Findings folded into Check Run summaries (no line, outside diff, stale head,
    /// or over the per-review cap).
    public var findingsFoldedIntoSummary: Int
    /// Check Runs created (one per `(scope, review)`).
    public var checkRunsCreated: Int
    /// Check Runs skipped because the token cannot create them (PAT, not App token).
    public var checkRunsSkipped: Int
    /// Whether a PR review was posted (false when no PR or no inline comments).
    public var reviewPosted: Bool
    /// Non-fatal warnings (stale head, degraded Check Runs, …).
    public var warnings: [String]

    public init(
        inlineCommentsPosted: Int = 0,
        inlineCommentsDeduped: Int = 0,
        findingsFoldedIntoSummary: Int = 0,
        checkRunsCreated: Int = 0,
        checkRunsSkipped: Int = 0,
        reviewPosted: Bool = false,
        warnings: [String] = []
    ) {
        self.inlineCommentsPosted = inlineCommentsPosted
        self.inlineCommentsDeduped = inlineCommentsDeduped
        self.findingsFoldedIntoSummary = findingsFoldedIntoSummary
        self.checkRunsCreated = checkRunsCreated
        self.checkRunsSkipped = checkRunsSkipped
        self.reviewPosted = reviewPosted
        self.warnings = warnings
    }
}

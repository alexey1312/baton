import ArgumentParser

/// Output formats for `baton render`.
enum RenderFormat: String, CaseIterable, ExpressibleByArgument {
    case terminal
    case markdown
    case json
    case githubReview = "github-review"
    case checkRun = "check-run"
    case githubSummary = "github-summary"

    /// Whether the format anchors comments to a commit and therefore needs a head SHA.
    var requiresHeadSHA: Bool {
        self == .githubReview || self == .checkRun
    }

    /// Whether a user `--template` may override this format. Only the human-facing
    /// `markdown` report is templatable; the GitHub formats keep their required
    /// marker, reaction affordance, and AI block built in code (Shape A).
    var supportsTemplate: Bool {
        self == .markdown
    }
}

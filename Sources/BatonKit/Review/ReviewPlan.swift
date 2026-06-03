import Foundation

/// One scope's input to orchestration: its effective config, the files it owns, and
/// the on-disk directory used to resolve skills and `prompt_file`.
public struct ScopePlan: Sendable {
    public var config: EffectiveConfig
    public var files: [FileChange]
    public var configDir: URL

    public init(config: EffectiveConfig, files: [FileChange], configDir: URL) {
        self.config = config
        self.files = files
        self.configDir = configDir
    }

    /// Repo-relative scope path (`""` for the root).
    public var scopePath: String {
        config.scopePath
    }
}

/// The result of running one `(scope, review)` task.
public struct ReviewTaskResult: Sendable, Codable {
    public var scope: String
    public var review: String
    public var findings: [Finding]
    /// The review's effective `fail_on` threshold.
    public var failOn: Severity
    /// True when the task itself errored (agent failure, parse failure, …).
    public var taskFailed: Bool
    public var errorMessage: String?
    public var warnings: [String]
    /// Files marked truncated by chunking.
    public var truncatedFiles: [String]
    /// Total wall-clock time spent across all chunks of this task, in ms.
    /// Optional so legacy on-disk run records still decode.
    public var durationMs: Int?
    /// Token and cost accounting summed across all chunks. Optional for the
    /// same reason; nil means no chunk emitted parseable usage.
    public var usage: AgentUsage?
    /// The resolved agent kind for this task (e.g. `claude`). Optional for
    /// backwards-compat with run records written before this field existed.
    public var agentKind: String?
    /// The resolved model for this task, if one was set. Optional.
    public var model: String?
    /// Set by cross-task dedup when a finding that crossed this review's `failOn`
    /// was merged away into a sibling review. Keeps `failed` (and thus the run's
    /// exit code) from being softened by deduplication. Optional on decode so
    /// legacy run records still load.
    public var removedCrossingFindings: Bool

    public init(
        scope: String,
        review: String,
        findings: [Finding],
        failOn: Severity,
        taskFailed: Bool = false,
        errorMessage: String? = nil,
        warnings: [String] = [],
        truncatedFiles: [String] = [],
        durationMs: Int? = nil,
        usage: AgentUsage? = nil,
        agentKind: String? = nil,
        model: String? = nil,
        removedCrossingFindings: Bool = false
    ) {
        self.scope = scope
        self.review = review
        self.findings = findings
        self.failOn = failOn
        self.taskFailed = taskFailed
        self.errorMessage = errorMessage
        self.warnings = warnings
        self.truncatedFiles = truncatedFiles
        self.durationMs = durationMs
        self.usage = usage
        self.agentKind = agentKind
        self.model = model
        self.removedCrossingFindings = removedCrossingFindings
    }

    /// Custom decode so records predating `removedCrossingFindings` still load. Keeps
    /// the existing strictness for fields that were always required. `encode` stays
    /// synthesized (keys are the property names, unchanged on disk).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scope = try container.decode(String.self, forKey: .scope)
        review = try container.decode(String.self, forKey: .review)
        findings = try container.decode([Finding].self, forKey: .findings)
        failOn = try container.decode(Severity.self, forKey: .failOn)
        taskFailed = try container.decode(Bool.self, forKey: .taskFailed)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        warnings = try container.decode([String].self, forKey: .warnings)
        truncatedFiles = try container.decode([String].self, forKey: .truncatedFiles)
        durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs)
        usage = try container.decodeIfPresent(AgentUsage.self, forKey: .usage)
        agentKind = try container.decodeIfPresent(String.self, forKey: .agentKind)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        removedCrossingFindings = try container.decodeIfPresent(Bool.self, forKey: .removedCrossingFindings) ?? false
    }

    /// Whether this review failed under its `fail_on` threshold: any finding at or
    /// above `failOn`, a task error, or a threshold-crossing finding that cross-task
    /// dedup merged into a sibling review.
    public var failed: Bool {
        if taskFailed { return true }
        if removedCrossingFindings { return true }
        return findings.contains { $0.severity >= failOn }
    }

    /// The highest finding severity, if any.
    public var maxSeverity: Severity? {
        findings.map(\.severity).max()
    }
}

/// The aggregate result of a review run.
public struct ReviewOutcome: Sendable {
    public var results: [ReviewTaskResult]
    public var warnings: [String]

    public init(results: [ReviewTaskResult], warnings: [String] = []) {
        self.results = results
        self.warnings = warnings
    }

    /// All findings across tasks.
    public var allFindings: [Finding] {
        results.flatMap(\.findings)
    }

    /// Non-zero exit semantics: any review failed under its `fail_on`.
    public var shouldFailExit: Bool {
        results.contains(where: \.failed)
    }
}

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
        model: String? = nil
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
    }

    /// Whether this review failed under its `fail_on` threshold: any finding at or
    /// above `failOn`, or a task error.
    public var failed: Bool {
        if taskFailed { return true }
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

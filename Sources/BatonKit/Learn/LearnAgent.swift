import Foundation

/// One per-scope learning pass: the scope's effective agent/skills plus the
/// signal the agent should reason about. Mirrors `ReviewAgentRequest`.
public struct LearnAgentRequest: Sendable {
    public var scopePath: String
    public var configDir: URL
    public var agent: AgentConfig
    public var skills: [SkillConfig]
    public var defaults: EffectiveDefaults
    public var security: SecurityConfig?
    public var model: String?
    public var repoRoot: URL
    public var candidates: [RuleCandidate]
    public var bucketCounts: [ThreadBucket: Int]
    public var missingCoverage: [ReviewThreadSignal]

    public init(
        scopePath: String,
        configDir: URL,
        agent: AgentConfig,
        skills: [SkillConfig],
        defaults: EffectiveDefaults,
        security: SecurityConfig?,
        model: String?,
        repoRoot: URL,
        candidates: [RuleCandidate],
        bucketCounts: [ThreadBucket: Int],
        missingCoverage: [ReviewThreadSignal]
    ) {
        self.scopePath = scopePath
        self.configDir = configDir
        self.agent = agent
        self.skills = skills
        self.defaults = defaults
        self.security = security
        self.model = model
        self.repoRoot = repoRoot
        self.candidates = candidates
        self.bucketCounts = bucketCounts
        self.missingCoverage = missingCoverage
    }
}

/// The result of one learning pass: the file changes the agent produced (before
/// allowlist enforcement) plus diagnostics.
public struct LearnAgentOutcome: Sendable {
    public var edits: [ProposedEdit]
    public var rawOutput: String
    public var warnings: [String]
    public var usage: AgentUsage?

    public init(
        edits: [ProposedEdit],
        rawOutput: String = "",
        warnings: [String] = [],
        usage: AgentUsage? = nil
    ) {
        self.edits = edits
        self.rawOutput = rawOutput
        self.warnings = warnings
        self.usage = usage
    }
}

/// Runs one per-scope learning pass and returns the file changes the agent made.
/// Abstracted so the engine is unit-testable without spawning processes (mirrors
/// `ReviewAgentRunning`).
public protocol LearnAgentRunning: Sendable {
    func proposeEdits(_ request: LearnAgentRequest) async throws -> LearnAgentOutcome
}

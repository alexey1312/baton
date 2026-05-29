import Foundation

/// One scope's resolved plan for a learning pass.
public struct LearnScopePlan: Sendable {
    public var scope: ScopeConfig
    public var effective: EffectiveConfig
    public var configDir: URL
    /// Repo-relative local skill directories this scope may edit (allowlist).
    public var localSkillDirs: [String]

    public init(scope: ScopeConfig, effective: EffectiveConfig, configDir: URL, localSkillDirs: [String] = []) {
        self.scope = scope
        self.effective = effective
        self.configDir = configDir
        self.localSkillDirs = localSkillDirs
    }
}

/// A proposed set of review-setup edits for one scope, post-allowlist.
public struct ScopeProposal: Sendable {
    public var scopePath: String
    public var edits: [ProposedEdit]
    public var droppedPaths: [String]
    public var candidates: [RuleCandidate]
    public var bucketCounts: [ThreadBucket: Int]
    public var signalVolume: Int
    public var rawOutput: String

    public init(
        scopePath: String,
        edits: [ProposedEdit],
        droppedPaths: [String],
        candidates: [RuleCandidate],
        bucketCounts: [ThreadBucket: Int],
        signalVolume: Int,
        rawOutput: String = ""
    ) {
        self.scopePath = scopePath
        self.edits = edits
        self.droppedPaths = droppedPaths
        self.candidates = candidates
        self.bucketCounts = bucketCounts
        self.signalVolume = signalVolume
        self.rawOutput = rawOutput
    }
}

/// Why a scope produced no proposal.
public enum ScopeSkipReason: Sendable, Equatable {
    case disabled
    case belowMinSignal(volume: Int, required: Int)
}

/// A scope skipped during a learning pass.
public struct ScopeSkip: Sendable, Equatable {
    public var scopePath: String
    public var reason: ScopeSkipReason

    public init(scopePath: String, reason: ScopeSkipReason) {
        self.scopePath = scopePath
        self.reason = reason
    }
}

/// The result of a full learning pass over a repository.
public struct LearnRunResult: Sendable {
    public var proposals: [ScopeProposal]
    public var skipped: [ScopeSkip]
    /// Candidates across every enabled scope, for `baton stats` and the cache.
    public var allCandidates: [RuleCandidate]
    public var warnings: [String]

    public init(
        proposals: [ScopeProposal] = [],
        skipped: [ScopeSkip] = [],
        allCandidates: [RuleCandidate] = [],
        warnings: [String] = []
    ) {
        self.proposals = proposals
        self.skipped = skipped
        self.allCandidates = allCandidates
        self.warnings = warnings
    }
}

/// Drives the stateless, per-scope learning pass: attribute → gate → analyze →
/// agent → allowlist. Requires no persisted local state; the signal it consumes
/// is read fresh from GitHub by the caller, and delivery (one rolling PR) makes a
/// re-run idempotent.
public struct LearnEngine: Sendable {
    private let agent: any LearnAgentRunning

    public init(agent: any LearnAgentRunning) {
        self.agent = agent
    }

    /// Run the learning pass over `plans` against `signals`, in `repoRoot`.
    public func run(
        plans: [LearnScopePlan],
        signals: [ReviewThreadSignal],
        repoRoot: URL
    ) async throws -> LearnRunResult {
        let scopes = plans.map(\.scope)
        let attributed = SignalAnalysis.attribute(signals, scopes: scopes)
        var result = LearnRunResult()

        for plan in plans {
            // A disabled scope is skipped entirely and collects no signal.
            guard plan.effective.learn.enabled else {
                result.skipped.append(ScopeSkip(scopePath: plan.scope.path, reason: .disabled))
                continue
            }
            let threads = attributed[plan.scope.path] ?? []
            result.allCandidates += SignalAnalysis.candidates(threads)
            try await process(plan: plan, threads: threads, repoRoot: repoRoot, into: &result)
        }
        return result
    }

    // MARK: - Per-scope

    private func process(
        plan: LearnScopePlan,
        threads: [ReviewThreadSignal],
        repoRoot: URL,
        into result: inout LearnRunResult
    ) async throws {
        let minSignal = plan.effective.learn.minSignal
        let volume = SignalAnalysis.signalVolume(threads)
        let humanThreads = SignalAnalysis.humanAuthoredThreads(threads)
        let meetsThreshold = volume >= minSignal

        // Gate proposals on Baton-thread volume, but still run for missing-coverage
        // signal from human-authored threads.
        guard meetsThreshold || !humanThreads.isEmpty else {
            result.skipped.append(ScopeSkip(
                scopePath: plan.scope.path,
                reason: .belowMinSignal(volume: volume, required: minSignal)
            ))
            return
        }

        let candidates = meetsThreshold ? SignalAnalysis.candidates(threads) : []
        let outcome = try await agent.proposeEdits(makeRequest(
            plan: plan, repoRoot: repoRoot,
            candidates: candidates, threads: threads, missingCoverage: humanThreads
        ))

        let allowlist = EditAllowlist(scopePath: plan.scope.path, localSkillDirs: plan.localSkillDirs)
        let allowed = allowlist.filter(outcome.edits)
        let allowedPaths = Set(allowed.map(\.path))
        let dropped = outcome.edits.map(\.path).filter { !allowedPaths.contains($0) }

        result.warnings += outcome.warnings
        result.proposals.append(ScopeProposal(
            scopePath: plan.scope.path,
            edits: allowed,
            droppedPaths: dropped,
            candidates: candidates,
            bucketCounts: SignalAnalysis.bucketCounts(threads),
            signalVolume: volume,
            rawOutput: outcome.rawOutput
        ))
    }

    private func makeRequest(
        plan: LearnScopePlan,
        repoRoot: URL,
        candidates: [RuleCandidate],
        threads: [ReviewThreadSignal],
        missingCoverage: [ReviewThreadSignal]
    ) -> LearnAgentRequest {
        let effective = plan.effective
        let agentConfig = effective.agent ?? AgentConfig(kind: .claude)
        return LearnAgentRequest(
            scopePath: plan.scope.path,
            configDir: plan.configDir,
            agent: agentConfig,
            skills: effective.skills,
            defaults: effective.defaults,
            security: effective.security,
            model: agentConfig.model,
            repoRoot: repoRoot,
            localSkillDirs: plan.localSkillDirs,
            candidates: candidates,
            bucketCounts: SignalAnalysis.bucketCounts(threads),
            missingCoverage: missingCoverage
        )
    }
}

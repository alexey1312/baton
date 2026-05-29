@testable import BatonKit
import Foundation
import Testing

struct LearnEngineTests {
    /// A recording agent that returns canned edits and captures each request.
    actor MockLearnAgent: LearnAgentRunning {
        private let edits: @Sendable (LearnAgentRequest) -> [ProposedEdit]
        private(set) var requests: [LearnAgentRequest] = []

        init(_ edits: @escaping @Sendable (LearnAgentRequest) -> [ProposedEdit]) {
            self.edits = edits
        }

        func proposeEdits(_ request: LearnAgentRequest) async throws -> LearnAgentOutcome {
            requests.append(request)
            return LearnAgentOutcome(edits: edits(request))
        }
    }

    private let repoRoot = URL(fileURLWithPath: "/tmp/repo")

    private func scope(_ path: String) -> ScopeConfig {
        ScopeConfig(
            path: path,
            configPath: path.isEmpty ? "baton.toml" : "\(path)/baton.toml",
            config: BatonConfig(agent: AgentConfig(kind: .claude))
        )
    }

    private func plan(
        _ path: String,
        learn: EffectiveLearn = EffectiveLearn(),
        skillDirs: [String] = []
    ) -> LearnScopePlan {
        LearnScopePlan(
            scope: scope(path),
            effective: EffectiveConfig(
                scopePath: path, agent: AgentConfig(kind: .claude), defaults: EffectiveDefaults(),
                skills: [], reviews: [], security: nil, learn: learn, provenance: ConfigProvenance()
            ),
            configDir: repoRoot,
            localSkillDirs: skillDirs
        )
    }

    private func batonThread(
        file: String,
        resolution: ThreadResolution = .unresolved,
        down: Int = 0
    ) -> ReviewThreadSignal {
        ReviewThreadSignal(
            threadId: file, pullRequest: 1, prAuthor: "author", file: file, line: 1,
            isBatonAuthored: true, resolution: resolution,
            reactions: Array(repeating: Reaction(kind: .thumbsDown, author: "bob"), count: down),
            finding: FindingIdentity(file: file, line: 1, title: "rule", severity: .high)
        )
    }

    private func humanThread(file: String) -> ReviewThreadSignal {
        ReviewThreadSignal(
            threadId: file, pullRequest: 1, prAuthor: "author", file: file, line: 1,
            isBatonAuthored: false, resolution: .unresolved
        )
    }

    // MARK: - Gating

    @Test("below-threshold scope yields no proposal")
    func belowThreshold() async throws {
        let agent = MockLearnAgent { _ in [ProposedEdit(path: "ios/baton.toml", newContents: "x")] }
        let engine = LearnEngine(agent: agent)
        let learn = EffectiveLearn(minSignal: 3)
        let result = try await engine.run(
            plans: [plan("ios", learn: learn)],
            signals: [batonThread(file: "ios/A.swift")], // volume 1 < 3
            repoRoot: repoRoot
        )
        #expect(result.proposals.isEmpty)
        #expect(result.skipped.first?.reason == .belowMinSignal(volume: 1, required: 3))
        #expect(await agent.requests.isEmpty)
    }

    @Test("net-negative scope at/above volume is NOT skipped")
    func negativeNotSkipped() async throws {
        let agent = MockLearnAgent { _ in [ProposedEdit(path: "ios/baton.toml", newContents: "x")] }
        let engine = LearnEngine(agent: agent)
        let learn = EffectiveLearn(minSignal: 2)
        // Two Baton threads, both heavily downvoted → net-negative but volume 2 ≥ 2.
        let result = try await engine.run(
            plans: [plan("ios", learn: learn)],
            signals: [
                batonThread(file: "ios/A.swift", down: 3),
                batonThread(file: "ios/B.swift", down: 3),
            ],
            repoRoot: repoRoot
        )
        #expect(result.skipped.isEmpty)
        #expect(result.proposals.first?.edits.count == 1)
        #expect(result.proposals.first?.candidates.allSatisfy { $0.direction == .relax } == true)
    }

    @Test("disabled scope is skipped and collects no signal")
    func disabledSkipped() async throws {
        let agent = MockLearnAgent { _ in [] }
        let engine = LearnEngine(agent: agent)
        let result = try await engine.run(
            plans: [plan("ios", learn: EffectiveLearn(enabled: false))],
            signals: [batonThread(file: "ios/A.swift")],
            repoRoot: repoRoot
        )
        #expect(result.skipped.first?.reason == .disabled)
        #expect(result.allCandidates.isEmpty) // no signal collected for it
        #expect(await agent.requests.isEmpty)
    }

    // MARK: - Allowlist enforcement

    @Test("out-of-allowlist changes are dropped even when the agent emits them")
    func dropsOutOfAllowlist() async throws {
        let agent = MockLearnAgent { _ in
            [
                ProposedEdit(path: "ios/baton.toml", newContents: "ok"),
                ProposedEdit(path: "ios/Sources/App.swift", newContents: "nope"),
            ]
        }
        let engine = LearnEngine(agent: agent)
        let result = try await engine.run(
            plans: [plan("ios", learn: EffectiveLearn(minSignal: 1))],
            signals: [batonThread(file: "ios/A.swift")],
            repoRoot: repoRoot
        )
        let proposal = try #require(result.proposals.first)
        #expect(proposal.edits.map(\.path) == ["ios/baton.toml"])
        #expect(proposal.droppedPaths == ["ios/Sources/App.swift"])
    }

    // MARK: - Missing coverage

    @Test("human-authored threads feed the agent and allow a coverage proposal even below min_signal")
    func missingCoverage() async throws {
        // Agent adds coverage only when it sees missing-coverage signal.
        let agent = MockLearnAgent { request in
            request.missingCoverage.isEmpty
                ? []
                : [ProposedEdit(path: "ios/baton.toml", newContents: "[[reviews]]")]
        }
        let engine = LearnEngine(agent: agent)
        // No Baton threads (volume 0) but two human threads → still runs for coverage.
        let result = try await engine.run(
            plans: [plan("ios", learn: EffectiveLearn(minSignal: 1))],
            signals: [humanThread(file: "ios/A.swift"), humanThread(file: "ios/B.swift")],
            repoRoot: repoRoot
        )
        #expect(result.proposals.first?.edits.first?.path == "ios/baton.toml")
        let request = try #require(await agent.requests.first)
        #expect(request.missingCoverage.count == 2)
        #expect(request.candidates.isEmpty) // below baton-volume threshold → no relax/reinforce candidates
    }

    @Test("proposals are identical with and without a populated local cache")
    func cacheDoesNotChangeProposals() async throws {
        let agent = MockLearnAgent { req in
            req.candidates.isEmpty ? [] : [ProposedEdit(path: "ios/baton.toml", newContents: "x")]
        }
        let engine = LearnEngine(agent: agent)
        let signals = [batonThread(file: "ios/A.swift"), batonThread(file: "ios/B.swift")]
        let plans = [plan("ios", learn: EffectiveLearn(minSignal: 1))]

        // Run without any cache.
        let withoutCache = try await engine.run(plans: plans, signals: signals, repoRoot: repoRoot)

        // Populate a feedback cache, then run again. The engine takes no cache input,
        // so the cache can never widen the window or reweight the agent's signal.
        let db = try BatonDatabase.openInMemory()
        let feedback = FeedbackRepository(connection: db.connection)
        try feedback.upsertAll(SignalAnalysis.candidates(signals), repoId: "r1")
        let withCache = try await engine.run(plans: plans, signals: signals, repoRoot: repoRoot)

        #expect(withoutCache.proposals.first?.edits.map(\.path) == withCache.proposals.first?.edits.map(\.path))
        #expect(withoutCache.allCandidates.map(\.weight) == withCache.allCandidates.map(\.weight))
    }

    @Test("no proposal without any signal")
    func noSignalNoProposal() async throws {
        let agent = MockLearnAgent { _ in [ProposedEdit(path: "ios/baton.toml", newContents: "x")] }
        let engine = LearnEngine(agent: agent)
        let result = try await engine.run(
            plans: [plan("ios", learn: EffectiveLearn(minSignal: 1))],
            signals: [],
            repoRoot: repoRoot
        )
        #expect(result.proposals.isEmpty)
        #expect(await agent.requests.isEmpty)
    }

    // MARK: - Agent resolution

    @Test("resolveAgent: scope agent is the default when nothing overrides it")
    func resolveAgentDefaultsToScope() {
        let resolved = LearnEngine.resolveAgent(
            scopeAgent: AgentConfig(kind: .claude, model: "haiku"),
            learnAgent: nil, learnModel: nil, agentOverride: nil, modelOverride: nil
        )
        #expect(resolved.kind == .claude)
        #expect(resolved.model == "haiku") // carried over: kind matches
    }

    @Test("resolveAgent: [learn] block wins over the scope agent")
    func resolveAgentLearnBlockWins() {
        let resolved = LearnEngine.resolveAgent(
            scopeAgent: AgentConfig(kind: .claude, model: "haiku"),
            learnAgent: .codex, learnModel: "opus", agentOverride: nil, modelOverride: nil
        )
        #expect(resolved.kind == .codex)
        #expect(resolved.model == "opus")
    }

    @Test("resolveAgent: CLI override wins over the [learn] block")
    func resolveAgentCLIWins() {
        let resolved = LearnEngine.resolveAgent(
            scopeAgent: AgentConfig(kind: .claude, model: "haiku"),
            learnAgent: .codex, learnModel: "opus", agentOverride: .gemini, modelOverride: "g-pro"
        )
        #expect(resolved.kind == .gemini)
        #expect(resolved.model == "g-pro")
    }

    @Test("resolveAgent: scope model carries over only when the resolved kind matches")
    func resolveAgentModelCarryoverGuard() {
        // Differing kind ([learn].agent) → scope's claude model is NOT carried to codex.
        let differing = LearnEngine.resolveAgent(
            scopeAgent: AgentConfig(kind: .claude, model: "haiku"),
            learnAgent: .codex, learnModel: nil, agentOverride: nil, modelOverride: nil
        )
        #expect(differing.kind == .codex)
        #expect(differing.model == nil)

        // Same kind with no model override → scope's model carries over.
        let matching = LearnEngine.resolveAgent(
            scopeAgent: AgentConfig(kind: .claude, model: "haiku"),
            learnAgent: .claude, learnModel: nil, agentOverride: nil, modelOverride: nil
        )
        #expect(matching.kind == .claude)
        #expect(matching.model == "haiku")
    }

    @Test("resolveAgent: matching kind preserves the scope's other agent fields")
    func resolveAgentPreservesScopeFields() {
        let resolved = LearnEngine.resolveAgent(
            scopeAgent: AgentConfig(kind: .claude, model: "haiku", binary: "/bin/claude", sandbox: false),
            learnAgent: nil, learnModel: "sonnet", agentOverride: nil, modelOverride: nil
        )
        #expect(resolved.kind == .claude)
        #expect(resolved.model == "sonnet") // [learn].model applied
        #expect(resolved.binary == "/bin/claude") // carried from scope
        #expect(resolved.sandbox == false) // carried from scope
    }

    @Test("resolveAgent: defaults to claude when no agent is configured anywhere")
    func resolveAgentDefaultsToClaude() {
        let resolved = LearnEngine.resolveAgent(
            scopeAgent: nil, learnAgent: nil, learnModel: nil, agentOverride: nil, modelOverride: nil
        )
        #expect(resolved.kind == .claude)
        #expect(resolved.model == nil)
    }

    @Test("the [learn] model override flows into the agent request")
    func learnModelOverrideFlowsToRequest() async throws {
        let agent = MockLearnAgent { _ in [ProposedEdit(path: "ios/baton.toml", newContents: "x")] }
        let engine = LearnEngine(agent: agent, agentOverride: .codex, modelOverride: "opus")
        let learn = EffectiveLearn(minSignal: 1, model: "sonnet") // CLI override must win
        _ = try await engine.run(
            plans: [plan("ios", learn: learn)],
            signals: [batonThread(file: "ios/a.swift")],
            repoRoot: repoRoot
        )
        let request = await agent.requests.first
        #expect(request?.agent.kind == .codex)
        #expect(request?.agent.model == "opus")
        #expect(request?.model == "opus")
    }
}

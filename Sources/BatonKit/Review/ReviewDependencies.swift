import Foundation

/// Resolves a skill declaration into its body. Abstracts ``SkillResolver`` so the
/// orchestrator can be tested with a stub.
public protocol SkillResolving: Sendable {
    func resolve(_ skill: SkillConfig, declaringConfigDir: URL, security: SecurityConfig?) throws -> ResolvedSkill
}

extension SkillResolver: SkillResolving {}

/// One agent pass: the resolved agent config, defaults, model, assembled prompt,
/// review context, and repository root.
public struct ReviewAgentRequest: Sendable {
    public var agent: AgentConfig
    public var defaults: EffectiveDefaults
    public var model: String?
    public var prompt: String
    public var context: ReviewContext
    public var repoRoot: URL

    public init(
        agent: AgentConfig,
        defaults: EffectiveDefaults,
        model: String?,
        prompt: String,
        context: ReviewContext,
        repoRoot: URL
    ) {
        self.agent = agent
        self.defaults = defaults
        self.model = model
        self.prompt = prompt
        self.context = context
        self.repoRoot = repoRoot
    }
}

/// Runs one agent pass for an assembled prompt and returns its findings. Abstracts
/// the live agent stack (registry + invocation builder + isolation + executor) so
/// the orchestrator can be tested without spawning processes.
public protocol ReviewAgentRunning: Sendable {
    func run(_ request: ReviewAgentRequest) async throws -> AgentRunOutcome
}

/// The production agent runner: provisions an isolated workspace, builds the
/// invocation uniformly, and executes through ``AgentInvoker``.
public struct LiveReviewAgent: ReviewAgentRunning {
    private let invoker: AgentInvoker

    public init(invoker: AgentInvoker = AgentInvoker()) {
        self.invoker = invoker
    }

    public func run(_ request: ReviewAgentRequest) async throws -> AgentRunOutcome {
        let runner = AgentRegistry.runner(for: request.agent.kind)
        let workspace = try Isolation.makeWorkspace(context: request.context, repoRoot: request.repoRoot)
        defer { Isolation.cleanup(workspace) }

        let invocation = InvocationBuilder.make(
            runner: runner,
            agent: request.agent,
            defaults: request.defaults,
            model: request.model,
            prompt: request.prompt,
            workdir: workspace
        )
        return try await invoker.run(runner: runner, invocation: invocation, model: request.model)
    }
}

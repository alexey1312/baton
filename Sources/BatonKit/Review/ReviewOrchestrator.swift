import Foundation

/// A finished task plus the artifacts needed to persist it (prompt, raw output).
public struct CompletedTask: Sendable {
    public var result: ReviewTaskResult
    public var prompt: String
    public var rawOutput: String

    public init(result: ReviewTaskResult, prompt: String, rawOutput: String) {
        self.result = result
        self.prompt = prompt
        self.rawOutput = rawOutput
    }
}

/// Creates one task per `(scope, review)`, runs them with sliding-window
/// concurrency, and merges per-chunk findings. A failing task is recorded rather
/// than aborting the run.
public struct ReviewOrchestrator: Sendable {
    private let agent: any ReviewAgentRunning
    private let skills: any SkillResolving
    private let repoRoot: URL

    public init(repoRoot: URL, agent: any ReviewAgentRunning = LiveReviewAgent(), skills: any SkillResolving) {
        self.repoRoot = repoRoot
        self.agent = agent
        self.skills = skills
    }

    /// Options controlling a run.
    public struct Options: Sendable {
        public var onlyReview: String?
        public var agentOverride: AgentKind?
        public var modelOverride: String?
        public var maxConcurrencyOverride: Int?

        public init(
            onlyReview: String? = nil,
            agentOverride: AgentKind? = nil,
            modelOverride: String? = nil,
            maxConcurrencyOverride: Int? = nil
        ) {
            self.onlyReview = onlyReview
            self.agentOverride = agentOverride
            self.modelOverride = modelOverride
            self.maxConcurrencyOverride = maxConcurrencyOverride
        }
    }

    /// Run all matching `(scope, review)` tasks. Results are returned in plan order.
    public func run(scopes: [ScopePlan], options: Options = Options()) async throws -> [CompletedTask] {
        let specs = buildSpecs(scopes: scopes, options: options)
        guard !specs.isEmpty else { return [] }

        let concurrency = max(
            1,
            options.maxConcurrencyOverride
                ?? scopes.map(\.config.defaults.maxConcurrency).max()
                ?? ConfigDefaults.maxConcurrency
        )

        return try await parallelMapEntries(specs, maxParallel: concurrency) { spec in
            await runOne(spec)
        }
    }

    // MARK: - Planning

    private struct TaskSpec {
        var scopePath: String
        var configDir: URL
        var agent: AgentConfig
        var model: String?
        var defaults: EffectiveDefaults
        var security: SecurityConfig?
        var review: ReviewConfig
        var skills: [SkillConfig]
        var files: [FileChange]
    }

    private func buildSpecs(scopes: [ScopePlan], options: Options) -> [TaskSpec] {
        var specs: [TaskSpec] = []
        for scope in scopes {
            let baseAgent = scope.config.agent
            let agentConfig: AgentConfig = if let override = options.agentOverride {
                AgentConfig(kind: override, context: baseAgent?.context)
            } else {
                baseAgent ?? AgentConfig(kind: .claude)
            }
            let model = options.modelOverride ?? (options.agentOverride == nil ? baseAgent?.model : nil)

            for review in scope.config.reviews {
                if let only = options.onlyReview, review.name != only { continue }
                let filtered = DiffRouter.filter(scope.files, glob: review.glob)
                if filtered.isEmpty { continue }
                let reviewSkills = (review.skills ?? []).compactMap { name in
                    scope.config.skills.first { $0.name == name }
                }
                specs.append(TaskSpec(
                    scopePath: scope.scopePath,
                    configDir: scope.configDir,
                    agent: agentConfig,
                    model: model,
                    defaults: scope.config.defaults,
                    security: scope.config.security,
                    review: review,
                    skills: reviewSkills,
                    files: filtered
                ))
            }
        }
        return specs
    }

    // MARK: - Execution

    /// Accumulated output of running every chunk of one task.
    private struct ChunkRun {
        var findings: [Finding] = []
        var warnings: [String] = []
        var prompts: [String] = []
        var outputs: [String] = []
        var truncated: Set<String> = []
        var durationMs: Int = 0
        var usage: AgentUsage = .zero
    }

    private func runOne(_ spec: TaskSpec) async -> CompletedTask {
        let failOn = spec.review.failOn ?? spec.defaults.failOn
        do {
            let run = try await executeChunks(spec)
            let result = ReviewTaskResult(
                scope: spec.scopePath,
                review: spec.review.name,
                findings: Self.dedupe(run.findings),
                failOn: failOn,
                warnings: run.warnings,
                truncatedFiles: run.truncated.sorted(),
                durationMs: run.durationMs > 0 ? run.durationMs : nil,
                usage: run.usage.hasData ? run.usage : nil,
                agentKind: spec.agent.kind.rawValue,
                model: spec.model
            )
            return CompletedTask(
                result: result,
                prompt: run.prompts.joined(separator: "\n\n=== next chunk ===\n\n"),
                rawOutput: run.outputs.joined(separator: "\n")
            )
        } catch {
            let message = (error as? any LocalizedError)?.errorDescription ?? "\(error)"
            let result = ReviewTaskResult(
                scope: spec.scopePath,
                review: spec.review.name,
                findings: [],
                failOn: failOn,
                taskFailed: true,
                errorMessage: message,
                agentKind: spec.agent.kind.rawValue,
                model: spec.model
            )
            return CompletedTask(result: result, prompt: "", rawOutput: "")
        }
    }

    /// Resolve skills + instructions, chunk the diff, and run one agent pass per chunk.
    private func executeChunks(_ spec: TaskSpec) async throws -> ChunkRun {
        let resolvedSkills = try spec.skills.map {
            try skills.resolve($0, declaringConfigDir: spec.configDir, security: spec.security)
        }
        let instructions = try PromptBuilder.instructions(for: spec.review, configDir: spec.configDir)
        let context = spec.review.context ?? spec.agent.context ?? .diff
        let chunking = DiffChunker.chunks(
            files: spec.files,
            budget: spec.defaults.diffBudget,
            strategy: spec.defaults.chunkStrategy
        )

        var run = ChunkRun(warnings: chunking.warnings)
        for chunk in chunking.chunks {
            for file in chunk.files where file.truncated {
                run.truncated.insert(file.path)
            }
            let prompt = PromptBuilder.build(
                reviewName: spec.review.name,
                instructions: instructions,
                skills: resolvedSkills,
                context: context,
                diff: chunk.text
            )
            run.prompts.append(prompt)
            let outcome = try await agent.run(ReviewAgentRequest(
                agent: spec.agent,
                defaults: spec.defaults,
                model: spec.model,
                prompt: prompt,
                context: context,
                repoRoot: repoRoot
            ))
            run.findings += outcome.findings
            run.warnings += outcome.warnings
            run.outputs.append(outcome.rawOutput)
            run.durationMs += Int((outcome.duration * 1000).rounded())
            if let usage = outcome.usage {
                run.usage = run.usage.adding(usage)
            }
        }
        return run
    }

    /// Deduplicate findings by `(file, line, severity, title)`, keeping first seen.
    static func dedupe(_ findings: [Finding]) -> [Finding] {
        var seen: Set<Finding.DedupeKey> = []
        var result: [Finding] = []
        for finding in findings where seen.insert(finding.dedupeKey).inserted {
            result.append(finding)
        }
        return result
    }
}

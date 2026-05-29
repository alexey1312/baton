import Foundation

/// A finished task plus the artifacts needed to persist it (prompt, raw output).
public struct CompletedTask: Sendable {
    public var result: ReviewTaskResult
    public var prompt: String
    public var rawOutput: String
    /// When this task began (wall-clock), so the run's true elapsed span can be
    /// derived across concurrent tasks instead of summing their durations.
    public var startedAt: Date?

    public init(result: ReviewTaskResult, prompt: String, rawOutput: String, startedAt: Date? = nil) {
        self.result = result
        self.prompt = prompt
        self.rawOutput = rawOutput
        self.startedAt = startedAt
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

    /// A resolved skill paired with the directory of the `baton.toml` that declared
    /// it, so a relative local `source` resolves against the declaring scope even
    /// when the skill is inherited into a descendant consuming scope.
    private struct SkillBinding {
        var config: SkillConfig
        var declaringDir: URL
    }

    private struct TaskSpec {
        var scopePath: String
        var agent: AgentConfig
        var model: String?
        var defaults: EffectiveDefaults
        var security: SecurityConfig?
        var review: ReviewConfig
        var skills: [SkillBinding]
        /// Directory used to resolve the review's `prompt_file` (the review's
        /// declaring scope when inherited, else the consuming scope).
        var instructionsDir: URL
        var files: [FileChange]
    }

    private func buildSpecs(scopes: [ScopePlan], options: Options) -> [TaskSpec] {
        var specs: [TaskSpec] = []
        for scope in scopes {
            for review in scope.config.reviews {
                if let only = options.onlyReview, review.name != only { continue }
                let filtered = DiffRouter.filter(scope.files, glob: review.glob)
                if filtered.isEmpty { continue }

                let (agentConfig, model) = Self.resolveAgent(
                    scopeAgent: scope.config.agent,
                    reviewAgent: review.agent,
                    options: options
                )
                let reviewSkills: [SkillBinding] = (review.skills ?? []).compactMap { name in
                    guard let config = scope.config.skills.first(where: { $0.name == name }) else { return nil }
                    let dir = scope.config.skillDeclaringDirs[name] ?? scope.scopePath
                    return SkillBinding(config: config, declaringDir: declaringURL(dir))
                }
                let instructionsDir = review.promptFile == nil
                    ? scope.configDir
                    : declaringURL(scope.config.reviewDeclaringDirs[review.name] ?? scope.scopePath)

                specs.append(TaskSpec(
                    scopePath: scope.scopePath,
                    agent: agentConfig,
                    model: model,
                    defaults: scope.config.defaults,
                    security: scope.config.security,
                    review: review,
                    skills: reviewSkills,
                    instructionsDir: instructionsDir,
                    files: filtered
                ))
            }
        }
        return specs
    }

    /// Resolve the effective agent and model for one review. Precedence: a CLI
    /// `--agent` override (forces kind for every review) beats a per-review
    /// `[[reviews]].agent` block, which beats the scope's `[agent]` block.
    static func resolveAgent(
        scopeAgent: AgentConfig?,
        reviewAgent: AgentConfig?,
        options: Options
    ) -> (AgentConfig, String?) {
        if let override = options.agentOverride {
            let context = (reviewAgent ?? scopeAgent)?.context
            return (AgentConfig(kind: override, context: context), options.modelOverride)
        }
        let base = reviewAgent ?? scopeAgent ?? AgentConfig(kind: .claude)
        return (base, options.modelOverride ?? base.model)
    }

    /// Map a repo-relative scope directory to an absolute URL under ``repoRoot``
    /// (mirrors how `ScopePlan.configDir` is built from the scope path).
    private func declaringURL(_ dir: String) -> URL {
        dir.isEmpty ? repoRoot : repoRoot.appendingPathComponent(dir, isDirectory: true)
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
        let startedAt = Date()
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
                rawOutput: run.outputs.joined(separator: "\n"),
                startedAt: startedAt
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
            return CompletedTask(result: result, prompt: "", rawOutput: "", startedAt: startedAt)
        }
    }

    /// Resolve skills + instructions, chunk the diff, and run one agent pass per chunk.
    private func executeChunks(_ spec: TaskSpec) async throws -> ChunkRun {
        let resolvedSkills = try spec.skills.map {
            try skills.resolve($0.config, declaringConfigDir: $0.declaringDir, security: spec.security)
        }
        let instructions = try PromptBuilder.instructions(for: spec.review, configDir: spec.instructionsDir)
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

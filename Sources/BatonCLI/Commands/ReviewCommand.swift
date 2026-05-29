import ArgumentParser
import BatonKit
import Foundation

/// `baton review [name]` — discover scopes, cascade config, resolve the diff, and
/// run the review orchestration.
struct ReviewCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "review",
        abstract: "Run configured reviews over the resolved diff."
    )

    @OptionGroup var global: GlobalOptions

    @Argument(help: "Run only the named review (otherwise all reviews run).")
    var name: String?

    @Option(help: "Diff base (takes precedence over scope defaults).")
    var base: String?

    @Option(help: "Override the agent kind (\(AgentKind.listForHelp)).")
    var agent: AgentKind?

    @Option(help: "Override the agent model.")
    var model: String?

    @Flag(help: "Emit findings as machine-readable JSON.")
    var json = false

    @Option(name: .customLong("max-concurrency"), help: "Maximum concurrent (scope, review) tasks.")
    var maxConcurrency: Int?

    @Option(help: "Repository root to operate on.")
    var repo: String?

    @Flag(name: .customLong("allow-unpinned"), help: "Permit remote skills without a SHA ref.")
    var allowUnpinned = false

    func run() async throws {
        try await present(global.outputMode) {
            let root = try CLISupport.resolveRepoRoot(repo)
            let git = GitRunner(repoRoot: root)
            let discovery = try ScopeDiscovery.discover(repoRoot: root)
            emitWarnings(discovery.warnings)

            let effectives = try discovery.scopes.map { try Cascade.effective(for: $0, in: discovery.scopes) }
            try validateNamedReview(effectives)
            try preflightAgents(effectives)

            let resolvedBase = BaseResolver.resolve(flag: base, scopeDefault: rootDefaults(effectives)?.base)
            let diff = try DiffCollector(git: git).collect(base: resolvedBase)
            let headSHA = try git.revParse("HEAD")
            let store = RunRecordStore(repoRoot: root)
            let repoIdentity = RepoIdentity.resolve(repoRoot: root)
            let database = RunDatabaseStore(location: .both(repoRoot: root))

            if diff.isEmpty {
                let hook = RunRecordStore.DatabaseHook(
                    store: database, repo: repoIdentity, status: .empty, cliVersion: Self.cliVersion
                )
                let outcome = try store.write(
                    runId: RunRecordStore.newRunId(),
                    base: resolvedBase, headSHA: headSHA, tasks: [], database: hook
                )
                emitDatabaseWarnings(outcome.databaseErrors)
                try emitNothing(store: store, message: "No changes to review.")
                return
            }

            let plans = buildPlans(effectives: effectives, diff: diff, scopes: discovery.scopes, root: root)
            let tasks = try await orchestrate(
                plans: plans,
                root: root,
                git: git,
                referencesBudgetBytes: rootReferencesBudget(effectives)
            )
            let reviewOutcome = ReviewOutcome(results: tasks.map(\.result))
            let status: RunStatus = reviewOutcome.shouldFailExit ? .failed : .success
            let hook = RunRecordStore.DatabaseHook(
                store: database, repo: repoIdentity, status: status, cliVersion: Self.cliVersion
            )
            let writeOutcome = try store.write(
                runId: RunRecordStore.newRunId(),
                base: resolvedBase, headSHA: headSHA, tasks: tasks, database: hook
            )
            emitDatabaseWarnings(writeOutcome.databaseErrors)

            try renderAndExit(store: store, tasks: tasks)
        }
    }

    // MARK: - Steps

    private func validateNamedReview(_ effectives: [EffectiveConfig]) throws {
        guard let name else { return }
        let available = Set(effectives.flatMap { $0.reviews.map(\.name) })
        if !available.contains(name) {
            throw CLIError.namedReviewMissing(name: name, available: available.sorted())
        }
    }

    private func preflightAgents(_ effectives: [EffectiveConfig]) throws {
        var binaries: Set<String> = []
        for effective in effectives where !effective.reviews.isEmpty {
            guard let kind = agent ?? effective.agent?.kind else { continue }
            let configBinary = agent == nil ? effective.agent?.binary : nil
            try binaries.insert(AgentToolPreflight.resolveBinary(kind: kind, configBinary: configBinary))
        }
        for binary in binaries {
            try AgentToolPreflight.verify(binary: binary, agent: binary)
        }
    }

    private func buildPlans(
        effectives: [EffectiveConfig],
        diff: RepoDiff,
        scopes: [ScopeConfig],
        root: URL
    ) -> [ScopePlan] {
        let groups = DiffRouter.group(diff, scopes: scopes)
        return effectives.compactMap { effective in
            let files = groups[effective.scopePath] ?? []
            guard !files.isEmpty else { return nil }
            let configDir = effective.scopePath.isEmpty
                ? root
                : root.appendingPathComponent(effective.scopePath, isDirectory: true)
            return ScopePlan(config: effective, files: files, configDir: configDir)
        }
    }

    private func orchestrate(
        plans: [ScopePlan],
        root: URL,
        git: GitRunner,
        referencesBudgetBytes: Int
    ) async throws -> [CompletedTask] {
        let resolver = SkillResolver(
            repoRoot: root,
            cacheDir: SkillResolver.defaultCacheDir(),
            git: git,
            allowUnpinned: allowUnpinned,
            referencesBudgetBytes: referencesBudgetBytes
        )
        let orchestrator = ReviewOrchestrator(repoRoot: root, agent: LiveReviewAgent(), skills: resolver)
        return try await orchestrator.run(scopes: plans, options: .init(
            onlyReview: name,
            agentOverride: agent,
            modelOverride: model,
            maxConcurrencyOverride: maxConcurrency
        ))
    }

    private func renderAndExit(store: RunRecordStore, tasks: [CompletedTask]) throws {
        if tasks.isEmpty {
            try emitNothing(store: store, message: "Nothing to review.")
        } else {
            let run = try store.load(runId: nil)
            let format: RenderFormat = json ? .json : .terminal
            let output = try Renderer.render(
                run: run,
                format: format,
                headSHA: nil,
                useColors: global.outputMode.useColors
            )
            TerminalOutput.shared.out(output)
        }
        if ReviewOutcome(results: tasks.map(\.result)).shouldFailExit {
            throw ExitCode.failure
        }
    }

    /// Emit a "nothing to do" outcome while honoring `--json`: stdout always stays
    /// a valid JSON document (an empty `results` array) so `baton review --json |
    /// jq` does not break on an unchanged tree, and the human note goes to stderr.
    /// In terminal mode the note goes to stdout as before.
    private func emitNothing(store: RunRecordStore, message: String) throws {
        let colors = global.outputMode.useColors
        guard json else {
            TerminalOutput.shared.out(NooraUI.info(message, useColors: colors))
            return
        }
        let run = try store.load(runId: nil)
        let output = try Renderer.render(run: run, format: .json, headSHA: nil, useColors: false)
        TerminalOutput.shared.out(output)
        TerminalOutput.shared.err(NooraUI.info(message, useColors: colors))
    }

    private func rootDefaults(_ effectives: [EffectiveConfig]) -> EffectiveDefaults? {
        (effectives.first { $0.scopePath.isEmpty } ?? effectives.first)?.defaults
    }

    private func rootReferencesBudget(_ effectives: [EffectiveConfig]) -> Int {
        (effectives.first { $0.scopePath.isEmpty } ?? effectives.first)?.referencesBudgetBytes
            ?? ConfigDefaults.referencesBudgetBytes
    }

    private func emitWarnings(_ warnings: [String]) {
        for warning in warnings {
            TerminalOutput.shared.err(NooraUI.warning(warning, useColors: global.outputMode.useColors))
        }
    }

    private func emitDatabaseWarnings(_ errors: [BatonDatabaseError]) {
        for error in errors {
            let message = error.errorDescription ?? "Database write failed"
            TerminalOutput.shared.err(NooraUI.warning(message, useColors: global.outputMode.useColors))
        }
    }

    private static var cliVersion: String {
        Baton.configuration.version.isEmpty ? "dev" : Baton.configuration.version
    }
}

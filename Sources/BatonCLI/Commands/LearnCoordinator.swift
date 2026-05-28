import BatonForge
import BatonKit
import Foundation

/// Bridges the `learn` command to the BatonKit engine and BatonForge GitHub
/// reads/writes: discover scopes, read signal from GitHub, run the per-scope
/// learning pass, cache the observed signal, and either preview or deliver the
/// rolling draft pull request.
enum LearnCoordinator {
    struct Options {
        var repoRoot: URL
        var ghRepo: String?
        var apply: Bool
        var markdown: Bool
        var outputMode: OutputMode
    }

    static func run(_ options: Options) async throws {
        let discovery = try ScopeDiscovery.discover(repoRoot: options.repoRoot)
        let colors = options.outputMode.useColors
        for warning in discovery.warnings {
            TerminalOutput.shared.err(NooraUI.warning(warning, useColors: colors))
        }
        let plans = try LearnPlanning.plans(discovery: discovery, repoRoot: options.repoRoot)
        let repo = try resolveRepo(options.ghRepo)

        let forge = GitHubForge()
        try await forge.preflight()

        let lookback = plans
            .filter(\.effective.learn.enabled)
            .map(\.effective.learn.lookbackDays)
            .max() ?? ConfigDefaults.learnLookbackDays
        let reader = GitHubLearnForge(repo: repo)
        let signals = try await reader.collectSignal(lookbackDays: lookback)

        let resolver = SkillResolver(
            repoRoot: options.repoRoot,
            cacheDir: SkillResolver.defaultCacheDir(),
            git: GitRunner(repoRoot: options.repoRoot)
        )
        let engine = LearnEngine(agent: LiveLearnAgent(skills: resolver))
        let result = try await engine.run(plans: plans, signals: signals, repoRoot: options.repoRoot)

        // Refused (out-of-allowlist) edits never persist, in preview or delivery.
        LearnGit.restore(result.proposals.flatMap(\.droppedPaths), repoRoot: options.repoRoot)
        cacheSignal(result, repoRoot: options.repoRoot)

        let deliver = options.apply || deliveryConfigured(discovery)
        if deliver {
            try await delivery(result: result, plans: plans, repo: repo, options: options)
        } else {
            emitPreview(result, options: options)
        }
    }

    // MARK: - Preview

    private static func emitPreview(_ result: LearnRunResult, options: Options) {
        let output = options.markdown
            ? LearnPreview.markdown(result)
            : LearnPreview.terminal(result, useColors: options.outputMode.useColors)
        TerminalOutput.shared.out(output)
        for warning in result.warnings {
            TerminalOutput.shared.err(NooraUI.warning(warning, useColors: options.outputMode.useColors))
        }
    }

    // MARK: - Delivery

    private static func delivery(
        result: LearnRunResult,
        plans: [LearnScopePlan],
        repo: String,
        options: Options
    ) async throws {
        let rootLearn = plans.first { $0.scope.path.isEmpty }?.effective.learn ?? EffectiveLearn()
        let edits = result.proposals.flatMap { $0.edits.map(\.path) }
        let colors = options.outputMode.useColors

        guard !edits.isEmpty else {
            TerminalOutput.shared.out(NooraUI.success("Baton learn: no setup edits to deliver.", useColors: colors))
            return
        }

        try LearnGit.commitAndPush(
            branch: rootLearn.branch, paths: edits,
            message: "chore(baton): learn — review-setup proposals", repoRoot: options.repoRoot
        )
        let report = try await GitHubLearnDelivery().deliver(LearnDeliveryRequest(
            repo: repo, branch: rootLearn.branch, base: rootLearn.base,
            title: "Baton learn — review-setup proposals", body: LearnPreview.markdown(result),
            draft: rootLearn.draft, reviewers: rootLearn.reviewers,
            teamReviewers: rootLearn.teamReviewers, labels: rootLearn.labels
        ))
        emitDeliveryReport(report, result: result, colors: colors)
    }

    private static func emitDeliveryReport(_ report: LearnDeliveryReport, result: LearnRunResult, colors: Bool) {
        for warning in report.warnings + result.warnings {
            TerminalOutput.shared.err(NooraUI.warning(warning, useColors: colors))
        }
        if report.degradedToPreview {
            TerminalOutput.shared.out(LearnPreview.terminal(result, useColors: colors))
            return
        }
        let verb = report.created ? "Opened" : "Updated"
        let number = report.pullRequestNumber.map { "#\($0)" } ?? "(unknown)"
        TerminalOutput.shared.out(NooraUI.success(
            "Baton learn: \(verb) rolling draft PR \(number).", useColors: colors
        ))
    }

    // MARK: - Helpers

    private static func cacheSignal(_ result: LearnRunResult, repoRoot: URL) {
        guard !result.allCandidates.isEmpty else { return }
        let identity = RepoIdentity.resolve(repoRoot: repoRoot)
        guard let db = try? BatonDatabase.open(at: DatabasePathResolver.globalDatabaseURL) else { return }
        try? FeedbackRepository(connection: db.connection).upsertAll(result.allCandidates, repoId: identity.id)
    }

    private static func deliveryConfigured(_ discovery: DiscoveryResult) -> Bool {
        guard let root = discovery.scopes.first(where: { $0.path.isEmpty }), let learn = root.config.learn else {
            return false
        }
        return learn.branch != nil || learn.base != nil || learn.reviewers != nil
            || learn.teamReviewers != nil || learn.labels != nil || learn.draft != nil
    }

    private static func resolveRepo(_ override: String?) throws -> String {
        if let override, !override.trimmingCharacters(in: .whitespaces).isEmpty { return override }
        if let repo = GitHubEnv.detect()?.repository, !repo.isEmpty { return repo }
        throw CLIError.learnRepoUnresolvable
    }
}

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
        /// CLI `--agent`/`--model` overrides for the learning pass (win over `[learn]`).
        var agent: AgentKind?
        var model: String?
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

        // Honor the root scope's configured references budget so learn and review
        // enforce the same skill policy (review threads it via rootReferencesBudget).
        let referencesBudget = plans.first { $0.scope.path.isEmpty }?.effective.referencesBudgetBytes
            ?? ConfigDefaults.referencesBudgetBytes
        let resolver = SkillResolver(
            repoRoot: options.repoRoot,
            cacheDir: SkillResolver.defaultCacheDir(),
            git: GitRunner(repoRoot: options.repoRoot),
            referencesBudgetBytes: referencesBudget
        )
        let engine = LearnEngine(
            agent: LiveLearnAgent(skills: resolver),
            agentOverride: options.agent,
            modelOverride: options.model
        )
        let result = try await engine.run(plans: plans, signals: signals, repoRoot: options.repoRoot)

        // The agent returns proposed edits as structured data — nothing is written
        // to the working tree until the apply/delivery path writes the allowlisted
        // edits below, so preview stays read-only and refused paths never persist.
        if let cacheWarning = cacheSignal(result, repoRoot: options.repoRoot) {
            TerminalOutput.shared.err(NooraUI.warning(cacheWarning, useColors: colors))
        }

        let learnTemplate = try learnTemplateOverride(plans: plans, repoRoot: options.repoRoot)
        let deliver = options.apply || deliveryConfigured(discovery)
        if deliver {
            try await delivery(result: result, plans: plans, repo: repo, template: learnTemplate, options: options)
        } else {
            try emitPreview(result, template: learnTemplate, options: options)
        }
    }

    // MARK: - Preview

    private static func emitPreview(_ result: LearnRunResult, template: Renderer.Template?, options: Options) throws {
        let output: String = if options.markdown {
            try LearnPreview.markdown(result, template: template)
        } else {
            LearnPreview.terminal(result, useColors: options.outputMode.useColors)
        }
        TerminalOutput.shared.out(output)
        for warning in result.warnings {
            TerminalOutput.shared.err(NooraUI.warning(warning, useColors: options.outputMode.useColors))
        }
    }

    /// The learn PR-body template override from the root `[render].learn_pr_body_template`.
    private static func learnTemplateOverride(plans: [LearnScopePlan], repoRoot: URL) throws -> Renderer.Template? {
        guard let path = plans.first(where: { $0.scope.path.isEmpty })?.effective.render.learnPrBodyTemplate else {
            return nil
        }
        return try ReportTemplating.userTemplate(path: path, configDir: repoRoot)
    }

    // MARK: - Delivery

    private static func delivery(
        result: LearnRunResult,
        plans: [LearnScopePlan],
        repo: String,
        template: Renderer.Template?,
        options: Options
    ) async throws {
        let rootLearn = plans.first { $0.scope.path.isEmpty }?.effective.learn ?? EffectiveLearn()
        let allowedEdits = result.proposals.flatMap(\.edits)
        let editPaths = allowedEdits.map(\.path)
        let colors = options.outputMode.useColors

        guard !editPaths.isEmpty else {
            TerminalOutput.shared.out(NooraUI.success("Baton learn: no setup edits to deliver.", useColors: colors))
            return
        }

        // Only the apply/delivery path writes to disk; the agent emitted structured
        // edits, so Baton writes the allowlisted full contents here before staging.
        try LearnGit.writeEdits(allowedEdits, repoRoot: options.repoRoot)
        try LearnGit.commitAndPush(
            branch: rootLearn.branch, paths: editPaths,
            message: "chore(baton): learn — review-setup proposals", repoRoot: options.repoRoot
        )
        let report = try await GitHubLearnDelivery().deliver(LearnDeliveryRequest(
            repo: repo, branch: rootLearn.branch, base: rootLearn.base,
            title: "Baton learn — review-setup proposals", body: LearnPreview.markdown(result, template: template),
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

    /// Best-effort write to the non-authoritative feedback cache. Returns a warning
    /// when the write fails so a broken cache is visible — swallowing the error
    /// would leave `baton stats` silently stale with no explanation.
    private static func cacheSignal(_ result: LearnRunResult, repoRoot: URL) -> String? {
        guard !result.allCandidates.isEmpty else { return nil }
        let identity = RepoIdentity.resolve(repoRoot: repoRoot)
        do {
            let db = try BatonDatabase.open(at: DatabasePathResolver.globalDatabaseURL)
            try FeedbackRepository(connection: db.connection).upsertAll(result.allCandidates, repoId: identity.id)
            return nil
        } catch {
            return "Feedback cache not updated (\(error)); `baton stats` trends may be stale."
        }
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

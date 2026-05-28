import ArgumentParser
import BatonKit
import Foundation

/// `baton stats` — aggregated history of past review runs.
struct StatsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stats",
        abstract: "Show aggregated stats for past review runs."
    )

    @OptionGroup var global: GlobalOptions

    @Option(help: "Repository root to scope stats to. Defaults to the current directory.")
    var repo: String?

    @Flag(name: .customLong("all-repos"), help: "Aggregate across every repository in the database.")
    var allRepos = false

    @Option(help: "Filter by scope path (e.g. `ios` or `web/api`).")
    var scope: String?

    @Option(help: "Filter by review name.")
    var review: String?

    @Option(help: "Only include runs at or after this ISO-8601 date (yyyy-MM-dd).")
    var since: String?

    @Flag(help: "Emit a machine-readable JSON document on stdout.")
    var json = false

    func run() async throws {
        try await present(global.outputMode) {
            let context = try StatsContext.resolve(repo: repo, allRepos: allRepos)
            let filter = try StatsFilter(
                repoId: context.repoId, scope: scope, review: review, since: parseSince()
            )
            let stats = StatsRepository(connection: context.database.connection)
            let feedback = FeedbackRepository(connection: context.database.connection)
            let payload = try gather(stats: stats, feedback: feedback, repoId: context.repoId, filter: filter)
            if json {
                try emitJSON(payload)
            } else {
                emitText(payload)
            }
        }
    }

    // MARK: - Gather

    private func gather(
        stats: StatsRepository,
        feedback: FeedbackRepository,
        repoId: String?,
        filter: StatsFilter
    ) throws -> StatsPayload {
        let summary = try stats.summary(filter: filter)
        let byReview = try stats.byReview(filter: filter)
        let bySeverity = try stats.bySeverity(filter: filter)
        let topFiles = try stats.topFiles(filter: filter, limit: 10)
        let costByModel = try stats.costByModel(filter: filter)
        return try StatsPayload(
            summary: summary, byReview: byReview, bySeverity: bySeverity,
            topFiles: topFiles, costByModel: costByModel,
            mostDownvoted: feedback.mostDownvoted(repoId: repoId),
            mostUpvoted: feedback.mostUpvoted(repoId: repoId)
        )
    }

    // MARK: - JSON

    private func emitJSON(_ payload: StatsPayload) throws {
        let output = StatsOutput.from(payload)
        let data = try JSONCodec.encodeWithISO8601DatePretty(output)
        TerminalOutput.shared.out(String(bytes: data, encoding: .utf8) ?? "")
    }

    // MARK: - Text

    private func emitText(_ payload: StatsPayload) {
        let colors = global.outputMode.useColors
        TerminalOutput.shared.out(NooraUI.success("Baton stats", useColors: colors))
        emitSummary(payload.summary)
        emitByReview(payload.byReview)
        emitBySeverity(payload.bySeverity)
        emitTopFiles(payload.topFiles)
        emitCostByModel(payload.costByModel)
        emitFeedback(payload.mostDownvoted, payload.mostUpvoted)
    }

    private func emitFeedback(_ down: [FeedbackRow], _ up: [FeedbackRow]) {
        guard !down.isEmpty || !up.isEmpty else { return }
        TerminalOutput.shared.out("\n  Learn Feedback\n  \(line)")
        emitFeedbackRows("Most downvoted (👎)", down)
        emitFeedbackRows("Most upvoted (👍)", up)
    }

    private func emitFeedbackRows(_ title: String, _ rows: [FeedbackRow]) {
        guard !rows.isEmpty else { return }
        TerminalOutput.shared.out("  \(title)")
        for row in rows {
            let label = TextTable.truncate("\(row.severity) \(row.title)", 44)
            let weight = row.weight > 0 ? "+\(row.weight)" : String(row.weight)
            TerminalOutput.shared.out("  " + TextTable.pad(label, 46) + TextTable.lpad(weight, 6))
        }
    }

    private func emitSummary(_ summary: StatsSummary) {
        TerminalOutput.shared.out("\n  Summary")
        TerminalOutput.shared.out("  \(line)")
        row("Runs", TextTable.formatNumber(summary.totalRuns))
        row("Tasks", TextTable.formatNumber(summary.totalTasks))
        row("Findings", TextTable.formatNumber(summary.totalFindings))
        row("Total cost", MoneyFormatter.format(summary.totalCostUSD))
        row("Input tokens", MoneyFormatter.formatTokens(summary.totalInputTokens))
        row("Output tokens", MoneyFormatter.formatTokens(summary.totalOutputTokens))
        if let earliest = summary.earliestRun {
            row("Tracking since", Self.dateFormatter.string(from: earliest))
        }
    }

    private func emitByReview(_ rows: [ReviewStat]) {
        guard !rows.isEmpty else { return }
        TerminalOutput.shared.out("\n  By Review\n  \(line)")
        let header = "  " + TextTable.pad("Review", 20)
            + TextTable.lpad("Runs", 6)
            + TextTable.lpad("Findings", 10)
            + TextTable.lpad("Cost", 12)
        TerminalOutput.shared.out(header)
        for stat in rows {
            let cost = MoneyFormatter.format(stat.totalCostUSD)
            let row = "  " + TextTable.pad(stat.review, 20)
                + TextTable.lpad(String(stat.runs), 6)
                + TextTable.lpad(String(stat.findings), 10)
                + TextTable.lpad(cost, 12)
            TerminalOutput.shared.out(row)
        }
    }

    private func emitBySeverity(_ rows: [SeverityStat]) {
        guard !rows.isEmpty else { return }
        TerminalOutput.shared.out("\n  By Severity\n  \(line)")
        let maxCount = rows.map(\.count).max() ?? 1
        for stat in rows {
            let bar = TextTable.bar(value: stat.count, max: maxCount)
            TerminalOutput.shared.out(
                "  \(TextTable.pad(stat.severity, 10))\(TextTable.lpad(String(stat.count), 6))   \(bar)"
            )
        }
    }

    private func emitTopFiles(_ rows: [FileStat]) {
        guard !rows.isEmpty else { return }
        TerminalOutput.shared.out("\n  Top Files\n  \(line)")
        for stat in rows {
            let file = TextTable.truncate(stat.file, 50)
            TerminalOutput.shared.out("  \(TextTable.pad(file, 50))\(TextTable.lpad(String(stat.count), 6))")
        }
    }

    private func emitCostByModel(_ rows: [ModelCostStat]) {
        guard rows.contains(where: { $0.costUSD > 0 }) else { return }
        TerminalOutput.shared.out("\n  Cost By Model\n  \(line)")
        for stat in rows where stat.costUSD > 0 {
            let model = TextTable.truncate("\(stat.agentKind) / \(stat.model ?? "—")", 36)
            let cost = MoneyFormatter.format(stat.costUSD)
            TerminalOutput.shared.out("  " + TextTable.pad(model, 36) + TextTable.lpad(cost, 12))
        }
    }

    // MARK: - Helpers

    private func row(_ label: String, _ value: String) {
        TerminalOutput.shared.out("  \(TextTable.pad(label, 18))\(value)")
    }

    private var line: String {
        "─────────────────────────────────────────────"
    }

    private func parseSince() throws -> Date? {
        guard let since else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: since) else {
            throw CLIError.invalidDate(value: since)
        }
        return date
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

// MARK: - Payload shapes

private struct StatsPayload {
    var summary: StatsSummary
    var byReview: [ReviewStat]
    var bySeverity: [SeverityStat]
    var topFiles: [FileStat]
    var costByModel: [ModelCostStat]
    var mostDownvoted: [FeedbackRow]
    var mostUpvoted: [FeedbackRow]
}

/// JSON shape exposed by `baton stats --json`. Kept as a private mirror of the
/// repository structs so we control the wire format independently of the
/// internal types.
private struct StatsOutput: Codable {
    var summary: SummaryJSON
    var byReview: [ReviewJSON]
    var bySeverity: [SeverityJSON]
    var topFiles: [FileJSON]
    var costByModel: [ModelCostJSON]
    var mostDownvoted: [FeedbackJSON]
    var mostUpvoted: [FeedbackJSON]

    private enum CodingKeys: String, CodingKey {
        case summary
        case byReview = "by_review"
        case bySeverity = "by_severity"
        case topFiles = "top_files"
        case costByModel = "cost_by_model"
        case mostDownvoted = "most_downvoted"
        case mostUpvoted = "most_upvoted"
    }

    static func from(_ payload: StatsPayload) -> StatsOutput {
        StatsOutput(
            summary: SummaryJSON(from: payload.summary),
            byReview: payload.byReview.map(ReviewJSON.init),
            bySeverity: payload.bySeverity.map(SeverityJSON.init),
            topFiles: payload.topFiles.map(FileJSON.init),
            costByModel: payload.costByModel.map(ModelCostJSON.init),
            mostDownvoted: payload.mostDownvoted.map(FeedbackJSON.init),
            mostUpvoted: payload.mostUpvoted.map(FeedbackJSON.init)
        )
    }
}

private struct FeedbackJSON: Codable {
    var file: String
    var line: Int?
    var title: String
    var severity: String
    var weight: Int
    var threadCount: Int

    init(_ row: FeedbackRow) {
        file = row.file
        line = row.line
        title = row.title
        severity = row.severity
        weight = row.weight
        threadCount = row.threadCount
    }

    private enum CodingKeys: String, CodingKey {
        case file, line, title, severity, weight
        case threadCount = "thread_count"
    }
}

private struct SummaryJSON: Codable {
    var totalRuns: Int
    var totalTasks: Int
    var totalFindings: Int
    var totalCostUSD: Double?
    var totalInputTokens: Int?
    var totalOutputTokens: Int?
    var trackingSince: Date?

    init(from summary: StatsSummary) {
        totalRuns = summary.totalRuns
        totalTasks = summary.totalTasks
        totalFindings = summary.totalFindings
        totalCostUSD = summary.totalCostUSD
        totalInputTokens = summary.totalInputTokens
        totalOutputTokens = summary.totalOutputTokens
        trackingSince = summary.earliestRun
    }

    private enum CodingKeys: String, CodingKey {
        case totalRuns = "total_runs"
        case totalTasks = "total_tasks"
        case totalFindings = "total_findings"
        case totalCostUSD = "total_cost_usd"
        case totalInputTokens = "total_input_tokens"
        case totalOutputTokens = "total_output_tokens"
        case trackingSince = "tracking_since"
    }
}

private struct ReviewJSON: Codable {
    var review: String
    var runs: Int
    var findings: Int
    var avgDurationMs: Double?
    var totalCostUSD: Double?

    init(_ stat: ReviewStat) {
        review = stat.review
        runs = stat.runs
        findings = stat.findings
        avgDurationMs = stat.avgDurationMs
        totalCostUSD = stat.totalCostUSD
    }

    private enum CodingKeys: String, CodingKey {
        case review, runs, findings
        case avgDurationMs = "avg_duration_ms"
        case totalCostUSD = "total_cost_usd"
    }
}

private struct SeverityJSON: Codable {
    var severity: String
    var count: Int
    init(_ stat: SeverityStat) {
        severity = stat.severity; count = stat.count
    }
}

private struct FileJSON: Codable {
    var file: String
    var count: Int
    init(_ stat: FileStat) {
        file = stat.file; count = stat.count
    }
}

private struct ModelCostJSON: Codable {
    var agentKind: String
    var model: String?
    var costUSD: Double
    var runs: Int

    init(_ stat: ModelCostStat) {
        agentKind = stat.agentKind
        model = stat.model
        costUSD = stat.costUSD
        runs = stat.runs
    }

    private enum CodingKeys: String, CodingKey {
        case agentKind = "agent_kind"
        case model
        case costUSD = "cost_usd"
        case runs
    }
}

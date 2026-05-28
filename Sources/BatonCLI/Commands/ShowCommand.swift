import ArgumentParser
import BatonKit
import Foundation

/// `baton show <runId>` — detailed view of one run.
struct ShowCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show the tasks and findings of a single run."
    )

    @OptionGroup var global: GlobalOptions

    @Argument(help: "Run id, or `latest` for the most recent run in this repo.")
    var runId: String = "latest"

    @Option(help: "Repository root. Defaults to the current directory.")
    var repo: String?

    @Flag(name: .customLong("all-repos"), help: "Search across every repository in the database.")
    var allRepos = false

    @Flag(help: "Emit a machine-readable JSON document on stdout.")
    var json = false

    func run() async throws {
        try await present(global.outputMode) {
            let context = try StatsContext.resolve(repo: repo, allRepos: allRepos)
            let history = HistoryRepository(connection: context.database.connection)
            let resolvedId = try resolveRunId(history: history, repoId: context.repoId)
            guard let detail = try history.detail(runId: resolvedId) else {
                let message = "Run '\(resolvedId)' was not found in the database."
                TerminalOutput.shared.err(NooraUI.warning(message, useColors: global.outputMode.useColors))
                throw ExitCode.failure
            }
            if json {
                try emitJSON(detail)
            } else {
                emitText(detail)
            }
        }
    }

    private func resolveRunId(history: HistoryRepository, repoId: String?) throws -> String {
        guard runId == "latest" else { return runId }
        let recent = try history.recentRuns(repoId: repoId, limit: 1)
        if let first = recent.first { return first.runId }
        throw CLIError.noRunsRecorded
    }

    private func emitJSON(_ detail: RunDetail) throws {
        let output = RunDetailJSON(detail)
        let data = try JSONCodec.encodeWithISO8601DatePretty(output)
        TerminalOutput.shared.out(String(bytes: data, encoding: .utf8) ?? "")
    }

    private func emitText(_ detail: RunDetail) {
        let colors = global.outputMode.useColors
        TerminalOutput.shared.out(NooraUI.success("Run \(detail.summary.runId)", useColors: colors))
        emitSummary(detail.summary)
        emitTasks(detail.tasks)
    }

    private func emitSummary(_ summary: RunSummary) {
        TerminalOutput.shared.out("  \(line)")
        row("Status", summary.status.rawValue)
        row("Repo", summary.repoLabel ?? summary.repoId)
        row("Base → Head", "\(summary.baseRef) → \(String(summary.headSHA.prefix(8)))")
        row("When", Self.dateFormatter.string(from: summary.createdAt))
        if let durationMs = summary.durationMs {
            row("Duration", String(format: "%.2fs", Double(durationMs) / 1000.0))
        }
        row("Findings", String(summary.totalFindings))
        row("Cost", MoneyFormatter.format(summary.totalCostUSD))
    }

    private func emitTasks(_ tasks: [TaskWithFindings]) {
        guard !tasks.isEmpty else { return }
        TerminalOutput.shared.out("\n  Tasks")
        TerminalOutput.shared.out("  \(line)")
        for entry in tasks {
            let scope = entry.task.scope.isEmpty ? "(root)" : entry.task.scope
            let cost = MoneyFormatter.format(entry.task.costUSD)
            let duration = entry.task.durationMs.map { String(format: "%.2fs", Double($0) / 1000.0) } ?? "—"
            TerminalOutput.shared.out(
                "  \(scope)/\(entry.task.review)" +
                    "  agent=\(entry.task.agentKind)" +
                    "  duration=\(duration)" +
                    "  cost=\(cost)" +
                    "  findings=\(entry.findings.count)"
            )
            for finding in entry.findings {
                let location = finding.line.map { "\(finding.file):\($0)" } ?? finding.file
                TerminalOutput.shared.out("    [\(finding.severity)] \(location) — \(finding.title)")
            }
        }
    }

    private func row(_ label: String, _ value: String) {
        TerminalOutput.shared.out("  \(TextTable.pad(label, 14))\(value)")
    }

    private var line: String { "─────────────────────────────────────────────" }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
}

private struct RunDetailJSON: Codable {
    var summary: HistoryRowJSON
    var tasks: [TaskDetailJSON]

    init(_ detail: RunDetail) {
        summary = HistoryRowJSON(detail.summary)
        tasks = detail.tasks.map(TaskDetailJSON.init)
    }
}

private struct HistoryRowJSON: Codable {
    var runId: String
    var repoLabel: String?
    var createdAt: Date
    var baseRef: String
    var headSHA: String
    var durationMs: Int?
    var totalFindings: Int
    var totalCostUSD: Double?
    var status: String
    var agentKind: String?

    init(_ run: RunSummary) {
        runId = run.runId
        repoLabel = run.repoLabel
        createdAt = run.createdAt
        baseRef = run.baseRef
        headSHA = run.headSHA
        durationMs = run.durationMs
        totalFindings = run.totalFindings
        totalCostUSD = run.totalCostUSD
        status = run.status.rawValue
        agentKind = run.agentKind
    }

    private enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case repoLabel = "repo_label"
        case createdAt = "created_at"
        case baseRef = "base_ref"
        case headSHA = "head_sha"
        case durationMs = "duration_ms"
        case totalFindings = "total_findings"
        case totalCostUSD = "total_cost_usd"
        case status
        case agentKind = "agent_kind"
    }
}

private struct TaskDetailJSON: Codable {
    var task: TaskRowJSON
    var findings: [FindingRowJSON]

    init(_ entry: TaskWithFindings) {
        task = TaskRowJSON(entry.task)
        findings = entry.findings.map(FindingRowJSON.init)
    }
}

private struct TaskRowJSON: Codable {
    var scope: String
    var review: String
    var agentKind: String
    var model: String?
    var durationMs: Int?
    var inputTokens: Int?
    var outputTokens: Int?
    var costUSD: Double?
    var failed: Bool
    var errorMessage: String?

    init(_ row: TaskRow) {
        scope = row.scope
        review = row.review
        agentKind = row.agentKind
        model = row.model
        durationMs = row.durationMs
        inputTokens = row.inputTokens
        outputTokens = row.outputTokens
        costUSD = row.costUSD
        failed = row.failed
        errorMessage = row.errorMessage
    }

    private enum CodingKeys: String, CodingKey {
        case scope, review
        case agentKind = "agent_kind"
        case model
        case durationMs = "duration_ms"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case costUSD = "cost_usd"
        case failed
        case errorMessage = "error_message"
    }
}

private struct FindingRowJSON: Codable {
    var file: String
    var line: Int?
    var severity: String
    var title: String
    var body: String

    init(_ row: FindingRow) {
        file = row.file
        line = row.line
        severity = row.severity
        title = row.title
        body = row.body
    }
}

import ArgumentParser
import BatonKit
import Foundation

/// `baton history` — list recent review runs.
struct HistoryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "history",
        abstract: "List recent review runs."
    )

    @OptionGroup var global: GlobalOptions

    @Option(help: "Repository root. Defaults to the current directory.")
    var repo: String?

    @Flag(name: .customLong("all-repos"), help: "List runs from every repository in the database.")
    var allRepos = false

    @Option(help: "Maximum number of runs to show.")
    var limit: Int = 20

    @Flag(help: "Emit a machine-readable JSON document on stdout.")
    var json = false

    func run() async throws {
        try await present(global.outputMode) {
            let context = try StatsContext.resolve(repo: repo, allRepos: allRepos)
            let history = HistoryRepository(connection: context.database.connection)
            let runs = try history.recentRuns(repoId: context.repoId, limit: limit)
            if json {
                try emitJSON(runs)
            } else {
                emitText(runs)
            }
        }
    }

    private func emitJSON(_ runs: [RunSummary]) throws {
        let output = runs.map(HistoryRowJSON.init)
        let data = try JSONCodec.encodeWithISO8601DatePretty(output)
        TerminalOutput.shared.out(String(bytes: data, encoding: .utf8) ?? "")
    }

    private func emitText(_ runs: [RunSummary]) {
        if runs.isEmpty {
            let message = "No runs recorded yet. Run `baton review` to start."
            TerminalOutput.shared.out(NooraUI.info(message, useColors: global.outputMode.useColors))
            return
        }

        TerminalOutput.shared.out(NooraUI.success("Recent runs", useColors: global.outputMode.useColors))
        TerminalOutput.shared.out(
            "  \(TextTable.pad("RUN ID", 24))" +
                "\(TextTable.pad("WHEN", 17))" +
                "\(TextTable.lpad("FINDINGS", 10))" +
                "\(TextTable.lpad("COST", 12))" +
                "  STATUS"
        )
        for run in runs {
            TerminalOutput.shared.out(line(for: run))
        }
    }

    private func line(for run: RunSummary) -> String {
        let when = Self.dateFormatter.string(from: run.createdAt)
        return "  \(TextTable.pad(run.runId, 24))" +
            "\(TextTable.pad(when, 17))" +
            "\(TextTable.lpad(String(run.totalFindings), 10))" +
            "\(TextTable.lpad(MoneyFormatter.format(run.totalCostUSD), 12))" +
            "  \(run.status.rawValue)"
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
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

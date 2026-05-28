import Foundation
import SQLite

/// A summary row for `baton history` and the header of `baton show`.
public struct RunSummary: Sendable, Equatable {
    public var runId: String
    public var repoLabel: String?
    public var repoId: String
    public var createdAt: Date
    public var baseRef: String
    public var headSHA: String
    public var durationMs: Int?
    public var totalFindings: Int
    public var totalCostUSD: Double?
    public var status: RunStatus
    public var agentKind: String?
}

/// A task row with its findings, used by `baton show`.
public struct RunDetail: Sendable, Equatable {
    public var summary: RunSummary
    public var tasks: [TaskWithFindings]
}

public struct TaskWithFindings: Sendable, Equatable {
    public var task: TaskRow
    public var findings: [FindingRow]
}

/// Read-only queries that list runs and load run details.
public final class HistoryRepository: @unchecked Sendable {
    private let connection: Connection

    public init(connection: Connection) {
        self.connection = connection
    }

    /// Most recent runs first, optionally filtered to a single repo.
    public func recentRuns(repoId: String?, limit: Int) throws -> [RunSummary] {
        var conditions: [String] = []
        var args: [Binding?] = []
        if let repoId {
            conditions.append("repo_id = ?")
            args.append(repoId)
        }
        let clause = conditions.isEmpty ? "" : "WHERE \(conditions.joined(separator: " AND "))"
        let sql = """
        SELECT run_id, repo_label, repo_id, created_at, base_ref, head_sha,
               duration_ms, total_findings, total_cost_usd, status, agent_kind
        FROM runs
        \(clause)
        ORDER BY created_at DESC
        LIMIT \(limit)
        """
        var results: [RunSummary] = []
        for row in try connection.prepare(sql, args) {
            guard let summary = Self.summary(from: row) else { continue }
            results.append(summary)
        }
        return results
    }

    /// Load the detailed view of one run: tasks plus findings.
    public func detail(runId: String) throws -> RunDetail? {
        let summarySQL = """
        SELECT run_id, repo_label, repo_id, created_at, base_ref, head_sha,
               duration_ms, total_findings, total_cost_usd, status, agent_kind
        FROM runs WHERE run_id = ?
        """
        guard
            let summaryRow = try connection.prepare(summarySQL, [runId]).makeIterator().next(),
            let summary = Self.summary(from: summaryRow)
        else {
            return nil
        }

        let tasksSQL = """
        SELECT task_id, run_id, scope, review, agent_kind, model,
               started_at, duration_ms, input_tokens, output_tokens, cost_usd,
               finding_count, failed, error_message,
               truncated_files_count, warnings_count, fail_on
        FROM tasks WHERE run_id = ?
        ORDER BY scope, review
        """
        var taskRows: [TaskRow] = []
        for row in try connection.prepare(tasksSQL, [runId]) {
            if let taskRow = Self.taskRow(from: row) { taskRows.append(taskRow) }
        }

        let findingsSQL = """
        SELECT finding_id, task_id, run_id, file, line, severity, title, body, ai_instructions
        FROM findings WHERE run_id = ?
        ORDER BY task_id, file, line
        """
        var grouped: [String: [FindingRow]] = [:]
        for row in try connection.prepare(findingsSQL, [runId]) {
            if let finding = Self.findingRow(from: row) {
                grouped[finding.taskId, default: []].append(finding)
            }
        }

        let combined = taskRows.map { TaskWithFindings(task: $0, findings: grouped[$0.taskId] ?? []) }
        return RunDetail(summary: summary, tasks: combined)
    }

    // MARK: - Row decoders

    private static func summary(from row: Statement.Element) -> RunSummary? {
        guard
            let runId = row[0] as? String,
            let repoId = row[2] as? String,
            let createdAt = row[3] as? Double,
            let baseRef = row[4] as? String,
            let headSHA = row[5] as? String,
            let totalFindings = row[7] as? Int64,
            let statusRaw = row[9] as? String,
            let status = RunStatus(rawValue: statusRaw)
        else {
            return nil
        }
        return RunSummary(
            runId: runId,
            repoLabel: row[1] as? String,
            repoId: repoId,
            createdAt: Date(timeIntervalSince1970: createdAt),
            baseRef: baseRef,
            headSHA: headSHA,
            durationMs: (row[6] as? Int64).map(Int.init),
            totalFindings: Int(totalFindings),
            totalCostUSD: row[8] as? Double,
            status: status,
            agentKind: row[10] as? String
        )
    }

    private static func taskRow(from row: Statement.Element) -> TaskRow? {
        guard
            let taskId = row[0] as? String,
            let runId = row[1] as? String,
            let scope = row[2] as? String,
            let review = row[3] as? String,
            let agentKind = row[4] as? String,
            let failOn = row[16] as? String
        else {
            return nil
        }
        let started = (row[6] as? Double).map { Date(timeIntervalSince1970: $0) }
        return TaskRow(
            taskId: taskId, runId: runId, scope: scope, review: review,
            agentKind: agentKind, model: row[5] as? String,
            startedAt: started,
            durationMs: (row[7] as? Int64).map(Int.init),
            inputTokens: (row[8] as? Int64).map(Int.init),
            outputTokens: (row[9] as? Int64).map(Int.init),
            costUSD: row[10] as? Double,
            findingCount: Int(row[11] as? Int64 ?? 0),
            failed: (row[12] as? Int64 ?? 0) != 0,
            errorMessage: row[13] as? String,
            truncatedFilesCount: Int(row[14] as? Int64 ?? 0),
            warningsCount: Int(row[15] as? Int64 ?? 0),
            failOn: failOn
        )
    }

    private static func findingRow(from row: Statement.Element) -> FindingRow? {
        guard
            let findingId = row[0] as? String,
            let taskId = row[1] as? String,
            let runId = row[2] as? String,
            let file = row[3] as? String,
            let severity = row[5] as? String,
            let title = row[6] as? String,
            let body = row[7] as? String
        else {
            return nil
        }
        return FindingRow(
            findingId: findingId, taskId: taskId, runId: runId,
            file: file,
            line: (row[4] as? Int64).map(Int.init),
            severity: severity, title: title, body: body,
            aiInstructions: row[8] as? String
        )
    }
}

import Foundation
import SQLite

/// Bundle of data needed to record one run (keeps `recordRun` parameter count
/// under swiftlint's limit and gives callers a clear input contract).
public struct RunRecordInput: Sendable {
    public var runId: String
    public var repo: RepoIdentity
    public var baseRef: String
    public var headSHA: String
    public var createdAt: Date
    public var status: RunStatus
    public var tasks: [TaskRecordInput]
    public var cliVersion: String?

    public init(
        runId: String,
        repo: RepoIdentity,
        baseRef: String,
        headSHA: String,
        createdAt: Date,
        status: RunStatus,
        tasks: [TaskRecordInput],
        cliVersion: String? = nil
    ) {
        self.runId = runId
        self.repo = repo
        self.baseRef = baseRef
        self.headSHA = headSHA
        self.createdAt = createdAt
        self.status = status
        self.tasks = tasks
        self.cliVersion = cliVersion
    }
}

/// One task plus the findings it produced.
public struct TaskRecordInput: Sendable {
    public var scope: String
    public var review: String
    public var agentKind: String
    public var model: String?
    public var startedAt: Date?
    public var durationMs: Int?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var costUSD: Double?
    public var failed: Bool
    public var errorMessage: String?
    public var truncatedFilesCount: Int
    public var warningsCount: Int
    public var failOn: String
    public var findings: [Finding]

    public init(
        scope: String,
        review: String,
        agentKind: String,
        model: String? = nil,
        startedAt: Date? = nil,
        durationMs: Int? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        costUSD: Double? = nil,
        failed: Bool = false,
        errorMessage: String? = nil,
        truncatedFilesCount: Int = 0,
        warningsCount: Int = 0,
        failOn: String,
        findings: [Finding] = []
    ) {
        self.scope = scope
        self.review = review
        self.agentKind = agentKind
        self.model = model
        self.startedAt = startedAt
        self.durationMs = durationMs
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUSD = costUSD
        self.failed = failed
        self.errorMessage = errorMessage
        self.truncatedFilesCount = truncatedFilesCount
        self.warningsCount = warningsCount
        self.failOn = failOn
        self.findings = findings
    }
}

/// Writes runs to one or more SQLite databases.
///
/// The store dispatches a single `RunRecordInput` to every path implied by
/// the `location`, so a `.both(repoRoot:)` write goes to the global database
/// and the per-repo database in turn. Failures on one path do not abort the
/// other — they are returned to the caller, who decides whether to surface
/// them.
public struct RunDatabaseStore: Sendable {
    public let location: DatabaseLocation

    public init(location: DatabaseLocation) {
        self.location = location
    }

    /// Record a run, its tasks, and the findings for each task.
    ///
    /// Best-effort: a failure on one configured database file does not stop
    /// the write to the next path. Any errors are returned per-target; JSON
    /// artifacts remain the source of truth.
    public func recordRun(_ input: RunRecordInput) -> [BatonDatabaseError] {
        var errors: [BatonDatabaseError] = []
        for target in DatabasePathResolver.writeTargets(for: location) {
            do {
                let database = try BatonDatabase.open(at: target)
                try write(input, to: database.connection)
            } catch let error as BatonDatabaseError {
                errors.append(error)
            } catch {
                errors.append(.queryFailed(
                    operation: "recordRun(\(target.path))",
                    underlying: "\(error)"
                ))
            }
        }
        return errors
    }

    // MARK: - Write

    private func write(_ input: RunRecordInput, to db: Connection) throws {
        try db.transaction {
            let totals = aggregate(tasks: input.tasks)
            try insertRun(input: input, totals: totals, db: db)
            for task in input.tasks {
                let taskId = Self.makeTaskId(runId: input.runId, scope: task.scope, review: task.review)
                try insertTask(taskId: taskId, runId: input.runId, task: task, db: db)
                for finding in task.findings {
                    try insertFinding(taskId: taskId, runId: input.runId, finding: finding, db: db)
                }
            }
        }
    }

    private func aggregate(tasks: [TaskRecordInput]) -> Totals {
        var totals = Totals()
        totals.totalTasks = tasks.count
        for task in tasks {
            totals.totalFindings += task.findings.count
            if let value = task.inputTokens {
                totals.totalInputTokens = (totals.totalInputTokens ?? 0) + value
            }
            if let value = task.outputTokens {
                totals.totalOutputTokens = (totals.totalOutputTokens ?? 0) + value
            }
            if let value = task.costUSD {
                totals.totalCostUSD = (totals.totalCostUSD ?? 0) + value
            }
            if let value = task.durationMs {
                totals.durationMs = (totals.durationMs ?? 0) + value
            }
            if totals.agentKind == nil {
                totals.agentKind = task.agentKind
            } else if totals.agentKind != task.agentKind {
                totals.agentKind = "mixed"
            }
        }
        return totals
    }

    private func insertRun(input: RunRecordInput, totals: Totals, db: Connection) throws {
        try db.run(
            """
            INSERT OR REPLACE INTO runs(
                run_id, repo_id, repo_root, repo_label, base_ref, head_sha,
                created_at, finished_at, duration_ms, status,
                total_tasks, total_findings,
                total_input_tokens, total_output_tokens, total_cost_usd,
                agent_kind, cli_version
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            input.runId,
            input.repo.id,
            input.repo.absolutePath,
            input.repo.label,
            input.baseRef,
            input.headSHA,
            input.createdAt.timeIntervalSince1970,
            totals.durationMs.map { input.createdAt.addingTimeInterval(Double($0) / 1000.0).timeIntervalSince1970 },
            totals.durationMs.map { Int64($0) },
            input.status.rawValue,
            Int64(totals.totalTasks),
            Int64(totals.totalFindings),
            totals.totalInputTokens.map { Int64($0) },
            totals.totalOutputTokens.map { Int64($0) },
            totals.totalCostUSD,
            totals.agentKind,
            input.cliVersion
        )
    }

    private func insertTask(taskId: String, runId: String, task: TaskRecordInput, db: Connection) throws {
        try db.run(
            """
            INSERT OR REPLACE INTO tasks(
                task_id, run_id, scope, review, agent_kind, model,
                started_at, duration_ms, input_tokens, output_tokens, cost_usd,
                finding_count, failed, error_message,
                truncated_files_count, warnings_count, fail_on
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            taskId,
            runId,
            task.scope,
            task.review,
            task.agentKind,
            task.model,
            task.startedAt?.timeIntervalSince1970,
            task.durationMs.map { Int64($0) },
            task.inputTokens.map { Int64($0) },
            task.outputTokens.map { Int64($0) },
            task.costUSD,
            Int64(task.findings.count),
            task.failed ? Int64(1) : Int64(0),
            task.errorMessage,
            Int64(task.truncatedFilesCount),
            Int64(task.warningsCount),
            task.failOn
        )
    }

    private func insertFinding(taskId: String, runId: String, finding: Finding, db: Connection) throws {
        let findingId = Self.makeFindingId(taskId: taskId, finding: finding)
        try db.run(
            """
            INSERT OR REPLACE INTO findings(
                finding_id, task_id, run_id, file, line, severity, title, body, ai_instructions
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            findingId,
            taskId,
            runId,
            finding.file,
            finding.line.map { Int64($0) },
            finding.severity.rawValue,
            finding.title,
            finding.body,
            finding.aiInstructions
        )
    }

    // MARK: - ID derivation

    public static func makeTaskId(runId: String, scope: String, review: String) -> String {
        let s = scope.isEmpty ? "root" : sanitize(scope)
        let r = sanitize(review)
        return "\(runId):\(s):\(r)"
    }

    public static func makeFindingId(taskId: String, finding: Finding) -> String {
        let line = finding.line.map(String.init) ?? "_"
        let key = "\(finding.file)|\(line)|\(finding.severity.rawValue)|\(finding.title)"
        let hash = RepoIdentity.leftPadHex(FNV1a.hash(key), width: 16).prefix(8)
        return "\(taskId):\(hash)"
    }

    private static func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "/", with: "__")
            .replacingOccurrences(of: "\\", with: "__")
            .replacingOccurrences(of: ":", with: "_")
    }

    // MARK: - Internal totals

    private struct Totals {
        var totalTasks = 0
        var totalFindings = 0
        var totalInputTokens: Int?
        var totalOutputTokens: Int?
        var totalCostUSD: Double?
        var durationMs: Int?
        var agentKind: String?
    }
}

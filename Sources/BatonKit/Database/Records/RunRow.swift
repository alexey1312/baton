import Foundation

/// DTO mirroring a row in the `runs` table.
public struct RunRow: Sendable, Codable, Equatable {
    public var runId: String
    public var repoId: String
    public var repoRoot: String
    public var repoLabel: String?
    public var baseRef: String
    public var headSHA: String
    public var createdAt: Date
    public var finishedAt: Date?
    public var durationMs: Int?
    public var status: RunStatus
    public var totalTasks: Int
    public var totalFindings: Int
    public var totalInputTokens: Int?
    public var totalOutputTokens: Int?
    public var totalCostUSD: Double?
    public var agentKind: String?
    public var cliVersion: String?

    public init(
        runId: String,
        repoId: String,
        repoRoot: String,
        repoLabel: String?,
        baseRef: String,
        headSHA: String,
        createdAt: Date,
        finishedAt: Date? = nil,
        durationMs: Int? = nil,
        status: RunStatus,
        totalTasks: Int = 0,
        totalFindings: Int = 0,
        totalInputTokens: Int? = nil,
        totalOutputTokens: Int? = nil,
        totalCostUSD: Double? = nil,
        agentKind: String? = nil,
        cliVersion: String? = nil
    ) {
        self.runId = runId
        self.repoId = repoId
        self.repoRoot = repoRoot
        self.repoLabel = repoLabel
        self.baseRef = baseRef
        self.headSHA = headSHA
        self.createdAt = createdAt
        self.finishedAt = finishedAt
        self.durationMs = durationMs
        self.status = status
        self.totalTasks = totalTasks
        self.totalFindings = totalFindings
        self.totalInputTokens = totalInputTokens
        self.totalOutputTokens = totalOutputTokens
        self.totalCostUSD = totalCostUSD
        self.agentKind = agentKind
        self.cliVersion = cliVersion
    }
}

/// Outcome of a recorded run.
public enum RunStatus: String, Sendable, Codable, Equatable {
    case success
    case failed
    case empty
}

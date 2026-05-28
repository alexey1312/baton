import Foundation

/// DTO mirroring a row in the `tasks` table.
public struct TaskRow: Sendable, Codable, Equatable {
    public var taskId: String
    public var runId: String
    public var scope: String
    public var review: String
    public var agentKind: String
    public var model: String?
    public var startedAt: Date?
    public var durationMs: Int?
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var costUSD: Double?
    public var findingCount: Int
    public var failed: Bool
    public var errorMessage: String?
    public var truncatedFilesCount: Int
    public var warningsCount: Int
    public var failOn: String

    public init(
        taskId: String,
        runId: String,
        scope: String,
        review: String,
        agentKind: String,
        model: String? = nil,
        startedAt: Date? = nil,
        durationMs: Int? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        costUSD: Double? = nil,
        findingCount: Int = 0,
        failed: Bool = false,
        errorMessage: String? = nil,
        truncatedFilesCount: Int = 0,
        warningsCount: Int = 0,
        failOn: String
    ) {
        self.taskId = taskId
        self.runId = runId
        self.scope = scope
        self.review = review
        self.agentKind = agentKind
        self.model = model
        self.startedAt = startedAt
        self.durationMs = durationMs
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUSD = costUSD
        self.findingCount = findingCount
        self.failed = failed
        self.errorMessage = errorMessage
        self.truncatedFilesCount = truncatedFilesCount
        self.warningsCount = warningsCount
        self.failOn = failOn
    }
}

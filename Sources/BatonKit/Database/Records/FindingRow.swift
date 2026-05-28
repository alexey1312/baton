import Foundation

/// DTO mirroring a row in the `findings` table.
public struct FindingRow: Sendable, Codable, Equatable {
    public var findingId: String
    public var taskId: String
    public var runId: String
    public var file: String
    public var line: Int?
    public var severity: String
    public var title: String
    public var body: String
    public var aiInstructions: String?

    public init(
        findingId: String,
        taskId: String,
        runId: String,
        file: String,
        line: Int?,
        severity: String,
        title: String,
        body: String,
        aiInstructions: String? = nil
    ) {
        self.findingId = findingId
        self.taskId = taskId
        self.runId = runId
        self.file = file
        self.line = line
        self.severity = severity
        self.title = title
        self.body = body
        self.aiInstructions = aiInstructions
    }
}

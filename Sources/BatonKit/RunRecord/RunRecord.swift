import Foundation

/// Errors raised while writing or reading run records.
public enum RunRecordError: BatonError {
    case writeFailed(path: String, underlying: String)
    case runNotFound(runId: String)
    case latestMissing
    case corruptRecord(path: String)

    public var errorDescription: String? {
        switch self {
        case let .writeFailed(path, underlying):
            "Failed to write run artifact at \(path): \(underlying)"
        case let .runNotFound(runId):
            "Run '\(runId)' was not found under .baton/runs"
        case .latestMissing:
            "No latest run found under .baton/runs"
        case let .corruptRecord(path):
            "Run record at \(path) is missing or corrupt"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .writeFailed:
            "Check available disk space and write permissions for .baton/runs."
        case .runNotFound, .corruptRecord:
            "Verify the run id, or re-run `baton review`."
        case .latestMissing:
            "Run `baton review` first to produce a run."
        }
    }
}

/// Run-level metadata persisted to `manifest.json`.
public struct RunManifest: Codable, Sendable {
    public var runId: String
    public var base: String
    /// The review-time head commit SHA, so `publish` can detect a stale head.
    public var headSHA: String
    public var createdAt: Date
    public var tasks: [TaskSummary]

    public init(runId: String, base: String, headSHA: String, createdAt: Date, tasks: [TaskSummary]) {
        self.runId = runId
        self.base = base
        self.headSHA = headSHA
        self.createdAt = createdAt
        self.tasks = tasks
    }

    public struct TaskSummary: Codable, Sendable {
        public var scope: String
        public var review: String
        public var findingsCount: Int
        public var failed: Bool
        public var recordFile: String

        public init(scope: String, review: String, findingsCount: Int, failed: Bool, recordFile: String) {
            self.scope = scope
            self.review = review
            self.findingsCount = findingsCount
            self.failed = failed
            self.recordFile = recordFile
        }
    }
}

/// A run loaded back from disk for rendering or publishing.
public struct LoadedRun: Sendable {
    public var directory: URL
    public var manifest: RunManifest
    public var results: [ReviewTaskResult]

    public init(directory: URL, manifest: RunManifest, results: [ReviewTaskResult]) {
        self.directory = directory
        self.manifest = manifest
        self.results = results
    }
}

/// Writes and reads per-run artifacts under `.baton/runs/<run-id>/`.
public struct RunRecordStore: Sendable {
    /// The `.baton/runs` directory.
    public let runsDirectory: URL

    public init(repoRoot: URL) {
        runsDirectory = repoRoot
            .appendingPathComponent(".baton", isDirectory: true)
            .appendingPathComponent("runs", isDirectory: true)
    }

    /// Generate a sortable run id (timestamp-based).
    public static func newRunId(date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    /// Flatten path separators so a scope/review name is filesystem-safe.
    public static func sanitize(_ name: String) -> String {
        let cleaned = name.isEmpty ? "root" : name
        return cleaned
            .replacingOccurrences(of: "/", with: "__")
            .replacingOccurrences(of: "\\", with: "__")
    }

    /// Write a full run: per-task `.json`/`.log`/`.prompt.md`, a `manifest.json`,
    /// and update the `latest` pointer. Returns the run directory.
    @discardableResult
    public func write(runId: String, base: String, headSHA: String, tasks: [CompletedTask]) throws -> URL {
        let runDir = runsDirectory.appendingPathComponent(runId, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: runDir, withIntermediateDirectories: true)
        } catch {
            throw RunRecordError.writeFailed(path: runDir.path, underlying: "\(error)")
        }

        var summaries: [RunManifest.TaskSummary] = []
        for task in tasks {
            let stem = "\(Self.sanitize(task.result.scope))--\(Self.sanitize(task.result.review))"
            try writeData(encode(task.result), to: runDir.appendingPathComponent("\(stem).json"))
            try writeData(Data(task.rawOutput.utf8), to: runDir.appendingPathComponent("\(stem).log"))
            try writeData(Data(task.prompt.utf8), to: runDir.appendingPathComponent("\(stem).prompt.md"))
            summaries.append(RunManifest.TaskSummary(
                scope: task.result.scope,
                review: task.result.review,
                findingsCount: task.result.findings.count,
                failed: task.result.failed,
                recordFile: "\(stem).json"
            ))
        }

        let manifest = RunManifest(
            runId: runId, base: base, headSHA: headSHA, createdAt: Date(), tasks: summaries
        )
        let manifestData = (try? JSONCodec.encodeWithISO8601DatePretty(manifest)) ?? Data()
        try writeData(manifestData, to: runDir.appendingPathComponent("manifest.json"))

        // Update the latest pointer (a plain file holding the run id).
        try writeData(Data(runId.utf8), to: runsDirectory.appendingPathComponent("latest"))
        return runDir
    }

    /// Load a saved run. `nil` resolves the `latest` pointer.
    public func load(runId: String?) throws -> LoadedRun {
        let id: String
        if let runId, runId != "latest" {
            id = runId
        } else {
            let latestURL = runsDirectory.appendingPathComponent("latest")
            guard let data = try? Data(contentsOf: latestURL),
                  let pointer = String(bytes: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
                  !pointer.isEmpty
            else {
                throw RunRecordError.latestMissing
            }
            id = pointer
        }

        let runDir = runsDirectory.appendingPathComponent(id, isDirectory: true)
        let manifestURL = runDir.appendingPathComponent("manifest.json")
        guard let manifestData = try? Data(contentsOf: manifestURL) else {
            throw RunRecordError.runNotFound(runId: id)
        }
        guard let manifest = try? JSONCodec.decodeWithISO8601Date(RunManifest.self, from: manifestData) else {
            throw RunRecordError.corruptRecord(path: manifestURL.path)
        }

        let results: [ReviewTaskResult] = try manifest.tasks.map { summary in
            let url = runDir.appendingPathComponent(summary.recordFile)
            guard let data = try? Data(contentsOf: url),
                  let result = try? JSONCodec.decode(ReviewTaskResult.self, from: data)
            else {
                throw RunRecordError.corruptRecord(path: url.path)
            }
            return result
        }
        return LoadedRun(directory: runDir, manifest: manifest, results: results)
    }

    // MARK: - Helpers

    private func encode(_ result: ReviewTaskResult) throws -> Data {
        do {
            return try JSONCodec.encodePretty(result)
        } catch {
            throw RunRecordError.writeFailed(path: "\(result.scope)--\(result.review).json", underlying: "\(error)")
        }
    }

    private func writeData(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url)
        } catch {
            throw RunRecordError.writeFailed(path: url.path, underlying: "\(error)")
        }
    }
}

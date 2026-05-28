import Foundation
import SQLite

/// One cached feedback row: a finding's identity plus its accumulated signal.
public struct FeedbackRow: Sendable, Equatable {
    public var file: String
    public var line: Int?
    public var title: String
    public var severity: String
    public var weight: Int
    public var threadCount: Int

    public init(file: String, line: Int?, title: String, severity: String, weight: Int, threadCount: Int) {
        self.file = file
        self.line = line
        self.title = title
        self.severity = severity
        self.weight = weight
        self.threadCount = threadCount
    }
}

/// Reads and writes the optional, non-authoritative `learn` feedback cache.
///
/// The cache exists only to power `baton stats` trends. A `learn` run never reads
/// it — the signal is re-derived from GitHub on every run — so the cache can never
/// widen the effective `lookback_days` window or alter the agent's inputs. Upserts
/// store absolute (not incremented) values keyed by finding identity, so writing
/// the same observation twice is idempotent.
public final class FeedbackRepository: @unchecked Sendable {
    private let connection: Connection

    public init(connection: Connection) {
        self.connection = connection
    }

    /// Upsert one candidate's signal. Idempotent: a repeated write replaces the row
    /// rather than accumulating.
    public func upsert(_ candidate: RuleCandidate, repoId: String, at date: Date = Date()) throws {
        try connection.run(
            """
            INSERT OR REPLACE INTO feedback(
                repo_id, finding_id, file, line, title, severity, weight, thread_count, last_seen_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            repoId,
            candidate.finding.cacheKey,
            candidate.finding.file,
            candidate.finding.line.map { Int64($0) },
            candidate.finding.title,
            candidate.finding.severity.rawValue,
            Int64(candidate.weight),
            Int64(candidate.threadCount),
            date.timeIntervalSince1970
        )
    }

    /// Upsert many candidates in one transaction.
    public func upsertAll(_ candidates: [RuleCandidate], repoId: String, at date: Date = Date()) throws {
        try connection.transaction {
            for candidate in candidates {
                try upsert(candidate, repoId: repoId, at: date)
            }
        }
    }

    /// The most net-negative (👎-weighted) rules.
    public func mostDownvoted(repoId: String?, limit: Int = 5) throws -> [FeedbackRow] {
        try query(repoId: repoId, order: "weight ASC", having: "weight < 0", limit: limit)
    }

    /// The most net-positive (👍-weighted) rules.
    public func mostUpvoted(repoId: String?, limit: Int = 5) throws -> [FeedbackRow] {
        try query(repoId: repoId, order: "weight DESC", having: "weight > 0", limit: limit)
    }

    private func query(repoId: String?, order: String, having: String, limit: Int) throws -> [FeedbackRow] {
        var conditions = [having]
        var args: [Binding?] = []
        if let repoId {
            conditions.append("repo_id = ?")
            args.append(repoId)
        }
        let sql = """
        SELECT file, line, title, severity, weight, thread_count
        FROM feedback
        WHERE \(conditions.joined(separator: " AND "))
        ORDER BY \(order)
        LIMIT \(limit)
        """
        var rows: [FeedbackRow] = []
        for row in try connection.prepare(sql, args) {
            guard let file = row[0] as? String,
                  let title = row[2] as? String,
                  let severity = row[3] as? String
            else { continue }
            rows.append(FeedbackRow(
                file: file,
                line: (row[1] as? Int64).map(Int.init),
                title: title,
                severity: severity,
                weight: Int(row[4] as? Int64 ?? 0),
                threadCount: Int(row[5] as? Int64 ?? 0)
            ))
        }
        return rows
    }
}

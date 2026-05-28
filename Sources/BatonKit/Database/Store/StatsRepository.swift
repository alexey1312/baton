import Foundation
import SQLite

/// Filters that narrow stats / history queries.
public struct StatsFilter: Sendable, Equatable {
    public var repoId: String?
    public var scope: String?
    public var review: String?
    public var since: Date?

    public init(
        repoId: String? = nil,
        scope: String? = nil,
        review: String? = nil,
        since: Date? = nil
    ) {
        self.repoId = repoId
        self.scope = scope
        self.review = review
        self.since = since
    }
}

/// Aggregate counts for the headline stats block.
public struct StatsSummary: Sendable, Equatable {
    public var totalRuns: Int
    public var totalTasks: Int
    public var totalFindings: Int
    public var totalCostUSD: Double?
    public var totalInputTokens: Int?
    public var totalOutputTokens: Int?
    public var earliestRun: Date?
}

public struct ReviewStat: Sendable, Equatable {
    public var review: String
    public var runs: Int
    public var findings: Int
    public var avgDurationMs: Double?
    public var totalCostUSD: Double?
}

public struct SeverityStat: Sendable, Equatable {
    public var severity: String
    public var count: Int
}

public struct FileStat: Sendable, Equatable {
    public var file: String
    public var count: Int
}

public struct ModelCostStat: Sendable, Equatable {
    public var agentKind: String
    public var model: String?
    public var costUSD: Double
    public var runs: Int
}

/// Aggregate read-only queries powering `baton stats`.
public final class StatsRepository: @unchecked Sendable {
    private let connection: Connection

    public init(connection: Connection) {
        self.connection = connection
    }

    public func summary(filter: StatsFilter) throws -> StatsSummary {
        let needsTasksJoin = filter.review != nil || filter.scope != nil
        let (clause, args) = whereClause(filter, runsAlias: "r", joinsTasks: needsTasksJoin)
        let sql = if needsTasksJoin {
            """
            SELECT COUNT(DISTINCT r.run_id),
                   COUNT(t.task_id),
                   COALESCE(SUM(t.finding_count), 0),
                   SUM(t.cost_usd),
                   SUM(t.input_tokens),
                   SUM(t.output_tokens),
                   MIN(r.created_at)
            FROM runs r
            JOIN tasks t ON t.run_id = r.run_id
            \(clause)
            """
        } else {
            """
            SELECT COUNT(*),
                   COALESCE(SUM(total_tasks), 0),
                   COALESCE(SUM(total_findings), 0),
                   SUM(total_cost_usd),
                   SUM(total_input_tokens),
                   SUM(total_output_tokens),
                   MIN(created_at)
            FROM runs r
            \(clause)
            """
        }
        let row = try connectionScalarRow(connection, sql, args)
        let earliest = (row[6] as? Double).map { Date(timeIntervalSince1970: $0) }
        return StatsSummary(
            totalRuns: Int(row[0] as? Int64 ?? 0),
            totalTasks: Int(row[1] as? Int64 ?? 0),
            totalFindings: Int(row[2] as? Int64 ?? 0),
            totalCostUSD: row[3] as? Double,
            totalInputTokens: (row[4] as? Int64).map(Int.init),
            totalOutputTokens: (row[5] as? Int64).map(Int.init),
            earliestRun: earliest
        )
    }

    public func byReview(filter: StatsFilter) throws -> [ReviewStat] {
        let (clause, args) = whereClause(filter, runsAlias: "r")
        let sql = """
        SELECT t.review,
               COUNT(DISTINCT t.run_id),
               COALESCE(SUM(t.finding_count), 0),
               AVG(t.duration_ms),
               SUM(t.cost_usd)
        FROM tasks t
        JOIN runs r ON r.run_id = t.run_id
        \(clause)
        GROUP BY t.review
        ORDER BY COUNT(DISTINCT t.run_id) DESC
        """
        var results: [ReviewStat] = []
        for row in try connection.prepare(sql, args) {
            guard let review = row[0] as? String else { continue }
            results.append(ReviewStat(
                review: review,
                runs: Int(row[1] as? Int64 ?? 0),
                findings: Int(row[2] as? Int64 ?? 0),
                avgDurationMs: row[3] as? Double,
                totalCostUSD: row[4] as? Double
            ))
        }
        return results
    }

    public func bySeverity(filter: StatsFilter) throws -> [SeverityStat] {
        let (clause, args) = whereClause(filter, runsAlias: "r")
        let sql = """
        SELECT f.severity, COUNT(*)
        FROM findings f
        JOIN runs r ON r.run_id = f.run_id
        \(clause)
        GROUP BY f.severity
        ORDER BY CASE f.severity
            WHEN 'high' THEN 0 WHEN 'medium' THEN 1 ELSE 2
        END
        """
        var results: [SeverityStat] = []
        for row in try connection.prepare(sql, args) {
            guard let severity = row[0] as? String else { continue }
            results.append(SeverityStat(severity: severity, count: Int(row[1] as? Int64 ?? 0)))
        }
        return results
    }

    public func topFiles(filter: StatsFilter, limit: Int = 10) throws -> [FileStat] {
        let (clause, args) = whereClause(filter, runsAlias: "r")
        let sql = """
        SELECT f.file, COUNT(*)
        FROM findings f
        JOIN runs r ON r.run_id = f.run_id
        \(clause)
        GROUP BY f.file
        ORDER BY COUNT(*) DESC
        LIMIT \(limit)
        """
        var results: [FileStat] = []
        for row in try connection.prepare(sql, args) {
            guard let file = row[0] as? String else { continue }
            results.append(FileStat(file: file, count: Int(row[1] as? Int64 ?? 0)))
        }
        return results
    }

    public func costByModel(filter: StatsFilter) throws -> [ModelCostStat] {
        let (clause, args) = whereClause(filter, runsAlias: "r")
        let sql = """
        SELECT t.agent_kind, t.model,
               COALESCE(SUM(t.cost_usd), 0),
               COUNT(DISTINCT t.run_id)
        FROM tasks t
        JOIN runs r ON r.run_id = t.run_id
        \(clause)
        GROUP BY t.agent_kind, t.model
        ORDER BY SUM(t.cost_usd) IS NULL, SUM(t.cost_usd) DESC
        """
        var results: [ModelCostStat] = []
        for row in try connection.prepare(sql, args) {
            guard let agent = row[0] as? String else { continue }
            let model = row[1] as? String
            let cost = row[2] as? Double ?? 0
            let runs = Int(row[3] as? Int64 ?? 0)
            results.append(ModelCostStat(agentKind: agent, model: model, costUSD: cost, runs: runs))
        }
        return results
    }

    // MARK: - WHERE clause builder

    /// Build a parametrised WHERE clause from the filter. `runsAlias` is the alias
    /// for the runs table; set `joinsTasks` when the caller's FROM clause includes
    /// a `tasks t` join so review/scope predicates can reference `t.review` /
    /// `t.scope` safely.
    private func whereClause(
        _ filter: StatsFilter,
        runsAlias: String = "runs",
        joinsTasks: Bool = true
    ) -> (String, [Binding?]) {
        var conditions: [String] = []
        var args: [Binding?] = []
        if let repoId = filter.repoId {
            conditions.append("\(runsAlias).repo_id = ?")
            args.append(repoId)
        }
        if let since = filter.since {
            conditions.append("\(runsAlias).created_at >= ?")
            args.append(since.timeIntervalSince1970)
        }
        if joinsTasks, let review = filter.review {
            conditions.append("t.review = ?")
            args.append(review)
        }
        if joinsTasks, let scope = filter.scope {
            conditions.append("t.scope = ?")
            args.append(scope)
        }
        guard !conditions.isEmpty else { return ("", []) }
        return ("WHERE \(conditions.joined(separator: " AND "))", args)
    }
}

/// Fetch the first row of a parametrised query as a `Statement.Element`.
/// Throws ``BatonDatabaseError.queryFailed`` when the row is missing.
private func connectionScalarRow(
    _ connection: Connection, _ sql: String, _ args: [Binding?]
) throws -> Statement.Element {
    guard let row = try connection.prepare(sql, args).makeIterator().next() else {
        throw BatonDatabaseError.queryFailed(operation: "scalar row", underlying: "no rows")
    }
    return row
}

import Foundation

/// Which category a collected thread falls into.
public enum ThreadBucket: String, Sendable, Equatable, Codable {
    /// Baton thread resolved by a human — the finding was acted on.
    case accepted
    /// Baton thread left unresolved (or resolved only by Baton's automation).
    case ignored
    /// Baton thread GitHub flagged as outdated.
    case outdated
    /// Human-authored thread Baton did not author — a missing-coverage signal.
    case humanAuthored
}

/// Direction a rule should move based on accumulated signal.
public enum CandidateDirection: String, Sendable, Equatable, Codable {
    case reinforce
    case relax
}

/// A ranked rule candidate: the underlying finding identity, its signed weight,
/// and the number of attributed threads that contributed.
public struct RuleCandidate: Sendable, Equatable {
    public var finding: FindingIdentity
    public var weight: Int
    public var threadCount: Int

    public init(finding: FindingIdentity, weight: Int, threadCount: Int) {
        self.finding = finding
        self.weight = weight
        self.threadCount = threadCount
    }

    /// Net-negative weight ⇒ relax/remove; otherwise reinforce.
    public var direction: CandidateDirection {
        weight < 0 ? .relax : .reinforce
    }
}

/// Pure functions that attribute, bucket, and weight collected thread signal.
public enum SignalAnalysis {
    // MARK: - Attribution

    /// Attribute each thread to the deepest scope that owns its file (the same
    /// owner resolution diff routing uses). Threads on files outside any scope are
    /// dropped. Returns a dictionary keyed by `scope.path` (`""` for the root).
    public static func attribute(
        _ threads: [ReviewThreadSignal],
        scopes: [ScopeConfig]
    ) -> [String: [ReviewThreadSignal]] {
        var groups: [String: [ReviewThreadSignal]] = [:]
        for thread in threads {
            guard let owner = DiffRouter.owner(of: thread.file, scopes: scopes) else { continue }
            groups[owner.path, default: []].append(thread)
        }
        return groups
    }

    // MARK: - Bucketing

    /// Categorize a single thread.
    public static func bucket(_ thread: ReviewThreadSignal) -> ThreadBucket {
        guard thread.isBatonAuthored else { return .humanAuthored }
        switch thread.resolution {
        case .outdated:
            return .outdated
        case .resolved:
            return thread.resolvedByAutomation ? .ignored : .accepted
        case .unresolved:
            return .ignored
        }
    }

    /// Count threads per bucket.
    public static func bucketCounts(_ threads: [ReviewThreadSignal]) -> [ThreadBucket: Int] {
        var counts: [ThreadBucket: Int] = [:]
        for thread in threads {
            counts[bucket(thread), default: 0] += 1
        }
        return counts
    }

    // MARK: - Weighting

    /// The signed signal weight of one thread: the resolution contribution
    /// (augmented, not replaced, by reaction weight). Outdated threads contribute
    /// no resolution weight (weighted low); resolution by Baton's own automation
    /// contributes none either.
    public static func weight(_ thread: ReviewThreadSignal) -> Int {
        resolutionContribution(thread) + thread.netReactionWeight
    }

    private static func resolutionContribution(_ thread: ReviewThreadSignal) -> Int {
        switch thread.resolution {
        case .outdated:
            0
        case .resolved:
            thread.resolvedByAutomation ? 0 : 1
        case .unresolved:
            -1
        }
    }

    // MARK: - Candidate ranking

    /// Rank Baton-authored threads into rule candidates by summing per-finding
    /// weight. Sorted by ascending weight so the most 👎-heavy relax candidates
    /// lead. Human-authored threads carry no finding identity and are excluded.
    public static func candidates(_ threads: [ReviewThreadSignal]) -> [RuleCandidate] {
        var order: [String] = []
        var byKey: [String: RuleCandidate] = [:]

        for thread in threads {
            guard thread.isBatonAuthored, let finding = thread.finding else { continue }
            let key = finding.cacheKey
            if var existing = byKey[key] {
                existing.weight += weight(thread)
                existing.threadCount += 1
                byKey[key] = existing
            } else {
                order.append(key)
                byKey[key] = RuleCandidate(finding: finding, weight: weight(thread), threadCount: 1)
            }
        }

        return order.compactMap { byKey[$0] }
            .sorted { $0.weight < $1.weight }
    }

    /// The count of Baton-authored threads in `threads` — the signal *volume*
    /// `min_signal` is measured against (never the signed net weight, so a
    /// 👎-heavy scope is not skipped for being "below threshold").
    public static func signalVolume(_ threads: [ReviewThreadSignal]) -> Int {
        threads.reduce(0) { $1.isBatonAuthored ? $0 + 1 : $0 }
    }

    /// Human-authored threads, which carry missing-coverage signal.
    public static func humanAuthoredThreads(_ threads: [ReviewThreadSignal]) -> [ReviewThreadSignal] {
        threads.filter { !$0.isBatonAuthored }
    }
}

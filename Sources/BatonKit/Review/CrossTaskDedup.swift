/// Folds findings that multiple parallel `(scope, review)` tasks independently
/// reported for the same `(file, line)` into a single finding, tagging it with the
/// reviews that confirmed it.
///
/// Runs once after orchestration, before persistence, so the deduplicated set is
/// what reaches the database, the renderer, and GitHub publish alike. It is a
/// no-op when no two tasks overlap (each finding is its own group → emitted
/// unchanged), so the common case preserves output byte-for-byte.
///
/// Exit semantics are never softened: a duplicate that crossed its owning review's
/// `failOn` but was merged into a sibling sets ``ReviewTaskResult/removedCrossingFindings``,
/// and the surviving finding's severity is the max across the group.
public enum CrossTaskDedup {
    /// Deduplicate findings across `results`, returning results in the same order.
    public static func merge(_ results: [ReviewTaskResult]) -> [ReviewTaskResult] {
        let groups = group(flatten(results))
        return apply(buildPlan(groups: groups, results: results), to: results)
    }

    // MARK: - Model

    /// One reported finding tagged with where it came from, used for stable grouping.
    private struct Occurrence {
        var finding: Finding
        var resultIndex: Int
        var findingIndex: Int
    }

    /// Findings on one `(file, line)` judged to describe the same issue. `members[0]`
    /// is the representative (earliest in `(resultIndex, findingIndex)` order).
    private struct Group {
        var members: [Occurrence]
    }

    private struct Bucket: Hashable {
        var file: String
        var line: Int?
    }

    /// A finding's position, used as a stable lookup key during reassembly.
    private struct Position: Hashable {
        var resultIndex: Int
        var findingIndex: Int

        init(_ resultIndex: Int, _ findingIndex: Int) {
            self.resultIndex = resultIndex
            self.findingIndex = findingIndex
        }
    }

    /// The reassembly instructions derived from the groups.
    private struct MergePlan {
        var canonicalAt: [Position: Finding] = [:]
        var removed: Set<Position> = []
        var removedCrossing: Set<Int> = []
    }

    // MARK: - Steps

    private static func flatten(_ results: [ReviewTaskResult]) -> [Occurrence] {
        var occurrences: [Occurrence] = []
        for (resultIndex, result) in results.enumerated() {
            for (findingIndex, finding) in result.findings.enumerated() {
                occurrences.append(Occurrence(finding: finding, resultIndex: resultIndex, findingIndex: findingIndex))
            }
        }
        return occurrences
    }

    /// Greedily bucket by exact `(file, line)`, then fuzzy-group titles within a
    /// bucket. A finding joins an existing group only if its title matches the
    /// representative AND no member comes from the same task (cross-task only).
    private static func group(_ occurrences: [Occurrence]) -> [Group] {
        var groups: [Group] = []
        var byBucket: [Bucket: [Int]] = [:]
        for occurrence in occurrences {
            let bucket = Bucket(file: occurrence.finding.file, line: occurrence.finding.line)
            let candidates = byBucket[bucket] ?? []
            if let index = candidates.first(where: { canJoin(groups[$0], occurrence) }) {
                groups[index].members.append(occurrence)
            } else {
                byBucket[bucket, default: []].append(groups.count)
                groups.append(Group(members: [occurrence]))
            }
        }
        return groups
    }

    private static func canJoin(_ group: Group, _ occurrence: Occurrence) -> Bool {
        guard let representative = group.members.first,
              FindingMatch.titlesMatch(representative.finding.title, occurrence.finding.title)
        else {
            return false
        }
        return !group.members.contains { $0.resultIndex == occurrence.resultIndex }
    }

    private static func buildPlan(groups: [Group], results: [ReviewTaskResult]) -> MergePlan {
        var plan = MergePlan()
        for group in groups {
            guard let representative = group.members.first else { continue }
            plan.canonicalAt[Position(representative.resultIndex, representative.findingIndex)]
                = canonicalFinding(group, results: results)
            guard group.members.count > 1 else { continue }
            for member in group.members.dropFirst() {
                plan.removed.insert(Position(member.resultIndex, member.findingIndex))
                if member.finding.severity >= results[member.resultIndex].failOn {
                    plan.removedCrossing.insert(member.resultIndex)
                }
            }
        }
        return plan
    }

    /// The surviving finding: the representative, with severity raised to the group
    /// max and `confirmedBy` set to the distinct confirming reviews (only when two or
    /// more reviews agreed, so single-review findings stay untagged).
    private static func canonicalFinding(_ group: Group, results: [ReviewTaskResult]) -> Finding {
        var canonical = group.members[0].finding
        canonical.severity = group.members.map(\.finding.severity).max() ?? canonical.severity
        let reviews = Set(group.members.map { results[$0.resultIndex].review })
        canonical.confirmedBy = reviews.count >= 2 ? reviews.sorted() : []
        return canonical
    }

    private static func apply(_ plan: MergePlan, to results: [ReviewTaskResult]) -> [ReviewTaskResult] {
        results.enumerated().map { resultIndex, result in
            var rebuilt: [Finding] = []
            for (findingIndex, finding) in result.findings.enumerated() {
                let position = Position(resultIndex, findingIndex)
                if let canonical = plan.canonicalAt[position] {
                    rebuilt.append(canonical)
                } else if plan.removed.contains(position) {
                    continue
                } else {
                    rebuilt.append(finding)
                }
            }
            var copy = result
            copy.findings = rebuilt
            if plan.removedCrossing.contains(resultIndex) {
                copy.removedCrossingFindings = true
            }
            return copy
        }
    }
}

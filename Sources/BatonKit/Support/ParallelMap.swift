/// Process entries concurrently using a sliding window, preserving input order.
///
/// Ported from ExFig's `parallelMapEntries`. At most `maxParallel` tasks run at
/// any moment; a new task starts as soon as an in-flight one finishes. Results are
/// returned in the same order as `entries`.
///
/// - Empty input returns immediately.
/// - A single entry is processed directly without task-group overhead.
///
/// - Parameters:
///   - entries: The work items.
///   - maxParallel: Maximum concurrent tasks (forced to at least 1).
///   - process: Async transform applied to each entry.
/// - Returns: Results ordered to match `entries`.
/// - Throws: Rethrows the first error from `process`; remaining tasks are cancelled.
public func parallelMapEntries<Entry: Sendable, Result: Sendable>(
    _ entries: [Entry],
    maxParallel: Int,
    process: @escaping @Sendable (Entry) async throws -> Result
) async throws -> [Result] {
    switch entries.count {
    case 0:
        return []
    case 1:
        return try await [process(entries[0])]
    default:
        break
    }

    let effectiveMax = max(maxParallel, 1)

    return try await withThrowingTaskGroup(of: (Int, Result).self) { group in
        var results = [Result?](repeating: nil, count: entries.count)
        var nextIndex = 0

        for _ in 0 ..< min(effectiveMax, entries.count) {
            let index = nextIndex
            let entry = entries[index]
            group.addTask { try await (index, process(entry)) }
            nextIndex += 1
        }

        for try await (index, result) in group {
            results[index] = result
            if nextIndex < entries.count {
                let next = nextIndex
                let entry = entries[next]
                group.addTask { try await (next, process(entry)) }
                nextIndex += 1
            }
        }

        return results.map { $0! } // swiftlint:disable:this force_unwrapping
    }
}

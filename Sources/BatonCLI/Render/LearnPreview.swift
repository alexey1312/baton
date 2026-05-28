import BatonKit

/// Pure, UI-free rendering of a ``LearnRunResult`` — a terminal preview (mirroring
/// `render`'s read-only philosophy) and the markdown body for the rolling PR.
enum LearnPreview {
    /// A human-readable terminal preview of the proposed edits and signal.
    static func terminal(_ result: LearnRunResult, useColors: Bool) -> String {
        var lines = [NooraUI.success("Baton learn — preview", useColors: useColors)]
        if result.proposals.isEmpty, result.skipped.isEmpty {
            lines.append("  No signal in the lookback window; nothing to propose.")
        }
        for proposal in result.proposals {
            lines.append(contentsOf: proposalLines(proposal))
        }
        for skip in result.skipped {
            lines.append("\n  \(scopeName(skip.scopePath)): skipped — \(reasonText(skip.reason))")
        }
        return lines.joined(separator: "\n")
    }

    /// The markdown body for the rolling `learn` pull request.
    static func markdown(_ result: LearnRunResult) -> String {
        var sections = ["## Baton learn", "", "Proposed edits to Baton's review setup based on recent review signal."]
        for proposal in result.proposals where !proposal.edits.isEmpty {
            sections.append("\n### `\(scopeName(proposal.scopePath))`\n")
            sections.append(candidateSummary(proposal))
            for edit in proposal.edits {
                sections.append("- `\(edit.path)`" + (edit.summary.map { " — \($0)" } ?? ""))
            }
        }
        if !result.proposals.contains(where: { !$0.edits.isEmpty }) {
            sections.append("\n_No setup edits proposed this run._")
        }
        return sections.joined(separator: "\n")
    }

    // MARK: - Helpers

    private static func proposalLines(_ proposal: ScopeProposal) -> [String] {
        var lines = ["\n  \(scopeName(proposal.scopePath)): \(proposal.edits.count) proposed edit(s)"]
        for edit in proposal.edits {
            lines.append("    - \(edit.path)")
        }
        lines.append("    signal: \(candidateSummary(proposal))")
        if !proposal.droppedPaths.isEmpty {
            lines.append("    dropped (out of allowlist): \(proposal.droppedPaths.joined(separator: ", "))")
        }
        return lines
    }

    private static func candidateSummary(_ proposal: ScopeProposal) -> String {
        let relax = proposal.candidates.count { $0.direction == .relax }
        let reinforce = proposal.candidates.count { $0.direction == .reinforce }
        return "\(proposal.signalVolume) thread(s), \(relax) relax / \(reinforce) reinforce candidate(s)"
    }

    private static func reasonText(_ reason: ScopeSkipReason) -> String {
        switch reason {
        case .disabled:
            "[learn].enabled = false"
        case let .belowMinSignal(volume, required):
            "below min_signal (\(volume) < \(required))"
        }
    }

    private static func scopeName(_ path: String) -> String {
        path.isEmpty ? "(root)" : path
    }
}

import Foundation

/// Assembles the headless prompt for one per-scope learning pass: the signal
/// summary (rule candidates + missing-coverage clusters) plus instructions
/// constraining the agent to review-setup edits only.
public enum LearnPromptBuilder {
    /// Build the learning prompt for `request`. `skillBodies` are the resolved
    /// skill texts to inline (empty when none).
    public static func build(_ request: LearnAgentRequest, skillBodies: [String] = []) -> String {
        var sections: [String] = [header(request.scopePath)]
        if !skillBodies.isEmpty {
            sections.append("## Skills\n\n" + skillBodies.joined(separator: "\n\n---\n\n"))
        }
        sections.append(bucketSummary(request.bucketCounts))
        if !request.candidates.isEmpty {
            sections.append(candidateSection(request.candidates))
        }
        if !request.missingCoverage.isEmpty {
            sections.append(missingCoverageSection(request.missingCoverage))
        }
        sections.append(instructions)
        return sections.joined(separator: "\n\n")
    }

    private static func header(_ scopePath: String) -> String {
        let name = scopePath.isEmpty ? "(repository root)" : scopePath
        return """
        # Baton learn — review-setup reflection for scope `\(name)`

        You are improving Baton's *own* review setup for this scope based on how its findings
        landed with human reviewers. You MUST only edit review-setup files for this scope:
        `baton.toml`, local skill directories, and agent-facing docs. Never edit source code,
        tests, CI workflows, or dependency manifests.
        """
    }

    private static func bucketSummary(_ counts: [ThreadBucket: Int]) -> String {
        let order: [ThreadBucket] = [.accepted, .ignored, .outdated, .humanAuthored]
        let rows = order.map { "- \($0.rawValue): \(counts[$0] ?? 0)" }.joined(separator: "\n")
        return "## Signal summary\n\n\(rows)"
    }

    private static func candidateSection(_ candidates: [RuleCandidate]) -> String {
        let rows = candidates.prefix(20).map { candidate -> String in
            let location = candidate.finding.line.map { "\(candidate.finding.file):\($0)" } ?? candidate.finding.file
            return "- [\(candidate.direction.rawValue)] weight \(candidate.weight) "
                + "over \(candidate.threadCount) thread(s): \(candidate.finding.title) (\(location))"
        }.joined(separator: "\n")
        return """
        ## Rule candidates

        Negative weight ⇒ relax or remove the rule; positive ⇒ reinforce it.

        \(rows)
        """
    }

    private static func missingCoverageSection(_ threads: [ReviewThreadSignal]) -> String {
        let files = Set(threads.map(\.file)).sorted()
        let rows = files.map { "- \($0)" }.joined(separator: "\n")
        return """
        ## Missing coverage (human-authored threads Baton did not produce)

        These files drew human review comments Baton did not flag. If they cluster into a
        category Baton fails to cover, add or broaden a `[[reviews]]` entry or skill.

        \(rows)
        """
    }

    private static let instructions = """
    ## What to do

    Edit `baton.toml` review prompts / skill lists, local skill files, or agent docs to relax
    over-eager rules, reinforce useful ones, and add coverage for recurring human-only findings.
    Make the smallest change that addresses the signal. Do not touch anything outside the review
    setup — any such change will be dropped.
    """
}

import BatonKit
import Jinja

/// Builds the typed Jinja render context from saved-run and learn-result models.
/// Kept separate from the templates so the data shape is testable and stable.
enum TemplateContext {
    /// Context for the `markdown` report: run metadata, failed tasks, and the
    /// results that carry findings.
    static func run(_ run: LoadedRun) throws -> [String: Value] {
        let resultsWithFindings = run.results.filter { !$0.findings.isEmpty }
        let failures = run.results.filter(\.taskFailed)
        let runDict: [String: Any?] = [
            "base": run.manifest.base,
            "head_sha": run.manifest.headSHA,
            "has_findings": !resultsWithFindings.isEmpty,
            "has_failures": !failures.isEmpty,
            "failures": failures.map { result -> [String: Any?] in [
                "scope_display": displayScope(result.scope),
                "review": result.review,
                "error_message": result.errorMessage ?? "review failed",
            ] },
            "results": resultsWithFindings.map { result -> [String: Any?] in [
                "scope_display": displayScope(result.scope),
                "review": result.review,
                "findings": result.findings.map(finding),
            ] },
        ]
        return try ["run": Value(any: runDict)]
    }

    /// Context for the `learn` rolling-PR body: proposals with edits and signal.
    static func learn(_ result: LearnRunResult) throws -> [String: Value] {
        let proposals = result.proposals.filter { !$0.edits.isEmpty }
        let learnDict: [String: Any?] = [
            "has_proposals": !proposals.isEmpty,
            "proposals": proposals.map { proposal -> [String: Any?] in
                let relax = proposal.candidates.count { $0.direction == .relax }
                let reinforce = proposal.candidates.count { $0.direction == .reinforce }
                return [
                    "scope_display": displayScope(proposal.scopePath),
                    "signal_volume": proposal.signalVolume,
                    "relax": relax,
                    "reinforce": reinforce,
                    "edits": proposal.edits.map { edit -> [String: Any?] in
                        ["path": edit.path, "summary_suffix": edit.summary.map { " — \($0)" } ?? ""]
                    },
                ]
            },
        ]
        return try ["learn": Value(any: learnDict)]
    }

    private static func finding(_ finding: Finding) -> [String: Any?] {
        [
            "badge": finding.severity.badge,
            "severity": finding.severity.rawValue,
            "title": finding.title,
            "file": finding.file,
            "line": finding.line,
            "location": finding.line.map { "\(finding.file):\($0)" } ?? finding.file,
            "body": finding.body,
            "ai_instructions": finding.aiInstructions,
            "confirmed_count": finding.confirmedBy.count,
            "confirmed_by": finding.confirmedBy.joined(separator: ", "),
        ]
    }

    private static func displayScope(_ path: String) -> String {
        path.isEmpty ? "(root)" : path
    }
}

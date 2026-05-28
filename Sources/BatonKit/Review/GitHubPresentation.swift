/// Stable, machine-recognizable markers Baton embeds in PR content.
public enum BatonMarker {
    /// Footer marker on every Baton-authored finding comment (dedupe + future `learn`).
    public static let finding = "<!-- baton:finding -->"

    /// The reviewed-head-SHA marker embedded in the Baton PR-review body.
    public static func lastReviewed(_ sha: String) -> String {
        "<!-- baton:last-reviewed=\(sha) -->"
    }

    /// Prefix used to recover the reviewed SHA from a review body.
    public static let lastReviewedPrefix = "<!-- baton:last-reviewed="

    /// Extract the reviewed SHA from text containing a `last-reviewed` marker.
    public static func parseLastReviewed(from text: String) -> String? {
        guard let start = text.range(of: lastReviewedPrefix) else { return nil }
        let rest = text[start.upperBound...]
        guard let end = rest.range(of: " -->") else { return nil }
        return String(rest[..<end.lowerBound]).trimmingCharacters(in: .whitespaces)
    }
}

/// A finding rendered as a PR inline review comment.
public struct InlineComment: Sendable, Codable, Equatable {
    public var path: String
    public var line: Int
    public var body: String

    public init(path: String, line: Int, body: String) {
        self.path = path
        self.line = line
        self.body = body
    }
}

/// The conclusion of a `(scope, review)` Check Run.
public enum CheckRunConclusion: String, Sendable, Codable {
    case success
    case failure
    case neutral
}

/// Pure, UI-free GitHub presentation of findings — shared by the `rendering`
/// capability (which emits payloads) and `github-publish` (which posts them).
public enum GitHubPresentation {
    /// The body of an inline review comment: severity badge + title + body + a
    /// collapsible AI-agent instructions block + a 👍/👎 usefulness affordance + the
    /// `baton:finding` footer marker.
    public static func inlineCommentBody(_ finding: Finding) -> String {
        var lines = ["**\(finding.severity.badge) \(finding.severity.rawValue) — \(finding.title)**", ""]
        if !finding.body.isEmpty {
            lines.append(finding.body)
            lines.append("")
        }
        if let instructions = finding.aiInstructions, !instructions.isEmpty {
            lines.append(aiInstructionsBlock(instructions))
            lines.append("")
        }
        lines.append("<sub>React 👍 / 👎 if this was useful. — Baton</sub>")
        lines.append(BatonMarker.finding)
        return lines.joined(separator: "\n")
    }

    /// A markdown entry for a finding inside a summary (Check Run summary or
    /// `github-summary`), file/line-anchored, including the AI-agent block + marker.
    public static func summaryEntry(_ finding: Finding) -> String {
        let location = finding.line.map { "\(finding.file):\($0)" } ?? finding.file
        var lines = [
            "### \(finding.severity.badge) \(finding.severity.rawValue) — \(finding.title)",
            "",
            "`\(location)`",
            "",
        ]
        if !finding.body.isEmpty {
            lines.append(finding.body)
            lines.append("")
        }
        if let instructions = finding.aiInstructions, !instructions.isEmpty {
            lines.append(aiInstructionsBlock(instructions))
            lines.append("")
        }
        lines.append(BatonMarker.finding)
        return lines.joined(separator: "\n")
    }

    /// A Check Run / github-summary body aggregating findings for a scope-review.
    public static func summaryBody(scope: String, review: String, findings: [Finding]) -> String {
        let title = "Baton — \(scope.isEmpty ? "(root)" : scope) / \(review)"
        if findings.isEmpty {
            return "## \(title)\n\nNo findings. ✅\n\n\(BatonMarker.finding)"
        }
        let entries = findings.map(summaryEntry).joined(separator: "\n\n")
        return "## \(title)\n\n\(entries)"
    }

    /// High-gated conclusion, independent of `fail_on` (design Decision 11):
    /// `failure` if any high finding, `success` if no findings, else `neutral`.
    public static func conclusion(for findings: [Finding]) -> CheckRunConclusion {
        if findings.isEmpty { return .success }
        if findings.contains(where: { $0.severity == .high }) { return .failure }
        return .neutral
    }

    private static func aiInstructionsBlock(_ instructions: String) -> String {
        """
        <details><summary>Instructions for AI agents</summary>

        \(instructions)

        </details>
        """
    }
}
